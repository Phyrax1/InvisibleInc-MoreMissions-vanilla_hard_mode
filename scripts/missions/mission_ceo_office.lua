local mission = include("sim/missions/mission_ceo_office")
local simdefs = include("sim/simdefs")
local simquery = include("sim/simquery")
local cdefs = include("client_defs")
local mission_util = include("sim/missions/mission_util")
local simfactory = include("sim/simfactory")
local unitdefs = include("sim/unitdefs")
local SCRIPTS = include('client/story_scripts')

--------------------------------------------------------------------------------------------
-- copied from mission_util
local function createInterrogationHook(importantGuard, onFailInterrogate)
    local function checkGuardDistance(script, sim)
        assert(importantGuard)
        local warned, queued, failed = false, false, false
        local lastDistance = 0

        while not failed do
            local ev, triggerData = script:waitFor(mission_util.UNIT_WARP)
            if queued then
                script:queue(
                    {
                        type = "clearOperatorMessage"
                    }
                )
                queued = false
            end

            local x0, y0 = importantGuard:getLocation()
            if x0 == nil then
                failed = SCRIPTS.INGAME.CENTRAL_FAILED_TARGET_DIED
            else
                if importantGuard:getTraits().interrogationStarted
                    and not importantGuard:getTraits().interrogationFinished then
                    if not importantGuard:isKO() then

                        failed = SCRIPTS.INGAME.CENTRAL_FAILED_TARGET_WOKEUP

                    else
                        local closestUnit, closestDistance = simquery.findClosestUnit(
                                                                 sim:getPC():getAgents(), x0, y0, function(u)
                                return not u:isKO()
                            end
                                                             )
                        if closestDistance > lastDistance then
                            if closestDistance >= 2 then -- orig >5
                                failed = SCRIPTS.INGAME.CENTRAL_FAILED_CONNECTION_BROKEN
                            elseif closestDistance >= 1 and not warned then -- orig >3
                                script:queue(
                                    {
                                        script = SCRIPTS.INGAME.CENTRAL_STAY_CLOSE,
                                        type = "newOperatorMessage"
                                    }
                                )
                                triggerData.unit:interruptMove(sim)
                                warned = true
                                queued = true
                            else
                                warned = false
                            end
                        end
                        lastDistance = closestDistance
                    end
                end
            end
        end

        onFailInterrogate(script, sim)
        script:queue(
            {
                script = failed,
                type = "newOperatorMessage"
            }
        )
        script:waitFor(mission_util.PC_ANY)
        script:queue(
            {
                type = "clearOperatorMessage"
            }
        )
    end

    return checkGuardDistance

end

--------------------------------------------------------------------------------------------

local OBJECTIVE_ID = "ceoOffice"

local PC_KNOCKOUT_CEO = {
    trigger = simdefs.TRG_UNIT_KO,
    fn = function(sim, triggerData)
        if triggerData and (triggerData.ticks or 0) > 0 then
            if (not sim:isVersion("0.17.12") and triggerData.unit:getTraits().ko_trigger == "intimidate_guard")
                or triggerData.unit:getTraits().cfo then
                return triggerData.unit
            end
        end
    end
}

local function createVaultCard(script, sim)
    local target = nil
    sim:forEachUnit(
        function(unit)
            if sim:isVersion("0.17.11") then
                if unit:getTraits().cfo then
                    target = unit
                end
            else
                if unit:getTraits().ko_trigger == "intimidate_guard" then
                    target = unit
                end
            end
        end
    )
    if target then

        local cell = sim:getCell(target:getLocation())
        local newUnit = simfactory.createUnit(unitdefs.lookupTemplate("vault_passcard"), sim)
        sim:spawnUnit(newUnit)
        newUnit:addTag("access_card_obj")
        sim:warpUnit(newUnit, cell)

        sim:emitSound(simdefs.SOUND_ITEM_PUTDOWN, cell.x, cell.y)

    end
end

local function callReinforcement(script, sim)
    local target = nil

    sim:forEachUnit(
        function(unit)
            if sim:isVersion("0.17.11") then
                if unit:getTraits().cfo then
                    target = unit
                end
            else
                if unit:getTraits().ko_trigger == "intimidate_guard" then
                    target = unit
                end
            end
        end
    )
    if target then
        local newGuards = sim:getNPC():spawnGuards(sim, "npc_guard_enforcer_reinforcement", 1)
        for i, newUnit in ipairs(newGuards) do
            local x1, y1 = target:getLocation()
            newUnit:getBrain():spawnInterest(x1, y1, simdefs.SENSE_RADIO, simdefs.REASON_REINFORCEMENTS, target)
        end
        return true
    else
        return false
    end

