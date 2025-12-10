local RSGCore = exports['rsg-core']:GetCoreObject()
local horsePed = nil
local horse = nil
local horseSpeed = 0
local horsespeedcheck = false
local horseEXP = 0
lib.locale()

-- Cooldown tracking
local lastBrush = 0
local lastFeed = 0
local lastCalm = 0
local lastHoof = 0
local lastWater = 0
local lastTreat = 0

-- Distance riding tracking
local ridingDistance = 0
local lastRidingPos = nil
local isDistanceTrainingActive = false  -- Must be started manually from menu

-- Horse training state
local isHorseFullyTrained = false
local cachedHorseXP = 0

--------------------------------------------------------------------
-- Helper function to get XP based on job
--------------------------------------------------------------------
local function GetXPAmount(basePlayer, baseTrainer)
    local PlayerData = RSGCore.Functions.GetPlayerData()
    local jobtype = PlayerData.job.type
    return jobtype == 'trainer' and baseTrainer or basePlayer
end

--------------------------------------------------------------------
-- Get active horse based on stable script
--------------------------------------------------------------------
local function GetActiveHorsePed()
    if Config.StableScript == 'QC-Stables' then
        -- Try QC-Stables export
        local success, result = pcall(function()
            return exports['QC-Stables']:GetActiveHorse()
        end)
        if success and result then
            return result
        end
        -- Fallback: check if player is on a mount
        local ped = PlayerPedId()
        if IsPedOnMount(ped) then
            return GetLastMount(ped)
        end
        return nil
    else
        -- rsg-horses fallback
        return exports['rsg-horses']:CheckActiveHorse()
    end
end

--------------------------------------------------------------------
-- Apply stats to trained horse when mounted
--------------------------------------------------------------------
local lastMountCheck = 0
local statsAppliedToCurrentHorse = false

CreateThread(function()
    while true do
        Wait(1000)
        
        if not LocalPlayer.state['isLoggedIn'] then 
            statsAppliedToCurrentHorse = false
            goto continue 
        end
        
        if not Config.MaxHorseStats or not Config.MaxHorseStats.enabled or not Config.MaxHorseStats.applyOnMount then
            goto continue
        end
        
        local ped = PlayerPedId()
        local isMounted = IsPedOnMount(ped)
        
        if isMounted and not statsAppliedToCurrentHorse then
            -- Check if horse is fully trained
            RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:GetActiveHorseData', function(data)
                if data and data.horsexp and data.horsexp >= Config.MaxHorseXP then
                    local horsePed = GetLastMount(ped)
                    if horsePed and DoesEntityExist(horsePed) then
                        ApplyMaxHorseStatsToEntity(horsePed)
                        statsAppliedToCurrentHorse = true
                        
                        if Config.Debug then
                            print('^2[rex-horsetrainer] DEBUG: Applied max stats to fully trained horse on mount^7')
                        end
                    end
                end
            end)
        elseif not isMounted then
            statsAppliedToCurrentHorse = false
        end
        
        ::continue::
    end
end)

--------------------------------------------------------------------
-- Helper function to check and award XP
--------------------------------------------------------------------
local function AwardXP(xpAmount, taskName)
    -- Use server callback to get horse data from database
    RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:GetActiveHorseData', function(data)
        if not data then
            if Config.Debug then
                print('^1[rex-horsetrainer] ERROR: GetActiveHorseData callback returned nil^7')
            end
            return
        end
        
        horseEXP = data.horsexp or 0
        if horseEXP >= Config.MaxHorseXP then
            lib.notify({
                title = 'Horse Training',
                description = 'Horse is fully trained!',
                type = 'info',
                duration = 3000
            })
            return
        end

        if Config.Debug then
            print(('^3[rex-horsetrainer] DEBUG: %s XP - Amount: %d^7'):format(taskName, xpAmount))
        end
        TriggerServerEvent('rex-horsetrainer:server:updatexp', xpAmount, taskName)
    end)
end

--------------------------------------------------------------------
-- Distance Riding XP System
--------------------------------------------------------------------
local wasMounted = false -- Track mount state

CreateThread(function()
    while true do
        Wait(Config.DistanceRiding.checkInterval or 1000)

        if not LocalPlayer.state['isLoggedIn'] then 
            ridingDistance = 0
            lastRidingPos = nil
            wasMounted = false
            isDistanceTrainingActive = false
            goto continue 
        end
        
        if not Config.DistanceRiding.enabled then goto continue end
        
        -- Only track if training is active (started from menu)
        if not isDistanceTrainingActive then goto continue end

        local ped = PlayerPedId()
        horsePed = GetActiveHorsePed()

        if not horsePed or not IsEntityAPed(horsePed) then 
            lastRidingPos = nil
            goto continue 
        end

        local isMounted = IsPedOnMount(ped)
        
        -- Check if player dismounted (was mounted, now not mounted)
        if wasMounted and not isMounted then
            if ridingDistance > 0 then
                lib.notify({
                    title = 'Distance Training',
                    description = 'You dismounted! Task cancelled.',
                    type = 'error',
                    duration = 4000
                })
                ridingDistance = 0
                lastRidingPos = nil
                isDistanceTrainingActive = false
            end
            wasMounted = false
            goto continue
        end
        
        -- Update mount state
        wasMounted = isMounted
        
        -- Check if mounted and moving
        if not isMounted then
            lastRidingPos = nil
            goto continue
        end
        
        horseSpeed = GetEntitySpeed(horsePed)
        if horseSpeed < (Config.DistanceRiding.minSpeed or 3) then
            goto continue
        end

        local currentPos = GetEntityCoords(horsePed)
        
        if lastRidingPos then
            local dist = #(currentPos - lastRidingPos)
            ridingDistance = ridingDistance + dist
            
            if Config.Debug then
                print(('^3[rex-horsetrainer] DEBUG: Distance: %.1f / %d meters^7'):format(ridingDistance, Config.DistanceRiding.targetDistance))
            end
            
            -- Check if target reached
            if ridingDistance >= Config.DistanceRiding.targetDistance then
                print(('^2[rex-horsetrainer] CLIENT: Distance target reached! Sending to server: %.2f^7'):format(ridingDistance))
                TriggerServerEvent('rex-horsetrainer:server:completeDistanceRiding', ridingDistance)
                isDistanceTrainingActive = false -- Stop tracking after completion
            end
        end
        
        lastRidingPos = currentPos

        ::continue::
    end
end)

