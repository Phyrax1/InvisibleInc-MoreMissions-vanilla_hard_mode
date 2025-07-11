-- hard mode: cyberlabs have guaranteed daemons + 3 devices are also rebooted on the secondcyberlab use
-- TODO: bad reception about doubling down on reboot, maybe do something else instead
---------------------------------------------------------------------------------------------------------------
local mission = include("sim/missions/mission_cyberlab")
local simdefs = include("sim/simdefs")
local mission_util = include("sim/missions/mission_util")
local serverdefs = include("modules/serverdefs")

local USE_AUGMENT = {trigger = simdefs.TRG_CLOSE_AUGMENT_MACHINE, fn = function(sim, triggerData)
    return triggerData.unit, triggerData.user
end}

local OBJECTIVE_ID = "cyberlab"

-- modified mission_util.findUnitByTag to fetch all units
local function findUnitsByTag(sim, tag)
    local results = {}
    for _, unit in pairs(sim:getAllUnits()) do
        if unit:hasTag(tag) then
            table.insert(results, unit)
        end
    end
    return results
end

local function installCyberlabDaemons(script, sim)
    local PROGRAM_LIST = serverdefs.PROGRAM_LIST
    if sim:isVersion("0.17.5") then
        PROGRAM_LIST = sim:getIcePrograms()
    end
    for i, cyberlab in pairs(findUnitsByTag(sim, OBJECTIVE_ID)) do
        local daemon = PROGRAM_LIST:getChoice(sim:nextRand(1, PROGRAM_LIST:getTotalWeight()))
        if not cyberlab:getTraits().mainframe_program then
            cyberlab:getTraits().mainframe_program = daemon
        else
            -- if cyberlab already has daemon, install on random device instead
            local candidates = {}
            for _, unit in pairs(sim:getAllUnits()) do
                if unit:getTraits().mainframe_item and unit:getPlayerOwner() ~= sim:getPC()
                    and not unit:getTraits().mainframe_program and unit:getTraits().mainframe_status ~= "off" then
                    table.insert(candidates, unit)
                end
            end
            if #candidates > 0 then
                local idx = sim:nextRand(1, #candidates)
                candidates[idx]:getTraits().mainframe_program = daemon
            end
        end
    end
end

local function hardmode(script, sim, mission)
    installCyberlabDaemons(script, sim)
    -- need to wait for seen because:
    -- if for some reason augment drill is used but cyberlab was not seen,
    -- both reboots would trigger on the same grafter because vanilla waits for it to be seen
    script:waitFor(mission_util.PC_SAW_UNIT("cyberlab"))
    script:waitFor(USE_AUGMENT)
    local _, usedCyberLab, agent = script:waitFor(USE_AUGMENT)
    -- removed 4th argument to not play central message on repeat
    mission_util.doRecapturePresentation(script, sim, usedCyberLab, nil, true, 3)
    sim:dispatchEvent(simdefs.EV_SCRIPT_EXIT_MAINFRAME)
    if agent then
        local x, y = agent:getLocation()
        script:queue({type = "pan", x = x, y = y})
    end
end

------------------------------------------------------------------------------------------------

local oldmissioninit = mission.init
function mission:init(scriptMgr, sim)
    oldmissioninit(self, scriptMgr, sim)
    local diffOpts = sim:getParams().difficultyOptions
    if diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        scriptMgr:addHook("MM_HARDMODE", hardmode, nil, self)
    end
end
