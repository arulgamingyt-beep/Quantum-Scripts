local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

-- Task XP tracking per horse (horseId -> { taskType -> xpEarned })
local HorseTaskXP = {}

-- Track horse XP to re-apply if QC-Stables overwrites it
local TrackedHorseXP = {}

-- Database helper functions
local function GetDBTable()
    return Config.StableDatabase.tableName
end

local function GetDBColumns()
    return Config.StableDatabase
end

-- Get task XP cap
local function GetTaskXPCap(taskType)
    local taskKey = string.lower(taskType)
    if Config.TaskXPCaps and Config.TaskXPCaps[taskKey] then
        return Config.TaskXPCaps[taskKey]
    end
    return Config.MaxHorseXP -- No cap if not defined
end

-- Get current task XP for horse
local function GetHorseTaskXP(horseId, taskType)
    if not HorseTaskXP[horseId] then
        HorseTaskXP[horseId] = {}
    end
    return HorseTaskXP[horseId][taskType] or 0
end

-- Add task XP for horse
local function AddHorseTaskXP(horseId, taskType, amount)
    if not HorseTaskXP[horseId] then
        HorseTaskXP[horseId] = {}
    end
    HorseTaskXP[horseId][taskType] = (HorseTaskXP[horseId][taskType] or 0) + amount
end

-------------------------------------
-- Sync Horse XP with QC-Stables cache
-------------------------------------
function SyncHorseXPWithStables(src, horseId, newXP)
    -- Track the XP we set so we can verify/restore it
    TrackedHorseXP[horseId] = newXP
    
    -- Try to update QC-Stables internal cache
    pcall(function()
        TriggerEvent('QC-Stables:server:UpdateHorseXP', horseId, newXP)
    end)
    
    pcall(function()
        exports['QC-Stables']:UpdateHorseXP(horseId, newXP)
    end)
    
    pcall(function()
        exports['QC-Stables']:RefreshHorseData(horseId)
    end)
    
    -- Trigger client to refresh
    if src then
        TriggerClientEvent('rex-horsetrainer:client:syncHorseXP', src, horseId, newXP)
    end
    
    print(('^3[rex-horsetrainer] DEBUG: Synced XP with stables - Horse ID: %d, XP: %d^7'):format(horseId, newXP))
end

-------------------------------------
-- Verify and restore XP if overwritten
-------------------------------------
function VerifyHorseXP(horseId)
    local trackedXP = TrackedHorseXP[horseId]
    if not trackedXP then return end
    
    local db = GetDBColumns()
    local query = string.format('SELECT %s as xp FROM %s WHERE id = ?', db.xpColumn, db.tableName)
    local result = MySQL.query.await(query, { horseId })
    
    if result and result[1] then
        local currentXP = result[1].xp or 0
        if currentXP < trackedXP then
            print(('^1[rex-horsetrainer] WARNING: Horse ID %d XP was overwritten! DB: %d, Should be: %d. Restoring...^7'):format(horseId, currentXP, trackedXP))
            local updateQuery = string.format('UPDATE %s SET %s = ? WHERE id = ?', db.tableName, db.xpColumn)
            MySQL.update.await(updateQuery, { trackedXP, horseId })
            print(('^2[rex-horsetrainer] SUCCESS: Restored XP for horse ID %d to %d^7'):format(horseId, trackedXP))
        end
    end
end

-- Periodic XP verification (every 30 seconds)
CreateThread(function()
    while true do
        Wait(30000)
        for horseId, xp in pairs(TrackedHorseXP) do
            VerifyHorseXP(horseId)
        end
    end
end)

