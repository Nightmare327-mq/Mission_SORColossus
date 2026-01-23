local mq = require('mq')

-- #region local Variables
local config_path = ''
local my_class = mq.TLO.Me.Class.ShortName()
local my_name = mq.TLO.Me.CleanName()
local cwtn_StartingMode = ''

local task = mq.TLO.Task(Task_Name)

-- Lookup table: Class ShortName -> CWTN Plugin Name
local classPluginLookup = {
    BER = 'MQ2BerZerker',
    BRD = 'MQ2Bard',
    BST = 'Mq2Bst',
    CLR = 'Mq2Cleric',
    DRU = 'Mq2Druid',
    ENC = 'MQ2Enchanter',
    MAG = 'MQ2Mage',
    MNK = 'MQ2Monk',
    NEC = 'MQ2Necro',
    PAL = 'Mq2Paladin',
    RNG = 'MQ2Ranger',
    ROG = 'MQ2Rogue',
    SHD = 'MQ2Eskay',
    SHM = 'MQ2Shaman',
    WAR = 'MQ2War',
    WIZ = 'MQ2Wizard',
}

-- #endregion


-- #region local functions
local function file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then io.close(f) return true else return false end
end


-- Reload CWTN plugins for all non-mercenary group members
--- Skips mercenaries automatically
local function ReloadGroupCWTNPlugins()
    local groupSize = mq.TLO.Me.GroupSize() or 0
    local grouperRunning = mq.TLO.Lua.Script('grouper').Status() == 'RUNNING'
    
    -- 0 = self, 1..GroupSize = other members
    for i = 0, groupSize do
        local member = mq.TLO.Group.Member(i)

        if member() and member.Present() then
            -- Skip mercenaries
            if member.Mercenary() then
                Logger.info('Skipping mercenary in group slot %s', i)
            else
                local name = member.Name()
                local classShort = member.Class.ShortName()
                local pluginName = classPluginLookup[classShort]

                if pluginName then
                    if name == mq.TLO.Me.Name() then 
                        mq.cmdf('/timed 50 /plugin %s unload', pluginName) 
                        mq.cmdf('/timed 100 /plugin %s load', pluginName) 
                        Logger.info('Local Plugin reset on %s (%s) %s', name, classShort, pluginName)
                        if grouperRunning == true then mq.cmd('/timed 200 /lua run grouper') end
                    else
                        mq.cmdf('/dex %s /plugin %s unload', name, pluginName)
                        mq.cmdf('/dex %s /timed 10 /plugin %s', name, pluginName)
                        Logger.info('Remote Plugin reset on %s (%s) %s', name, classShort, pluginName)
                    end
                    
                else
                    Logger.info('No plugin mapping for %s (%s)', name, classShort)
                end
            end
        end
    end
end
 -- #endregion

 -- #region Global functions 
Load_settings=function ()
    local config_dir = mq.configDir:gsub('\\', '/') .. '/'
    local config_file = string.format('mission_sorcolossus_%s.ini', mq.TLO.Me.CleanName())
    config_path = config_dir .. config_file
    if (file_exists(config_path) == false) then
        LIP.save(config_path, Settings)
    else
        Settings = LIP.load(config_path)

        -- Version updates
        local is_dirty = false
        if (Settings.general.GroupMessage == nil) then
            Settings.general.GroupMessage = 'dannet'
            is_dirty = true
        end
        if (Settings.general.Automation == nil) then
            Settings.general.Automation = 'CWTN'
            is_dirty = true
        end
        if (Settings.general.PreManaCheck == nil) then
            Settings.general.PreManaCheck = false
            is_dirty = true
        end
        if (Settings.general.Burn == nil) then
            Settings.general.Burn = true
            is_dirty = true
        end
        if (Settings.general.IgnoreStoneFall == nil) then
            Settings.general.IgnoreStoneFall = false
            is_dirty = true
        end
		if (Settings.general.OpenChest == nil) then
            Settings.general.OpenChest = false
            is_dirty = true
        end
        if (Settings.general.WriteCharacterIni == nil) then
            Settings.general.WriteCharacterIni = true
            is_dirty = true
        end

        if (is_dirty) then LIP.save(config_path, Settings) end
    end
 end


 Get_dist_to = function(target_y, target_x, target_z)
    -- Use mq.TLO.Math.Distance to get the distance to a specific point
    -- The format for the TLO is "X Y Z"
    local dist_str = mq.TLO.Math.Distance(string.format("%f,%f,%f", target_y, target_x, target_z))()
  
    -- -- mq.TLO returns a string, so convert it to a number (float)
    local distance = tonumber(dist_str)
    
    return distance
