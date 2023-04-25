---@author CARTOK
---@author RusteyBucket
-- General Transport Fever 2 API documentation can be found here: https://transportfever2.com/wiki/api/index.html
-- GUI items contain code and inspiration from 'Departure Board' created by kryfield, available here: https://steamcommunity.com/workshop/filedetails/?id=2692112427
-- GUI specific API documentation can be found here: https://transportfever2.com/wiki/api/modules/api.gui.html
-- Further information of GUI states and functions can be found here: https://www.transportfever2.com/wiki/doku.php?id=modding:userinterface

-- Include all required helper functions and scripts to make this mod work
local log = require 'cartok/logging'
local helper = require 'cartok/helper'
local api_helper = require 'cartok/api_helper'
local sampling = require 'cartok/sampling'
local lume = require 'cartok/lume'

local firstRun = true        -- Keeps track of the first update run (to do some init)
local lastRegularUpdate = -1 -- Keeps track of the last regular update (should run once per second)

local session_cachedDepotHit = 0
local session_cachedDepotMiss = 0

local gui_settingsWindow = nil
local gui_notificationWindow = nil

-- This is the entire data for the mod, it is stored in the save game as well as loaded in GUI thread for access
local state = {
    -- The version of the data, this is for compatibility purposes and only meant to be updated when the state data format changes.
    version = 38,
    version_change = true,               -- This simply keeps track of whether the state version has changed. This is meant to always default to true, it will be set to false when no longer the case (and then stored in the save game data).
    log_settings = {
        level = 3,                       -- The log level (3 = INFO)
        show_extended_line_info = false, -- Whether to show extended line info in the console.
    },
    auto_settings = {
        PASSENGER = {
            ROAD = true,
            TRAM = true,
            RAIL = true,
            WATER = true,
            AIR = true,
        },
        CARGO = {
            ROAD = true,
            TRAM = true,
            RAIL = true,
            WATER = true,
            AIR = true,
        },
    },
    linemanager_settings = {
        enabled = true,
        congestion_control = true,
        reverse_no_path_trains = true,
    },
    sampling_settings = {
        last_sample_time = -1,       -- Keeps track of what month (or time) the last sample was taken, in order to re-trigger a new sampling when month (or time) changes.
        time_based_sampling = false, -- If true, then os time is used for sampling rather than in-game months.
        sample_time_interval = 60,   -- If OS time is used for sampling, take a sample every this number of seconds. This is based on using GameSpeed = 1 (normal speed), with faster speeds, this time will be reduced accordingly.
    },
    line_data = {},                  -- An up-to-date list (since last sampling...) of the Player lines and associated data.
}

helper.setLog(log)
sampling.setLog(log)
api_helper.setLog(log)

---@param line_id number
---@return number vehiclesRemoved how many vehicles that were removed
---removes one or more empty (or oldest) vehicles from the specified line
local function removeVehicleFromLine(line_id)
    log.debug("linemanager: removeVehicleFromLine(" .. tostring(line_id) .. ") starting")

    local vehiclesRemoved = 0
    local lineVehicles = api_helper.getLineVehicles(line_id)
    local emptyVehicles = sampling.getEmptyVehicles(lineVehicles)

    -- If the rule is X (i.e. REMOVE ALL vehicles from this line), then process that only.
    if state.line_data[line_id].rule == "X" then
        for _, vehicle_id in pairs(emptyVehicles) do
            api_helper.sellVehicle(vehicle_id)
            helper.printSoldVehicleInfo(state.line_data, line_id, vehicle_id)
            -- Set this to true if any vehicle was removed i.e. this loop ran at least once
            vehiclesRemoved = vehiclesRemoved + 1
        end
        -- Else, run this only if there's more than one vehicle on the line.
    elseif #lineVehicles > 1 then
        local vehicleToRemove = nil

        -- If there are empty vehicles on the line, choose the oldest one of those, otherwise just use the oldest vehicle
        if #emptyVehicles > 0 then
            vehicleToRemove = helper.getOldestVehicleId(emptyVehicles)
        else
            -- Find the oldest vehicle on the line
            vehicleToRemove = helper.getOldestVehicleId(lineVehicles)
        end

        if vehicleToRemove then
            -- Reset depot_id and stop_id on vehicle removal - this will hopefully keep the depot_id and stop_id fresh.
            local depot_id, stop_id = helper.findDepotAndStop(line_id, vehicleToRemove)

            -- Remove/sell the oldest vehicle (instantly sells)
            api_helper.sellVehicle(vehicleToRemove)

            helper.printSoldVehicleInfo(state.line_data, line_id, vehicleToRemove)

            vehiclesRemoved = 1

            -- Update depot_id and stop_id if found, with appropriate debug message.
            if depot_id and stop_id then
                -- Store depot_id and stop_id
                state.line_data[line_id].depot_update_required = nil
                state.line_data[line_id].depot_id = depot_id
                state.line_data[line_id].depot_stop_id = stop_id
            else
                -- Trigger update of depot_id and stop_id
                state.line_data[line_id].depot_update_required = true
                state.line_data[line_id].depot_id = nil
                state.line_data[line_id].depot_stop_id = nil
            end
        end
        -- Not rule X and only 1 vehicle on the line, then don't remove the remaining vehicle as this will cause LineManager to stop working for that line.
    else
        log.error("Only one vehicle left on line '" .. state.line_data[line_id].name .. "' - Requested vehicle removal cancelled.")
    end

    log.debug("linemanager: removeVehicleFromLine(" .. tostring(line_id) .. ") finished. success=" .. tostring(success))

    return vehiclesRemoved
