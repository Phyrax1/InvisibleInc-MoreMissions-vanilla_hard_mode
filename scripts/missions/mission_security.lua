-- hard mode: 
-- Instead of 1 guard distraction: reboot power supply of the laser in front of the locker room, alert the next 2 guards to the position of the locker,
-- +1 Alarm (I think alerting guards should always increase alarm like in vanilla)
---------------------------------------------------------------------------------------------------------------
local mission = include("sim/missions/mission_security")
local simdefs = include("sim/simdefs")
local mission_util = include("sim/missions/mission_util")
local cdefs = include("client_defs")
local SCRIPTS = include('client/story_scripts')
local mainframe = include("sim/mainframe")

local OBJECTIVE_ID = "guardOffice"

-- fetch grid ids for the laser grids that spawned in the security dispatch prefab (usually only one but I made it work for multiple grids just in case)
local function getLockerGridIDs(sim)
    local grids = {}
    local alreadyFetched = {}
    for _, room in pairs(sim._rooms or {}) do
        if room.tags and room.tags.guard_office then
            for _, unit in pairs(sim:getAllUnits()) do
                local traits = unit:getTraits()
                if traits.mainframe_laser then
                    local x, y = unit:getLocation()
                    for _, rect in pairs(room.rects or {}) do
                        if rect.x0 and rect.y0 and rect.x1 and rect.y1 and x >= rect.x0 and x <= rect.x1 and y >= rect.y0
                            and y <= rect.y1 then
                            local gridID = traits.powerGrid
                            if gridID and not alreadyFetched[gridID] then
                                alreadyFetched[gridID] = true
                                table.insert(grids, gridID)
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    return grids
end

-- custom mission_util.doRecapturePresentation
local function doGridRecapturePresentation(script, sim, agent)
    local possibleRebootUnits = {}

    for _, gridID in ipairs(getLockerGridIDs(sim)) do
        for _, unit in pairs(sim:getPC():getUnits()) do
            if unit:getTraits().laser_gen and unit:getTraits().powerGrid and unit:getTraits().powerGrid == gridID
                and mainframe.canRevertIce(sim, unit) then
                table.insert(possibleRebootUnits, unit)
            end
        end
    end

    local relocked = #possibleRebootUnits > 0
    if relocked then
        for _, unit in ipairs(possibleRebootUnits) do
            local x, y = unit:getLocation()
            script:queue({type = "pan", x = x, y = y})
            mainframe.revertIce(sim, unit)
            script:waitFrames(.5 * cdefs.SECONDS)
        end
        sim:dispatchEvent(simdefs.EV_SCRIPT_EXIT_MAINFRAME)
        if agent then
            local x, y = agent:getLocation()
            script:queue({type = "pan", x = x, y = y})
            script:waitFrames(1 * cdefs.SECONDS)
        end
    end
end

local function angryGuards(script, sim, agent)
    if not agent then
        return
    end
    local x, y = agent:getLocation()
    local alreadyComing = {}
    for k = 1, 2 do
        -- spawnInterestWithReturn is perfect for this, skips pacifists who wouldn't check on it anyway when alerted
        local comingIn = sim:getNPC():spawnInterestWithReturn(
                             x, y, simdefs.SENSE_RADIO, simdefs.REASON_SHARED, agent, alreadyComing
                         )
        if comingIn and comingIn:isValid() then
            sim:getPC():glimpseUnit(sim, comingIn:getID())
            table.insert(alreadyComing, comingIn:getID())
        end
    end
end

local function checkTopGearItem(script, sim)
    local _, _, agent = script:waitFor(mission_util.PC_TOOK_UNIT_WITH_TAG("topGearItem"))
    local topGearSafe = mission_util.findUnitByTag(sim, "topGear")
    topGearSafe:destroyTab()

    sim:setClimax(true)
    script:waitFor(mission_util.UI_LOOT_CLOSED)
    sim:removeObjective(OBJECTIVE_ID)
    script:waitFrames(.5 * cdefs.SECONDS)
    ---------------------------------------------------------------------------------------------
    -- new!
    doGridRecapturePresentation(script, sim, agent)
    angryGuards(script, sim, agent) -- replacing old "distract nearest guard"
    sim:trackerAdvance(1, STRINGS.UI.ALARM_INCREASE)
    script:queue(1.25 * cdefs.SECONDS)
    ---------------------------------------------------------------------------------------------
    script:queue(
        {script = SCRIPTS.INGAME.AFTERMATH.DISPATCH[sim:nextRand(1, #SCRIPTS.INGAME.AFTERMATH.DISPATCH)],
         type = "newOperatorMessage"}
    )
end

---------------------------------------------------------------------------------------------------------------

local oldmissioninit = mission.init
function mission:init(scriptMgr, sim)
    oldmissioninit(self, scriptMgr, sim)
    local diffOpts = sim:getParams().difficultyOptions
    if diffOpts and diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        for _, hook in pairs(scriptMgr.hooks) do
            if hook.name == "TOPGEAR" then
                scriptMgr:removeHook(hook)
                break
            end
        end
        scriptMgr:addHook("TOPGEAR", checkTopGearItem, nil, self)
    end
end
