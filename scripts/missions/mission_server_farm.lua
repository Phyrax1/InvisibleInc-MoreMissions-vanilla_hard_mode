local mission = include("sim/missions/mission_server_farm")
local simdefs = include("sim/simdefs")
local mission_util = include("sim/missions/mission_util")
local SCRIPTS = include('client/story_scripts')
local serverdefs = include("modules/serverdefs")
local cdefs = include("client_defs")

local USE_TERM = {
    action = "abilityAction",
    fn = function(sim, ownerID, userID, abilityIdx, ...)
        local unit, ownerUnit = sim:getUnit(userID), sim:getUnit(ownerID)

        if not unit or not unit:isPC() or not ownerUnit or not ownerUnit:getTraits().bigshopcat then
            return nil
        end

        if ownerUnit:getAbilities()[abilityIdx]:getID() == "showItemStore" then
            return ownerUnit
        end
    end
}

local function useServerTerminal(script, sim, mission)
    local _, terminal = script:waitFor(USE_TERM)
    mission.used_terminal = true
    script:waitFor(mission_util.UI_SHOP_CLOSED)

    terminal:destroyTab()
    --------------------------------------------------------------------------------------------
    -- daemon on terminal use
    script:waitFrames(.5 * cdefs.SECONDS)
    sim:getNPC():addMainframeAbility(
        sim, serverdefs.ENDLESS_DAEMONS[sim:nextRand(1, #serverdefs.ENDLESS_DAEMONS)], sim:getNPC(), 0
    )
    --------------------------------------------------------------------------------------------
    local possibleUnits = {}
    for _, unit in pairs(sim:getAllUnits()) do
        if unit:getTraits().mainframe_item and unit:getPlayerOwner() ~= sim:getPC()
            and not unit:getTraits().mainframe_program and unit:getTraits().mainframe_status ~= "off" then
            table.insert(possibleUnits, unit)
        end
    end
    if #possibleUnits > 0 then
        script:waitFrames(.75 * cdefs.SECONDS)
        script:queue(
            {
                type = "showIncognitaWarning",
                txt = STRINGS.UI.WARNING_NEW_DAEMON,
                vo = "SpySociety/VoiceOver/Incognita/Pickups/Warning_New_Daemon"
            }
        )
        script:waitFrames(.75 * cdefs.SECONDS)

        for k = 1, 3 do
            if #possibleUnits > 0 then
                local index = sim:nextRand(1, #possibleUnits)
                local unit = possibleUnits[index]
                table.remove(possibleUnits, index)
                --------------------------------------------------------------------------------------------
                -- replaced daemons with 2.0 daemons
                unit:getTraits().mainframe_program = serverdefs.ENDLESS_DAEMONS[sim:nextRand(
                                                         1, #serverdefs.ENDLESS_DAEMONS
                                                     )]
                ---------------------------------------------------------------------------------------------
                local x, y = unit:getLocation()
                script:queue(
                    {
                        type = "pan",
                        x = x,
                        y = y
                    }
                )

                sim:getPC():glimpseUnit(sim, unit:getID())
                sim:dispatchEvent(
                    simdefs.EV_UNIT_MAINFRAME_UPDATE, {
                        units = {unit.unitID},
                        reveal = true
                    }
                )
                sim:dispatchEvent(
                    simdefs.EV_UNIT_UPDATE_ICE, {
                        unit = unit,
                        ice = unit:getTraits().mainframe_ice,
                        delta = 0,
                        refreshAll = true
                    }
                )
                sim:dispatchEvent(
                    simdefs.EV_MAINFRAME_INSTALL_NEW_DAEMON, {
                        target = unit
                    }
                )
                sim:dispatchEvent(simdefs.EV_PLAY_SOUND, "SpySociety/Actions/mainframe_daemonmove")
                script:waitFrames(1 * cdefs.SECONDS)
            end
        end

        local x, y = terminal:getLocation()
        sim:dispatchEvent(simdefs.EV_SCRIPT_EXIT_MAINFRAME)
        script:queue(
            {
                type = "pan",
                x = x,
                y = y
            }
        )
        script:waitFrames(1 * cdefs.SECONDS)
        script:queue(
            {
                script = SCRIPTS.INGAME.AFTERMATH.SERVERFARM[sim:nextRand(1, #SCRIPTS.INGAME.AFTERMATH.SERVERFARM)],
                type = "newOperatorMessage"
            }
        )

        script:queue(1 * cdefs.SECONDS)
        script:queue(
            {
                script = SCRIPTS.INGAME.MONSTERCAT_POST[sim:nextRand(1, #SCRIPTS.INGAME.MONSTERCAT_POST)],
                type = "newOperatorMessage"
            }
        )
    end
end

local oldmissioninit = mission.init
function mission:init(scriptMgr, sim)
    local rets = {oldmissioninit(self, scriptMgr, sim)}
    local diffOpts = sim:getParams().difficultyOptions
    if diffOpts.MM_difficulty and diffOpts.MM_difficulty == "hard" then
        for _, hook in pairs(scriptMgr.hooks) do
            if hook.name == "USE_TERMINAL" then
                scriptMgr:removeHook(hook)
                break
            end
        end
        scriptMgr:addHook("USE_TERMINAL", useServerTerminal, nil, self)
    end
    return unpack(rets)
end