end

---@param line_id number
---@return number vehiclesAdded number of vehicles added
---adds one or more vehicles to the specified line_id by cloning an existing vehicle
local function addVehicleToLine(line_id)
    log.debug("linemanager: addVehicleToLine(" .. tostring(line_id) .. ") starting")

    local vehiclesAdded = 0
    local lineVehicles = api_helper.getLineVehicles(line_id)
    local depot_id = nil
    local stop_id = nil
    local vehicleToDuplicate = nil
    local new_vehicle_id = nil
    local using_cached_depot = false

    -- TODO: Test whether enough money is available or don't empty the vehicle when it's hopeless anyway.
    -- TODO: Figure out a better way to find the closest depot (or one at all).
    -- This merely tries to send an existing vehicle on the line to the depot, checks if succeeds then cancel the depot call but uses the depot data.
    -- Unfortunately sending a vehicle to a depot empties the vehicle.
    if #lineVehicles > 0 then
        -- If a depot_id has already been identified, use it
        if not state.line_data[line_id].depot_update_required and state.line_data[line_id].depot_id and api_helper.getDepot(state.line_data[line_id].depot_id) then
            using_cached_depot = true

            -- Set up data for vehicle to duplicate (use the first vehicle)
            vehicleToDuplicate = api_helper.getVehicle(lineVehicles[1])

            -- Use existing depot_id
            depot_id = state.line_data[line_id].depot_id

            -- If a stop_id exists then use it. Otherwise, start from stop_id 0 (first stop of the line).
            if state.line_data[line_id].depot_stop_id then
                stop_id = state.line_data[line_id].depot_stop_id
            else
                stop_id = 0
            end
        else
            -- Find the emptiest vehicle (this will help with the depot testing as the impact will be smallest, although less likely to find a depot)
            -- Note that there may also be a delay between the cache being set up and sampling completing, so it might no longer be the emptiest vehicle
            local vehicle_id = sampling.getEmptiestVehicle(lineVehicles)

            if vehicle_id then
                vehicleToDuplicate = api_helper.getVehicle(vehicle_id)
                depot_id, stop_id = helper.findDepotAndStop(line_id, vehicle_id)
            end
        end
    else
        log.error("There are no vehicles on line '" .. state.line_data[line_id].name .. "' - Requested vehicle addition cancelled. This message indicates a code error, please report it.")
    end

    if vehicleToDuplicate and vehicleToDuplicate.transportVehicleConfig and depot_id and stop_id then
        -- Check that the carrier is the same for both depot and vehicleToDuplicate
        -- For instance, different types of vehicles can be assigned to the same line (trams and buses, for instance).
        -- If depot and vehicleToDuplicate carrier is different, you'll get weird results...
        local depot = api_helper.getDepot(depot_id)
        if depot and depot.carrier == vehicleToDuplicate.carrier then
            -- Store depot_id and stop_id
            state.line_data[line_id].depot_id = depot_id
            state.line_data[line_id].depot_stop_id = stop_id

            local transportVehicleConfig = vehicleToDuplicate.transportVehicleConfig
            local purchaseTime = api_helper.getGameTime()

            -- Reset applicable parts of the transportVehicleConfig
            for _, vehicle in pairs(transportVehicleConfig.vehicles) do
                vehicle.purchaseTime = purchaseTime
                vehicle.maintenanceState = 1
            end

            api_helper.buyVehicle(depot_id, transportVehicleConfig, function(cmd, res)
                if (res and cmd.resultVehicleEntity) then
                    new_vehicle_id = cmd.resultVehicleEntity

                    api_helper.sendVehicleToLine(new_vehicle_id, line_id, stop_id)

                    -- Check if vehicle remains in depot despite being sent to a line.
                    -- If it is, then there's a problem - sell the vehicle again.
                    if api_helper.isVehicleInDepot(new_vehicle_id) then
                        api_helper.sellVehicle(new_vehicle_id)

                        session_cachedDepotMiss = session_cachedDepotMiss + 1

                        log.warn("Unable to add vehicle to line '" .. state.line_data[line_id].name .. "' - Need to identify a new depot.")
                    else
                        -- Ensure the currently used depot_id and stop_id are retained for next vehicle addition.
                        state.line_data[line_id].depot_update_required = nil

                        if using_cached_depot then
                            session_cachedDepotHit = session_cachedDepotHit + 1
                        else
                            session_cachedDepotMiss = session_cachedDepotMiss + 1
                        end

                        helper.printBoughtVehicleInfo(state.line_data, line_id, new_vehicle_id, depot_id)
                        vehiclesAdded = 1
                    end
                else
                    log.warn("Unable to add vehicle to line '" .. state.line_data[line_id].name .. "' - Insufficient cash?")
                end
            end)
        else
            log.warn("Unable to add vehicle to line '" .. state.line_data[line_id].name .. "' - Depot carrier is different than the vehicleToDuplicate.")
        end
    else
        log.warn("Unable to add vehicle to line '" .. state.line_data[line_id].name .. "' - Either no available depot, or not possible to find a depot on this update.")
    end

    log.debug("linemanager: session_cachedDepotHit=" .. session_cachedDepotHit .. " session_cachedDepotMiss=" .. session_cachedDepotMiss)

    log.debug("linemanager: addVehicleToLine(" .. tostring(line_id) .. ") finished. success=" .. tostring(success))

    if vehiclesAdded < 1 then
        -- If this addVehicleToLine() run was not successful for any reason, force an update of depot_id and stop_id on next run.
        log.debug("linemanager: Forcing depot update on next run for line '" .. state.line_data[line_id].name .. "' (" .. line_id .. ").")
        state.line_data[line_id].depot_update_required = true
    end

    return vehiclesAdded
