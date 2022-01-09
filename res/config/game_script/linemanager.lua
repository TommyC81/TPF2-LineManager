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

-- This is the entire data for the mod, it is stored in the savegame as well as loaded in GUI thread for access
local state = {
    version = 1, -- The version of the data, this is for compatibility purposes and only meant to be updated when the data format changes.
    log = {
        debugging = false, -- Debugging on/off.
        verboseDebugging = true, -- Verbose debugging on/off.
    },
    currentLineData = {}, -- An up-to-date list (since last sampling...) of the Player lines and associated data.
    last_sampled_month = -1, -- Keeps track of what month number the last sample was taken, in order to re-trigger a new sampling when month changes.
    sample_size = 6, -- Number of samples to average data out over.
    update_interval = 2, -- For every x sampling, do a vehicle update (check if a vehicle should be added or removed)
    sample_restart = 2, -- Following an update of a Line, the number of recorded samples will be reset to this value for the line to delay an update until sufficient data is available.
    samples_since_last_update = 0, -- A counter to keep track of how many samples have been taken since last update, and then re-trigger an update when 'update_interval' is reached.
}


---@param line_id number
---@return boolean success whether a vehicle was removed
---removes the oldest vehicle from the specified line
local function removeVehicleFromLine(line_id)
    local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)

    -- Find the oldest vehicle on the line
    if (#lineVehicles > 0 ) then
        local oldestVehicleId = helper.getOldestVehicleId(lineVehicles)

        -- Remove/sell the oldest vehicle (instantly sells)
        api.cmd.sendCommand(api.cmd.make.sellVehicle(oldestVehicleId))
        log.info(" -1 vehicle: " .. helper.getEntityName(line_id) .. " (" .. helper.printLineData(state.currentLineData, line_id) .. ")")
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

                log.info(" +1 vehicle: " .. helper.getEntityName(line_id) .. " (" .. helper.printLineData(state.currentLineData, line_id) .. ")")
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
        if state.currentLineData[line_id] then
            sampledLineData[line_id].samples = state.currentLineData[line_id].samples + 1
            -- The below ones are already captured in the fresh sample taken, don't overwrite those values!
            -- sampledLineData[line_id].vehicles = state.currentLineData[line_id].vehicles
            -- sampledLineData[line_id].capacity = state.currentLineData[line_id].capacity
            -- sampledLineData[line_id].occupancy = state.currentLineData[line_id].occupancy
            sampledLineData[line_id].demand = math.round(((state.currentLineData[line_id].demand * (state.sample_size - 1)) + line_data.demand) / state.sample_size)
            sampledLineData[line_id].usage = math.round(((state.currentLineData[line_id].usage * (state.sample_size - 1)) + line_data.usage) / state.sample_size)
            sampledLineData[line_id].rate = math.round(((state.currentLineData[line_id].rate * (state.sample_size - 1)) + line_data.rate) / state.sample_size)
        else
            sampledLineData[line_id].samples = 1
        end

        local name = helper.printLine(line_id)
        table.insert(sampledLines, name)
    end

    -- By initially just using the fresh sampledLineData, no longer existing lines are removed. Does this cause increased memory/CPU usage?
    state.currentLineData = sampledLineData

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
        if state.currentLineData[line_id] then
            lineCount = lineCount + 1
            totalVehicleCount = totalVehicleCount + state.currentLineData[line_id].vehicles

            -- If a line has sufficient samples, then check whether vehicles should be added/removed.
            if state.currentLineData[line_id].samples and state.currentLineData[line_id].samples >= state.sample_size then
                -- Check if a vehicle should be added to a Line.
                if helper.moreVehicleConditions(state.currentLineData, line_id) then
                    if addVehicleToLine(line_id) then
                        state.currentLineData[line_id].samples = state.sample_restart
                        totalVehicleCount = totalVehicleCount + 1
                    end
                    -- Check instead whether a vehicle should be removed from a Line.
                elseif helper.lessVehiclesConditions(state.currentLineData, line_id) then
                    if removeVehicleFromLine(line_id) then
                        state.currentLineData[line_id].samples = state.sample_restart
                        totalVehicleCount = totalVehicleCount - 1
                    end
                end
            end
        end
    end

    local ignored = #api.engine.system.lineSystem.getLines() - lineCount
    log.info("Total Lines: " .. lineCount .. " Total Vehicles: " .. totalVehicleCount .. " (Ignored Lines: " .. ignored .. ")")
end

-- TODO: get it to update periodically independently from the date, at least as an option
---updates the trackers of when the next update gets unlocked
local function checkIfUpdateIsDue()
    local current_month = helper.getGameMonth()

    -- Check if the month has changed since last sample. If so, do another sample. 1 sample/month.
    if state.last_sampled_month ~= current_month then
        state.last_sampled_month = current_month

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

    -- Add a header for the Debugging options
    local header_Debugging = api.gui.comp.TextView.new("Debugging options")
    settingsBox:addItem(header_Debugging)

    -- Create a toggle for debugging mode and add it to the SettingsBox (BoxLayout)
    local checkBox_debugging = api.gui.comp.CheckBox.new("Debugging")
    checkBox_debugging:setSelected(state.log.debugging, false)
    checkBox_debugging:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", "settingsGui", "debuggingUpdate", selected))
    end)
    settingsBox:addItem(checkBox_debugging)

    -- Create a toggle for verboseDebugging mode
    local checkBox_verboseDebugging = api.gui.comp.CheckBox.new("Verbose Debugging")
    checkBox_verboseDebugging:setSelected(state.log.verboseDebugging, false)
    checkBox_verboseDebugging:onToggle(function(selected)
        -- Send a script event to say that the verboseDebugging setting has been changed.
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", "settingsGui", "verboseDebuggingUpdate", selected))
    end)
    settingsBox:addItem(checkBox_verboseDebugging)

    -- Add a force sample button
    local forceSampleButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Force Sample"), true)
    forceSampleButton:onClick(function()
        -- Send a script event to say that a forced sample has been requested.
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", "settingsGui", "forceSample", true))
    end)
    settingsBox:addItem(forceSampleButton)

    -- Add a force update button
    local forceUpdateButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Force Update"), true)
    forceUpdateButton:onClick(function()
        -- Send a script event to say that a forced sample has been requested.
        api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", "settingsGui", "forceUpdate", true))
    end)
    settingsBox:addItem(forceUpdateButton)
end

-------------------------------------------------------------
--------------------- MOD STUFF -----------------------------
-------------------------------------------------------------

function data()
    return {
        handleEvent = function(filename, id, name, param)
            if filename == "LineManager" and id == "settingsGui" then
                if (name == "debuggingUpdate") then
                    state.log.debugging = param
                    log.setDebugging(param)
                elseif (name == "verboseDebuggingUpdate") then
                    state.log.verboseDebugging = param
                    log.setVerboseDebugging(param)
                elseif (name == "forceSample") then
                    log.info("** Force Sample ** ")
                    sampleLines()
                elseif (name == "forceUpdate") then
                    log.info("** Force Update **")
                    updateLines()
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
                log.info("Preparing initial settings after load.")
                log.setDebugging(state.log.debugging)
                log.setVerboseDebugging(state.log.verboseDebugging)
                log.info("Initial settings loaded.")
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