--------------------------------------------------------------------
-- Distance Riding HUD Display
--------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 500
        
        if LocalPlayer.state['isLoggedIn'] and Config.DistanceRiding.enabled and isDistanceTrainingActive then
            local ped = PlayerPedId()
            
            -- Show HUD only when training is active
            if IsPedOnMount(ped) then
                sleep = 0
                local percentage = math.floor((ridingDistance / Config.DistanceRiding.targetDistance) * 100)
                percentage = math.min(percentage, 100)
                
                local isMoving = GetEntitySpeed(GetLastMount(ped)) >= (Config.DistanceRiding.minSpeed or 3)
                local movingText = isMoving and 'MOVING!' or 'STOPPED'
                
                -- Draw centered HUD like the image
                DrawDistanceHUDCentered(percentage, movingText)
            end
        end
        
        Wait(sleep)
    end
end)

--------------------------------------------------------------------
-- Draw Distance HUD Centered (Like image style)
--------------------------------------------------------------------
function DrawDistanceHUDCentered(percentage, movingText)
    local x = 0.5  -- Center of screen
    local y = 0.08 -- Top of screen
    
    -- Title: "DISTANCE TRAINING"
    SetTextScale(0.6, 0.6)
    SetTextFontForCurrentCommand(7) -- Pricedown/Western style font
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    SetTextDropshadow(3, 0, 0, 0, 255)
    DisplayText(CreateVarString(10, "LITERAL_STRING", "DISTANCE TRAINING"), x, y)
    
    -- Progress line: "1500/3000M (50%) MOVING!"
    local progressText = ('%.0f/%dM (%d%%) %s'):format(ridingDistance, Config.DistanceRiding.targetDistance, percentage, movingText)
    
    SetTextScale(0.45, 0.45)
    SetTextFontForCurrentCommand(7)
    SetTextColor(255, 255, 0, 255) -- Yellow color like image
    SetTextCentre(true)
    SetTextDropshadow(2, 0, 0, 0, 255)
    DisplayText(CreateVarString(10, "LITERAL_STRING", progressText), x, y + 0.04)
    
    -- Sync with rsg-hud if available
    UpdateRSGHud(percentage)
end

--------------------------------------------------------------------
-- RSG-HUD Integration
--------------------------------------------------------------------
local lastHudUpdate = 0

function UpdateRSGHud(percentage)
    if not Config.RSGHud or not Config.RSGHud.enabled or not Config.RSGHud.showTrainingProgress then return end
    
    local currentTime = GetGameTimer()
    -- Only update HUD every 500ms to avoid spam
    if currentTime - lastHudUpdate < 500 then return end
    lastHudUpdate = currentTime
    
    -- Try to update rsg-hud with horse training info
    pcall(function()
        -- Method 1: Send NUI message to rsg-hud
        SendNUIMessage({
            action = 'horseTraining',
            show = true,
            progress = percentage,
            distance = math.floor(ridingDistance),
            target = Config.DistanceRiding.targetDistance,
            xp = cachedHorseXP,
            maxXp = Config.MaxHorseXP
        })
    end)
    
    -- Method 2: Trigger rsg-hud event
    pcall(function()
        TriggerEvent('rsg-hud:client:UpdateHorseTraining', {
            active = true,
            progress = percentage,
            distance = math.floor(ridingDistance),
            target = Config.DistanceRiding.targetDistance,
            xp = cachedHorseXP,
            maxXp = Config.MaxHorseXP
        })
    end)
end

function HideRSGHudTraining()
    if not Config.RSGHud or not Config.RSGHud.enabled then return end
    
    pcall(function()
        SendNUIMessage({
            action = 'horseTraining',
            show = false
        })
    end)
    
    pcall(function()
        TriggerEvent('rsg-hud:client:UpdateHorseTraining', {
            active = false
        })
    end)
end

-- Update rsg-hud with horse XP (for persistent display)
function UpdateRSGHudHorseXP(xp)
    if not Config.RSGHud or not Config.RSGHud.enabled or not Config.RSGHud.showHorseXP then return end
    
    local percentage = math.floor((xp / Config.MaxHorseXP) * 100)
    
    pcall(function()
        SendNUIMessage({
            action = 'updateHorseXP',
            xp = xp,
            maxXp = Config.MaxHorseXP,
            percentage = percentage,
            fullyTrained = (xp >= Config.MaxHorseXP)
        })
    end)
    
    pcall(function()
        TriggerEvent('rsg-hud:client:UpdateHorseXP', {
            xp = xp,
            maxXp = Config.MaxHorseXP,
            percentage = percentage,
            fullyTrained = (xp >= Config.MaxHorseXP)
        })
    end)
end

