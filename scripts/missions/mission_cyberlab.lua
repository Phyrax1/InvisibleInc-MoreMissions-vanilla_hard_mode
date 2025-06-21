local mission = include("sim/missions/mission_cyberlab")
local simdefs = include("sim/simdefs")
local mission_util = include("sim/missions/mission_util")
local cdefs = include("client_defs")

local USE_AUGMENT = {
    trigger = simdefs.TRG_CLOSE_AUGMENT_MACHINE,
    fn = function(sim, triggerData)
        return triggerData.unit, triggerData.user
    end
}

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

local function checkAugmentMachine(script, sim, mission)
    script:waitFor(mission_util.PC_SAW_UNIT(OBJECTIVE_ID))
    sim:setClimax(true)
    sim.exit_warning = nil
    sim:removeObjective(OBJECTIVE_ID)
    sim:addObjective(STRINGS.MISSIONS.ESCAPE.OBJ_CYBERLAB_2, OBJECTIVE_ID)
    local firstLoop = true
    while true do
        local _, usedCyberLab, agent = script:waitFor(USE_AUGMENT)
        if agent then
            local x, y = agent:getLocation()
            sim:dispatchEvent(simdefs.EV_CAM_PAN, {x, y})
            sim:getNPC():spawnInterest(x, y, simdefs.SENSE_RADIO, simdefs.REASON_ALARMEDSAFE, agent)
            script:waitFrames(.75 * cdefs.SECONDS)
        end
        if firstLoop then
            sim:removeObjective(OBJECTIVE_ID)

            mission.opened_machine = true
            mission_util.doRecapturePresentation(script, sim, usedCyberLab, agent, true, 3)
            firstLoop = false
        end
        local cyberlabs = findUnitsByTag(sim, OBJECTIVE_ID)
        for i, cyberlab in ipairs(cyberlabs) do
            if cyberlab:getTraits().mainframe_status ~= "off" then
                cyberlab:processEMP(2, true, false, true)
                sim:dispatchEvent(
                    simdefs.EV_UNIT_REFRESH, {
                        unit = cyberlab
                    }
                )
            end
        end
    end
end

local oldmissioninit = mission.init
function mission:init(scriptMgr, sim)
    local rets = {oldmissioninit(self, scriptMgr, sim)}
    local diffOpts = sim:getParams().difficultyOptions
    if diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        for _, hook in pairs(scriptMgr.hooks) do
            if hook.name == "AUGMENT" then
                scriptMgr:removeHook(hook)
                break
            end
        end
        scriptMgr:addHook("AUGMENT", checkAugmentMachine, nil, self)
    end
    return unpack(rets)
end
