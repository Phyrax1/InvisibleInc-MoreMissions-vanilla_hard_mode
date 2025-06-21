local mission = include("sim/missions/mission_security")
local simdefs = include("sim/simdefs")
local mission_util = include("sim/missions/mission_util")
local cdefs = include("client_defs")
local SCRIPTS = include('client/story_scripts')

local OBJECTIVE_ID = "guardOffice"

local function checkTopGearItem(script, sim)
    local _, item, agent = script:waitFor(mission_util.PC_TOOK_UNIT_WITH_TAG("topGearItem"))
    local topGearSafe = mission_util.findUnitByTag(sim, "topGear")
    topGearSafe:destroyTab()

    sim:setClimax(true)
    script:waitFor(mission_util.UI_LOOT_CLOSED)
    sim:removeObjective(OBJECTIVE_ID)

    sim:getNPC():addMainframeAbility(sim, "bruteForce", nil, 0)
    if agent then
        local x2, y2 = agent:getLocation()
        local alreadycoming = {}
        for k = 1, 2 do
            local comingin = sim:getNPC():spawnInterestWithReturn(
                                 x2, y2, simdefs.SENSE_RADIO, simdefs.REASON_SHARED, agent, alreadycoming
                             )
            if comingin then
                table.insert(alreadycoming, comingin:getID())
            end
        end
    end

    script:waitFrames(1.5 * cdefs.SECONDS)
    script:queue(
        {
            script = SCRIPTS.INGAME.AFTERMATH.DISPATCH[sim:nextRand(1, #SCRIPTS.INGAME.AFTERMATH.DISPATCH)],
            type = "newOperatorMessage"
        }
    )

end

local oldmissioninit = mission.init
function mission:init(scriptMgr, sim)
    local rets = {oldmissioninit(self, scriptMgr, sim)}
    local diffOpts = sim:getParams().difficultyOptions
    if diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        for _, hook in pairs(scriptMgr.hooks) do
            if hook.name == "TOPGEAR" then
                scriptMgr:removeHook(hook)
                break
            end
        end
        scriptMgr:addHook("TOPGEAR", checkTopGearItem, nil, self)
    end
    return unpack(rets)
end