-------------------------------------
-- Apply Max Stats when fully trained
-------------------------------------
function ApplyMaxHorseStats(citizenid, src)
    if not Config.MaxHorseStats or not Config.MaxHorseStats.enabled then return end
    
    local db = GetDBColumns()
    local maxHealth = Config.MaxHorseStats.health or 100
    local maxStamina = Config.MaxHorseStats.stamina or 100
    
    -- First get the horse ID for reliable update
    local getIdQuery = string.format('SELECT id FROM %s WHERE %s = ? AND %s = 1 LIMIT 1', db.tableName, db.citizenidColumn, db.activeColumn)
    local result = MySQL.query.await(getIdQuery, { citizenid })
    
    if not result or not result[1] then
        print(('^1[rex-horsetrainer] ERROR: Could not find active horse for citizen %s^7'):format(citizenid))
        return
    end
    
    local horseId = result[1].id
    
    -- Update health and stamina using horse ID
    local updateQuery = string.format('UPDATE %s SET health = ?, stamina = ? WHERE id = ?', db.tableName)
    local affected = MySQL.update.await(updateQuery, { maxHealth, maxStamina, horseId })
    
    if affected > 0 then
        print(('^2[rex-horsetrainer] SUCCESS: Max stats applied for horse ID %d (Health: %d, Stamina: %d)^7'):format(horseId, maxHealth, maxStamina))
        
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Fully Trained!',
            description = 'Your horse is now a champion! Stats maxed out!',
            type = 'success',
            duration = 8000
        })
        
        -- Trigger QC-Stables refresh if available
        TriggerClientEvent('rex-horsetrainer:client:refreshHorseStats', src)
    end
end

-------------------------------------
-- Get Active Horse Data Callback
-------------------------------------
RSGCore.Functions.CreateCallback('rex-horsetrainer:server:GetActiveHorseData', function(source, cb)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then
        cb(nil)
        return
    end
    
    local citizenid = Player.PlayerData.citizenid
    local db = GetDBColumns()
    
    local query = string.format(
        'SELECT %s as horsexp, %s as name FROM %s WHERE %s = ? AND %s = 1 LIMIT 1',
        db.xpColumn, db.nameColumn, db.tableName, db.citizenidColumn, db.activeColumn
    )
    
    local result = MySQL.query.await(query, { citizenid })
    
    if result and result[1] then
        cb({ horsexp = result[1].horsexp or 0, name = result[1].name })
    else
        cb(nil)
    end
end)

-------------------------------------
-- Update horse XP
-------------------------------------
RegisterNetEvent('rex-horsetrainer:server:updatexp', function(amount, taskName)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then
        print(('^1[rex-horsetrainer] ERROR: Player object not found for source %s^7'):format(src))
        return
    end
    
    if not Player.PlayerData.citizenid then
        print(('^1[rex-horsetrainer] ERROR: CitizenID not found for source %s^7'):format(src))
        return
    end

    local citizenid = Player.PlayerData.citizenid
    local db = GetDBColumns()
    taskName = taskName or 'Training'
    
    if Config.Debug then
        print(('^3[rex-horsetrainer] DEBUG: XP update received - Player: %s, Amount: %s, Task: %s^7'):format(citizenid, tostring(amount), taskName))
    end

    -- Check valid amount
    if type(amount) ~= 'number' or amount <= 0 or amount > Config.MaxXPGain then
        print(('^1[rex-horsetrainer] WARNING: Invalid XP amount (%s) from player %s^7'):format(tostring(amount), src))
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = 'Invalid XP amount',
            type = 'error',
            duration = 5000
        })
        return
    end

    -- Check if player has any horses at all
    local checkQuery = string.format('SELECT id, %s FROM %s WHERE %s = ?', db.activeColumn, db.tableName, db.citizenidColumn)
    local playerHorses = MySQL.query.await(checkQuery, { citizenid })
    
    if not playerHorses or #playerHorses == 0 then
        print(('^1[rex-horsetrainer] ERROR: No horses found for citizen %s^7'):format(citizenid))
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = 'No horses found!',
            type = 'error',
            duration = 5000
        })
        return
    end

    -- Check if an active horse exists
    local activeQuery = string.format('SELECT id, %s as horsexp, %s as name FROM %s WHERE %s = ? AND %s = 1 LIMIT 1', db.xpColumn, db.nameColumn, db.tableName, db.citizenidColumn, db.activeColumn)
    local activeHorse = MySQL.query.await(activeQuery, { citizenid })
    
    if not activeHorse or not activeHorse[1] then
        print(('^3[rex-horsetrainer] WARNING: No active horse for citizen %s. Available horses: %d^7'):format(citizenid, #playerHorses))
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = 'No active horse!',
            type = 'error',
            duration = 5000
        })
        return
    end

    if Config.Debug then
        print(('^3[rex-horsetrainer] DEBUG: Active horse found - Current XP: %d^7'):format(activeHorse[1].horsexp or 0))
    end

    local horseId = activeHorse[1].id
    
    -- Check task XP cap
    local taskKey = string.lower(taskName:gsub(' ', ''))
    local taskCap = GetTaskXPCap(taskKey)
    local currentTaskXP = GetHorseTaskXP(horseId, taskKey)
    
    if currentTaskXP >= taskCap then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = ('Max XP reached for %s! (%d/%d)'):format(taskName, currentTaskXP, taskCap),
            type = 'info',
            duration = 5000
        })
        return
    end
    
    -- Calculate actual XP to add (don't exceed cap)
    local remainingCap = taskCap - currentTaskXP
    local actualAmount = math.min(amount, remainingCap)
    local currentXP = activeHorse[1].horsexp or 0
    local newXPValue = math.min(currentXP + actualAmount, Config.MaxHorseXP)

    -- Update XP using horse ID directly (more reliable)
    local updateQuery = string.format('UPDATE %s SET %s = ? WHERE id = ?', db.tableName, db.xpColumn)
    local affected = MySQL.update.await(updateQuery, { newXPValue, horseId })

    if not affected or affected == 0 then
        print(('^1[rex-horsetrainer] ERROR: XP update failed - no rows affected for horse ID %d^7'):format(horseId))
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = 'Failed to update XP',
            type = 'error',
            duration = 5000
        })
        return
    end

    -- Track task XP
    AddHorseTaskXP(horseId, taskKey, actualAmount)
    
    -- Sync with QC-Stables to prevent data overwrite
    SyncHorseXPWithStables(src, horseId, newXPValue)
    
    -- Update client cached XP
    TriggerClientEvent('rex-horsetrainer:client:updateCachedXP', src, newXPValue)
    
    print(('^2[rex-horsetrainer] SUCCESS: XP updated - Horse ID: %d, New XP: %d (+%d, Task: %s %d/%d)^7'):format(horseId, newXPValue, actualAmount, taskKey, GetHorseTaskXP(horseId, taskKey), taskCap))
    
    local taskXPNow = GetHorseTaskXP(horseId, taskKey)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Horse Training',
        description = ('%s +%d XP! (Total: %d/%d, Task: %d/%d)'):format(taskName, actualAmount, newXPValue, Config.MaxHorseXP, taskXPNow, taskCap),
        type = 'success',
        duration = 5000
    })
    
    -- Check if horse is fully trained and apply max stats
    if newXPValue >= Config.MaxHorseXP then
        ApplyMaxHorseStatsById(horseId, src)
    end
