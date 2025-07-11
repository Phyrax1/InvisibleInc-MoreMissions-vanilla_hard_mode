-- hard mode: additional enforcer on using vault keycard, nearest enforcers will investigate when a container is lootspawned
-- + guard entry spawns in a fixed distance from the vault. adjust optDepth in the fitness function to tweak
local mission = include("sim/missions/mission_vault")
local simdefs = include("sim/simdefs")
local cdefs = include("client_defs")
local mazegen = include("sim/mazegen")

local LOOT_SAFE = {action = "abilityAction", fn = function(sim, ownerID, userID, abilityIdx, ...)
    local unit, ownerUnit = sim:getUnit(userID), sim:getUnit(ownerID)

    if not unit or not unit:isPC() or not ownerUnit then
        return nil
    end
    if ownerUnit:getAbilities()[abilityIdx]:getID() == "stealCredits" then
        if ownerUnit:hasTag("vault") then
            return ownerUnit, unit
        end
    end
end}

-- from mission.util, added actual returns
local PC_UNLOCK_DOOR = function()
    return {trigger = simdefs.TRG_UNLOCK_DOOR, fn = function(sim, evData)
        return evData.cell, evData.tocell, evData.unit
    end}
end

-- nearest enforcer investigates for every looted vault container
local function lootVaultAftermath(script, sim, mission)
    while true do
        local _, _, unit = script:waitFor(LOOT_SAFE)
        local x, y = unit:getLocation()
        local notEnforcer = {}
        for _, unit in pairs(sim:getNPC():getUnits()) do
            if unit:isValid() and not unit:getTraits().enforcer then
                table.insert(notEnforcer, unit:getID())
            end
        end
        sim:getNPC():spawnInterestWithReturn(x, y, simdefs.SENSE_RADIO, simdefs.REASON_ALARMEDSAFE, unit, notEnforcer)
    end
end

-- second enforcer spawns on opening the vault (NIAA lock decoder bypasses this - bug or feature?)
local function unlockVaultDoorAftermath(script, sim, mission)
    while true do
        local _, cell = script:waitFor(PC_UNLOCK_DOOR())
        if cell.procgenRoom and cell.procgenRoom.tags and cell.procgenRoom.tags["vault"] then
            local x, y = cell.x, cell.y
            local newGuards = sim:getNPC():spawnGuards(sim, simdefs.TRACKER_SPAWN_UNIT_ENFORCER, 1)
            for i, newUnit in ipairs(newGuards) do
                script:queue({type = "pan", x = x, y = y})
                script:waitFrames(.25 * cdefs.SECONDS)
                newUnit:getBrain():spawnInterest(x, y, simdefs.SENSE_RADIO, simdefs.REASON_REINFORCEMENTS)
            end
            break
        end
    end
end

local function guardEntranceFitness(cxt, prefab, x, y)
    local adjX, adjY = x + 1, y + 1 -- need to adjust for the prefab anchor of the guard entry being outside of it

    local startRoom = cxt:roomContaining(adjX, adjY)
    if not startRoom then
        return 0
    end

    local minDepth = nil
    mazegen.breadthFirstSearch(
        cxt, startRoom, function(r)
            if r.tags["vault"] and minDepth == nil then
                minDepth = r.depth
            end
        end
    )

    if not minDepth then
        return 0
    end

    local optDepth = 6 -- this feels about right
    local fitness = 1 / (1 + math.abs(minDepth - optDepth))
    log:write(
        simdefs.LOG_PROCGEN, string.format(
            "[MM] guardEntranceFitness (BFS): at (%d,%d) → minDepth=%d, optDepth=%d, fitness=%.3f", adjX, adjY,
            minDepth, optDepth, fitness
        )
    )
    return fitness
end

---------------------------------------------------------------------------------------------------------------

local oldmissioninit = mission.init
function mission:init(scriptMgr, sim)
    oldmissioninit(self, scriptMgr, sim)
    local diffOpts = sim:getParams().difficultyOptions
    if diffOpts and diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        scriptMgr:addHook("MM_VAULT-LOOT", lootVaultAftermath, nil, self)
        scriptMgr:addHook("MM_VAULT-UNLOCK", unlockVaultDoorAftermath, nil, self)
    end
end

local oldGeneratePrefabs = mission.generatePrefabs
function mission.generatePrefabs(cxt, candidates)
    local diffOpts = cxt.params.difficultyOptions
    if diffOpts and diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        local prefabs = include("sim/prefabs")
        cxt.defaultFitnessFn = cxt.defaultFitnessFn or {}
        cxt.defaultFitnessFn["entry_guard"] = guardEntranceFitness
        cxt.defaultFitnessSelect = cxt.defaultFitnessSelect or {}
        cxt.defaultFitnessSelect["entry_guard"] = prefabs.SELECT_HIGHEST
        cxt.checkAllPieces = cxt.checkAllPieces or {}
        cxt.checkAllPieces["entry_guard"] = true
    end
    return oldGeneratePrefabs(cxt, candidates)
end
