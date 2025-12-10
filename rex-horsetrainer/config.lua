Config = {}

Config.Debug = false

-------------------------
-- RSG-HUD Integration
-------------------------
Config.RSGHud = {
    enabled = true,              -- Enable rsg-hud integration
    showTrainingProgress = true, -- Show distance training progress on HUD
    showHorseXP = true,          -- Show horse XP on HUD
}

-------------------------
-- XP Settings
-------------------------
Config.MaxXPGain = 50
Config.MaxHorseXP = 5000

-------------------------
-- Max Horse Stats (Applied when training complete)
-------------------------
Config.MaxHorseStats = {
    enabled = true,              -- Enable stat boost when fully trained
    health = 100,                -- Max health value (0-100)
    stamina = 100,               -- Max stamina value (0-100)
    speed = 1.3,                 -- Speed multiplier (1.0 = normal, 1.3 = 30% faster)
    acceleration = 1.3,          -- Acceleration multiplier
    applyOnMount = true,         -- Apply stats when mounting trained horse
}

-------------------------
-- Distance Riding XP (Physical Task)
-------------------------
Config.DistanceRiding = {
    enabled = true,
    targetDistance = 3000,      -- Target distance in meters
    xpReward = 1500,            -- XP reward for completing target
    checkInterval = 1000,       -- Check distance every 1 second
    minSpeed = 3,               -- Minimum speed to count distance
}

-------------------------
-- Riding XP (Time-based - disabled if distance riding enabled)
-------------------------
Config.PlayerRidingXP = 5
Config.TrainerRidingXP = 10
Config.RidingWait = 30000

-------------------------
-- Leading XP
-------------------------
Config.PlayerLeadingXP = 10
Config.TrainerLeadingXP = 20
Config.LeadingWait = 20000

-------------------------
-- Task XP Caps (Max XP earnable from each task type)
-------------------------
Config.TaskXPCaps = {
    brushing = 500,             -- Max 500 XP from brushing
    feeding = 500,              -- Max 500 XP from feeding
    watering = 500,             -- Max 500 XP from watering
    hoofcleaning = 500,         -- Max 500 XP from hoof cleaning
    treating = 500,             -- Max 500 XP from treating
    calming = 500,              -- Max 500 XP from calming
    riding = 1500,              -- Max 1500 XP from distance riding
    leading = 1000,             -- Max 1000 XP from leading
}

-------------------------
-- Brushing XP
-------------------------
Config.PlayerBrushingXP = 15
Config.TrainerBrushingXP = 25
Config.BrushingCooldown = 60000 -- 1 minute cooldown

-------------------------
-- Feeding XP
-------------------------
Config.PlayerFeedingXP = 12
Config.TrainerFeedingXP = 20
Config.FeedingCooldown = 60000 -- 1 minute cooldown

-------------------------
-- Calming XP
-------------------------
Config.PlayerCalmingXP = 8
Config.TrainerCalmingXP = 15
Config.CalmingCooldown = 30000 -- 30 second cooldown

-------------------------
-- Hoof Cleaning XP
-------------------------
Config.PlayerHoofXP = 18
Config.TrainerHoofXP = 30
Config.HoofCooldown = 90000 -- 1.5 minute cooldown

-------------------------
-- Watering XP
-------------------------
Config.PlayerWateringXP = 10
Config.TrainerWateringXP = 18
Config.WateringCooldown = 60000 -- 1 minute cooldown

-------------------------
-- Treating XP (Medicine)
-------------------------
Config.PlayerTreatingXP = 20
Config.TrainerTreatingXP = 35
Config.TreatingCooldown = 120000 -- 2 minute cooldown

-------------------------
-- Boss Management
-------------------------
Config.BossMenu = {
    enabled = true,
    jobName = 'trainer',
    coords = vector3(-877.7722, -1370.1595, 43.5261),
    heading = 297.5206,
    blip = {
        enabled = true,
        sprite = 'blip_horse_owned',
        label = 'Horse Trainer HQ'
    }
}

-------------------------
-- Trainer Locations (Trainer Menu)
-------------------------
Config.TrainerLocations = {
    {
        name = 'blackwater',
        label = 'Blackwater Stables',
        coords = vector3(-877.7722, -1370.1595, 43.5261),
        heading = 297.5206,
        blip = {
            enabled = true,
            sprite = 'blip_horse_owned',
            label = 'Blackwater Horse Trainer'
        }
    }
}

-------------------------
-- Required Items
-------------------------
Config.RequireItems = true -- Requires items for tasks
Config.Items = {
    brush = 'horsebrush',
    feed = 'horsefeed',
    water = 'horsewaterbucket',
    hoofpick = 'hoofpick',
    medicine = 'horsemedicine'
}

-------------------------
-- Stable Script Integration
-------------------------
Config.StableScript = 'QC-Stables' -- Options: 'QC-Stables', 'rsg-horses'
Config.StableDatabase = {
    tableName = 'player_horses',    -- Database table name
    citizenidColumn = 'citizenid',  -- Column for citizen ID
    activeColumn = 'selected',      -- Column for active status (1 = selected/active)
    xpColumn = 'xp',                -- Column for horse XP
    nameColumn = 'name'             -- Column for horse name
}

-------------------------
-- Trainer Shop (Job Restricted)
-------------------------
Config.TrainerShop = {
    enabled = true,
    jobName = 'trainer',
    coords = vector3(-877.8484, -1365.5051, 43.5294),
    heading = 263.9081,
    blip = {
        enabled = true,
        sprite = 'blip_shop',
        label = 'Trainer Supplies'
    },
    items = {
        { name = 'horsebrush',       label = 'Horse Brush',    price = 5 },
        { name = 'horsefeed',        label = 'Horse Feed',     price = 3 },
        { name = 'horsewaterbucket', label = 'Water Bucket',   price = 2 },
        { name = 'hoofpick',         label = 'Hoof Pick',      price = 8 },
        { name = 'horsemedicine',    label = 'Horse Medicine', price = 15 }
    }
}