end
--------------------------------------------------------------------------------------------
-- moved third step to second and added an extra callReinforcement at step 4
local function brainScanBanter(script, sim)
    script:waitFor(mission_util.PC_START_TURN)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    script:queue(0.5 * cdefs.SECONDS)
    script:queue(
        {
            script = SCRIPTS.INGAME.CENTRAL_CFO_BRAINSCAN_1,
            type = "newOperatorMessage"
        }
    )
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    script:queue(
        {
            type = "clearOperatorMessage"
        }
    )
    script:waitFor(mission_util.PC_START_TURN)
    sim:setClimax(true)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    callReinforcement(script, sim)
    script:queue(0.5 * cdefs.SECONDS)
    script:queue(
        {
            script = SCRIPTS.INGAME.CENTRAL_CFO_BRAINSCAN_3,
            type = "newOperatorMessage"
        }
    )
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    script:queue(
        {
            type = "clearOperatorMessage"
        }
    )
    script:waitFor(mission_util.PC_START_TURN)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    script:queue(0.5 * cdefs.SECONDS)
    script:queue(
        {
            script = SCRIPTS.INGAME.CENTRAL_CFO_BRAINSCAN_2,
            type = "newOperatorMessage"
        }
    )
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    script:queue(
        {
            type = "clearOperatorMessage"
        }
    )

    script:waitFor(mission_util.PC_START_TURN)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    callReinforcement(script, sim)
    script:queue(0.5 * cdefs.SECONDS)
    script:queue(
        {
            script = SCRIPTS.INGAME.CENTRAL_CFO_BRAINSCAN_4,
            type = "newOperatorMessage"
        }
    )
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    script:queue(
        {
            type = "clearOperatorMessage"
        }
    )
    script:waitFor(mission_util.PC_START_TURN)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    script:queue(0.5 * cdefs.SECONDS)
    script:queue(
        {
            script = SCRIPTS.INGAME.CENTRAL_CFO_BRAINSCAN_5,
            type = "newOperatorMessage"
        }
    )
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    script:queue(
        {
            type = "clearOperatorMessage"
        }
    )

    script:waitFor(mission_util.PC_START_TURN)
end
--------------------------------------------------------------------------------------------

local function checkForTargetInRange(script, sim, guard, range)
    local x0, y0 = guard:getLocation()
    local closestUnit, closestDistance = simquery.findClosestUnit(
                                             sim:getPC():getAgents(), x0, y0, function(u)
            return not u:isKO()
        end
                                         )
    if closestDistance > range then
        script:queue(
            {
                script = SCRIPTS.INGAME.CENTRAL_MOVE_INTO_RANGE,
                type = "newOperatorMessage"
            }
        )
    end
end

local function followHeatSig(script, sim)
    local guardUnit = nil
    sim:forEachUnit(
        function(unit)
            if unit:getTraits().cfo then
                guardUnit = unit
                local x, y = unit:getLocation()
                script:queue(
                    {
                        type = "displayHUDInstruction",
                        text = STRINGS.MISSIONS.UTIL.HEAT_SIGNATURE_DETECTED,
                        x = x,
                        y = y
                    }
                )
                script:queue(
                    {
                        type = "pan",
                        x = x,
                        y = y
                    }
                )
            end
        end
    )

    while true do
        local ev, triggerData = script:waitFor(mission_util.UNIT_WARP)
        if triggerData.unit:getTraits().cfo then
            script:queue(
                {
                    type = "hideHUDInstruction"
                }
            )
            local x, y = triggerData.unit:getLocation()
            if x and y then
                script:queue(
                    {
                        type = "displayHUDInstruction",
                        text = STRINGS.MISSIONS.UTIL.HEAT_SIGNATURE_DETECTED,
                        x = x,
                        y = y
                    }
                )
                script:queue(
                    {
                        type = "pan",
                        x = x,
                        y = y
                    }
                )
            end
        end
    end
end

local function followAccessCard(script, sim)
    local cardUnit = nil
    sim:forEachUnit(
        function(unit)
            if unit:hasTag("access_card_obj") then
                cardUnit = unit
                local x, y = unit:getLocation()
                script:queue(
                    {
                        type = "displayHUDInstruction",
                        text = STRINGS.MISSIONS.UTIL.ACCESS_CARD_DETECTED,
                        x = x,
                        y = y
                    }
                )
                script:queue(
                    {
                        type = "pan",
                        x = x,
                        y = y
                    }
                )
            end
        end
    )

    while true do
        local ev, triggerData = script:waitFor(mission_util.UNIT_WARP)
        if triggerData.unit:hasTag("access_card_obj") then
            script:queue(
                {
                    type = "hideHUDInstruction"
                }
            )
            local x, y = triggerData.unit:getLocation()
            if x and y then
                script:queue(
                    {
                        type = "displayHUDInstruction",
                        text = STRINGS.MISSIONS.UTIL.ACCESS_CARD_DETECTED,
                        x = x,
                        y = y
                    }
                )
                script:queue(
                    {
                        type = "pan",
                        x = x,
                        y = y
                    }
                )
            end
        end
    end
end