-- Reset distance event from server (with XP update)
RegisterNetEvent('rex-horsetrainer:client:resetDistance', function(newXP)
    ridingDistance = 0
    lastRidingPos = nil
    wasMounted = false
    isDistanceTrainingActive = false
    
    -- Hide rsg-hud training display
    HideRSGHudTraining()
    
    -- Update cached XP if provided
    if newXP then
        cachedHorseXP = newXP
        isHorseFullyTrained = (newXP >= Config.MaxHorseXP)
        
        -- Update rsg-hud with new horse XP
        UpdateRSGHudHorseXP(newXP)
    end
    
    lib.notify({
        title = 'Horse Training',
        description = 'Distance training completed! Start new training from menu.',
        type = 'success',
        duration = 3000
    })
end)

-- Update cached XP from server (after any training)
RegisterNetEvent('rex-horsetrainer:client:updateCachedXP', function(newXP)
    if newXP then
        cachedHorseXP = newXP
        isHorseFullyTrained = (newXP >= Config.MaxHorseXP)
        
        -- Sync with rsg-hud
        UpdateRSGHudHorseXP(newXP)
        
        if Config.Debug then
            print(('^3[rex-horsetrainer] DEBUG: Cached XP updated to %d^7'):format(newXP))
        end
    end
end)

--------------------------------------------------------------------
-- Cancel Training Command
--------------------------------------------------------------------
RegisterCommand('canceltraining', function()
    if not LocalPlayer.state['isLoggedIn'] then return end
    
    if isDistanceTrainingActive then
        ridingDistance = 0
        lastRidingPos = nil
        wasMounted = false
        isDistanceTrainingActive = false
        
        -- Hide rsg-hud training display
        HideRSGHudTraining()
        
        lib.notify({
            title = 'Training Cancelled',
            description = 'Distance training has been cancelled.',
            type = 'error',
            duration = 4000
        })
    else
        lib.notify({
            title = 'Training',
            description = 'No active training to cancel.',
            type = 'info',
            duration = 3000
        })
    end
end, false)

-- Sync horse XP with QC-Stables (prevent cache overwrite)
RegisterNetEvent('rex-horsetrainer:client:syncHorseXP', function(horseId, newXP)
    print(('^3[rex-horsetrainer] DEBUG: Syncing horse XP - ID: %d, XP: %d^7'):format(horseId, newXP))
    
    -- Update local cache
    cachedHorseXP = newXP
    isHorseFullyTrained = (newXP >= Config.MaxHorseXP)
    
    -- Try to update QC-Stables client cache
    pcall(function()
        exports['QC-Stables']:SetHorseXP(horseId, newXP)
    end)
    
    pcall(function()
        exports['QC-Stables']:UpdateHorseXP(newXP)
    end)
    
    pcall(function()
        TriggerEvent('QC-Stables:client:SetHorseXP', horseId, newXP)
    end)
    
    pcall(function()
        TriggerEvent('QC-Stables:client:RefreshHorseData')
    end)
end)

-- Set horse fully trained state (from admin command)
RegisterNetEvent('rex-horsetrainer:client:setHorseFullyTrained', function(isTrained)
    isHorseFullyTrained = isTrained
    if isTrained then
        cachedHorseXP = Config.MaxHorseXP
    end
end)

-- Refresh horse stats event (called when horse is fully trained)
RegisterNetEvent('rex-horsetrainer:client:refreshHorseStats', function()
    if Config.Debug then
        print('^3[rex-horsetrainer] DEBUG: Attempting to refresh horse stats...^7')
    end
    
    -- Method 1: Try QC-Stables RefreshHorse export
    pcall(function()
        exports['QC-Stables']:RefreshHorse()
    end)
    
    -- Method 2: Try QC-Stables UpdateHorseStats export
    pcall(function()
        exports['QC-Stables']:UpdateHorseStats()
    end)
    
    -- Method 3: Try triggering QC-Stables events
    pcall(function()
        TriggerEvent('QC-Stables:client:RefreshHorse')
    end)
    
    pcall(function()
        TriggerEvent('QC-Stables:client:UpdateStats')
    end)
    
    -- Method 4: Apply stats directly to horse ped if available
    local horsePed = GetActiveHorsePed()
    if horsePed and DoesEntityExist(horsePed) then
        ApplyMaxHorseStatsToEntity(horsePed)
    end
    
    lib.notify({
        title = 'Horse Training',
        description = 'Horse stats updated! Stable your horse and retrieve it to see full changes.',
        type = 'info',
        duration = 5000
    })
end)