end)

-------------------------------------
-- Complete Distance Riding
-------------------------------------
RegisterNetEvent('rex-horsetrainer:server:completeDistanceRiding', function(distance)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then 
        print('^1[rex-horsetrainer] ERROR: Player not found for distance riding^7')
        return 
    end
    
    local citizenid = Player.PlayerData.citizenid
    local db = GetDBColumns()
    
    print(('^3[rex-horsetrainer] DEBUG: Distance riding complete - Citizen: %s, Distance: %.2f, Target: %d^7'):format(citizenid, distance or 0, Config.DistanceRiding.targetDistance))
    
    -- Verify distance (allow small tolerance for floating point)
    if type(distance) ~= 'number' then
        print('^1[rex-horsetrainer] ERROR: Distance is not a number^7')
        return
    end
    
    -- Allow 10 meter tolerance for floating point issues
    if distance < (Config.DistanceRiding.targetDistance - 10) then
        print(('^1[rex-horsetrainer] ERROR: Distance %.2f is less than target %d^7'):format(distance, Config.DistanceRiding.targetDistance))
        return
    end
    
    -- Get active horse
    local activeQuery = string.format('SELECT id, %s as horsexp FROM %s WHERE %s = ? AND %s = 1 LIMIT 1', db.xpColumn, db.tableName, db.citizenidColumn, db.activeColumn)
    local activeHorse = MySQL.query.await(activeQuery, { citizenid })
    
    if not activeHorse or not activeHorse[1] then
        print(('^1[rex-horsetrainer] ERROR: No active horse found for citizen %s^7'):format(citizenid))
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = 'No active horse found!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    local horseId = activeHorse[1].id
    local currentXP = activeHorse[1].horsexp or 0
    local taskKey = 'riding'
    local taskCap = GetTaskXPCap(taskKey)
    local currentTaskXP = GetHorseTaskXP(horseId, taskKey)
    
    print(('^3[rex-horsetrainer] DEBUG: Horse ID: %d, Current XP: %d, Task XP: %d/%d^7'):format(horseId, currentXP, currentTaskXP, taskCap))
    
    if currentTaskXP >= taskCap then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = ('Max riding XP reached! (%d/%d)'):format(currentTaskXP, taskCap),
            type = 'info',
            duration = 5000
        })
        -- Still reset distance so player can ride again
        TriggerClientEvent('rex-horsetrainer:client:resetDistance', src)
        return
    end
    
    local xpReward = Config.DistanceRiding.xpReward
    local remainingCap = taskCap - currentTaskXP
    local actualAmount = math.min(xpReward, remainingCap)
    
    -- Update XP using horse ID directly (more reliable)
    local newXPValue = math.min(currentXP + actualAmount, Config.MaxHorseXP)
    local updateQuery = string.format('UPDATE %s SET %s = ? WHERE id = ?', db.tableName, db.xpColumn)
    
    print(('^3[rex-horsetrainer] DEBUG: Updating XP - Query: %s, Values: %d, %d^7'):format(updateQuery, newXPValue, horseId))
    
    local affected = MySQL.update.await(updateQuery, { newXPValue, horseId })
    
    print(('^3[rex-horsetrainer] DEBUG: Rows affected: %d^7'):format(affected or 0))
    
    if affected and affected > 0 then
        AddHorseTaskXP(horseId, taskKey, actualAmount)
        
        print(('^2[rex-horsetrainer] SUCCESS: Distance riding XP updated - Horse ID: %d, New XP: %d^7'):format(horseId, newXPValue))
        
        -- Sync with QC-Stables to prevent data overwrite
        SyncHorseXPWithStables(src, horseId, newXPValue)
        
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Distance Riding Complete!',
            description = ('+%d XP! (Total: %d/%d)'):format(actualAmount, newXPValue, Config.MaxHorseXP),
            type = 'success',
            duration = 7000
        })
        
        -- Reset client distance tracker with new XP value
        TriggerClientEvent('rex-horsetrainer:client:resetDistance', src, newXPValue)
        
        -- Check if horse is fully trained and apply max stats
        if newXPValue >= Config.MaxHorseXP then
            ApplyMaxHorseStatsById(horseId, src)
        end
    else
        print('^1[rex-horsetrainer] ERROR: Failed to update distance riding XP^7')
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = 'Failed to update XP!',
            type = 'error',
            duration = 3000
        })
    end
