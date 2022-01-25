---@author CARTOK
---@author RusteyBucket
-- General Transport Fever 2 API documentation can be found here: https://transportfever2.com/wiki/api/index.html
-- GUI items contain code and inspiration from 'Departure Board' created by kryfield, available here: https://steamcommunity.com/workshop/filedetails/?id=2692112427
-- GUI specific API documentation can be found here: https://transportfever2.com/wiki/api/modules/api.gui.html
-- Further information of GUI states and functions can be found here: https://www.transportfever2.com/wiki/doku.php?id=modding:userinterface
-- Include all required helper functions and scripts to make this mod work
local gui = require "gui"
local log = require 'cartok/logging'
local helper = require 'cartok/helper'
local enums = require 'cartok/enums'

local firstLoad = true
local gui_settingsWindow = nil

-- This is the entire data for the mod, it is stored in the save game as well as loaded in GUI thread for access
local state = {
    -- The version of the data, this is for compatibility purposes and only meant to be updated when the state data format changes.
    version = 3,
    log = {
        debugging = false, -- Debugging on/off.
        verbose_debugging = true, -- Verbose debugging on/off.
    },
    line_data = {}, -- An up-to-date list (since last sampling...) of the Player lines and associated data.
    last_sample_time = -1, -- Keeps track of what month (or time) the last sample was taken, in order to re-trigger a new sampling when month (or time) changes.
    time_based_sampling = false, -- If true, then os time is used for sampling rather than in-game months.
    sample_time_interval = 30, -- If os time is used for sampling, take a sample every this number of seconds.
    sample_size = 6, -- Number of samples to average data out over.
    update_interval = 2, -- For every x sampling, do a vehicle update (check if a vehicle should be added or removed)
    sample_restart = 2, -- Following an update of a Line, the number of recorded samples will be reset to this value for the line to delay an update until sufficient data is available.
    samples_since_last_update = 0, -- A counter to keep track of how many samples have been taken since last update, and then re-trigger an update when 'update_interval' is reached.
    delaying_counter_due_to_being_paused = 0, -- A counter that keeps track of how many attempts at sampling were foiled due to the game being paused.
}

---@param line_id number
---@return boolean success whether a vehicle was removed
---removes the oldest vehicle from the specified line
local function removeVehicleFromLine(line_id)
    local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)

    -- Find the oldest vehicle on the line
    if (#lineVehicles > 0) then
        local oldestVehicleId = helper.getOldestVehicleId(lineVehicles)

        -- Remove/sell the oldest vehicle (instantly sells)
        api.cmd.sendCommand(api.cmd.make.sellVehicle(oldestVehicleId))
        log.info(" -1 vehicle: " .. helper.getEntityName(line_id) .. " (" .. helper.printLineData(state.line_data, line_id) .. ")")
        log.debug("vehicle_id: " .. oldestVehicleId .. " line_id: " .. line_id)

        return true
    else
        return false
    end
end

---@param line_id number
---@return boolean success whether a vehicle was added
---adds a vehicle to the specified line_id by cloning an existing vehicle
local function addVehicleToLine(line_id)
    local success = false
    local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
    local depot_id
    local stop_id
    local vehicleToDuplicate

    -- TODO: Test whether enough money is available or don't empty the vehicle when it's hopeless anyway
    -- TODO: Figure out a better way to find the closest depot (or one at all).
    -- This merely tries to send an existing vehicle on the line to the depot, checks if succeeds then cancel the depot call but uses the depot data.
    -- Unfortunately sending a vehicle to a depot empties the vehicle.
    for _, vehicle_id in pairs(lineVehicles) do
        -- For now filter this to passenger transportation only.
        -- TODO: Extend to further types of cargo.
        if helper.vehicleTransportsPassengers(vehicle_id) then

            --   vehiclePrice=api.engine.getComponent(vehicle_id,) TODO: figure out how the hell to get to the stuff you can see as a player, goddamnit...

            api.cmd.sendCommand(api.cmd.make.sendToDepot(vehicle_id, false))
            vehicleToDuplicate = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)

            if vehicleToDuplicate.state == api.type.enum.TransportVehicleState.GOING_TO_DEPOT then
                depot_id = vehicleToDuplicate.depot
                stop_id = vehicleToDuplicate.stopIndex

                local lineCommand = api.cmd.make.setLine(vehicle_id, line_id, stop_id)
                api.cmd.sendCommand(lineCommand)
                break
            end
        end
    end

    if depot_id then
        local transportVehicleConfig = vehicleToDuplicate.transportVehicleConfig
        local purchaseTime = helper.getGameTime()

        -- Reset applicable parts of the transportVehicleConfig
        for _, vehicle in pairs(transportVehicleConfig.vehicles) do
            vehicle.purchaseTime = purchaseTime
            vehicle.maintenanceState = 1
        end

        local buyCommand = api.cmd.make.buyVehicle(api.engine.util.getPlayer(), depot_id, transportVehicleConfig)
        api.cmd.sendCommand(buyCommand, function(cmd, res)
            if (res and cmd.resultVehicleEntity) then
                success = true

                local lineCommand = api.cmd.make.setLine(cmd.resultVehicleEntity, line_id, stop_id)
                api.cmd.sendCommand(lineCommand)

                log.info(" +1 vehicle: " .. helper.getEntityName(line_id) .. " (" .. helper.printLineData(state.line_data, line_id) .. ")")
                log.debug("vehicle_id: " .. cmd.resultVehicleEntity .. " line_id: " .. line_id .. " depot_id: " .. depot_id)
            else
                log.warn("Unable to add vehicle to line: " .. helper.getEntityName(line_id) .. " - Insufficient cash?")
            end
        end)
    else
        log.warn("Unable to add vehicle to line: " .. helper.getEntityName(line_id) .. " - No available depot.")
        log.debug("line_id: " .. line_id)
    end

    return success
