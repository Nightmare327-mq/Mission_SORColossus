-- Mission_SORColossus
-- Version 1.2
-- TODO: Implement bc support if asked for
-- TODO: Implement RGMercs.lua support if asked for (it has been)
-- Error Reports:
-- 
---------------------------
local mq = require('mq')
LIP = require('lib.LIP')
Logger = require('utils.logger')
C = require('utils/common')

-- #region Variables
Logger.set_log_level(4) -- 4 = Info level, use 5 for debug, and 6 for trace
Zone_name = mq.TLO.Zone.ShortName()
Task_Name = 'Colossus'
Command = 0

local Ready = false
local my_class = mq.TLO.Me.Class.ShortName()
local request_zone = 'arcstoneruins'
local request_npc = 'Black_Jay'
local request_phrase = 'smaller'
local zonein_phrase = 'ready'
local quest_zone = 'arcstoneruins_mission'
local delay_before_zoning = 35000  -- 27s
local section = 0

local CampY = -813
local CampX = 1840
local CampZ = 1779

Settings = {
    general = {
        GroupMessage = 'dannet',        -- or "bc" - not yet implemented
        Automation = 'CWTN',            -- automation method, 'CWTN' for the CWTN plugins, or 'rgmercs' for the rgmercs lua automation.  KissAssist is not really supported currently, though it might work
        PreManaCheck = false,           -- true to pause until the check for everyone's mana, endurance, hp is full before proceeding, false if it stalls at that point
        Burn = true,                    -- Whether we should burn by default. Some people have a bit of trouble handling the adds when they burn, so you are able to turn this off if you want
        OpenChest = false,              -- true if you want to open the chest automatically at the end of the mission run. I normally do not do this as you can swap toon's out before opening the chest to get the achievements
        IgnoreStoneFall = false,        -- true to ignore the calls for the stone's falling from the skies
        WriteCharacterIni = true,       -- Write/read character specific ini file to be able to run different groups with different parameters.  This must be changed in this section of code to take effect
    }
}
-- #endregion
Load_settings()

Logger.info('\awGroup Chat: \ay%s', Settings.general.GroupMessage)
if (Settings.general.GroupMessage ~= 'dannet')  then
   Logger.info("Unknown or invalid group command. Must be 'dannet'. Ending script. \ar")
   os.exit()
end

Logger.info('\awAutomation: \ay%s', Settings.general.Automation)
--if (Settings.general.Automation ~= 'CWTN' and Settings.general.Automation ~= 'rgmercs' and Settings.general.Automation ~= 'KA')  then
if (Settings.general.Automation ~= 'CWTN')  then
--    Logger.info("Unknown or invalid automation system. Must be either 'CWTN', 'rgmercs', or 'KA'. Ending script. \ar")
    Logger.info("Unknown or invalid automation system. Must be 'CWTN' currently, until I add the other automation systems'. Ending script. \ar")
    os.exit()
end

Logger.info('\awPreManaCheck: \ay%s', Settings.general.PreManaCheck)
Logger.info('\awBurn: \ay%s', Settings.general.Burn)
Logger.info('\awIgnoreStoneFall: \ay%s', Settings.general.IgnoreStoneFall)
Logger.info('\awOpen Chest: \ay%s', Settings.general.OpenChest)
Logger.info('\awWrite Character Ini: \ay%s\aw.', Settings.general.WriteCharacterIni)
if (Settings.general.WriteCharacterIni == true) then
    Load_settings()
elseif (Settings.general.WriteCharacterIni == false) then
else
    Logger.info("\awWrite Character Ini: %s \ar Invalid value. You can only use true or false.  Exiting script until you fix the issue.\ar", Settings.general.WriteCharacterIni)
    os.exit()
end

if my_class ~= 'WAR' and my_class ~= 'SHD' and my_class ~= 'PAL' then 
	Logger.info('You must run the script on a tank class...')
	os.exit()
end

if mq.TLO.Me.Combat() == true then 
    Logger.info('You started the script while you are in Combat.  Please kill the mobs first, then restart the script. Exiting script...')
	os.exit()
end

if mq.TLO.Group.AnyoneMissing() then
    Logger.info('You started the script, but not everyone is actually in zone with you. Exiting script...')
    os.exit()
end

if CheckGroupDistance(50) ~= true then 
    Logger.info('You started the script, but not everyone is within 50 feet of you. Exiting script...')
    os.exit()
end

if Zone_name == request_zone then 
	if mq.TLO.Spawn(request_npc).Distance() > 40 then 
		Logger.info('You are in %s, but too far away from %s to start the mission! You will have to manually run to the mission npc', mq.TLO.Zone.ShortName(), request_npc)
        os.exit()
    end
    local task = Task(Task_Name, request_zone, request_npc, request_phrase)
    local waitForDZ = WaitForDZ(60)
    if waitForDZ == false then
        Logger.info('Error getting the task and Zone initiated... Please fix the issue and try again... Exiting script...')
        os.exit()
    end
    ZoneIn(request_npc, zonein_phrase, quest_zone)
    mq.delay(5000)
    local allinzone = WaitForGroupToZone(600)
    if allinzone == false then
        Logger.info('Timeout while waiting for everyone to zone in.  Please check what is happening and restart the script')
        os.exit()
    end
end

Zone_name = mq.TLO.Zone.ShortName()

if Zone_name ~= quest_zone then 
	Logger.info('You are not in the mission...')
	os.exit()