end

 WaitForNav = function()
    local loopcount = 0
	Logger.debug('Starting WaitForNav()...')
	while mq.TLO.Navigation.Active() == false and loopcount < 10 do
		mq.delay(10)
        loopcount = loopcount + 1
	end
	while mq.TLO.Navigation.Active() == true do
		mq.delay(10)
	end
    mq.delay(10)
	Logger.debug('Exiting WaitForNav()...')
end

MoveToSpawn = function(spawn, distance)
    -- Logger.debug('spawn = '..spawn())
    -- Logger.debug('spawn.ID = '..spawn.ID())
    if (spawn ~= nil and spawn.ID() ~= nil) then
        if (distance == nil or type(distance) ~= "number") then
            distance = 15
        end
        -- Added section to handle if we are already in range of the spawn
        if (spawn.Distance() ~= nil and spawn.Distance() <= distance) then 
            return true
        end
        if (spawn.Distance() ~= nil and spawn.Distance() >= distance) then 
            mq.cmdf('/squelch /nav id %d |dist=%d log=off', spawn.ID(), distance)
            WaitForNav()
            if (spawn.Distance() ~= nil and spawn.Distance() <= distance) then
                return true
            else
                Logger.debug(string.format("[ERROR] MoveToSpawn() --> spawn.distance [%s]", spawn.Distance()))
                return false
            end
        end
    else
        Logger.debug(string.format("[ERROR] MoveToSpawn() --> spawn or spawn.id was nil"))
        return false
    end
end

MoveToId = function(spawn_id, distance)
    local spawn = mq.TLO.Spawn('npc id '..spawn_id)
    return MoveToSpawn(spawn, distance)
end

MoveTo = function(spawn_name, distance)
    local spawn = mq.TLO.Spawn('npc '..spawn_name)
    Logger.debug('Spawn: %s', spawn.CleanName())
    return MoveToSpawn(spawn, distance)
end

MoveToAndTarget = function(spawn_name)
    -- Logger.debug('spawn = '..spawn_name)
    if spawn_name ~= nil then
        if MoveTo(spawn_name, 15) == true then
            while mq.TLO.Target.CleanName() ~= mq.TLO.Spawn(spawn_name..' npc' ).CleanName() do 
                Logger.debug('Targeting %s', mq.TLO.Spawn(spawn_name..' npc').CleanName())
                mq.cmdf('/target %s npc', spawn_name) -- have to use the /target to avoid targeting the corpse
                mq.delay(250) -- allows for time to actually target without spamming the command
            end
            if mq.TLO.Target.CleanName() == mq.TLO.Spawn(spawn_name..' npc').CleanName() then
                return true
            end
        else
            Logger.debug(string.format("[ERROR] MoveToAndTarget() --> spawn was nil"))
            return false 
        end
    end
end

MoveToAndAct = function(spawn_name, cmd)
    if MoveToAndTarget(spawn_name) == false then return false end
    mq.cmd(cmd)
    return true
end

MoveToTargetAndAttack = function(spawn_name)
    if MoveToAndTarget(spawn_name) == true then
        if mq.TLO.Target.CleanName() == mq.TLO.Spawn(spawn_name).CleanName() and mq.TLO.Me.Combat() == false then 
            mq.cmd('/attack on') 
        end
        if mq.TLO.Target.CleanName() == mq.TLO.Spawn(spawn_name).CleanName() and mq.TLO.Me.Combat() == true then
            return true
        end
        return false
    end
end

MoveToAndSay = function(spawn_name,say) return MoveToAndAct(spawn_name, string.format('/say %s', say)) end

Query = function(peer, query, timeout)
    mq.cmdf('/dquery %s -q "%s"', peer, query)
    mq.delay(timeout)
    local value = mq.TLO.DanNet(peer).Q(query)()
    return value
end

Tell = function(delay,gm,aa) 
    local z = mq.cmdf('/timed %s /dex %s /multiline ; /stopcast; /timed 1 /alt act %s', delay, mq.TLO.Group.Member(gm).Name(), aa)
    return z