end

--- updates vehicle amount if applicable and line list in general
local function updateLines()
    log.debug("linemanager: updateLines() starting")

    local lines = api_helper.getPlayerLines()
    local lineCount = 0
    local vehicleCount = 0
    local problemCount = 0
    local congestedLines = {}

    for _, line_id in pairs(lines) do
        local lineIsCongested = false
        local lineIsExtremelyCongested = false

        -- Only proceed if data for the line exists in state.
        if state.line_data[line_id] then
            -- CONGESTION CONTROL (Generate messages regardless if congestion control is switched on or off).
            if state.line_data[line_id].congestion > math.max(10, 48 - 3 * state.line_data[line_id].vehicles) then
                -- Set this only if congestion control is enabled.
                if state.linemanager_settings.congestion_control then
                    lineIsCongested = true
                end

                -- If extremely congested, then generate that message otherwise the general congestion warning only.
                if state.line_data[line_id].congestion > math.max(20, 63 - 3 * state.line_data[line_id].vehicles) then
                    table.insert(congestedLines, lume.round(state.line_data[line_id].congestion) .. "% !! : " .. state.line_data[line_id].name)
                    if state.linemanager_settings.congestion_control then
                        lineIsExtremelyCongested = true
                    end
                else
                    table.insert(congestedLines, lume.round(state.line_data[line_id].congestion) .. "%    : " .. state.line_data[line_id].name)
                end
            end

            -- If a line is managed, then continue
            if state.line_data[line_id].managed then
                lineCount = lineCount + 1
                vehicleCount = vehicleCount + state.line_data[line_id].vehicles

                -- Check if a vehicle should be added to a Line. This has been evaluated as part of the sampling. Do not add if the line is congested (this is set to false/ignored if congestion_control is switched off).
                if state.line_data[line_id].action == "ADD" and not lineIsCongested then
                    local vehiclesAdded = addVehicleToLine(line_id)
                    if vehiclesAdded > 0 then
                        -- If succeeded, update line_data to indicate this
                        state.line_data[line_id].samples = 0
                        state.line_data[line_id].last_action = "ADD"
                        state.line_data[line_id].vehicles = state.line_data[line_id].vehicles + vehiclesAdded
                        vehicleCount = vehicleCount + vehiclesAdded
                    end
                    -- Check instead whether a vehicle should be removed from a Line. This has been evaluated as part of the sampling. Also run this in case of extreme congestion (this is set to false/ignored if congestion_control is switched off).
                elseif state.line_data[line_id].action == "REMOVE" or lineIsExtremelyCongested then
                    local vehiclesRemoved = removeVehicleFromLine(line_id)
                    if vehiclesRemoved > 0 then
                        -- If succeeded, update line_data to indicate this
                        state.line_data[line_id].samples = 0
                        state.line_data[line_id].last_action = "REMOVE"
                        state.line_data[line_id].vehicles = state.line_data[line_id].vehicles - vehiclesRemoved
                        vehicleCount = vehicleCount - vehiclesRemoved
                    end
                end

                if state.line_data[line_id].has_problem then
                    -- TODO: Need to insert code here to clear up any line problems.
                    problemCount = problemCount + 1
                end
            end
        end
    end

    local ignoredLineCount = #lines - lineCount
    log.info("==> SUMMARY: " .. lineCount .. " lines and " .. vehicleCount .. " vehicles managed (" .. ignoredLineCount .. " lines not managed)")
    if problemCount > 0 then
        log.warn(problemCount .. " managed lines had problems and were skipped in this update")
    end

    if #congestedLines > 0 then
        local logOutput = ""
        table.sort(congestedLines)
        if state.linemanager_settings.congestion_control then
            logOutput = "Possibly congested lines (vehicle addition inhibited, vehicle removal possible):"
        else
            logOutput = "Possibly congested lines (NO congestion control applied):"
        end
        for i = 1, #congestedLines do
            logOutput = logOutput .. "\n" .. "   " .. congestedLines[i]
        end
        log.warn(logOutput)
    end

    if log.isShowExtendedLineInfo() then
        local manualLines = {}
        local automaticLines = {}
        local ignoredLines = {}
        local logOutput = ""

        -- Populate the tables with managed/ignored lines
        for _, line_id in pairs(lines) do
            -- If a line exists in line_data and is managed, then continue
            if state.line_data[line_id] then
                if state.line_data[line_id].managed then
                    if state.line_data[line_id].rule_manual then
                        table.insert(manualLines, state.line_data[line_id].name)
                    else
                        table.insert(automaticLines, state.line_data[line_id].name)
                    end
                else
                    table.insert(ignoredLines, state.line_data[line_id].name)
                end
            end
        end

        -- Print manually managed lines
        if #manualLines > 0 then
            table.sort(manualLines)
            logOutput = "Manually managed lines:\n"
            logOutput = logOutput .. helper.tableToStringWithLineBreaks(manualLines)
            log.info(logOutput)
        end

        -- Print automatically managed lines
        if #automaticLines > 0 then
            table.sort(automaticLines)
            logOutput = "Automatically managed lines:\n"
            logOutput = logOutput .. helper.tableToStringWithLineBreaks(automaticLines)
            log.info(logOutput)
        end

        -- Print ignored lines
        if #ignoredLines > 0 then
            table.sort(ignoredLines)
            logOutput = "Ignored lines:\n"
            logOutput = logOutput .. helper.tableToStringWithLineBreaks(ignoredLines)
            log.info(logOutput)
        end
    end

    log.debug("linemanager: updateLines() finished")