end)

-------------------------------------
-- Check Horse XP
-------------------------------------
RegisterNetEvent('rex-horsetrainer:server:checkxp', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    local db = GetDBColumns()
    
    local query = string.format('SELECT %s as name, %s as horsexp FROM %s WHERE %s = ? AND %s = 1 LIMIT 1', db.nameColumn, db.xpColumn, db.tableName, db.citizenidColumn, db.activeColumn)
    local result = MySQL.query.await(query, { citizenid })
    
    if not result or not result[1] then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = 'No active horse found!',
            type = 'error',
            duration = 5000
        })
        return
    end
    
    local horseName = result[1].name or 'Your Horse'
    local horseXP = result[1].horsexp or 0
    local percentage = math.floor((horseXP / Config.MaxHorseXP) * 100)
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = horseName,
        description = ('XP: %d/%d (%d%%)'):format(horseXP, Config.MaxHorseXP, percentage),
        type = 'info',
        duration = 7000
    })
end)

-------------------------------------
-- Check if player has item
-------------------------------------
RSGCore.Functions.CreateCallback('rex-horsetrainer:server:hasItem', function(source, cb, itemName)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then
        cb(false)
        return
    end
    
    local item = Player.Functions.GetItemByName(itemName)
    cb(item and item.amount > 0)
end)

-------------------------------------
-- Remove item from player
-------------------------------------
RegisterNetEvent('rex-horsetrainer:server:removeItem', function(itemName)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    Player.Functions.RemoveItem(itemName, 1)
    TriggerClientEvent('inventory:client:ItemBox', src, RSGCore.Shared.Items[itemName], 'remove')
end)