end

ClassShortName = function(x)
    local y = mq.TLO.Group.Member(x).Class.ShortName()
    if mq.TLO.Group.Member(x).Mercenary() == true then 
        y = 'NIL'
    end
    return y
end

All_Invis = function(mode)
    local anyoneNotInvis = false
    local all_invis_status = false
    local grpsize = mq.TLO.Group.Members() 

    for gm = 0,grpsize do
        if mq.TLO.Group.Member(gm).Mercenary() == false then 
            local name = mq.TLO.Group.Member(gm).Name()
            local result1 = Query(name, 'Me.Invis[1]', 100) 
            local result2 = Query(name, 'Me.Invis[2]', 100)
            local invis_result = false
            
            if mode == 1 then 
                if result1 == 'TRUE' then
                    invis_result = true
                    Logger.debug(string.format("\ay%s \at%s \ag%s", name, "Invis: ", invis_result))
                else
                    Logger.debug('group member'..gm)
                    anyoneNotInvis = true
                    break
                end
            end
            if mode == 2 then 
                if result2 == 'TRUE' then
                    invis_result = true
                    Logger.debug(string.format("\ay%s \at%s \ag%s", name, "DBL Invis: ", invis_result))
                else
                    Logger.debug('group member'..gm)
                    anyoneNotInvis = true
                    break
                end
            end
            if mode == 3 then 
                if result1 == 'TRUE' and result2 == 'TRUE' then
                    invis_result = true
                    Logger.debug(string.format("\ay%s \at%s \ag%s", name, "DBL Invis: ", invis_result))
                else
                    Logger.debug('group member'..gm)
                    anyoneNotInvis = true
                    break
                end
            end
        end
        

        if gm == grpsize then
            all_invis_status = true
        end
        Logger.debug('all_invis_status: %s | anyoneNotInvis: %s', all_invis_status, anyoneNotInvis)
        all_invis_status = not anyoneNotInvis
        Logger.debug('all_invis_status: %s | anyoneNotInvis: %s', all_invis_status, anyoneNotInvis)
    end
    return all_invis_status
end

