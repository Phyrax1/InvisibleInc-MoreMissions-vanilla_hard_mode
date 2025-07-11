local util = include( "modules/util" )
local serverdefs = include( "modules/serverdefs" )
local simdefs = include( "sim/simdefs" )
local array = include( "modules/array" )
local abilitydefs = include( "sim/abilitydefs" )
local simquery = include ( "sim/simquery" )
local abilityutil = include( "sim/abilities/abilityutil" )
local cdefs = include( "client_defs" )
local simdefs = include( "sim/simdefs" )

-- inverted spawn fitness check allows existing generatePrefabs worldgen functions to maximise distance to a prefab tag specified in mission.

local prefabs = include("sim/prefabs")
local generatePrefabs_old = prefabs.generatePrefabs
prefabs.generatePrefabs = function(cxt, candidates, tag, maxCount, fitnessFn, fitnessSelect, ...)
    local oldFitnessFn = fitnessFn
    if cxt.defaultFitnessFn and cxt.defaultFitnessFn[tag] then
        fitnessFn = cxt.defaultFitnessFn[tag]
    end
    local oldFitnessSelect = fitnessSelect
    if cxt.defaultFitnessSelect and cxt.defaultFitnessSelect[tag] then
        fitnessSelect = cxt.defaultFitnessSelect[tag]
    end
    if cxt.maxCountOverride and cxt.maxCountOverride[tag] then
        maxCount = cxt.maxCountOverride[tag]
    end
    if fitnessFn and fitnessSelect and fitnessSelect == prefabs.SELECT_HIGHEST and cxt.checkAllPieces
        and cxt.checkAllPieces[tag] then
        -- reject all possible placements once to force game to calculate fitness for all of them
        -- then do up to spawnQuota or maxCount single‐placements, using only the best fitness
        local placed = 0
        local maxCount = maxCount or 1000
        while placed < maxCount
            and not (cxt.checkAllSpawnQuota and cxt.checkAllSpawnQuota[tag] and placed >= cxt.checkAllSpawnQuota[tag]) do

            -- first pass: gather every viable candidate’s score
            local allScores = {}
            local function gatherFitness(...)
                local score = fitnessFn(...)
                if score > 0 then
                    table.insert(allScores, {args = {...}, score = score})
                end
                return 0
            end

            -- gather fitness, place nothing
            local dryPass = generatePrefabs_old(cxt, candidates, tag, 1, gatherFitness, fitnessSelect, ...)
            assert(dryPass == 0, string.format("Expected 0 prefabs placed in dry pass for '%s', got %d", tag, dryPass))
            log:write(
                simdefs.LOG_PROCGEN,
                string.format("[MM] fitness gathering finished, trying to place %d '%s' soon", maxCount - placed, tag)
            )

            -- sort by descending fitness
            table.sort(
                allScores, function(a, b)
                    return a.score > b.score
                end
            )

            -- real pass: try each candidate in turn until one fits
            local gotOne = false
            for _, entry in ipairs(allScores) do
                -- build a fitnessFn that only accepts this exact placement
                local function pickThis(...)
                    local args = {...}
                    for i = 1, #args do
                        if args[i] ~= entry.args[i] then
                            return 0
                        end
                    end
                    return 1
                end
                local success = generatePrefabs_old(cxt, candidates, tag, 1, pickThis, fitnessSelect, ...)
                if success == 1 then
                    gotOne = true
                    placed = placed + 1
                    log:write(simdefs.LOG_PROCGEN, string.format("[MM] Placed 1 '%s' at fitness=%.2f", tag, entry.score))
                    break
                else
                    log:write(
                        simdefs.LOG_PROCGEN,
                        string.format("[MM] '%s' fitness=%.2f failed fit, retrying next best", tag, entry.score)
                    )
                end
            end

            -- if none of the scored candidates could actually place, bail out
            if not gotOne then
                log:write(
                    simdefs.LOG_PROCGEN,
                    string.format("[MM] No viable placements for '%s' after trying all %d candidates", tag, #allScores)
                )
                break
            end
        end

        -- if we couldn’t place all, fill the rest with default fitness (spawnQuota < maxCount)
        if placed < maxCount then
            local remaining = maxCount - placed
            local n2 = generatePrefabs_old(cxt, candidates, tag, remaining, oldFitnessFn, oldFitnessSelect, ...)
            log:write(simdefs.LOG_PROCGEN, string.format("[MM] Placed %d '%s' with default logic", n2, tag))
            placed = placed + (n2 or 0)
        end
        return placed
    end
    return generatePrefabs_old(cxt, candidates, tag, maxCount, fitnessFn, fitnessSelect, ...)
end
