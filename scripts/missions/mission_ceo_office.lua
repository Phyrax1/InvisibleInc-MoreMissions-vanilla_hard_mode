local mission = include("sim/missions/mission_ceo_office")
local simdefs = include("sim/simdefs")
local simquery = include("sim/simquery")
local cdefs = include("client_defs")
local mission_util = include("sim/missions/mission_util")
local simfactory = include("sim/simfactory")
local unitdefs = include("sim/unitdefs")
local SCRIPTS = include('client/story_scripts')
local mathutil = include("modules/mathutil")
local util = include("modules/util")

--------------------------------------------------------------------------------------------
--[[ copied from mission_util, no longer needed if scan radius remains unchanged
-- if adjusting range here, remember to also adjust closestDistance in checkInterrogateTargets

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

end ]]

--------------------------------------------------------------------------------------------

local OBJECTIVE_ID = "ceoOffice"

local PC_KNOCKOUT_CEO = {trigger = simdefs.TRG_UNIT_KO, fn = function(sim, triggerData)
    if triggerData and (triggerData.ticks or 0) > 0 then
        if (not sim:isVersion("0.17.12") and triggerData.unit:getTraits().ko_trigger == "intimidate_guard")
            or triggerData.unit:getTraits().cfo then
            return triggerData.unit
        end
    end
end}

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

---------------------------------------------------------------------------------------------
-- copied AGP's aiplayer:spawnGuards override and modified it to accept a target argument which the guards spawn as close as possible to

local enforcers = {{{"npc_guard_enforcer_reinforcement", 100}, {"ce_inspector", 75, max_one = true},
                    {"ce_guard_enforcer_reinforcement_drone", 75}},
                   {{"npc_guard_enforcer_reinforcement", 100}, {"ce_inspector", 75, max_one = true},
                    {"ce_guard_enforcer_reinforcement_drone", 75}},
                   {{"npc_guard_enforcer_reinforcement_2", 100}, {"ce_inspector_2", 100, max_one = true},
                    {"ce_guard_enforcer_reinforcement_drone_2", 100}, {"ce_guard_enforcer_reinforcement_heavy", 100}},
                   {{"npc_guard_enforcer_reinforcement_2", 100}, {"ce_inspector_2", 100, max_one = true},
                    {"ce_guard_enforcer_reinforcement_drone_2", 100}, {"ce_guard_enforcer_reinforcement_heavy", 100}},
                   {{"npc_guard_enforcer_reinforcement_2", 100}, {"ce_inspector_2", 100, max_one = true},
                    {"ce_guard_enforcer_reinforcement_drone_2", 100}, {"ce_guard_enforcer_reinforcement_heavy", 100}},
                   {{"ce_guard_enforcer_reinforcement_3", 100}, {"ce_inspector_3", 100, max_one = true},
                    {"ce_guard_enforcer_reinforcement_drone_3", 100}, {"ce_guard_enforcer_reinforcement_heavy_2", 100}}}