local function checkInterrogateTargets(script, sim, mission)
    local _, guard = script:waitFor(mission_util.PC_SAW_UNIT("interrogate"))

    local function onFailInterrogation(script, sim)
        sim:setMissionReward(0)
        sim:removeObjective("get_near")
        sim:removeObjective("stay_near")
        sim:removeObjective("guard_finish")
        sim:removeObjective("ko_target")
        script:removeHook(checkInterrogateTargets)
        sim.exit_warning = nil
        mission.failed = true
    end

    local function checkNoGuardKill(script, sim)
        script:waitFor(
            {
                trigger = "guard_dead"
            }
        )
        mission.killed_target = true
        onFailInterrogation(script, sim)
        script:queue(
            {
                script = SCRIPTS.INGAME.CENTRAL_FAILED_TARGET_DIED,
                type = "newOperatorMessage"
            }
        )
        script:waitFor(mission_util.PC_ANY)
        script:queue(
            {
                type = "clearOperatorMessage"
            }
        )
    end

    script:addHook(checkNoGuardKill)
    script:addHook(followHeatSig)
    sim:removeObjective(OBJECTIVE_ID)
    sim:addObjective(STRINGS.MISSIONS.ESCAPE.OBJ_DISABLE_TARGET, "ko_target")
    script:queue(1 * cdefs.SECONDS)
    script:queue(
        {
            script = SCRIPTS.INGAME.CENTRAL_SEEINTERROGATE,
            type = "newOperatorMessage"
        }
    )

    if not guard:isKO() then
        script:waitFor(PC_KNOCKOUT_CEO)
    end
    script:removeHook(checkNoGuardKill)
    assert(type(guard:getTraits().koTimer) == "number")

    guard:getTraits().koTimer = 6 -- nerf or remove fixed ko timer?

    script:removeHook(followHeatSig)
    script:queue(
        {
            type = "hideHUDInstruction"
        }
    )

    local x0, y0 = guard:getLocation()

    local checkGuardDistance = nil
    checkGuardDistance = createInterrogationHook(guard, onFailInterrogation)
    script:addHook(checkGuardDistance)

    local closestUnit, closestDistance = simquery.findClosestUnit(
                                             sim:getPC():getAgents(), x0, y0, function(u)
            return not u:isKO()
        end
                                         )
    --------------------------------------------------------------------------------------------
    -- adjusted range
    if closestDistance >= 1 then
        checkForTargetInRange(script, sim, guard, 1)
        script:waitFor(mission_util.PC_IN_RANGE_OF_TARGET(script, guard, 1))
    end
    --------------------------------------------------------------------------------------------
    guard:getTraits().interrogationStarted = true
    sim:addObjective(STRINGS.MISSIONS.ESCAPE.OBJ_BRAINSCAN, "guard_finish", 6)
    sim:addObjective(STRINGS.MISSIONS.ESCAPE.OBJ_STAYNEAR, "stay_near")

    sim:removeObjective("ko_target")

    script:queue(
        {
            script = SCRIPTS.INGAME.CENTRAL_INTERROGATE_START,
            type = "newOperatorMessage"
        }
    )
    script:waitFor(mission_util.PC_ANY)
    script:queue(
        {
            type = "clearOperatorMessage"
        }
    )

    brainScanBanter(script, sim)

    guard:getTraits().interrogationFinished = true

    if checkGuardDistance then
        script:removeHook(checkGuardDistance)
    end
    script:removeHook(checkNoGuardKill)
    sim:removeObjective("guard_finish")
    sim:removeObjective("stay_near")

    createVaultCard(script, sim)
    sim:getTags().cardEjected = true
    script:queue(
        {
            script = SCRIPTS.INGAME.CENTRAL_INTERROGATE_END,
            type = "newOperatorMessage"
        }
    )
    sim:addObjective(STRINGS.MISSIONS.ESCAPE.OBJ_RETRIEVE_ACCESS_CODE, "get_code")
    script:addHook(followAccessCard)

    local _, unit = script:waitFor(mission_util.PC_TOOK_UNIT_WITH_TAG("access_card_obj"))
    sim:removeObjective("get_code")
    unit:removeTag("access_card_obj")
    unit:addTag("mission_loot")
    mission.lootspawned = true
    script:removeHook(followAccessCard)
    script:queue(
        {
            type = "hideHUDInstruction"
        }
    )

    script:queue(16 * cdefs.SECONDS)
    script:queue(
        {
            type = "clearOperatorMessage"
        }
    )

end

local oldmissioninit = mission.init
function mission:init(scriptMgr, sim)
    local rets = {oldmissioninit(self, scriptMgr, sim)}
    local diffOpts = sim:getParams().difficultyOptions
    if diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        for _, hook in pairs(scriptMgr.hooks) do
            if hook.name == "CEO" then
                scriptMgr:removeHook(hook)
                break
            end
        end
        scriptMgr:addHook("CEO", checkInterrogateTargets, nil, self)
    end
    return unpack(rets)
end