The_Invis_Thing = function(mode)
    -- mode: 1 = Regular Invis, 2 = Invis Versus Undead (IVU) 3 = Double Invis
    --if i am bard or group has bard, do the bard invis thing
    -- this will apply to any mode, as it is a one-time cast, rather than a combination of casting characters
    if mq.TLO.Spawn('Group Bard').ID()>0 then
        local bard = mq.TLO.Spawn('Group Bard').Name()
            if bard == mq.TLO.Me.Name() then
                    mq.cmd('/mutliline ; /stopsong; /timed 1 /alt act 3704; /timed 3 /alt act 231') 
                else
                    mq.cmdf('/dex %s /multiline ; /stopsong; /timed 1 /alt act 3704; /timed 3 /alt act 231', bard)
            end
            Logger.info('\ag-->\at INVer: \ay %s \at IVUer: \ay %s \ag<--', bard, bard)
    else
    --without a bard, find who can invis and who can IVU
        local inver = 0
        local ivuer = 0
        local grpsize = mq.TLO.Group.Members()
        
            --check classes that can INVIS only
        for i=0,grpsize do
            if string.find("RNG DRU SHM", ClassShortName(i)) ~= nil then
                inver = i
                break
            end
        end

        --check classes that can IVU only
        for i=0,grpsize do
            if string.find("CLR NEC PAL SHD", ClassShortName(i)) ~= nil then
                ivuer = i
                break
            end
        end
        
        --check classes that can do BOTH
        if inver == 0 then
            for i=0,grpsize do
                if string.find("ENC MAG WIZ", ClassShortName(i)) ~= nil then
                    inver = i
                    break
                end    
            end
        end

        if ivuer == 0 then
            for i=grpsize,0,-1 do
                if string.find("ENC MAG WIZ", ClassShortName(i)) ~= nil then
                    ivuer = i
                    if i == inver then
                        if mode == 3 then 
                            Logger.info('\arUnable to Double Invis')
                            mq.exit()  
                        end
                        if mode == 2 then 
                            Logger.info('\arUnable to IVU')
                            mq.exit()  
                        end
                    end
                break
                end
            end
        end 

        --catch anyone else in group
        if string.find("WAR MNK ROG BER", ClassShortName(inver)) ~= nil or string.find("WAR MNK ROG BER", ClassShortName(ivuer)) ~= nil then
            if mode == 3 then 
                Logger.info('\arUnable to Double Invis')
                mq.exit()  
            end
        end

        if (inver >= 0 and mode ~= 2) then 
            Logger.info('\ag-->\atINVer: \ay %s<--', mq.TLO.Group.Member(inver).Name())
        end
        if (ivuer >= 0 and mode >= 2) then 
            Logger.info('\ag-->\atIVUer: \ay %s<--', mq.TLO.Group.Member(ivuer).Name())
        end
        
        -- Logger.info('\ag-->\atINVer: \ay%s\at IVUer: \ay%s\ag<--', mq.TLO.Group.Member(inver).Name(), mq.TLO.Group.Member(ivuer).Name())
        
        --if i am group leader and can INVIS, then do the INVIS thing
        if mode ~= 2 then 
            if ClassShortName(inver) == 'SHM' and inver == 0 then
                mq.cmd('/multiline ; /stopcast; /timed 3 /alt act 630')
            elseif string.find("ENC MAG WIZ", ClassShortName(inver)) ~= nil then
                mq.cmd('/multiline ; /stopcast; /timed 1 /alt act 1210')
            elseif string.find("RNG DRU", ClassShortName(inver)) ~= nil then
                mq.cmd('/multiline ; /stopcast; /timed 1 /alt act 518')
            end

            --if i have an INVISER in the group, then 'tell them' do the INVIS thing
            if ClassShortName(inver) == 'SHM' and inver ~= 0 then
                    Tell(4,inver,630)
                elseif string.find("ENC MAG WIZ", ClassShortName(inver)) ~= nil then
                    Tell(0,inver,1210)
                elseif string.find("RNG DRU", ClassShortName(inver)) ~= nil then
                    Tell(5,inver,518)
            end
        end
        
        if mode >= 2 then 
            --if i am group leader and can IVU, then do the IVU thing
            if string.find("CLR NEC PAL SHD", ClassShortName(ivuer)) ~= nil and ivuer == 0 then
                    mq.cmd('/multiline ; /stopcast; /timed 1 /alt activate 1212')
                else
                    mq.cmd('/multiline ; /stopcast; /timed 1 /alt activate 280')
            end
            
            --if i have an IVUER in the group, then 'tell them' do the IVU thing
            if string.find("CLR NEC PAL SHD", ClassShortName(ivuer)) ~= nil and ivuer ~= 0 then
                    Tell(2,ivuer,1212)    
                else
                    Tell(2,ivuer,280)
            end
        end
        
    end
    mq.delay(8000)
end

GroupInvis = function(mode)
    -- mode: 1 = Regular Invis, 2 = Invis Versus Undead (IVU) 3 = Double Invis
    if mode == nil then mode = 3 end
    if mode ~= 1 and mode ~= 2 and mode ~= 3 then 
        Logger.info('You called the Invis routine with an incorrect parameter (%s). You must call it with a 1, 2, or 3', mode)
        os.exit()
    end
    while not All_Invis(mode) do
        The_Invis_Thing(mode)
         mq.delay(5000)
    end
end

CheckGroupStats = function()
	local ready = true
	local groupSize = mq.TLO.Group()
    if mq.TLO.Group.AnyoneMissing() then return false end
   
    for i = groupSize, 0, -1 do
		-- if DEBUG and ( mq.TLO.Group.Member(i).PctHPs() < 98 or  mq.TLO.Group.Member(i).PctEndurance() < 98 or (mq.TLO.Group.Member(i).PctMana() ~= 0 and  mq.TLO.Group.Member(i).PctMana() < 98)) then 
		-- 	printf('%s : %s : %s : %s', mq.TLO.Group.Member(i).CleanName(), mq.TLO.Group.Member(i).PctHPs(), mq.TLO.Group.Member(i).PctEndurance(), mq.TLO.Group.Member(i).PctMana() )
		-- end
        if mq.TLO.Group.Member(i).Mercenary() ~= true then 
            if mq.TLO.Group.Member(i).PctHPs() < 99 then ready = false end
            if mq.TLO.Group.Member(i).PctEndurance() < 99 then ready = false end
            if mq.TLO.Group.Member(i).PctMana() ~= 0 and mq.TLO.Group.Member(i).PctMana() < 99 then ready = false end
        end
    end
	-- mq.delay(5000)
    return ready