--------------------------------------------------------------------
-- Apply Max Stats to Horse Entity (Speed, Acceleration, Health, Stamina)
--------------------------------------------------------------------
function ApplyMaxHorseStatsToEntity(horsePed)
    if not horsePed or not DoesEntityExist(horsePed) then return end
    
    local maxHealth = Config.MaxHorseStats and Config.MaxHorseStats.health or 100
    local maxStamina = Config.MaxHorseStats and Config.MaxHorseStats.stamina or 100
    local maxSpeed = Config.MaxHorseStats and Config.MaxHorseStats.speed or 1.0
    local maxAcceleration = Config.MaxHorseStats and Config.MaxHorseStats.acceleration or 1.0
    
    -- Apply health
    pcall(function()
        local healthMax = maxHealth * 10 -- RedM uses 0-1000 scale
        SetEntityMaxHealth(horsePed, healthMax)
        SetEntityHealth(horsePed, healthMax, 0)
    end)
    
    -- Apply stamina
    pcall(function()
        local staminaMax = maxStamina * 10.0
        Citizen.InvokeNative(0xC3D4B754C0E86B9E, horsePed, staminaMax) -- SET_PED_MAX_STAMINA
        Citizen.InvokeNative(0x675680D089BFA21F, horsePed, staminaMax) -- RESTORE_PED_STAMINA
    end)
    
    -- Apply speed modifier
    pcall(function()
        -- SET_PED_MOVE_RATE_OVERRIDE
        Citizen.InvokeNative(0x085BF80FA50A39D1, horsePed, maxSpeed)
    end)
    
    -- Apply acceleration/agility attributes
    pcall(function()
        -- Set horse agility attribute (affects acceleration)
        local agilityHash = GetHashKey('PPED_HORSE_AGILITY')
        Citizen.InvokeNative(0x09A59688C26D82DF, horsePed, agilityHash, 100, 100) -- SET_ATTRIBUTE_POINTS
        
        -- Set horse speed attribute
        local speedHash = GetHashKey('PPED_HORSE_SPEED')
        Citizen.InvokeNative(0x09A59688C26D82DF, horsePed, speedHash, 100, 100) -- SET_ATTRIBUTE_POINTS
        
        -- Set horse acceleration attribute
        local accelHash = GetHashKey('PPED_HORSE_ACCELERATION')
        Citizen.InvokeNative(0x09A59688C26D82DF, horsePed, accelHash, 100, 100) -- SET_ATTRIBUTE_POINTS
    end)
    
    -- Set horse bonding level to max (affects stats)
    pcall(function()
        Citizen.InvokeNative(0x931B241409216C1F, horsePed, 4) -- _SET_PED_BOND_LEVEL (max is 4)
    end)
    
    if Config.Debug then
        print('^2[rex-horsetrainer] DEBUG: Applied max stats to horse ped (Health, Stamina, Speed, Acceleration)^7')
    end
end

-- Command to check current riding distance
RegisterCommand('checkdistance', function()
    if Config.DistanceRiding.enabled then
        local remaining = Config.DistanceRiding.targetDistance - ridingDistance
        lib.notify({
            title = 'Distance Riding',
            description = ('Progress: %.0f / %d meters (%.0f remaining)'):format(ridingDistance, Config.DistanceRiding.targetDistance, math.max(0, remaining)),
            type = 'info',
            duration = 5000
        })
    else
        lib.notify({
            title = 'Distance Riding',
            description = 'Distance riding is disabled',
            type = 'error',
            duration = 3000
        })
    end
end, false)

--------------------------------------------------------------------
-- Leading horse XP loop
--------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.LeadingWait)

        if not LocalPlayer.state['isLoggedIn'] then goto continue end

        local ped = PlayerPedId()
        horse = GetLastMount(ped)
        horsePed = GetActiveHorsePed()

        if not horsePed or horsePed == 0 then goto continue end
        if IsPedOnMount(ped) or IsPedStopped(horsePed) then goto continue end
        if not IsPedLeadingHorse(horsePed) then goto continue end

        local xp = GetXPAmount(Config.PlayerLeadingXP, Config.TrainerLeadingXP)
        AwardXP(xp, 'Leading')

        ::continue::
    end
end)

