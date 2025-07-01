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
prefabs.generatePrefabs = function( cxt, candidates, tag, maxCount, fitnessFn, fitnessSelect, ... )
	if not fitnessFn and cxt.defaultFitnessFn and cxt.defaultFitnessSelect and cxt.defaultFitnessFn[tag] and cxt.defaultFitnessSelect[tag] then
		fitnessFn = cxt.defaultFitnessFn[tag]
		fitnessSelect = cxt.defaultFitnessSelect[tag]
		if cxt.maxCountOverride[tag] then
			maxCount = cxt.maxCountOverride[tag]
		end
		-- local oldMaxCount = maxCount
		-- maxCount = 1
		-- for i = (oldMaxCount - 1), 1, -1 do
			-- generatePrefabs_old( cxt, candidates, tag, maxCount, fitnessFn, fitnessSelect, ... ) --needed so BOTH guard exits spawn far from mole prefab. Re-run function as many times as original maxCount
		-- end
		        -- used for cfo office so only one guard entry gets adjusted, does custom fitness for maxUpdatedPlacement times, then default to vanilla
        	if cxt.maxUpdatedPlacement and cxt.maxUpdatedPlacement[tag] then
            		local limit = cxt.maxUpdatedPlacement[tag]
            		local placed = {}
            		local nSmart = math.min(limit, maxCount)

            		local smart = {generatePrefabs_old(cxt, candidates, tag, nSmart, fitnessFn, fitnessSelect, ...)}
            		for _, inst in ipairs(smart) do
                		table.insert(placed, inst)
            		end

            		cxt.maxUpdatedPlacement[tag] = limit - nSmart

            		local remain = maxCount - nSmart
            		if remain > 0 then
                		local oldFn = fitnessFn
                		local oldSelect = fitnessSelect

                		fitnessFn = nil
                		fitnessSelect = nil

                		local dumb = {generatePrefabs_old(cxt, candidates, tag, remain, fitnessFn, fitnessSelect, ...)}
                		for _, inst in ipairs(dumb) do
                    			table.insert(placed, inst)
                		end

                		fitnessFn = oldFn
                		fitnessSelect = oldSelect
            		end
            		return placed
        	end
	end

	return generatePrefabs_old( cxt, candidates, tag, maxCount, fitnessFn, fitnessSelect, ... )
end