end

-- This functions runs exactly once (and first) when a game is loaded
local function firstRunOnly()
    log.info("linemanager: firstRunOnly() starting")

    log.info("LineManager enabled is set to: " .. tostring(state.linemanager_settings.enabled))
    log.info("Automatically reverse trains with no path is set to: " .. tostring(state.linemanager_settings.reverse_no_path_trains))
    if (state.sampling_settings.time_based_sampling) then
        log.info("Using os time based sampling.")
        log.info("One sample is taken every " .. state.sampling_settings.sample_time_interval .. " seconds (divided by game speed).")
        state.sampling_settings.last_sample_time = os.time() -- Reset this time to delay first sampling (this potentially avoids some weird os.time stuff if it differs oddly between game starts and thus does not trigger updates when expected)
    else
        log.info("Using in-game month based sampling.")
        log.info("One sample is taken on every change of in-game month.")
    end
    log.setLevel(state.log_settings.level)
    log.setShowExtendedLineInfo(state.log_settings.show_extended_line_info)

    if state.version_change then
        log.info("The version of the state data has changed. Game has been paused to allow review of LineManager settings and changes.")
        game.interface.setGameSpeed(0)
    else
        log.info("The state data version is up-to-date.")
    end

    log.info("linemanager: firstRunOnly() finished")
end

-- This functions runs regularly every second
local function regularUpdate()
    log.debug("linemanager: regularUpdate() starting")

    -- Check if a sampling has finished (and then set sampling to stopped to only trigger this once)
    if sampling.isFinished() then
        -- Retrieve the line data first, then set sampling to stopped
        state.line_data = sampling.getSampledLineData()
        sampling.stop()

        log.info("============ Updating ============")
        updateLines()
        -- If sampling is stopped, check if a new sampling is due
    elseif sampling.isStopped() then
        local sampling_is_due = false

        if state.sampling_settings.time_based_sampling then
            -- Check if sufficient os time has passed since last sample. If so, trigger another sample.
            local current_os_time = os.time()
            -- Check if time has passed (Note: last_sample_time is "frozen" when game is paused, no need to account for that here - see data.update)
            local game_speed = game.interface.getGameSpeed()
            local sample_time_interval = state.sampling_settings.sample_time_interval

            if game_speed > 0 then
                sample_time_interval = sample_time_interval / game_speed
            end

            if current_os_time - state.sampling_settings.last_sample_time >= sample_time_interval then
                state.sampling_settings.last_sample_time = current_os_time
                sampling_is_due = true
            end
        else
            -- Check if the month has changed since last sample. If so, trigger another sample. 1 sample/month.
            local current_month = api_helper.getGameMonth()
            if state.sampling_settings.last_sample_time ~= current_month then
                state.sampling_settings.last_sample_time = current_month
                sampling_is_due = true
            end
        end

        -- If sampling is due, then start the sampler
        if (sampling_is_due) then
            log.info("============ Sampling ============")
            sampling.start(state.line_data, state.auto_settings)
        end
    end

    -- Take care of train reversing if enabled
    if state.linemanager_settings.reverse_no_path_trains then
        -- Reverse direction of no path trains to resolve stuck trains
        local noPathTrains = api_helper.getNoPathTrains()

        for i = 1, #noPathTrains do
            local vehicle_name = api_helper.getEntityName(noPathTrains[i])
            log.warn("Train '" .. vehicle_name .. "' has no path, reversing the train to find a new path")
            log.debug("vehicle_id: " .. noPathTrains[i])
            api_helper.reverseVehicle(noPathTrains[i])
        end
    end

    log.debug("linemanager: regularUpdate() finished")
