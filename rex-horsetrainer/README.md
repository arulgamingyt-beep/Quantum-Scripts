# rex-horsetrainer

A RedM horse training XP system that rewards players for riding and leading horses. This resource is designed for Red Dead Redemption 2 RedM servers and integrates seamlessly with RSG-Core and ox_lib.

## Features

### 🐴 Horse Experience System
- **Riding XP**: Earn XP while riding your horse at speed
- **Leading XP**: Earn XP while leading your horse on foot
- **Dual Reward Tracking**: Different XP amounts for players and trainers
- **Configurable XP Gains**: Customize XP amounts and wait times per activity

### 💼 Job Integration
- Multi-location horse trainer jobs (Valentine, Rhodes, Blackwater, Strawberry, Saint Denis)
- Job hierarchy with three grades: Recruit, Horse Trainer, Master Trainer
- Boss management capabilities for Master Trainers
- Customizable job payments per grade

### ⚙️ Configuration
- Adjustable XP multipliers for riding and leading
- Configurable wait times between XP awards
- Debug mode for development and troubleshooting
- Localized strings for multi-language support

### 🛡️ Safety & Validation
- Server-side validation of XP amounts
- Horse ownership verification
- Active horse tracking and validation
- Error logging for debugging issues

### 📊 Database Integration
- MySQL integration via ox_mysql
- Player horse tracking
- XP progression persistence
- Horse level management

## Requirements

- **Framework**: RSG-Core (Red Dead Redemption 2 RedM)
- **Libraries**: 
  - `ox_lib` - Notification and library functions
  - `oxmysql` - Database operations
  - `rsg-horses` - Horse management system
- **Game**: Red Dead Redemption 2 (RedM)
- **Lua**: 5.4+

## Installation

### Step 1: Download the Resource
1. Clone or download the `rex-horsetrainer` resource
2. Place it in your server's `resources` folder

### Step 2: Update Server Configuration
Add the resource to your `server.cfg`:
```
ensure rex-horsetrainer
```

**Ensure dependencies load first**:
```
ensure oxmysql
ensure ox_lib
ensure rsg-core
ensure rsg-horses
ensure rex-horsetrainer
```

### Step 3: Configure the Resource
Edit `config.lua` to customize:

```lua
Config.Debug = false  -- Enable for detailed logging

-- Riding XP Configuration
Config.PlayerRidingXP = 5      -- XP given to players while riding
Config.TrainerRidingXP = 10    -- XP given to trainers while riding
Config.RidingWait = 30000      -- Milliseconds between XP awards (riding)

-- Leading XP Configuration
Config.PlayerLeadingXP = 10    -- XP given to players while leading
Config.TrainerLeadingXP = 10   -- XP given to trainers while leading
Config.LeadingWait = 20000     -- Milliseconds between XP awards (leading)
```

### Step 4: Add Job Configuration (Optional)
If using shared jobs system, add the following to your `shared_jobs.lua`:

```lua
valhorsetrainer = {
    label = 'Valentine Horse Trainer',
    type = 'horsetrainer',
    defaultDuty = false,
    offDutyPay = false,
    grades = {
        ['0'] = { name = 'Recruit', payment = 5 },
        ['1'] = { name = 'Horse Trainer', payment = 10 },
        ['2'] = { name = 'Master Trainer', isboss = true, payment = 15 },
    },
},
rhohorsetrainer = {
    label = 'Rhodes Horse Trainer',
    type = 'horsetrainer',
    defaultDuty = false,
    offDutyPay = false,
    grades = {
        ['0'] = { name = 'Recruit', payment = 5 },
        ['1'] = { name = 'Horse Trainer', payment = 10 },
        ['2'] = { name = 'Master Trainer', isboss = true, payment = 15 },
    },
},
-- Add more locations as needed
```

Included locations:
- **Valentine** - `valhorsetrainer`
- **Rhodes** - `rhohorsetrainer`
- **Blackwater** - `blkhorsetrainer`
- **Strawberry** - `strhorsetrainer`
- **Saint Denis** - `stdenhorsetrainer`

### Step 5: Start the Resource
Restart your server or use the console command:
```
refresh && ensure rex-horsetrainer
```

Verify it loaded with:
```
status rex-horsetrainer
```

## How It Works

### Riding XP
- Players earn XP when mounted on an active horse
- Horse must be moving at speed > 5 (not idle)
- XP awarded at configured intervals (default: 30 seconds)
- Job type affects XP amount (trainers earn more than civilians)

### Leading XP
- Players earn XP while leading a horse on foot
- Requires proximity to the horse
- XP awarded at configured intervals (default: 20 seconds)
- Same job-based differentiation as riding

### XP Progression
- Each horse has an XP pool (max 5000)
- When XP reaches 5000, horse advances to next level
- Level progression resets XP to 0
- XP data persists in database

### Notifications
- Players receive XP gain notifications via ox_lib
- Notifications include XP amount and current progress
- Level-up announcements when milestones are reached

## Troubleshooting

### Resource won't start
- Verify all dependencies are present and loading first
- Check `server.cfg` for proper resource order
- Review console logs for missing exports

### No XP being awarded
- Ensure horse is moving (speed > 5)
- Verify player owns the horse in database
- Check `Config.Debug = true` for detailed logging
- Confirm RSG-Core is properly initialized

### Database errors
- Verify oxmysql is running and database connection is valid
- Check that `player_horses` table exists with proper schema
- Review MySQL error logs

### Notifications not appearing
- Confirm ox_lib is loaded before rex-horsetrainer
- Check that locale files are properly configured

## Configuration Tips

### For Hardcore Servers
```lua
Config.PlayerRidingXP = 8
Config.PlayerLeadingXP = 15
Config.RidingWait = 60000    -- 1 minute
Config.LeadingWait = 45000   -- 45 seconds
```

### For Casual Servers
```lua
Config.PlayerRidingXP = 2
Config.TrainerRidingXP = 5
Config.RidingWait = 15000    -- 15 seconds
```

### For Testing/Debug
```lua
Config.Debug = true
Config.PlayerRidingXP = 50   -- High XP for quick testing
Config.RidingWait = 5000     -- Quick intervals
Config.LeadingWait = 5000
```

## Support

For issues, bug reports, or feature requests, please check your server logs for error messages and review the configuration. Enable debug mode for detailed information.

## Version History

- **v2.1.1**: Current stable release with full XP system and job integration

## License

See LICENSE file for details.