--------------------------------------------------------------------
-- Brush Horse Command
--------------------------------------------------------------------
RegisterCommand('brushhorse', function()
    if not LocalPlayer.state['isLoggedIn'] then return end
    
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    local distance = #(playerCoords - horseCoords)
    
    if distance > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    -- Check cooldown
    local currentTime = GetGameTimer()
    if currentTime - lastBrush < Config.BrushingCooldown then
        local remaining = math.ceil((Config.BrushingCooldown - (currentTime - lastBrush)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds before brushing again'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    -- Check for required item
    if Config.RequireItems then
        RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:hasItem', function(hasItem)
            if not hasItem then
                lib.notify({ title = 'Horse Training', description = 'You need a horse brush!', type = 'error', duration = 3000 })
                return
            end
            DoBrushHorse()
        end, Config.Items.brush)
    else
        DoBrushHorse()
    end
end, false)

function DoBrushHorse()
    local ped = PlayerPedId()
    lastBrush = GetGameTimer()
    
    if lib.progressBar({
        duration = 5000,
        label = 'Brushing horse...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true }
    }) then
        local xp = GetXPAmount(Config.PlayerBrushingXP, Config.TrainerBrushingXP)
        AwardXP(xp, 'Brushing')
    else
        lib.notify({ title = 'Horse Training', description = 'Cancelled', type = 'error', duration = 2000 })
    end
end

--------------------------------------------------------------------
-- Feed Horse Command
--------------------------------------------------------------------
RegisterCommand('feedhorse', function()
    if not LocalPlayer.state['isLoggedIn'] then return end
    
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    local distance = #(playerCoords - horseCoords)
    
    if distance > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    -- Check cooldown
    local currentTime = GetGameTimer()
    if currentTime - lastFeed < Config.FeedingCooldown then
        local remaining = math.ceil((Config.FeedingCooldown - (currentTime - lastFeed)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds before feeding again'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    -- Check for required item
    if Config.RequireItems then
        RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:hasItem', function(hasItem)
            if not hasItem then
                lib.notify({ title = 'Horse Training', description = 'You need horse feed!', type = 'error', duration = 3000 })
                return
            end
            DoFeedHorse()
        end, Config.Items.feed)
    else
        DoFeedHorse()
    end
end, false)

function DoFeedHorse()
    local ped = PlayerPedId()
    lastFeed = GetGameTimer()
    
    if lib.progressBar({
        duration = 4000,
        label = 'Feeding horse...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true }
    }) then
        local xp = GetXPAmount(Config.PlayerFeedingXP, Config.TrainerFeedingXP)
        AwardXP(xp, 'Feeding')
        
        if Config.RequireItems then
            TriggerServerEvent('rex-horsetrainer:server:removeItem', Config.Items.feed)
        end
    else
        lib.notify({ title = 'Horse Training', description = 'Cancelled', type = 'error', duration = 2000 })
    end
end

--------------------------------------------------------------------
-- Calm Horse Command
--------------------------------------------------------------------
RegisterCommand('calmhorse', function()
    if not LocalPlayer.state['isLoggedIn'] then return end
    
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    local distance = #(playerCoords - horseCoords)
    
    if distance > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    -- Check cooldown
    local currentTime = GetGameTimer()
    if currentTime - lastCalm < Config.CalmingCooldown then
        local remaining = math.ceil((Config.CalmingCooldown - (currentTime - lastCalm)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds before calming again'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    DoCalmHorse()
end, false)

function DoCalmHorse()
    local ped = PlayerPedId()
    lastCalm = GetGameTimer()
    
    if lib.progressBar({
        duration = 3000,
        label = 'Calming horse...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true }
    }) then
        local xp = GetXPAmount(Config.PlayerCalmingXP, Config.TrainerCalmingXP)
        AwardXP(xp, 'Calming')
    else
        lib.notify({ title = 'Horse Training', description = 'Cancelled', type = 'error', duration = 2000 })
    end
end

--------------------------------------------------------------------
-- Clean Hooves Command
--------------------------------------------------------------------
RegisterCommand('cleanhooves', function()
    if not LocalPlayer.state['isLoggedIn'] then return end
    
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    local distance = #(playerCoords - horseCoords)
    
    if distance > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    local currentTime = GetGameTimer()
    if currentTime - lastHoof < Config.HoofCooldown then
        local remaining = math.ceil((Config.HoofCooldown - (currentTime - lastHoof)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds before cleaning hooves again'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    if Config.RequireItems then
        RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:hasItem', function(hasItem)
            if not hasItem then
                lib.notify({ title = 'Horse Training', description = 'You need a hoof pick!', type = 'error', duration = 3000 })
                return
            end
            DoCleanHooves()
        end, Config.Items.hoofpick)
    else
        DoCleanHooves()
    end
end, false)

function DoCleanHooves()
    local ped = PlayerPedId()
    lastHoof = GetGameTimer()
    
    if lib.progressBar({
        duration = 6000,
        label = 'Cleaning hooves...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true }
    }) then
        local xp = GetXPAmount(Config.PlayerHoofXP, Config.TrainerHoofXP)
        AwardXP(xp, 'Hoof Cleaning')
    else
        lib.notify({ title = 'Horse Training', description = 'Cancelled', type = 'error', duration = 2000 })
    end
end

--------------------------------------------------------------------
-- Water Horse Command
--------------------------------------------------------------------
RegisterCommand('waterhorse', function()
    if not LocalPlayer.state['isLoggedIn'] then return end
    
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    local distance = #(playerCoords - horseCoords)
    
    if distance > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    local currentTime = GetGameTimer()
    if currentTime - lastWater < Config.WateringCooldown then
        local remaining = math.ceil((Config.WateringCooldown - (currentTime - lastWater)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds before watering again'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    if Config.RequireItems then
        RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:hasItem', function(hasItem)
            if not hasItem then
                lib.notify({ title = 'Horse Training', description = 'You need a water bucket!', type = 'error', duration = 3000 })
                return
            end
            DoWaterHorse()
        end, Config.Items.water)
    else
        DoWaterHorse()
    end
end, false)

function DoWaterHorse()
    local ped = PlayerPedId()
    lastWater = GetGameTimer()
    
    if lib.progressBar({
        duration = 4000,
        label = 'Watering horse...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true }
    }) then
        local xp = GetXPAmount(Config.PlayerWateringXP, Config.TrainerWateringXP)
        AwardXP(xp, 'Watering')
        
        if Config.RequireItems then
            TriggerServerEvent('rex-horsetrainer:server:removeItem', Config.Items.water)
        end
    else
        lib.notify({ title = 'Horse Training', description = 'Cancelled', type = 'error', duration = 2000 })
    end
end

--------------------------------------------------------------------
-- Treat Horse Command (Medicine)
--------------------------------------------------------------------
RegisterCommand('treathorse', function()
    if not LocalPlayer.state['isLoggedIn'] then return end
    
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    local distance = #(playerCoords - horseCoords)
    
    if distance > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    local currentTime = GetGameTimer()
    if currentTime - lastTreat < Config.TreatingCooldown then
        local remaining = math.ceil((Config.TreatingCooldown - (currentTime - lastTreat)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds before treating again'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    if Config.RequireItems then
        RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:hasItem', function(hasItem)
            if not hasItem then
                lib.notify({ title = 'Horse Training', description = 'You need horse medicine!', type = 'error', duration = 3000 })
                return
            end
            DoTreatHorse()
        end, Config.Items.medicine)
    else
        DoTreatHorse()
    end
end, false)

function DoTreatHorse()
    local ped = PlayerPedId()
    lastTreat = GetGameTimer()
    
    if lib.progressBar({
        duration = 5000,
        label = 'Treating horse...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true }
    }) then
        local xp = GetXPAmount(Config.PlayerTreatingXP, Config.TrainerTreatingXP)
        AwardXP(xp, 'Treating')
        
        if Config.RequireItems then
            TriggerServerEvent('rex-horsetrainer:server:removeItem', Config.Items.medicine)
        end
    else
        lib.notify({ title = 'Horse Training', description = 'Cancelled', type = 'error', duration = 2000 })
    end
end

--------------------------------------------------------------------
-- Training Menu Command (can be used anywhere)
--------------------------------------------------------------------
RegisterCommand('trainermenu', function()
    if not LocalPlayer.state['isLoggedIn'] then return end
    
    local PlayerData = RSGCore.Functions.GetPlayerData()
    if PlayerData.job.name ~= 'trainer' then
        lib.notify({ title = 'Horse Training', description = 'You are not a horse trainer!', type = 'error', duration = 3000 })
        return
    end
    
    OpenTrainerMenu()
end, false)

--------------------------------------------------------------------
-- Boss Menu
--------------------------------------------------------------------
RegisterCommand('trainerboss', function()
    if not LocalPlayer.state['isLoggedIn'] then return end
    if not Config.BossMenu.enabled then return end
    
    local PlayerData = RSGCore.Functions.GetPlayerData()
    if PlayerData.job.name ~= 'trainer' then
        lib.notify({ title = 'Horse Training', description = 'You are not a horse trainer!', type = 'error', duration = 3000 })
        return
    end
    
    -- Check if player is boss (check both job.isBoss and grade.isBoss)
    local isBoss = PlayerData.job.isBoss or (PlayerData.job.grade and PlayerData.job.grade.isBoss)
    if not isBoss then
        lib.notify({ title = 'Horse Training', description = 'You are not a boss!', type = 'error', duration = 3000 })
        return
    end
    
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - Config.BossMenu.coords)
    
    if distance > 5.0 then
        lib.notify({ title = 'Horse Training', description = 'You must be at the trainer HQ!', type = 'error', duration = 3000 })
        return
    end
    
    -- Open boss menu with job name
    TriggerServerEvent('rsg-bossmenu:server:openMenu', 'trainer')
end, false)

--------------------------------------------------------------------
-- Create Blips
--------------------------------------------------------------------
CreateThread(function()
    for _, location in pairs(Config.TrainerLocations) do
        if location.blip.enabled then
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, location.coords.x, location.coords.y, location.coords.z)
            SetBlipSprite(blip, joaat(location.blip.sprite), true)
            SetBlipScale(blip, 0.2)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, location.blip.label)
        end
    end
    
    -- Boss menu blip
    if Config.BossMenu.enabled and Config.BossMenu.blip.enabled then
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, Config.BossMenu.coords.x, Config.BossMenu.coords.y, Config.BossMenu.coords.z)
        SetBlipSprite(blip, joaat(Config.BossMenu.blip.sprite), true)
        SetBlipScale(blip, 0.25)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, Config.BossMenu.blip.label)
    end
end)

--------------------------------------------------------------------
-- Target/Prompt at Trainer Location (Menu + Boss)
--------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        
        -- Check trainer locations for trainer menu
        for _, location in pairs(Config.TrainerLocations) do
            local distance = #(playerCoords - location.coords)
            
            if distance < 10.0 then
                sleep = 0
                local PlayerData = RSGCore.Functions.GetPlayerData()
                
                if distance < 2.0 and PlayerData.job.name == 'trainer' then
                    -- Show trainer menu prompt
                    DrawText3D(location.coords.x, location.coords.y, location.coords.z + 1.0, '[E] Trainer Menu')
                    
                    if IsControlJustPressed(0, 0xCEFD9220) then -- E key
                        OpenTrainerMenu()
                    end
                end
            end
        end
        
        -- Check boss menu location
        if Config.BossMenu.enabled then
            local bossDistance = #(playerCoords - Config.BossMenu.coords)
            
            if bossDistance < 10.0 then
                sleep = 0
                local PlayerData = RSGCore.Functions.GetPlayerData()
                
                local isBoss = PlayerData.job.isBoss or (PlayerData.job.grade and PlayerData.job.grade.isBoss)
                if bossDistance < 2.0 and PlayerData.job.name == 'trainer' and isBoss then
                    DrawText3D(Config.BossMenu.coords.x, Config.BossMenu.coords.y, Config.BossMenu.coords.z + 1.5, '[G] Boss Menu')
                    
                    if IsControlJustPressed(0, 0x760A9C6F) then -- G key
                        TriggerServerEvent('rsg-bossmenu:server:openMenu', 'trainer')
                    end
                end
            end
        end
        
        Wait(sleep)
    end
end)

--------------------------------------------------------------------
-- Open Trainer Menu Function
--------------------------------------------------------------------
function OpenTrainerMenu()
    -- First check horse XP from server
    RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:GetActiveHorseData', function(data)
        if data then
            cachedHorseXP = data.horsexp or 0
            isHorseFullyTrained = (cachedHorseXP >= Config.MaxHorseXP)
        end
        
        -- Build menu options
        local menuOptions = {}
        
        -- If horse is fully trained, show special message
        if isHorseFullyTrained then
            table.insert(menuOptions, {
                title = 'FULLY TRAINED',
                description = 'This horse has completed all training! (5000/5000 XP)',
                icon = 'trophy',
                iconColor = 'gold',
                disabled = true
            })
        end
        
        table.insert(menuOptions, {
            title = 'Brush Horse',
            description = isHorseFullyTrained and 'Horse is fully trained!' or 'Brush your horse to earn XP (Requires: Horse Brush)',
            icon = 'brush',
            disabled = isHorseFullyTrained,
            onSelect = function()
                StartBrushHorse()
            end
        })
        
        table.insert(menuOptions, {
            title = 'Feed Horse',
            description = isHorseFullyTrained and 'Horse is fully trained!' or 'Feed your horse to earn XP (Requires: Horse Feed)',
            icon = 'wheat-awn',
            disabled = isHorseFullyTrained,
            onSelect = function()
                StartFeedHorse()
            end
        })
        
        table.insert(menuOptions, {
            title = 'Water Horse',
            description = isHorseFullyTrained and 'Horse is fully trained!' or 'Give water to your horse (Requires: Water Bucket)',
            icon = 'droplet',
            disabled = isHorseFullyTrained,
            onSelect = function()
                StartWaterHorse()
            end
        })
        
        table.insert(menuOptions, {
            title = 'Clean Hooves',
            description = isHorseFullyTrained and 'Horse is fully trained!' or 'Clean your horse\'s hooves (Requires: Hoof Pick)',
            icon = 'shoe-prints',
            disabled = isHorseFullyTrained,
            onSelect = function()
                StartCleanHooves()
            end
        })
        
        table.insert(menuOptions, {
            title = 'Treat Horse',
            description = isHorseFullyTrained and 'Horse is fully trained!' or 'Give medicine to your horse (Requires: Horse Medicine)',
            icon = 'kit-medical',
            disabled = isHorseFullyTrained,
            onSelect = function()
                StartTreatHorse()
            end
        })
        
        table.insert(menuOptions, {
            title = 'Calm Horse',
            description = isHorseFullyTrained and 'Horse is fully trained!' or 'Calm your horse to earn XP (No item required)',
            icon = 'hand-holding-heart',
            disabled = isHorseFullyTrained,
            onSelect = function()
                StartCalmHorse()
            end
        })
        
        table.insert(menuOptions, {
            title = 'Check Horse XP',
            description = ('View your horse\'s current XP (%d/%d)'):format(cachedHorseXP, Config.MaxHorseXP),
            icon = 'chart-line',
            onSelect = function()
                TriggerServerEvent('rex-horsetrainer:server:checkxp')
            end
        })
        
        table.insert(menuOptions, {
            title = 'Start Distance Training',
            description = isHorseFullyTrained and 'Horse is fully trained!' or ('Ride %dm to earn %d XP. Must be mounted.'):format(Config.DistanceRiding.targetDistance, Config.DistanceRiding.xpReward),
            icon = 'horse',
            disabled = isHorseFullyTrained,
            onSelect = function()
                CheckDistanceProgress()
            end
        })
        
        local menuTitle = 'Horse Trainer Menu'
        local menuIcon = 'horse-head'
        
        if isHorseFullyTrained then
            menuTitle = 'Horse Trainer Menu (MAXED)'
            menuIcon = 'trophy'
        end
        
        lib.registerContext({
            id = 'trainer_menu',
            title = menuTitle,
            icon = menuIcon,
            menu = 'trainer_menu',
            options = menuOptions
        })
        lib.showContext('trainer_menu')
    end)