local function spawnCloseGuards(sim, unitType, numGuards, target)
    local npc = sim:getNPC()
    local worldgen = include("sim/worldgen")
    local cells = sim:getCells("guard_spawn")
    if cells then
        cells = util.tdupe(cells)
        local i = 1
        while i <= #cells do
            if not simquery.canStaticPath(sim, nil, nil, cells[i]) or simquery.checkDynamicImpass(sim, cells[i]) then
                table.remove(cells, i)
            else
                i = i + 1
            end
        end
        -- sort available cells by distance to target
        if target then
            local tx, ty = target:getLocation()
            table.sort(
                cells, function(a, b)
                    return mathutil.dist2d(a.x, a.y, tx, ty) < mathutil.dist2d(b.x, b.y, tx, ty)
                end
            )
        end
    end

    numGuards = math.min(numGuards, #cells)
    local units = {}

    if numGuards > 0 then
        local unitData = unitdefs.lookupTemplate(unitType)
        if unitData.traits.enforcer then
            if unitdefs.lookupTemplate("ce_dummy_omni") and sim:hasObjective("security_hub")
                and sim:hasObjective("security_hub").current == 2 and sim:getParams().missionEvents
                and sim:getParams().missionEvents.advancedAlarm and not sim:getTags().spawnedHubGuard then
                sim:getTags().spawnedHubGuard = true
                local wt = util.weighted_list(sim._patrolGuard)
                unitType = wt:getChoice(sim:nextRand(1, wt:getTotalWeight()))
            elseif unitdefs.lookupTemplate("ce_inspector") then
                local enforcer_list = enforcers[math.min(sim._params.difficulty, #enforcers)]
                local wt = util.weighted_list()

                for i, choice in ipairs(enforcer_list) do
                    local count = false
                    if choice.max_one then
                        for i, unit in pairs(npc:getUnits()) do
                            if unit:getUnitData().id == choice[1] then
                                count = true
                                break
                            end
                        end
                    end

                    if not count then
                        wt:addChoice(choice[1], choice[2])
                    end
                end

                unitType = wt:getChoice(sim:nextRand(1, wt:getTotalWeight()))
            end
        end
        for i = 1, numGuards do
            if (sim._patrolGuard[unitType] or (sim._patrolGuard[1] and util.tnext(
                sim._patrolGuard, function(v)
                    return v[1] == unitType
                end
            )()))
                and (sim._patrolGuard._unique
                    or ((unitdefs.lookupTemplate("ce_dummy_omni") or unitdefs.lookupTemplate("ce_omni_hacker"))
                        and (sim._patrolGuard == worldgen.OMNI_GUARD or sim._patrolGuard == worldgen.OMNI_GUARD_FIX))) then
                local spawnedThreaths = {}
                for i, unit in pairs(npc:getUnits()) do
                    if unit:getTraits().isGuard and not unit:isDead() then
                        spawnedThreaths[unit:getUnitData().id] = (spawnedThreaths[unit:getUnitData().id] or 0) + 1
                    end
                end
                local patrolGuard
                while true do
                    patrolGuard = util.tdupe(sim._patrolGuard)
                    patrolGuard._unique = nil
                    for i, v in pairs(patrolGuard) do
                        if (spawnedThreaths[type(i) == "string" and i or patrolGuard[i][1]] or 0) > 0 then
                            patrolGuard[i] = nil
                        end
                    end
                    local storageType
                    if util.tcount(patrolGuard) == 0 then
                        for i, v in pairs(spawnedThreaths) do
                            spawnedThreaths[i] = v - 1
                        end
                    else
                        if type(next(patrolGuard)) == "number" then
                            local newPatrolGuard = {}
                            for i, v in pairs(patrolGuard) do
                                newPatrolGuard[#newPatrolGuard + 1] = v
                            end
                            patrolGuard = newPatrolGuard
                        end
                        break
                    end
                end
                local wt = util.weighted_list(patrolGuard)
                unitType = wt:getChoice(sim:nextRand(1, wt:getTotalWeight()))
            end
            table.insert(units, npc:createGuard(sim, unitType))
        end

        for i, unit in ipairs(units) do
            if unit:getTraits().ReinforcementPWROnHand then
                unit:getTraits().PWROnHand = unit:getTraits().ReinforcementPWROnHand
                unit:getTraits().cashOnHand = nil
            end

            if cells and #cells > 0 then
                if unit:getTraits().mainframe_ice_based_on_level then
                    unit:getTraits().mainframe_ice = math.ceil(
                                                         math.ceil(
                                                             (sim._params.difficulty / 2 + 1)
                                                                 * (unit:getTraits().hardmode and 1.2 or 1)
                                                         )
                                                     )
                    unit:getTraits().mainframe_iceMax = unit:getTraits().mainframe_ice
                end
                local cell = target and table.remove(cells, 1) or table.remove(cells, sim:nextRand(1, #cells)) -- pick the first cell in the list instead of randomly
                sim:warpUnit(unit, cell)
                npc:returnToIdleSituation(unit)
            end
        end

        if #units == 1 then
            sim:dispatchEvent(simdefs.EV_SHOW_DIALOG, {dialog = "threatDialog", dialogParams = {units[1]}})
        end

        for i, unit in ipairs(units) do
            unit:getTraits().spawnedGuard = true
            sim:dispatchEvent(simdefs.EV_UNIT_APPEARED, {unitID = unit:getID()})
            sim:dispatchEvent(simdefs.EV_TELEPORT, {units = {unit}, warpOut = false})
            sim:getPC():glimpseUnit(sim, unit:getID())
        end
    end
    return units
end

---------------------------------------------------------------------------------------------

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
        local newGuards = spawnCloseGuards(sim, "npc_guard_enforcer_reinforcement", 1, target)
        for i, newUnit in ipairs(newGuards) do
            local x1, y1 = target:getLocation()
            newUnit:getBrain():spawnInterest(x1, y1, simdefs.SENSE_RADIO, simdefs.REASON_REINFORCEMENTS, target)
            --------------------------------------------------------------------------------------------
            -- add armor
            -- newUnit:buffArmor(sim, 1) -- no sound effect or flytxt :(
            script:waitFrames(.25 * cdefs.SECONDS)
            local x2, y2 = newUnit:getLocation()
            sim:dispatchEvent(
                simdefs.EV_PLAY_SOUND, {sound = "SpySociety_DLC001/Actions/Flackguard_ArmourIncrease", x = x2, y = y2}
            )
            if not newUnit:getTraits().armor then
                newUnit:getTraits().armor = 0
            end
            newUnit:getTraits().armor = newUnit:getTraits().armor + 1
            sim:dispatchEvent(
                simdefs.EV_UNIT_FLOAT_TXT,
                {txt = util.sformat(STRINGS.UI.FLY_TXT.ARMOR_UP, 1), x = x2, y = y2,
                 color = {r = 1, g = 1, b = 41 / 255, a = 1}, alwaysShow = true}
            )
            local params = {color = {{symbol = "wall", r = 1, g = 1, b = 41 / 255, a = 1}}}
            sim:dispatchEvent(
                simdefs.EV_UNIT_ADD_FX, {unit = newUnit, kanim = "fx/firewall_buff_fx_2", symbol = "character",
                                         anim = "in", above = true, params = params}
            )
            sim:getPC():glimpseUnit(sim, newUnit:getID()) -- armor is not shown on unit without this
            --------------------------------------------------------------------------------------------
        end
        return true
    else
        return false
    end

end

local function brainScanBanter(script, sim)
    script:waitFor(mission_util.PC_START_TURN)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    script:queue(0.5 * cdefs.SECONDS)
    script:queue({script = SCRIPTS.INGAME.CENTRAL_CFO_BRAINSCAN_1, type = "newOperatorMessage"}) -- "Cerebral implant is transmitting. Begin deepening the scan."
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    script:queue({type = "clearOperatorMessage"})
    script:waitFor(mission_util.PC_START_TURN)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    script:queue(0.5 * cdefs.SECONDS)
    script:queue({script = SCRIPTS.INGAME.CENTRAL_CFO_BRAINSCAN_2, type = "newOperatorMessage"}) -- "Interesting, he's had memetic defence training. This is going to be trickier than expected."
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    script:queue({type = "clearOperatorMessage"})
    script:waitFor(mission_util.PC_START_TURN)
    sim:setClimax(true)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    callReinforcement(script, sim)
    script:queue(0.5 * cdefs.SECONDS)
    script:queue({script = SCRIPTS.INGAME.CENTRAL_CFO_BRAINSCAN_3, type = "newOperatorMessage"}) -- "Dammit! He got a signal out. Expect more company soon."
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    script:queue({type = "clearOperatorMessage"})
    ---------------------------------------------------------------------------------------------
    -- filler turn here
    script:waitFor(mission_util.PC_START_TURN)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    ---------------------------------------------------------------------------------------------
    script:waitFor(mission_util.PC_START_TURN)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    script:queue(0.5 * cdefs.SECONDS)
    script:queue({script = SCRIPTS.INGAME.CENTRAL_CFO_BRAINSCAN_4, type = "newOperatorMessage"}) -- "Incognita is in! We've broken him down now. Almost there, Operator."
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    script:queue({type = "clearOperatorMessage"})
    script:waitFor(mission_util.PC_START_TURN)
    sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/transferData")
    script:queue(0.5 * cdefs.SECONDS)
    script:queue({script = SCRIPTS.INGAME.CENTRAL_CFO_BRAINSCAN_5, type = "newOperatorMessage"}) -- "The data is starting to come in now. Just a little longer."
    sim:incrementTimedObjective("guard_finish")
    script:waitFor(mission_util.PC_ANY)
    script:queue({type = "clearOperatorMessage"})

    script:waitFor(mission_util.PC_START_TURN)
end

local function checkForTargetInRange(script, sim, guard, range)
    local x0, y0 = guard:getLocation()
    local closestUnit, closestDistance = simquery.findClosestUnit(
                                             sim:getPC():getAgents(), x0, y0, function(u)
            return not u:isKO()
        end
                                         )
    if closestDistance > range then
        script:queue({script = SCRIPTS.INGAME.CENTRAL_MOVE_INTO_RANGE, type = "newOperatorMessage"})
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
                    {type = "displayHUDInstruction", text = STRINGS.MISSIONS.UTIL.HEAT_SIGNATURE_DETECTED, x = x, y = y}
                )
                script:queue({type = "pan", x = x, y = y})
            end
        end
    )

    while true do
        local ev, triggerData = script:waitFor(mission_util.UNIT_WARP)
        if triggerData.unit:getTraits().cfo then
            script:queue({type = "hideHUDInstruction"})
            local x, y = triggerData.unit:getLocation()
            if x and y then
                script:queue(
                    {type = "displayHUDInstruction", text = STRINGS.MISSIONS.UTIL.HEAT_SIGNATURE_DETECTED, x = x, y = y}
                )
                script:queue({type = "pan", x = x, y = y})
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
                    {type = "displayHUDInstruction", text = STRINGS.MISSIONS.UTIL.ACCESS_CARD_DETECTED, x = x, y = y}
                )
                script:queue({type = "pan", x = x, y = y})
            end
        end
    )

    while true do
        local ev, triggerData = script:waitFor(mission_util.UNIT_WARP)
        if triggerData.unit:hasTag("access_card_obj") then
            script:queue({type = "hideHUDInstruction"})
            local x, y = triggerData.unit:getLocation()
            if x and y then
                script:queue(
                    {type = "displayHUDInstruction", text = STRINGS.MISSIONS.UTIL.ACCESS_CARD_DETECTED, x = x, y = y}
                )
                script:queue({type = "pan", x = x, y = y})
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
        script:waitFor({trigger = "guard_dead"})
        mission.killed_target = true
        onFailInterrogation(script, sim)
        script:queue({script = SCRIPTS.INGAME.CENTRAL_FAILED_TARGET_DIED, type = "newOperatorMessage"})
        script:waitFor(mission_util.PC_ANY)
        script:queue({type = "clearOperatorMessage"})
    end

    script:addHook(checkNoGuardKill)
    script:addHook(followHeatSig)
    sim:removeObjective(OBJECTIVE_ID)
    sim:addObjective(STRINGS.MISSIONS.ESCAPE.OBJ_DISABLE_TARGET, "ko_target")
    script:queue(1 * cdefs.SECONDS)
    script:queue({script = SCRIPTS.INGAME.CENTRAL_SEEINTERROGATE, type = "newOperatorMessage"})

    if not guard:isKO() then
        script:waitFor(PC_KNOCKOUT_CEO)
    end
    script:removeHook(checkNoGuardKill)
    --[[assert(type(guard:getTraits().koTimer) == "number")

    guard:getTraits().koTimer = 6 ]] -- No longer override the ko time with 6

    script:removeHook(followHeatSig)
    script:queue({type = "hideHUDInstruction"})

    local x0, y0 = guard:getLocation()

    local checkGuardDistance = nil
    checkGuardDistance = mission_util.createInterrogationHook(guard, onFailInterrogation)
    script:addHook(checkGuardDistance)

    local closestUnit, closestDistance = simquery.findClosestUnit(
                                             sim:getPC():getAgents(), x0, y0, function(u)
            return not u:isKO()
        end
                                         )

    if closestDistance > 3 then
        checkForTargetInRange(script, sim, guard, 3)
        script:waitFor(mission_util.PC_IN_RANGE_OF_TARGET(script, guard, 3))
    end
    guard:getTraits().interrogationStarted = true

    sim:addObjective(STRINGS.MISSIONS.ESCAPE.OBJ_BRAINSCAN, "guard_finish", 7) -- changed from 6 to 7
    sim:addObjective(STRINGS.MISSIONS.ESCAPE.OBJ_STAYNEAR, "stay_near")

    sim:removeObjective("ko_target")

    script:queue({script = SCRIPTS.INGAME.CENTRAL_INTERROGATE_START, type = "newOperatorMessage"})
    script:waitFor(mission_util.PC_ANY)
    script:queue({type = "clearOperatorMessage"})

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
    script:queue({script = SCRIPTS.INGAME.CENTRAL_INTERROGATE_END, type = "newOperatorMessage"})
    sim:addObjective(STRINGS.MISSIONS.ESCAPE.OBJ_RETRIEVE_ACCESS_CODE, "get_code")
    script:addHook(followAccessCard)

    local _, unit = script:waitFor(mission_util.PC_TOOK_UNIT_WITH_TAG("access_card_obj"))
    sim:removeObjective("get_code")
    unit:removeTag("access_card_obj")
    unit:addTag("mission_loot")
    mission.lootspawned = true
    script:removeHook(followAccessCard)
    script:queue({type = "hideHUDInstruction"})

    script:queue(16 * cdefs.SECONDS)
    script:queue({type = "clearOperatorMessage"})

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

local escape_mission = include("sim/missions/escape_mission")

local function minDistanceByTag(cxt, x, y, tag)
    local best = math.huge
    for _, c in ipairs(cxt.candidates) do
        for _, t in ipairs(c.prefab.tags or {}) do
            if t == tag then
                local d = mathutil.dist2d(x, y, c.tx, c.ty)
                best = math.min(best, d)
            end
        end
    end
    return best ~= math.huge and best or 0
end

local OFFSET = 10000 -- negative fitness gets discarded so just add an offset

local function guardEntranceFitness(cxt, prefab, x, y)
    local tileCount = cxt:calculatePrefabLinkage(prefab, x, y)
    if tileCount == 0 then
        return 0
    end

    local minDist = minDistanceByTag(cxt, x, y, "ceo_office")
--[[     log:write(
        string.format(
            "guardEntranceFitness: prefab=%s at (%d,%d) → minDist=%d", prefab.filename or "<unknown>", x, y, minDist
        )
    ) ]]
    local fitness = tileCount - minDist ^ 2 + OFFSET
--[[     log:write(
        string.format(
            "guardEntranceFitness: prefab=%s at (%d,%d) → fitness=%d", prefab.filename or "<unknown>", x, y, fitness
        )
    ) ]]
    return fitness
end

function mission.generatePrefabs(cxt, candidates)
    local diffOpts = cxt.params.difficultyOptions
    if diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        local prefabs = include("sim/prefabs")
        cxt.defaultFitnessFn = cxt.defaultFitnessFn or {}
        cxt.defaultFitnessSelect = cxt.defaultFitnessSelect or {}
        cxt.maxCountOverride = cxt.maxCountOverride or {}
        cxt.maxUpdatedPlacement = cxt.maxUpdatedPlacement or {}
        cxt.defaultFitnessFn["entry_guard"] = guardEntranceFitness
        cxt.defaultFitnessSelect["entry_guard"] = prefabs.SELECT_HIGHEST
        cxt.maxUpdatedPlacement["entry_guard"] = 1
    end
    escape_mission.generatePrefabs(cxt, candidates)
end