-------------------------------------
-- Buy item from trainer shop
-------------------------------------
RegisterNetEvent('rex-horsetrainer:server:buyItem', function(itemName, amount)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    -- Check if player has trainer job
    if Player.PlayerData.job.name ~= Config.TrainerShop.jobName then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Trainer Shop',
            description = 'Only trainers can buy from this shop!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    -- Validate amount
    amount = tonumber(amount)
    if not amount or amount < 1 or amount > 100 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Trainer Shop',
            description = 'Invalid amount!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    -- Find item in shop config
    local shopItem = nil
    for _, item in pairs(Config.TrainerShop.items) do
        if item.name == itemName then
            shopItem = item
            break
        end
    end
    
    if not shopItem then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Trainer Shop',
            description = 'Item not found!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    local totalPrice = shopItem.price * amount
    local playerMoney = Player.Functions.GetMoney('cash')
    
    if playerMoney < totalPrice then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Trainer Shop',
            description = ('Not enough cash! Need $%d'):format(totalPrice),
            type = 'error',
            duration = 3000
        })
        return
    end
    
    -- Check if item exists in shared items
    local itemInfo = RSGCore.Shared.Items[itemName]
    if not itemInfo then
        print(('^1[rex-horsetrainer] ERROR: Item %s not found in RSGCore.Shared.Items - Please add it to rsg-core/shared/items.lua^7'):format(itemName))
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Trainer Shop',
            description = 'Item not configured in server!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    -- Process purchase
    if Player.Functions.RemoveMoney('cash', totalPrice, 'trainer-shop-purchase') then
        local success = Player.Functions.AddItem(itemName, amount)
        
        if success then
            -- Trigger inventory update
            TriggerClientEvent('rsg-inventory:client:ItemBox', src, itemInfo, 'add', amount)
            
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Trainer Shop',
                description = ('Bought %dx %s for $%d'):format(amount, shopItem.label, totalPrice),
                type = 'success',
                duration = 3000
            })
            
            if Config.Debug then
                print(('^2[rex-horsetrainer] Shop purchase: %s bought %dx %s for $%d^7'):format(Player.PlayerData.citizenid, amount, itemName, totalPrice))
            end
        else
            -- Refund if item add failed
            Player.Functions.AddMoney('cash', totalPrice, 'trainer-shop-refund')
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Trainer Shop',
                description = 'Failed to add item! Inventory full?',
                type = 'error',
                duration = 3000
            })
        end
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Trainer Shop',
            description = 'Payment failed!',
            type = 'error',
            duration = 3000
        })
    end
end)

-------------------------------------
-- Admin Command: Max Horse XP by Player ID
-------------------------------------
RegisterCommand('maxhorsexp', function(source, args, rawCommand)
    local src = source
    local targetPlayerId = tonumber(args[1])
    
    -- Console command (src = 0)
    if src == 0 then
        if not targetPlayerId then
            print('^1[rex-horsetrainer] Usage: maxhorsexp [playerID]^7')
            return
        end
        
        local TargetPlayer = RSGCore.Functions.GetPlayer(targetPlayerId)
        if not TargetPlayer then
            print('^1[rex-horsetrainer] Player not found or offline!^7')
            return
        end
        
        MaxHorseXPByPlayer(TargetPlayer, targetPlayerId, nil)
        return
    end
    
    -- In-game command - check admin permission
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Check if player is admin
    if not RSGCore.Functions.HasPermission(src, 'admin') and not RSGCore.Functions.HasPermission(src, 'god') then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = 'You do not have permission!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    -- If no target specified, max own horse
    if not targetPlayerId then
        MaxHorseXPByPlayer(Player, src, src)
        return
    end
    
    -- Max target player's horse
    local TargetPlayer = RSGCore.Functions.GetPlayer(targetPlayerId)
    if not TargetPlayer then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Training',
            description = 'Player not found or offline!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    MaxHorseXPByPlayer(TargetPlayer, targetPlayerId, src)
end, false)