end

-- Function to check the distance of all group members
CheckGroupDistance = function (max_distance)
    local allWithinRange = true
    -- mq.TLO.Group.Size() returns the number of people in your group, including yourself.
    local group_size = mq.TLO.Group()

    -- Loop through each member of the group, starting from index 1.
    -- Index 0 is the character running the script.
    for i = 1, group_size - 1 do
        -- Get the group member object for the current index
        local member = mq.TLO.Group.Member(i)
        
        -- Check if the member exists and is not null (e.g., they are in the zone)
        if member() and member.Mercenary() == false then
            -- Get the distance from yourself (mq.TLO.Me) to the group member
            local distance = member.Distance()
            Logger.debug('Group Member %s is at distance %s', member.Name(), distance)

            -- Check if the distance is greater than the defined maximum
            if distance > max_distance then
                allWithinRange = false
                -- If they are too far, print a warning message in the chat window
                -- string.format is used to insert the member's name and distance into the message
                Logger.info('Group Member %s is too far away: %s', member.Name(), distance)
            end
        end
    end
    return allWithinRange
end

StopAttack = function()
    Logger.debug('my_class = '..my_class)
    Logger.debug('my_name = '..my_name)
	mq.cmd('/attack off') 
    if Settings.general.Automation == 'CWTN' then 
       	mq.cmd('/cwtna CheckPriorityTarget off nosave')
        mq.cmdf('/%s CheckPriorityTarget off nosave', my_class )
        mq.cmdf('/%s manual nosave', my_class )
    elseif Settings.general.Automation == 'rgmercs' then 
        --TODO: Finish automation entries
    elseif Settings.general.Automation == 'KA' then 
        --TODO: Finish automation entries
    end
	Logger.debug('StopAttack branch...')
	if mq.TLO.Target.CleanName() ~= my_name then mq.cmdf('/eqtarget %s', my_name) end
end

ZoneIn = function(npcName, zoneInPhrase, quest_zone)
    if Settings.general.Automation == 'CWTN' then 
        Logger.info('Pausing CWTN modules so we can zone in')
        mq.cmd('/cwtna pause on nosave')
        mq.delay(1000)
    end
    -- Adding sections to handle other automation - these should work for rgmercs and KA
    -- mq.cmd('/dgga /squelch /boxr pause')
    local GroupSize = mq.TLO.Group.Members()

    for g = 1, GroupSize, 1 do
        local memberName = mq.TLO.Group.Member(g).Name()
        if mq.TLO.Group.Member(g).Mercenary() ~= true then         
            Logger.info('\ay-->%s<--\ap Should Be Zoning In Now', memberName)
            mq.cmdf('/dex %s /eqtarget %s', memberName, npcName)
            mq.delay(math.random(2000, 4000))
            mq.cmdf('/dex %s /say %s', memberName, zoneInPhrase)
            local groupSpawn = mq.TLO.Group.Member(g).Spawn()
            while groupSpawn ~= nil do 
                mq.delay(5000)
                Logger.debug('Waiting on %s to zone in...', memberName)
                groupSpawn = mq.TLO.Group.Member(g).Spawn()
            end
        end
    end

    -- This is to make us the last to zone in
    -- does this really work?
    while mq.TLO.Group.AnyoneMissing() == false do
        mq.delay(2000)
    end
    if mq.TLO.Target.CleanName() ~= npcName then
        mq.cmdf('/eqtarget %s', npcName)
        mq.delay(5000)
        Logger.info('\ay-->%s<--\ap Should Be Zoning In Now', mq.TLO.Me.CleanName())
        mq.cmdf('/say %s', zoneInPhrase)
    else
        mq.delay(5000)
        Logger.info('\ay-->%s<--\ap Should Be Zoning In Now', mq.TLO.Me.CleanName())
        mq.cmdf('/say %s', zoneInPhrase)
    end
    local counter = 0
    while mq.TLO.Zone.ShortName() ~= quest_zone do 
        counter = counter + 1
        if counter >= 12 then 
            Logger.info('Not able to zone into the %s. Look at the issue and fix it please.', quest_zone)
            os.exit()
        end
        mq.delay(5000)
    end
    Zone_name = mq.TLO.Zone.ShortName()
    if mq.TLO.Zone.ShortName() == quest_zone then 
        if Settings.general.Automation == 'CWTN' then 
            Logger.info('Un-Pausing CWTN modules after we have zoned in')
            mq.cmd('/cwtna pause off nosave')
            mq.delay(1000)
        end
        mq.cmd('/dgga /squelch /boxr Unpause')
        mq.delay(1000)
    end