end

---takes data samples of all applicable lines
local function sampleLines()
    log.info("============ Sampling ============")

    local sampledLineData = {}
    local ignoredLines = {}
    sampledLineData, ignoredLines = helper.getLineData()

    local sampledLines = {}

    for line_id, line_data in pairs(sampledLineData) do
        if state.line_data[line_id] then
            sampledLineData[line_id].samples = state.line_data[line_id].samples + 1
            -- The below ones are already captured in the fresh sample taken, don't overwrite those values!
            -- sampledLineData[line_id].vehicles = state.line_data[line_id].vehicles
            -- sampledLineData[line_id].capacity = state.line_data[line_id].capacity
            -- sampledLineData[line_id].occupancy = state.line_data[line_id].occupancy
            sampledLineData[line_id].demand = math.round(((state.line_data[line_id].demand * (state.sample_size - 1)) + line_data.demand) / state.sample_size)
            sampledLineData[line_id].usage = math.round(((state.line_data[line_id].usage * (state.sample_size - 1)) + line_data.usage) / state.sample_size)
            sampledLineData[line_id].rate = math.round(((state.line_data[line_id].rate * (state.sample_size - 1)) + line_data.rate) / state.sample_size)
        else
            sampledLineData[line_id].samples = 1
        end

        local name = helper.printLine(line_id)
        table.insert(sampledLines, name)
    end

    -- By initially just using the fresh sampledLineData, no longer existing lines are removed. Does this cause increased memory/CPU usage?
    state.line_data = sampledLineData

    -- print general summary for debugging purposes
    log.debug('Sampled Lines: ' .. #sampledLines .. ' (Ignored Lines: ' .. #ignoredLines .. ")")

    -- printing the list of lines sampled for additional debug info
    if (log.isVerboseDebugging()) then
        local debugOutput = ""

        -- Sampled lines
        if (#sampledLines > 0) then
            table.sort(sampledLines)
            debugOutput = "Sampled lines:\n"
            debugOutput = debugOutput .. helper.printArrayWithBreaks(sampledLines)
            log.debug(debugOutput)
        end

        -- Ignored lines
        if (#ignoredLines > 0) then
            local sampledIgnoredLines = {}
            for i = 1, #ignoredLines do
                local name = helper.printLine(ignoredLines[i])
                table.insert(sampledIgnoredLines, name)
            end
            table.sort(sampledIgnoredLines)

            debugOutput = "Ignored lines:\n"
            debugOutput = debugOutput .. helper.printArrayWithBreaks(sampledIgnoredLines)
            log.debug(debugOutput)
        end
    end
end

--- updates vehicle amount if applicable and line list in general
local function updateLines()
    log.info("============ Updating ============")

    local lines = helper.getPlayerLines()
    local lineCount = 0
    local totalVehicleCount = 0

    for _, line_id in pairs(lines) do
        -- TODO: Should check that the line still exists, and still transports passengers.
        if state.line_data[line_id] then
            lineCount = lineCount + 1
            totalVehicleCount = totalVehicleCount + state.line_data[line_id].vehicles

            -- If a line has sufficient samples, then check whether vehicles should be added/removed.
            if state.line_data[line_id].samples and state.line_data[line_id].samples >= state.sample_size then
                -- Check if a vehicle should be added to a Line.
                if helper.moreVehicleConditions(state.line_data, line_id) then
                    if addVehicleToLine(line_id) then
                        state.line_data[line_id].samples = state.sample_restart
                        totalVehicleCount = totalVehicleCount + 1
                    end
                    -- Check instead whether a vehicle should be removed from a Line.
                elseif helper.lessVehiclesConditions(state.line_data, line_id) then
                    if removeVehicleFromLine(line_id) then
                        state.line_data[line_id].samples = state.sample_restart
                        totalVehicleCount = totalVehicleCount - 1
                    end
                end
            end
        end
    end

    local ignored = #api.engine.system.lineSystem.getLines() - lineCount
    log.info("Total Lines: " .. lineCount .. " Total Vehicles: " .. totalVehicleCount .. " (Ignored Lines: " .. ignored .. ")")
end

---updates the trackers of when the next update gets unlocked
local function checkIfUpdateIsDue()
    local update_is_due = false

    ---TODO: make OS time pause with the game to avoid infinite loop
    if (state.time_based_sampling) then
        -- Check if sufficient os time has passed since last sample. If so, trigger another sample.
        local current_os_time = os.time()
        if current_os_time - state.last_sample_time >= state.sample_time_interval then
            if game.interface.getGameSpeed() > 0 then
                if state.delaying_counter_due_to_being_paused == 0 then
                    state.last_sample_time = current_os_time
                    update_is_due = true
                elseif state.delaying_counter_due_to_being_paused == 1 then
                    state.delaying_counter_due_to_being_paused = 0
                    state.last_sample_time = current_os_time
                elseif state.delaying_counter_due_to_being_paused > 1 then
                    state.delaying_counter_due_to_being_paused = 1
                end
            elseif state.delaying_counter_due_to_being_paused then
                state.delaying_counter_due_to_being_paused = state.delaying_counter_due_to_being_paused + 1
            else
                state.delaying_counter_due_to_being_paused = 1
            end
        end
    else
        -- Check if the month has changed since last sample. If so, trigger another sample. 1 sample/month.
        local current_month = helper.getGameMonth()
        if state.last_sample_time ~= current_month then
            state.last_sample_time = current_month
            update_is_due = true
        end
    end

    if (update_is_due) then
        sampleLines()
        state.samples_since_last_update = state.samples_since_last_update + 1

        if state.samples_since_last_update >= state.update_interval then
            updateLines()
            state.samples_since_last_update = 0
        end
    end
end

-------------------------------------------------------------
--------------------- GUI STUFF -----------------------------
-------------------------------------------------------------

local function gui_buttonClick()
    if not gui_settingsWindow:isVisible() then
        gui_settingsWindow:setVisible(true, false)
    else
        gui_settingsWindow:setVisible(false, false)
    end
end

local function gui_init()
    -- Create LineManager button in the main GUI
    local buttonLabel = gui.textView_create("gameInfo.linemanager.label", "[LM]")
    local button = gui.button_create("gameInfo.linemanager.button", buttonLabel)
    button:onClick(gui_buttonClick)
    -- TODO: Should add a divider in the bar before this button. How?
    game.gui.boxLayout_addItem("gameInfo.layout", button.id)

    -- SETTINGS WINDOW
    -- Create a BoxLayout for the options
    local settingsBox = api.gui.layout.BoxLayout.new("VERTICAL")

    -- Create the SETTINGS window
    gui_settingsWindow = api.gui.comp.Window.new("", settingsBox)
    gui_settingsWindow:setTitle("LineManager Settings")
    gui_settingsWindow:addHideOnCloseHandler()
    gui_settingsWindow:setMovable(true)
    gui_settingsWindow:setPinButtonVisible(true)
    gui_settingsWindow:setResizable(false)
    gui_settingsWindow:setSize(api.gui.util.Size.new(300, 200))
    gui_settingsWindow:setPosition(0, 0)
    gui_settingsWindow:setPinned(true)
    gui_settingsWindow:setVisible(false, false)

    -- Add a header for the Game options
    local header_GameOptions = api.gui.comp.TextView.new("Game options")
    settingsBox:addItem(header_GameOptions)

    --TODO: Add default mode selector

    --TODO: Add prefix default assigner (List where you can add line prefixes, so they get a different default mode from the global default), if that's even possible

    -- Create a toggle for debugging mode and add it to the SettingsBox (BoxLayout)
    local checkBox_timeBasedSampling = api.gui.comp.CheckBox.new("Use os time based sampling")
    checkBox_timeBasedSampling:setSelected(state.time_based_sampling, false)
    checkBox_timeBasedSampling:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", "settings_gui", "time_based_sampling", selected))
    end)
    settingsBox:addItem(checkBox_timeBasedSampling)

    -- Add a header for the Debugging options
    local header_Debugging = api.gui.comp.TextView.new("Debugging options")
    settingsBox:addItem(header_Debugging)

    -- Create a toggle for debugging mode and add it to the SettingsBox (BoxLayout)
    local checkBox_debugging = api.gui.comp.CheckBox.new("Debugging")
    checkBox_debugging:setSelected(state.log.debugging, false)
    checkBox_debugging:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", "settings_gui", "debugging", selected))
    end)
    settingsBox:addItem(checkBox_debugging)

    -- Create a toggle for verboseDebugging mode
    local checkBox_verboseDebugging = api.gui.comp.CheckBox.new("Verbose Debugging")
    checkBox_verboseDebugging:setSelected(state.log.verbose_debugging, false)
    checkBox_verboseDebugging:onToggle(function(selected)
        -- Send a script event to say that the verboseDebugging setting has been changed.
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", "settings_gui", "verbose_debugging", selected))
    end)
    settingsBox:addItem(checkBox_verboseDebugging)

    -- Add a force sample button
    local forceSampleButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Force Sample"), true)
    forceSampleButton:onClick(function()
        -- Send a script event to say that a forced sample has been requested.
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", "settings_gui", "force_sample", true))
    end)
    settingsBox:addItem(forceSampleButton)
end

-------------------------------------------------------------
--------------------- MOD STUFF -----------------------------
-------------------------------------------------------------

function data()
    return {
        handleEvent = function(filename, id, name, param)
            if filename == "LineManager" and id == "settings_gui" then
                if (name == "debugging") then
                    state.log.debugging = param
                    log.setDebugging(param)
                elseif (name == "verbose_debugging") then
                    state.log.verbose_debugging = param
                    log.setVerboseDebugging(param)
                elseif (name == "force_sample") then
                    log.info("** Force Sample ** ")
                    -- This will cause a new sample to be taken (as month/time has changed sufficiently).
                    -- An update will be triggered when the the required number of samples have been taken.
                    state.last_sample_time = -1
                elseif (name == "time_based_sampling") then
                    state.time_based_sampling = param
                    if (state.time_based_sampling) then
                        log.info("** Using os time based sampling. One sample is taken every " .. state.sample_time_interval .. " seconds. **")
                    else
                        log.info("** Using in-game month based sampling. One sample is taken on every change of in-game month. **")
                    end
                end
            end
        end,
        -- Save data - this goes into the save game.
        save = function()
            return state
        end,
        -- Load data - this is loaded by engine once on game start, and also loaded by the GUI thread on each update.
        load = function(data)
            if (data ~= nil and data.version == state.version) then
                state = data
            end
        end,
        update = function()
            if (firstLoad) then
                firstLoad = false
                log.info("** Preparing initial settings after load **")
                log.setDebugging(state.log.debugging)
                log.setVerboseDebugging(state.log.verbose_debugging)
                if (state.time_based_sampling) then
                    log.info("Using os time based sampling. One sample is taken every " .. state.sample_time_interval .. " seconds.")
                else
                    log.info("Using in-game month based sampling. One sample is taken on every change of in-game month.")
                end
                log.info("** Initial settings loaded **")
            end
            checkIfUpdateIsDue()
        end,
        guiInit = function()
            gui_init()
        end,


        -- TODO: Add something clever here eventually
        -- guiUpdate = function()
        -- end,
    }
end