-------------------------------------
-- Max Horse XP by Player ID
-------------------------------------
function MaxHorseXPByPlayer(TargetPlayer, targetSrc, adminSrc)
    local db = GetDBColumns()
    local citizenid = TargetPlayer.PlayerData.citizenid
    local targetName = TargetPlayer.PlayerData.charinfo.firstname .. ' ' .. TargetPlayer.PlayerData.charinfo.lastname
    
    -- Get player's active horse
    local activeQuery = string.format('SELECT id, %s as currentXP, %s as name FROM %s WHERE %s = ? AND %s = 1 LIMIT 1', 
        db.xpColumn, db.nameColumn, db.tableName, db.citizenidColumn, db.activeColumn)
    local horse = MySQL.query.await(activeQuery, { citizenid })
    
    if not horse or not horse[1] then
        print(('^1[rex-horsetrainer] ERROR: No active horse found for player %s^7'):format(targetName))
        if adminSrc then
            TriggerClientEvent('ox_lib:notify', adminSrc, {
                title = 'Horse Training',
                description = ('Player %s has no active horse!'):format(targetName),
                type = 'error',
                duration = 3000
            })
        end
        return
    end
    
    local horseId = horse[1].id
    local horseName = horse[1].name or 'Unknown'
    local currentXP = horse[1].currentXP or 0
    
    -- Check if already maxed
    if currentXP >= Config.MaxHorseXP then
        print(('^3[rex-horsetrainer] INFO: Horse "%s" is already fully trained^7'):format(horseName))
        if adminSrc then
            TriggerClientEvent('ox_lib:notify', adminSrc, {
                title = 'Horse Training',
                description = ('Horse "%s" is already fully trained!'):format(horseName),
                type = 'info',
                duration = 3000
            })
        end
        return
    end
    
    print(('^3[rex-horsetrainer] DEBUG: Found horse "%s" (ID: %d) for player %s with XP: %d^7'):format(horseName, horseId, targetName, currentXP))
    
    -- Update XP to max
    local updateQuery = string.format('UPDATE %s SET %s = ? WHERE id = ?', db.tableName, db.xpColumn)
    local affected = MySQL.update.await(updateQuery, { Config.MaxHorseXP, horseId })
    
    if affected > 0 then
        -- Track the XP to prevent overwrite
        TrackedHorseXP[horseId] = Config.MaxHorseXP
        
        print(('^2[rex-horsetrainer] SUCCESS: Maxed XP for horse "%s" (Player: %s) to %d^7'):format(horseName, targetName, Config.MaxHorseXP))
        
        if adminSrc then
            TriggerClientEvent('ox_lib:notify', adminSrc, {
                title = 'Admin',
                description = ('Maxed XP for %s\'s horse "%s" to %d'):format(targetName, horseName, Config.MaxHorseXP),
                type = 'success',
                duration = 5000
            })
        end
        
        -- Sync with QC-Stables
        SyncHorseXPWithStables(targetSrc, horseId, Config.MaxHorseXP)
        
        -- Apply max stats
        ApplyMaxHorseStatsById(horseId, targetSrc)
        
        -- Notify the target player
        TriggerClientEvent('ox_lib:notify', targetSrc, {
            title = 'Horse Training',
            description = ('Your horse "%s" has been fully trained!'):format(horseName),
            type = 'success',
            duration = 5000
        })
        
        -- Update their client state
        TriggerClientEvent('rex-horsetrainer:client:setHorseFullyTrained', targetSrc, true)
    else
        print(('^1[rex-horsetrainer] ERROR: Failed to update XP for horse ID %d^7'):format(horseId))
        if adminSrc then
            TriggerClientEvent('ox_lib:notify', adminSrc, {
                title = 'Horse Training',
                description = 'Failed to update XP!',
                type = 'error',
                duration = 3000
            })
        end
    end
end

-- Apply max stats by horse ID (more reliable)
function ApplyMaxHorseStatsById(horseId, src)
    if not Config.MaxHorseStats or not Config.MaxHorseStats.enabled then return end
    
    local db = GetDBColumns()
    local maxHealth = Config.MaxHorseStats.health or 100
    local maxStamina = Config.MaxHorseStats.stamina or 100
    
    local updateQuery = string.format('UPDATE %s SET health = ?, stamina = ? WHERE id = ?', db.tableName)
    local affected = MySQL.update.await(updateQuery, { maxHealth, maxStamina, horseId })
    
    if affected > 0 then
        print(('^2[rex-horsetrainer] SUCCESS: Max stats applied for horse ID %d^7'):format(horseId))
        
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Fully Trained!',
            description = 'Your horse is now a champion! Stats maxed out!',
            type = 'success',
            duration = 8000
        })
        
        TriggerClientEvent('rex-horsetrainer:client:refreshHorseStats', src)
    end
end