end

Task = function(task_name, request_zone, request_npc, request_phrase)
    Logger.debug('task_name = '..task_name)
    Logger.debug('request_zone = '..request_zone)
    Logger.debug('request_npc = '..request_npc)
    Logger.debug('request_phrase = '..request_phrase)
    if (task() == nil) then
        if (mq.TLO.Zone.ShortName() ~= request_zone) then
            Logger.info('Not In %s to request task.  Move group to that zone and restart.', request_zone)
            os.exit()
        end
        if Settings.general.Automation == 'CWTN' then 
            mq.cmd('/cwtna pause on nosave')
        else
            mq.cmd('/dgga /boxr pause')
        end
        
        MoveToAndSay(request_npc, request_phrase)

        for index=1, 5 do
            mq.delay(1000)
            mq.doevents()

            task = mq.TLO.Task(task_name)
            if (task() ~= nil) then break end

            if (index >= 5) then
                Logger.info('Unable to get quest. Exiting.')
                os.exit()
            end
            Logger.info('...waiting for quest.')
        end

        if (task() == nil) then
            Logger.info('Unable to get quest. Exiting.')
            os.exit()
        end

        Logger.info('\at Got quest... Closing Quest window in a few seconds...')
        mq.cmd('/dgga /squelch /timed 50 /windowstate TaskWnd close')
        mq.delay(100)
    end

    if (task() == nil) then
        Logger.info('Problem requesting or getting task.  Exiting.')
        os.exit()
    end
    return task
end

WaitForTask = function(delay_before_zoning)
    local time_since_request = 21600000 - task.Timer()
    local time_to_wait = delay_before_zoning - time_since_request
    Logger.debug('TimeSinceReq: \ag%d\ao  TimeToWait: \ag%d\ao', time_since_request, time_to_wait)
    if (time_to_wait > 0) then
        Logger.info('\at Waiting for instance generation \aw(\ay%.f second(s)\aw)', time_to_wait / 1000)
        mq.delay(time_to_wait)
    end  
end

WaitForDZ = function(waitTimeOut)
    Logger.info('Waiting for Dynamic Zone to be created...')
    local loopCounter = 0

    while not mq.TLO.DynamicZone.Leader() and loopCounter < waitTimeOut do
        mq.delay(1000)
        Logger.debug('LoopCounter: %s', loopCounter)
        loopCounter = loopCounter + 1
    end

    if mq.TLO.DynamicZone.Leader() then  
        Logger.info('Dynamic Zone ready. Leader: %s', mq.TLO.DynamicZone.Leader.Name())
        mq.delay(10000)
    end

    return mq.TLO.DynamicZone.Leader()
end
--- Gets the name of a group member, even if they are out of zone
---@param index integer
---@return string|nil
GetGroupMemberName = function(index)
    local member = mq.TLO.Group.Member(index)
    if not member() then return nil end
    local name = member.Name()
    if name and name:len() > 0 then
        return name
    end
    return nil
end

--- Returns a table of group members not in the zone
---@return string[]
GetGroupMembersNotInZone = function()
    local missing = {}
    for i = 1, mq.TLO.Me.GroupSize() do
        local name = GetGroupMemberName(i)
        if mq.TLO.Group.Member(i).Mercenary() == false  then
            if name and not mq.TLO.Spawn("pc = " .. name)() then
                table.insert(missing, name)
            end    
        end
    end
    return missing
end

TaskCheck = function(task_name)
    Logger.debug('Doing TaskCheck for %s', task_name)
    local task_check = mq.TLO.Task(task_name)
    mq.delay(250)
    Logger.debug('task_check = %s', task_check())
    if (task_check() == nil) then 
        Logger.info('You no longer have the mission task.  Ending the script...')
        ClearStartingSetup()
        os.exit()
    end
end