end

--------------------------------------------------------------------
-- Start/Check Distance Riding Training
--------------------------------------------------------------------
function CheckDistanceProgress()
    if not Config.DistanceRiding.enabled then
        lib.notify({
            title = 'Distance Riding',
            description = 'Distance riding is disabled',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    -- If training already active, show progress
    if isDistanceTrainingActive then
        local remaining = Config.DistanceRiding.targetDistance - ridingDistance
        local percentage = math.floor((ridingDistance / Config.DistanceRiding.targetDistance) * 100)
        lib.notify({
            title = 'Distance Training Active',
            description = ('Progress: %.0f / %d meters (%d%%)\nUse /canceltraining to cancel.'):format(ridingDistance, Config.DistanceRiding.targetDistance, percentage),
            type = 'info',
            duration = 5000
        })
        return
    end
    
    -- Check if player is mounted
    local ped = PlayerPedId()
    if not IsPedOnMount(ped) then
        lib.notify({
            title = 'Distance Training',
            description = 'You must be mounted on your horse to start!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    -- Start the training
    ridingDistance = 0
    lastRidingPos = nil
    wasMounted = true
    isDistanceTrainingActive = true
    
    lib.notify({
        title = 'Distance Training Started!',
        description = ('Ride %d meters to complete. Don\'t dismount!'):format(Config.DistanceRiding.targetDistance),
        type = 'success',
        duration = 5000
    })
end

--------------------------------------------------------------------
-- Menu Action Functions
--------------------------------------------------------------------
function StartBrushHorse()
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    if #(playerCoords - horseCoords) > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    local currentTime = GetGameTimer()
    if currentTime - lastBrush < Config.BrushingCooldown then
        local remaining = math.ceil((Config.BrushingCooldown - (currentTime - lastBrush)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    if Config.RequireItems then
        RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:hasItem', function(hasItem)
            if not hasItem then
                lib.notify({ title = 'Horse Training', description = 'You need a horse brush!', type = 'error', duration = 3000 })
                return
            end
            DoBrushHorse()
        end, Config.Items.brush)
    else
        DoBrushHorse()
    end
end

function StartFeedHorse()
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    if #(playerCoords - horseCoords) > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    local currentTime = GetGameTimer()
    if currentTime - lastFeed < Config.FeedingCooldown then
        local remaining = math.ceil((Config.FeedingCooldown - (currentTime - lastFeed)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    if Config.RequireItems then
        RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:hasItem', function(hasItem)
            if not hasItem then
                lib.notify({ title = 'Horse Training', description = 'You need horse feed!', type = 'error', duration = 3000 })
                return
            end
            DoFeedHorse()
        end, Config.Items.feed)
    else
        DoFeedHorse()
    end
end

function StartWaterHorse()
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    if #(playerCoords - horseCoords) > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    local currentTime = GetGameTimer()
    if currentTime - lastWater < Config.WateringCooldown then
        local remaining = math.ceil((Config.WateringCooldown - (currentTime - lastWater)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    if Config.RequireItems then
        RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:hasItem', function(hasItem)
            if not hasItem then
                lib.notify({ title = 'Horse Training', description = 'You need a water bucket!', type = 'error', duration = 3000 })
                return
            end
            DoWaterHorse()
        end, Config.Items.water)
    else
        DoWaterHorse()
    end
end

function StartCleanHooves()
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    if #(playerCoords - horseCoords) > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    local currentTime = GetGameTimer()
    if currentTime - lastHoof < Config.HoofCooldown then
        local remaining = math.ceil((Config.HoofCooldown - (currentTime - lastHoof)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    if Config.RequireItems then
        RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:hasItem', function(hasItem)
            if not hasItem then
                lib.notify({ title = 'Horse Training', description = 'You need a hoof pick!', type = 'error', duration = 3000 })
                return
            end
            DoCleanHooves()
        end, Config.Items.hoofpick)
    else
        DoCleanHooves()
    end
end

function StartTreatHorse()
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    if #(playerCoords - horseCoords) > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    local currentTime = GetGameTimer()
    if currentTime - lastTreat < Config.TreatingCooldown then
        local remaining = math.ceil((Config.TreatingCooldown - (currentTime - lastTreat)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    if Config.RequireItems then
        RSGCore.Functions.TriggerCallback('rex-horsetrainer:server:hasItem', function(hasItem)
            if not hasItem then
                lib.notify({ title = 'Horse Training', description = 'You need horse medicine!', type = 'error', duration = 3000 })
                return
            end
            DoTreatHorse()
        end, Config.Items.medicine)
    else
        DoTreatHorse()
    end
end

function StartCalmHorse()
    local ped = PlayerPedId()
    horsePed = GetActiveHorsePed()
    
    if not horsePed or not IsEntityAPed(horsePed) then
        lib.notify({ title = 'Horse Training', description = 'No active horse nearby!', type = 'error', duration = 3000 })
        return
    end
    
    local playerCoords = GetEntityCoords(ped)
    local horseCoords = GetEntityCoords(horsePed)
    if #(playerCoords - horseCoords) > 3.0 then
        lib.notify({ title = 'Horse Training', description = 'Get closer to your horse!', type = 'error', duration = 3000 })
        return
    end
    
    local currentTime = GetGameTimer()
    if currentTime - lastCalm < Config.CalmingCooldown then
        local remaining = math.ceil((Config.CalmingCooldown - (currentTime - lastCalm)) / 1000)
        lib.notify({ title = 'Horse Training', description = ('Wait %d seconds'):format(remaining), type = 'error', duration = 3000 })
        return
    end
    
    DoCalmHorse()
end

--------------------------------------------------------------------
-- Trainer Shop
--------------------------------------------------------------------
RegisterCommand('trainershop', function()
    if not LocalPlayer.state['isLoggedIn'] then return end
    if not Config.TrainerShop.enabled then return end
    
    local PlayerData = RSGCore.Functions.GetPlayerData()
    if PlayerData.job.name ~= Config.TrainerShop.jobName then
        lib.notify({ title = 'Trainer Shop', description = 'Only horse trainers can use this shop!', type = 'error', duration = 3000 })
        return
    end
    
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - Config.TrainerShop.coords)
    
    if distance > 3.0 then
        lib.notify({ title = 'Trainer Shop', description = 'You must be at the shop!', type = 'error', duration = 3000 })
        return
    end
    
    OpenTrainerShop()
end, false)

function OpenTrainerShop()
    local options = {}
    
    for _, item in pairs(Config.TrainerShop.items) do
        table.insert(options, {
            title = item.label,
            description = ('Price: $%d'):format(item.price),
            icon = 'shopping-cart',
            onSelect = function()
                local input = lib.inputDialog('Buy ' .. item.label, {
                    { type = 'number', label = 'Amount', default = 1, min = 1, max = 100 }
                })
                
                if input and input[1] then
                    TriggerServerEvent('rex-horsetrainer:server:buyItem', item.name, input[1])
                end
            end
        })
    end
    
    lib.registerContext({
        id = 'trainer_shop',
        title = 'Trainer Supplies',
        options = options
    })
    lib.showContext('trainer_shop')
end

--------------------------------------------------------------------
-- Shop Blip and Prompt
--------------------------------------------------------------------
CreateThread(function()
    if not Config.TrainerShop.enabled then return end
    
    -- Create shop blip
    if Config.TrainerShop.blip.enabled then
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, Config.TrainerShop.coords.x, Config.TrainerShop.coords.y, Config.TrainerShop.coords.z)
        SetBlipSprite(blip, joaat(Config.TrainerShop.blip.sprite), true)
        SetBlipScale(blip, 0.2)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, Config.TrainerShop.blip.label)
    end
end)

CreateThread(function()
    if not Config.TrainerShop.enabled then return end
    
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local distance = #(playerCoords - Config.TrainerShop.coords)
        
        if distance < 15.0 then
            sleep = 0
            local PlayerData = RSGCore.Functions.GetPlayerData()
            
            if distance < 2.5 then
                if PlayerData.job.name == Config.TrainerShop.jobName then
                    DrawText3D(Config.TrainerShop.coords.x, Config.TrainerShop.coords.y, Config.TrainerShop.coords.z + 1.0, '[E] Trainer Supplies')
                    
                    if IsControlJustPressed(0, 0xCEFD9220) then -- E key
                        OpenTrainerShop()
                    end
                else
                    DrawText3D(Config.TrainerShop.coords.x, Config.TrainerShop.coords.y, Config.TrainerShop.coords.z + 1.0, 'Trainer Supplies (Trainers Only)')
                end
            end
        end
        
        Wait(sleep)
    end
end)

--------------------------------------------------------------------
-- Draw 3D Text Helper
--------------------------------------------------------------------
function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = GetScreenCoordFromWorldCoord(x, y, z)
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFontForCurrentCommand(1)
        SetTextColor(255, 255, 255, 215)
        SetTextCentre(true)
        DisplayText(CreateVarString(10, "LITERAL_STRING", text), _x, _y)
    end
end