end

-- This function runs on each game tick if the game is not paused
local function everyTickUpdate()
    -- This must be run once per update to ensure sampling processing when triggered
    sampling.process()
end

-------------------------------------------------------------
--------------------- GUI STUFF -----------------------------
-------------------------------------------------------------

local function gui_LMButtonClick()
    api_helper.sendScriptCommand("debug", "linemanager: gui_LMButtonClick() starting")

    if not gui_settingsWindow:isVisible() then
        api_helper.sendScriptCommand("debug", "linemanager: gui_settingsWindow is NOT visible, show it")
        gui_settingsWindow:setVisible(true, false)
    else
        api_helper.sendScriptCommand("debug", "linemanager: gui_settingsWindow IS visible, hide it")
        gui_settingsWindow:setVisible(false, false)
    end

    api_helper.sendScriptCommand("debug", "linemanager: gui_LMButtonClick() finished")
end

local function gui_initNotificationWindow()
    -- TODO: The below is very manual and prone to future errors, make it a bit "smarter".

    -- NOTIFICATION WINDOW
    api_helper.sendScriptCommand("debug", "linemanager: gui_initNotificationWindow() starting")

    -- Create a BoxLayout to hold all options
    local notificationBox = api.gui.layout.BoxLayout.new("VERTICAL")

    -- LINEMANAGER NOTIFICATION TEXT
    local notification_text = "This is either the first run using LineManager, or the LineManager data format has been updated.\n"
    notification_text = notification_text .. "This means that LineManager default settings are in use.\n"
    notification_text = notification_text .. "\n"
    notification_text = notification_text .. "Check your in-game LineManager settings (use button at bottom of this window, or the '[LM]' button in the game status bar at the bottom of the screen), and review the manual to confirm any important functionality changes.\n"
    notification_text = notification_text .. "The LineManager manual is available here (copy the link and paste into your web browser):\n"
    notification_text = notification_text .. "                   https://github.com/TommyC81/TPF2-LineManager\n"
    notification_text = notification_text .. "\n"
    notification_text = notification_text .. "Note specifically that LineManager now uses square brackets to set manual line rules i.e. '[' and ']' (previously, parentheses/round brackets were used).\n"
    notification_text = notification_text .. "\n"
    notification_text = notification_text .. "By default, all automatic line management is disabled - it can be enabled as required in the LineManager settings. Depending on your preference and type of game, you may prefer to enable automatic line management for some/all types of lines, or only use manually assigned rules, or a combination thereof. There is no right or wrong.\n"
    notification_text = notification_text .. "\n"
    notification_text = notification_text .. "To tell LineManager to manage only specific lines, or adjust the rule used for a specific line, manual rules may be assigned as per below (add text within '' to the line name):\n"
    notification_text = notification_text .. "'[P]' to assign default PASSENGER line rules to a line.\n"
    notification_text = notification_text .. "'[C]' to assign default CARGO line rules to a line.\n"
    notification_text = notification_text .. "'[R:100]' to set a line to achieve a rate of 100. Change number as required.\n"
    notification_text = notification_text .. "'[PR]' to assign RusteyBucket's PASSENGER line rules to a line.\n"
    notification_text = notification_text .. "\n"
    notification_text = notification_text .. "If automatic line management is enabled for a certain type of line, then the below rule is also useful to inhibit automatic management as required for specific lines:\n"
    notification_text = notification_text .. "'[M]' to designate a line as manually managed only i.e. disable automatic line management.\n"
    notification_text = notification_text .. "\n"
    notification_text = notification_text .. "The game has been paused to allow you time to review settings and changes. Un-pause the game when you are ready to continue.\n"
    notification_text = lume.wordwrap(notification_text, 115)

    local text_LineManagerNotificationText = api.gui.comp.TextView.new(notification_text)
    text_LineManagerNotificationText:setSelectable(true)
    notificationBox:addItem(text_LineManagerNotificationText)

    -- Add a button to open settings
    local openSettingsButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Click here to open LineManager settings"), true)
    openSettingsButton:onClick(function()
        gui_notificationWindow:setVisible(false, false)
        gui_LMButtonClick()
    end)
    notificationBox:addItem(openSettingsButton)

    -- Create the NOTIFICATION window
    gui_notificationWindow = api.gui.comp.Window.new("LineManager Notification", notificationBox)
    gui_notificationWindow:setTitle("LineManager Notification")
    gui_notificationWindow:addHideOnCloseHandler()
    gui_notificationWindow:setMovable(true)
    gui_notificationWindow:setPinButtonVisible(true)
    gui_notificationWindow:setResizable(false)
    gui_notificationWindow:setSize(api.gui.util.Size.new(785, 540))
    -- TODO: Setting the position here seems to cause the window to be invisible (or outside the screen, or something...)
    --gui_notificationWindow:setPosition(100, 100)
    gui_notificationWindow:setPinned(true)
    gui_notificationWindow:setVisible(false, false)

    api_helper.sendScriptCommand("debug", "linemanager: gui_initNotificationWindow() finished")