--- Wait until all group members are in zone, or timeout
---@param timeoutSec number
---@return boolean
WaitForGroupToZone = function(timeoutSec)
    local checkTimer = 5000
    local cycleCount = 0
    local start_zone = mq.TLO.Zone.ShortName()
    local start = os.time()
    while os.difftime(os.time(), start) < timeoutSec do
        local notInZone = GetGroupMembersNotInZone()
        if #notInZone == 0 then
            Logger.info("All group members are in zone.")
            return true
        end
        Logger.info("Still waiting on: " .. table.concat(notInZone, ", "))
        mq.delay(checkTimer)
        cycleCount = cycleCount + 1
        if (cycleCount >= 10) then 
            checkTimer = checkTimer + 5000 
            cycleCount = 0
            Logger.debug('checkTimer = %s', checkTimer)
        end
        ZoneCheck(start_zone)
        -- TaskCheck(Task_name)
    end
    Logger.info("Timeout waiting for group members to zone.")
    return false
end

ZoneCheck = function(quest_zone)
    Logger.debug('Doing ZoneCheck %s', quest_zone)
    if mq.TLO.Zone.ShortName() ~= quest_zone then 
        Logger.info('You are no longer in the mission zone.  Ending the script...')
        ClearStartingSetup()
        os.exit()
    end
end

DoPrep = function()
    mq.cmd('/dgga /makemevis')
    if Settings.general.Automation == 'CWTN' then 
        -- cwtn_StartingMode = mq.TLO.CWTN.Mode()
        -- Logger.debug('CWTN Starting Mode: %s', cwtn_StartingMode)
        mq.cmd('/cwtn mode manual nosave')
        mq.delay(100)
        mq.cmd('/cwtn mode chase nosave')
        mq.cmdf('/%s mode sictank nosave', my_class)
        -- these next 2 lines are probably superfluous, but it makes me feel better
        mq.cmdf('/%s pause off', my_class)
        mq.cmd('/cwtna pause off nosave')
        mq.cmdf('/%s checkprioritytarget off nosave', my_class)
        mq.cmdf('/%s resetcamp nosave', my_class)
        mq.cmdf('/cwtna AutoAssistAt 99 nosave')
        
        Logger.debug('Settings.general.Burn = %s', Settings.general.Burn)
        Logger.debug('Setting BurnAlways off until the Colossus')
        mq.cmd('/cwtna burnalways off nosave')         
    elseif Settings.general.Automation == 'rgmercs' then 
        --TODO: Finish Automation Setup
        mq.cmd('/dgge /squelch /boxr Chase')
    elseif Settings.general.Automation == 'KA' then 
        --TODO: Finish Automation Setup
        mq.cmd('/dgge /squelch /boxr Chase')
        mq.cmd('/dgga /boxr unpause')
    else
        print('Unknown Automation method!  I am not sure how you got this far with this entry, but we need to stop the script now!')
        printf('Current Automation method in the ini: %s', Settings.general.Automation)
        os.exit()
    end
    mq.cmd('/dgga /makemevis')
end

ClearStartingSetup = function()
    mq.delay(2000)
    if Settings.general.Automation == 'CWTN' then 
        Logger.info('Resetting all group CWTN plugins to reset all settings to base...Waiting 5 seconds')
        mq.delay(5000)
        ReloadGroupCWTNPlugins()
    elseif Settings.general.Automation == 'rgmercs' then 
        --TODO: Finish Automation Setup
    elseif Settings.general.Automation == 'KA' then 
        --TODO: Finish Automation Setup
    else
        print('Unknown Automation method!  I am not sure how you got this far with this entry, but we need to stop the script now!')
        printf('Current Automation method in the ini: %s', Settings.general.Automation)
        os.exit()        
    end
    mq.delay(5000)
    -- mq.cmd('/dgga /boxr unpause')
    -- mq.cmd('/dgga /timed 15 /boxr unpause')

    -- Consider using a plugin unload / reload here to reset all of eh settings we used for the mission
end

Action_OpenChest = function()
    mq.cmd('/squelch /nav spawn _chest | log=off')
    mq.delay(250)
    WaitForNav()
    mq.cmd('/target _chest')
    mq.delay(250)
    mq.cmd('/open')
    mq.delay(250)
    mq.cmd('/target _chest')
    mq.delay(250)
    mq.cmd('/open')
end

-- #endregion