end

if mq.TLO.Group.AnyoneMissing() then
    Logger.info('You started the script in the mission zone, but not everyone is actually in zone.  Exiting script...')
    os.exit()
end
-- Check group mana / endurance / hp
while Settings.general.PreManaCheck == true and Ready == false do 
	Ready = CheckGroupStats()
	mq.cmd('/noparse /dgga /if (${Me.Standing}) /sit')
    Logger.info('Waiting for full hp / mana/ endurance to proceed...')
	mq.delay(15000)
    ZoneCheck(quest_zone)
    TaskCheck(Task_Name)
end

Logger.info('Doing initial setup...')

DoPrep()

Logger.info('Starting the event in 10 seconds!')

mq.delay(10000)

Logger.info('Starting the event...')
MoveToAndSay('Torm the Golden', 'now')

-- This section is waiting till all the 2 starting adds are killed to do the rest of the script
Logger.info('Killing the 2 initial mobs...')
while mq.TLO.SpawnCount("a stony worker npc")() + mq.TLO.SpawnCount("a runic worker npc")()  > 0 do
    if (mq.TLO.SpawnCount('a stony worker npc')() > 0) then
        Logger.debug('stony worker Attack branch...')
        MoveToTargetAndAttack('a stony worker')
    elseif (mq.TLO.SpawnCount('a runic worker npc')() > 0) then
        Logger.debug('runic worker Attack branch...')
        MoveToTargetAndAttack('a runic worker')
    end
	mq.delay(1000)
    ZoneCheck(quest_zone)
    TaskCheck(Task_Name)
end

mq.cmd('/dgga /nav loc -685 1760 1775 log=off')
WaitForNav()
section = 0

local event_zoned = function(line)
    -- zoned so quit
    Command = 1
end

local event_failed = function(line)
    -- failed so quit
    Command = 1
end

local event_stonefall = function(line)
    if Settings.general.IgnoreStoneFall == false then 
        if section == 0 then 
            section = 1
        elseif section == 1 then 
            section = 2
        elseif section == 2 then
            section = 3
        elseif section == 3 then
            section = 4
        elseif section == 4 then 
            section = 1
        end
        Logger.info('Stonefall event... Section %s', section)
    else
        Logger.info('Ignoring Stonefall event... Section %s', section)
    end    
    
end

mq.event('Zoned','LOADING, PLEASE WAIT...#*#',event_zoned)
mq.event('Failed','#*#Colossus of Skylance has been left to its own devices for too long#*#',event_failed)
mq.event('StoneFall', '#*#you hear cracking and groaning as stones begin to fall from the sky#*#', event_stonefall)
mq.event('StoneFall2', '#*#The Colossus tosses a large stone into the air and it hovers heavily#*#', event_stonefall)

local modeSet = false

while true do
	mq.doevents()

	if Command == 1 then
        break
	end

	if mq.TLO.SpawnCount('_chest')() == 1 then
		Logger.info('I see the chest! You won!')
		break
	end

    if (mq.TLO.SpawnCount('Colossus npc xtarhater')() > 0 ) then 
        Logger.debug('Colossus Attack branch...')
        MoveToTargetAndAttack('Colossus')
        if modeSet ~= true then 
            Logger.info('Killing the Colossus now...')
            if (Settings.general.Burn == true) then 
                Logger.debug('Settings.general.Burn = %s', Settings.general.Burn)
                Logger.debug('Setting BurnAlways on')
                if (Settings.general.Automation == 'CWTN') then mq.cmd('/cwtna burnnow') end
                mq.cmd('/boxr burnnow')
            end
            section = 1
            modeSet = true
        end
	end

    if mq.TLO.Target() ~= nil then 
        if mq.TLO.Target.Distance() > 20 then
            mq.cmd('/squelch /nav target distance=20 log=off') 
            WaitForNav()
        end
    end
			
    --ToDo: See if we actually need this section for slower kills
    
    if section > 0 and Settings.general.IgnoreStoneFall == false then 
        if section == 1 then 
            -- Center of the area
            CampY = -579
            CampX = 1724
        elseif section == 2 then
            CampY = -809
            CampX = 1683
        elseif section == 3 then 
            CampY = -706
            CampX = 1883
        elseif section == 4 then 
            CampY = -968
            CampX = 1798
        end

        if Get_dist_to(CampY, CampX, 1765) > 60 then 
        -- if math.abs(mq.TLO.Me.Y() - CampY) > 60 or math.abs(mq.TLO.Me.X() - CampX) > 60 then
            -- if math.random(1000) > 500 then
            -- Do we need to stop attacking?
            mq.cmdf('/dgga /nav locyx %s %s log=off', CampY, CampX)
            WaitForNav()
            if mq.TLO.Target() then  mq.cmd('/squelch /face') end
            -- Wait a bit to let the Colossus follow you to the camp spot
            mq.delay(5000)
            -- end
	    end
    end

	mq.delay(1000)
    ZoneCheck(quest_zone)
    TaskCheck(Task_Name)
end

if (Settings.general.OpenChest == true) then Action_OpenChest() end

mq.unevent('Zoned')
mq.unevent('Failed')

while mq.TLO.Me.Combat() == true do
    Logger.info('Mission has ended, but you are still in combat.... Delaying reset until combat has ended...')
    mq.delay(5000)
end

ClearStartingSetup()
Logger.info('...Ended')