end

local function gui_initSettingsWindow()
    -- SETTINGS WINDOW
    api_helper.sendScriptCommand("debug", "linemanager: gui_initSettingsWindow() starting")

    -- Create LineManager button in the main GUI
    local button = api.gui.comp.Button.new(api.gui.comp.TextView.new("[LM]"), true)
    button:onClick(gui_LMButtonClick)
    local gameInfoLayout = api.gui.util.getById("gameInfo"):getLayout()
    gameInfoLayout:addItem(api.gui.comp.Component.new("VerticalLine"))
    gameInfoLayout:addItem(button)
    gameInfoLayout:addItem(api.gui.comp.Component.new("VerticalLine"))

    -- SETTINGS WINDOW
    -- Create a BoxLayout to hold all options
    local settingsBox = api.gui.layout.BoxLayout.new("VERTICAL")

    -- LINEMANAGER OPTIONS
    local header_LineManagerOptions = api.gui.comp.TextView.new("** LineManager options **")
    settingsBox:addItem(header_LineManagerOptions)

    -- Create a toggle for enabling/disabling LineManager
    local checkBox_enableLineManager = api.gui.comp.CheckBox.new("LineManager enabled")
    checkBox_enableLineManager:setSelected(state.linemanager_settings.enabled, false)
    checkBox_enableLineManager:onToggle(function(selected)
        api_helper.sendScriptCommand("settings_gui", "linemanager_enabled", selected)
    end)
    settingsBox:addItem(checkBox_enableLineManager)

    -- Create a toggle for enabling/disabling LineManager
    local checkBox_congestionControl = api.gui.comp.CheckBox.new("Congestion control enabled")
    checkBox_congestionControl:setSelected(state.linemanager_settings.congestion_control, false)
    checkBox_congestionControl:onToggle(function(selected)
        api_helper.sendScriptCommand("settings_gui", "congestion_control", selected)
    end)
    settingsBox:addItem(checkBox_congestionControl)

    -- Create a toggle for enabling/disabling automatic reversal of blocked trains
    local checkBox_enableReverseNoPathTrains = api.gui.comp.CheckBox.new("Automatically reverse trains with no path")
    checkBox_enableReverseNoPathTrains:setSelected(state.linemanager_settings.reverse_no_path_trains, false)
    checkBox_enableReverseNoPathTrains:onToggle(function(selected)
        api_helper.sendScriptCommand("settings_gui", "reverse_no_path_trains", selected)
    end)
    settingsBox:addItem(checkBox_enableReverseNoPathTrains)

    -- SAMPLING OPTIONS
    local header_SamplingOptions = api.gui.comp.TextView.new("** Sampling options **")
    settingsBox:addItem(header_SamplingOptions)

    -- Create a toggle for using os time based sampling
    local checkBox_timeBasedSampling = api.gui.comp.CheckBox.new("Use OS time based sampling")
    checkBox_timeBasedSampling:setSelected(state.sampling_settings.time_based_sampling, false)
    checkBox_timeBasedSampling:onToggle(function(selected)
        api_helper.sendScriptCommand("settings_gui", "time_based_sampling", selected)
    end)
    settingsBox:addItem(checkBox_timeBasedSampling)

    -- Add a header for PASSENGER/CARGO automatic line management, and a BoxLayout to hold the options
    local header_AutomaticOptions = api.gui.comp.TextView.new("** Automatic line management **")
    settingsBox:addItem(header_AutomaticOptions)

    local automaticOptionBox = api.gui.layout.BoxLayout.new("HORIZONTAL")

    -- PASSENGER OPTIONS
    local passengerOptionBox = api.gui.layout.BoxLayout.new("VERTICAL")
    local header_PassengerOptions = api.gui.comp.TextView.new("PASSENGER")
    passengerOptionBox:addItem(header_PassengerOptions)

    local selectPassengerRoad = api.gui.comp.CheckBox.new("ROAD")
    local selectPassengerTram = api.gui.comp.CheckBox.new("TRAM")
    local selectPassengerRail = api.gui.comp.CheckBox.new("RAIL")
    local selectPassengerWater = api.gui.comp.CheckBox.new("WATER")
    local selectPassengerAir = api.gui.comp.CheckBox.new("AIR")

    selectPassengerRoad:setSelected(state.auto_settings.PASSENGER.ROAD, false)
    selectPassengerRoad:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "auto_passenger_road", selected)
    end)

    selectPassengerTram:setSelected(state.auto_settings.PASSENGER.TRAM, false)
    selectPassengerTram:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "auto_passenger_tram", selected)
    end)

    selectPassengerRail:setSelected(state.auto_settings.PASSENGER.RAIL, false)
    selectPassengerRail:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "auto_passenger_rail", selected)
    end)

    selectPassengerWater:setSelected(state.auto_settings.PASSENGER.WATER, false)
    selectPassengerWater:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "auto_passenger_water", selected)
    end)

    selectPassengerAir:setSelected(state.auto_settings.PASSENGER.AIR, false)
    selectPassengerAir:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "auto_passenger_air", selected)
    end)

    passengerOptionBox:addItem(selectPassengerRoad)
    passengerOptionBox:addItem(selectPassengerTram)
    passengerOptionBox:addItem(selectPassengerRail)
    passengerOptionBox:addItem(selectPassengerWater)
    passengerOptionBox:addItem(selectPassengerAir)

    automaticOptionBox:addItem(passengerOptionBox)

    -- CARGO OPTIONS
    local cargoOptionBox = api.gui.layout.BoxLayout.new("VERTICAL")
    local header_CargoOptions = api.gui.comp.TextView.new("CARGO")
    cargoOptionBox:addItem(header_CargoOptions)

    local selectCargoRoad = api.gui.comp.CheckBox.new("ROAD")
    local selectCargoTram = api.gui.comp.CheckBox.new("TRAM")
    local selectCargoRail = api.gui.comp.CheckBox.new("RAIL")
    local selectCargoWater = api.gui.comp.CheckBox.new("WATER")
    local selectCargoAir = api.gui.comp.CheckBox.new("AIR")

    selectCargoRoad:setSelected(state.auto_settings.CARGO.ROAD, false)
    selectCargoRoad:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "auto_cargo_road", selected)
    end)

    selectCargoTram:setSelected(state.auto_settings.CARGO.TRAM, false)
    selectCargoTram:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "auto_cargo_tram", selected)
    end)

    selectCargoRail:setSelected(state.auto_settings.CARGO.RAIL, false)
    selectCargoRail:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "auto_cargo_rail", selected)
    end)

    selectCargoWater:setSelected(state.auto_settings.CARGO.WATER, false)
    selectCargoWater:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "auto_cargo_water", selected)
    end)

    selectCargoAir:setSelected(state.auto_settings.CARGO.AIR, false)
    selectCargoAir:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "auto_cargo_air", selected)
    end)

    cargoOptionBox:addItem(selectCargoRoad)
    cargoOptionBox:addItem(selectCargoTram)
    cargoOptionBox:addItem(selectCargoRail)
    cargoOptionBox:addItem(selectCargoWater)
    cargoOptionBox:addItem(selectCargoAir)

    automaticOptionBox:addItem(cargoOptionBox)

    -- Add all the automatic options to the main settingsBox
    settingsBox:addItem(automaticOptionBox)

    -- Add a header for the Debugging options
    local header_Debugging = api.gui.comp.TextView.new("** Debugging options **")
    settingsBox:addItem(header_Debugging)

    -- Create a toggle for show_extended_line_info mode
    local checkBox_showExtendedLineInfo = api.gui.comp.CheckBox.new("Show extended line info")
    checkBox_showExtendedLineInfo:setSelected(state.log_settings.show_extended_line_info, false)
    checkBox_showExtendedLineInfo:onToggle(function(selected)
        -- Send a script event to say that the show_extended_line_info setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "show_extended_line_Info", selected)
    end)
    settingsBox:addItem(checkBox_showExtendedLineInfo)

    -- Create a toggle for debugging mode and add it to the SettingsBox (BoxLayout)
    local checkBox_debugging = api.gui.comp.CheckBox.new("Show debugging information")
    checkBox_debugging:setSelected(state.log_settings.level == log.levels.DEBUG, false)
    checkBox_debugging:onToggle(function(selected)
        -- Send a script event to say that the debugging setting has been changed.
        api_helper.sendScriptCommand("settings_gui", "debugging", selected)
    end)
    settingsBox:addItem(checkBox_debugging)

    -- Add a force sample button
    local forceSampleButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Force Sample"), true)
    forceSampleButton:onClick(function()
        -- Send a script event to say that a forced sample has been requested.
        api_helper.sendScriptCommand("settings_gui", "force_sample", true)
    end)
    settingsBox:addItem(forceSampleButton)

    -- Add a show LINEMANAGER NOTIFICATION window button
    local showNotificationWindowButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Show notification window"), true)
    showNotificationWindowButton:onClick(function()
        gui_settingsWindow:setVisible(false, false)
        gui_notificationWindow:setVisible(true, false)
    end)
    settingsBox:addItem(showNotificationWindowButton)

    -- Create the SETTINGS window
    gui_settingsWindow = api.gui.comp.Window.new("LineManager Settings", settingsBox)
    gui_settingsWindow:setTitle("LineManager Settings")
    gui_settingsWindow:addHideOnCloseHandler()
    gui_settingsWindow:setMovable(true)
    gui_settingsWindow:setPinButtonVisible(true)
    gui_settingsWindow:setResizable(false)
    gui_settingsWindow:setSize(api.gui.util.Size.new(300, 500))
    -- TODO: Setting the position here seems to cause the window to be invisible (or outside the screen, or something...)
    --gui_settingsWindow:setPosition(100, 100)
    gui_settingsWindow:setPinned(true)
    gui_settingsWindow:setVisible(false, false)

    api_helper.sendScriptCommand("debug", "linemanager: gui_initSettingsWindow() finished")
