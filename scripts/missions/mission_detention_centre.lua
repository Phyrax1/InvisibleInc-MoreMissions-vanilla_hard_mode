local mission = include("sim/missions/mission_detention_centre")
local simdefs = include("sim/simdefs")
local util = include("modules/util")
local cdefs = include("client_defs")
local mission_util = include("sim/missions/mission_util")
local prefabs = include("sim/prefabs")

-- modified PC_USED_ABILITY from mission_util to return the unit using the ability
local PC_USED_ABILITY = function(name)
    return {action = "abilityAction", pre = true, fn = function(sim, ownerID, userID, abilityIdx, ...)

        local unit, ownerUnit = sim:getUnit(userID), sim:getUnit(ownerID)

        if not unit or not unit:isPC() or not ownerUnit then
            return nil
        end

        return ownerUnit:getAbilities()[abilityIdx]:getID() == name, unit
    end}
end

-- opening cell doors warps them, so this is an easy way to wait for door anim to finish after the console was used
local FINISH_DOOR_ANIM = {trigger = simdefs.TRG_UNIT_WARP}

local function alertCaptain(script, sim, target)
    local captains = {}
    for _, unit in pairs(sim:getNPC():getUnits()) do
        local uData = unit:getUnitData()
        local id = uData.id
        if id == "important_guard" and unit:canAct() then
            table.insert(captains, unit)
        end
    end
    local x, y = target:getLocation()
    for _, captain in ipairs(captains) do
        local alreadyAlerted = captain:isAlerted()
        captain:getBrain():spawnInterest(x, y, simdefs.SENSE_RADIO, simdefs.REASON_SHARED, target)
        if not alreadyAlerted then
            local x0, y0 = captain:getLocation()
            sim:dispatchEvent(
                simdefs.EV_UNIT_FLOAT_TXT, {txt = util.sformat(STRINGS.UI.ALARM_ADD, 1), x = x0, y = y0,
                                            color = {r = 1, g = 0.04, b = 0.04, a = 1}}
            )
            sim:trackerAdvance(1, STRINGS.UI.ALARM_SPOTTED)
            script:waitFrames(.25 * cdefs.SECONDS)
        end
    end
end

local function checkForOpenCells(script, sim, mission)
    local _, _, user = script:waitFor(PC_USED_ABILITY("open_detention_cells"))
    script:waitFor(FINISH_DOOR_ANIM)
    alertCaptain(script, sim, user)
end

------------------------------------------------------------------------------------------------

-- removes specified string and - if now empty of strings - nukes pass
local function removeStringCleanly(tagSet, strings)
    local search = {}
    for _, t in ipairs(strings) do
        search[t] = true
    end

    local function hasString(list)
        for _, v in ipairs(list) do
            if type(v) == "string" then
                return true
            end
        end
        return false
    end

    local function clean(list)
        for i = #list, 1, -1 do
            local v = list[i]
            if type(v) == "string" and search[v] then
                table.remove(list, i)
                return v
            elseif type(v) == "table" then
                local found = clean(v)
                if found then
                    if not hasString(v) then
                        table.remove(list, i)
                    end
                    return found
                end
            end
        end
    end

    for i = #tagSet, 1, -1 do
        local got = clean(tagSet[i])
        if got then
            if not hasString(tagSet[i]) then
                table.remove(tagSet, i)
            end
            return got
        end
    end
end

local function findTagPass(tagSet, target)
    local function containsString(tbl, target)
        if type(tbl) == "string" then
            return tbl == target
        elseif type(tbl) == "table" then
            for _, v in pairs(tbl) do
                if containsString(v, target) then
                    return true
                end
            end
        end
        return false
    end
    for i = 1, #tagSet do
        if containsString(tagSet[i], target) then
            return i
        end
    end
    return nil
end

local function detentionFitness(cxt, prefab, x, y)
    local tileCount = cxt:calculatePrefabLinkage(prefab, x, y)
    if tileCount == 0 then
        return 0 -- Doesn't link up
    end

    local maxDist = mission_util.calculatePrefabDistance(cxt, x, y, "entry")
    local fitness = tileCount + maxDist ^ 2
    log:write(
        simdefs.LOG_PROCGEN,
        string.format("[MM] detentionfitness: at (%d,%d) → maxDist=%.2f, fitness=%.2f", x, y, maxDist, fitness)
    )
    return fitness
end

local function exitFitness(cxt, prefab, x, y)
    local tileCount = cxt:calculatePrefabLinkage(prefab, x, y)
    if tileCount == 0 then
        return 0 -- Doesn't link up
    end

    local maxDist = mission_util.calculatePrefabDistance(cxt, x, y, "holdingcell")
    local fitness = tileCount + maxDist ^ 2
    log:write(
        simdefs.LOG_PROCGEN,
        string.format("[MM] exitfitness: at (%d,%d) → maxDist=%.2f, fitness=%.2f", x, y, maxDist, fitness)
    )
    return fitness
end

------------------------------------------------------------------------------------------------

local oldmissioninit = mission.init
function mission:init(scriptMgr, sim)
    oldmissioninit(self, scriptMgr, sim)
    local diffOpts = sim:getParams().difficultyOptions
    if diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        scriptMgr:addHook("MM_CELLS", checkForOpenCells, nil, self)
    end
end

local oldpregeneratePrefabs = mission.pregeneratePrefabs
function mission.pregeneratePrefabs(cxt, tagSet)
    oldpregeneratePrefabs(cxt, tagSet)
    local diffOpts = cxt.params.difficultyOptions
    if diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        -- re-order so it's always entry -> detention -> exit
        local detention = removeStringCleanly(tagSet, {"detention"})
        local exit = removeStringCleanly(tagSet, {"exit", "exit_vault"})
        local entryPass = findTagPass(tagSet, "entry")
        if entryPass then
            table.insert(tagSet, entryPass + 1, {{detention, detentionFitness}, fitnessSelect = prefabs.SELECT_HIGHEST})
            table.insert(tagSet, entryPass + 2, {{exit, exitFitness}, fitnessSelect = prefabs.SELECT_HIGHEST})
        else
            table.insert(tagSet, {{detention, detentionFitness}, fitnessSelect = prefabs.SELECT_HIGHEST})
            table.insert(tagSet, {{exit, exitFitness}, fitnessSelect = prefabs.SELECT_HIGHEST})
        end
        cxt.checkAllPieces = cxt.checkAllPieces or {}
        -- avoid setting this for rooms, increases consistency at the cost of prefab variety
        -- cxt.checkAllPieces["detention"] = true

        -- variety not relevant for exits, consistency is
        cxt.checkAllPieces["exit"] = true
        cxt.checkAllPieces["exit_vault"] = true
    end
end