end

-------------------------------------------------------------
--------------------- MOD STUFF -----------------------------
-------------------------------------------------------------

function data()
    return {
        handleEvent = function(filename, id, name, param)
            if filename == "linemanager.lua" then
                if id == "debug" then
                    log.debug(name)
                elseif id == "settings_gui" then
                    if name == "debugging" then
                        if param == true then
                            state.log_settings.level = log.levels.DEBUG
                            log.setLevel(log.levels.DEBUG)
                        else
                            state.log_settings.level = log.levels.INFO
                            log.setLevel(log.levels.INFO)
                        end
                    elseif name == "show_extended_line_Info" then
                        state.log_settings.show_extended_line_info = param
                        log.setShowExtendedLineInfo(param)
                    elseif name == "force_sample" then
                        log.info("Forcing a sample")
                        -- This will cause a new sample to be taken (as month/time has changed sufficiently).
                        -- An update will be triggered when the the required number of samples have been taken.
                        state.sampling_settings.last_sample_time = -1
                    elseif name == "linemanager_enabled" then
                        state.linemanager_settings.enabled = param
                        log.info("LineManager enabled set to: " .. tostring(param))
                    elseif name == "congestion_control" then
                        state.linemanager_settings.congestion_control = param
                        log.info("Congestion control set to: " .. tostring(param))
                    elseif name == "reverse_no_path_trains" then
                        state.linemanager_settings.reverse_no_path_trains = param
                        log.info("Automatically reverse trains with no path set to: " .. tostring(param))
                    elseif name == "time_based_sampling" then
                        state.sampling_settings.time_based_sampling = param
                        if state.sampling_settings.time_based_sampling then
                            log.info("Using os time based sampling.")
                            log.info("One sample is taken every " .. state.sampling_settings.sample_time_interval .. " seconds (divided by game speed).")
                        else
                            log.info("Using in-game month based sampling.")
                            log.info("One sample is taken on every change of in-game month.")
                        end
                    elseif name == "auto_passenger_road" then
                        state.auto_settings.PASSENGER.ROAD = param
                        log.info("Automatic management of PASSENGER / ROAD line vehicles set to: " .. tostring(param))
                    elseif name == "auto_passenger_tram" then
                        state.auto_settings.PASSENGER.TRAM = param
                        log.info("Automatic management of PASSENGER / TRAM line vehicles set to: " .. tostring(param))
                    elseif name == "auto_passenger_rail" then
                        state.auto_settings.PASSENGER.RAIL = param
                        log.info("Automatic management of PASSENGER / RAIL line vehicles set to: " .. tostring(param))
                    elseif name == "auto_passenger_water" then
                        state.auto_settings.PASSENGER.WATER = param
                        log.info("Automatic management of PASSENGER / WATER line vehicles set to: " .. tostring(param))
                    elseif name == "auto_passenger_air" then
                        state.auto_settings.PASSENGER.AIR = param
                        log.info("Automatic management of PASSENGER / AIR line vehicles set to: " .. tostring(param))
                    elseif name == "auto_cargo_road" then
                        state.auto_settings.CARGO.ROAD = param
                        log.info("Automatic management of CARGO / ROAD line vehicles set to: " .. tostring(param))
                    elseif name == "auto_cargo_tram" then
                        state.auto_settings.CARGO.TRAM = param
                        log.info("Automatic management of CARGO / TRAM line vehicles set to: " .. tostring(param))
                    elseif name == "auto_cargo_rail" then
                        state.auto_settings.CARGO.RAIL = param
                        log.info("Automatic management of CARGO / RAIL line vehicles set to: " .. tostring(param))
                    elseif name == "auto_cargo_water" then
                        state.auto_settings.CARGO.WATER = param
                        log.info("Automatic management of CARGO / WATER line vehicles set to: " .. tostring(param))
                    elseif name == "auto_cargo_air" then
                        state.auto_settings.CARGO.AIR = param
                        log.info("Automatic management of CARGO / AIR line vehicles set to: " .. tostring(param))
                    end
                elseif id == "notification_gui" and name == "state_version_change_handled" then
                    state.version_change = false
                    log.debug("State version change has been handled")
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
        update = function(data)
            local current_time = os.time()

            -- First run
            if firstRun then
                firstRun = false
                firstRunOnly()
            end

            -- Every tick update
            everyTickUpdate()

            -- If linemanager is enabled and game is not paused
            if state.linemanager_settings.enabled and game.interface.getGameSpeed() > 0 then
                -- Regular update
                if current_time ~= lastRegularUpdate then
                    lastRegularUpdate = current_time
                    regularUpdate()
                end
                -- If game is paused and we're using os time based sampling, then "freeze" the time of the last sample taken
            elseif state.sampling_settings.time_based_sampling then
                state.sampling_settings.last_sample_time = state.sampling_settings.last_sample_time + (current_time - state.sampling_settings.last_sample_time)
            end
        end,
        guiInit = function()
            gui_initSettingsWindow()
            gui_initNotificationWindow()
            if state.version_change then
                gui_notificationWindow:setVisible(true, false)
                api_helper.sendScriptCommand("notification_gui", "state_version_change_handled")
            end
        end,
    }
end
