local rules = require 'cartok/rules'
local enums = require 'cartok/enums'
local api_helper = require 'cartok/api_helper'
local lume = require 'cartok/lume'
local timer = require 'cartok/timer'

local sampling = {}

local log = nil

local SAMPLING_WINDOW_SIZE = 8 -- This must be 2 or greater, or...danger. Lower number means quicker changes to data and vice versa.

local NO_ENTITY = -1

local MAX_LINES_TO_PROCESS_PER_RUN = 20 -- Maximum lines to process per run
local MAX_VEHICLES_TO_PROCESS_PER_RUN = 50 -- Maximum vehicles to process per run
local MAX_ENTITIES_TO_PROCESS_PER_RUN = 300 -- Maximum entities to process per run

local STATE_STOPPED = 1
local STATE_WAITING = 2
local STATE_PREPARING_INITIAL_DATA = 3
local STATE_PREPARING_LINE_DATA = 4
local STATE_SAMPLING_WAITING_CARGO = 5
local STATE_MERGING_LINE_DATA = 6
local STATE_APPLYING_RULES = 7
local STATE_FINISHED = 8

local sampling_state = STATE_STOPPED -- To track the progress of the sampling

local vehicleOccupancyCache = nil
local problemLineCache = nil
local problemVehicleCache = nil

local simEntityAtTerminalCache = nil -- Holder for all SIM_ENTITY_AT_TERMINAL: api.engine.getComponent(entity_id, api.type.ComponentType.SIM_ENTITY_AT_TERMINAL)
local lineSimPersonCache = nil -- Holder for line specific SimPerson: api.engine.system.simPersonSystem.getSimPersonsForLine(line_id)
local lineSimCargoCache = nil -- Holder for line specific SimCargo: api.engine.system.simCargoSystem.getSimCargosForLine(line_id)

local sampledLineData = nil

local stateAutoSettings = nil
local stateLineData = nil

function sampling.setLog(input_log)
    log = input_log
    rules.setLog(input_log)
end

local function setStateStopped()
    sampling_state = STATE_STOPPED
end

local function isStateStopped()
    return sampling_state == STATE_STOPPED
end

local function setStateWaiting()
    sampling_state = STATE_WAITING
end

local function isStateWaiting()
    return sampling_state == STATE_WAITING
end

local function setStatePreparingInitialData()
    sampling_state = STATE_PREPARING_INITIAL_DATA
end

local function isStatePreparingInitialData()
    return sampling_state == STATE_PREPARING_INITIAL_DATA
end

local function setStatePreparingLineData()
    sampling_state = STATE_PREPARING_LINE_DATA
end

local function isStatePreparingLineData()
    return sampling_state == STATE_PREPARING_LINE_DATA
end

local function setStateSamplingWaitingCargo()
    sampling_state = STATE_SAMPLING_WAITING_CARGO
end

local function isStateSamplingWaitingCargo()
    return sampling_state == STATE_SAMPLING_WAITING_CARGO
end

local function setStateMergingLineData()
    sampling_state = STATE_MERGING_LINE_DATA
end

local function isStateMergingLineData()
    return sampling_state == STATE_MERGING_LINE_DATA
end

local function setStateApplyingRules()
    sampling_state = STATE_APPLYING_RULES
end

local function isStateApplyingRules()
    return sampling_state == STATE_APPLYING_RULES
end

local function setStateFinished()
    sampling_state = STATE_FINISHED
end

local function isStateFinished()
    return sampling_state == STATE_FINISHED
end

---checks whether the sampling is currently stopped
function sampling.isStopped()
    return isStateStopped()
end

---checks whether the sampling is currently finished
function sampling.isFinished()
    return isStateFinished()
end

---@param dividend number : absolute number
---@param divisor number : absolute maximum
---@return number : relative ratio as percentage
local function roundPercentage(dividend, divisor)
    if (dividend > 0 and divisor > 0) then
        local factor = dividend / divisor
        local percentage = 100 * factor
        return lume.round(percentage)
    else
        return 0
    end
end

---@param window_size number : the size of the window to average new data out over
---@param existing_value number : the existing value
---@param new_value number : the new value to be averaged into the existing value
---@param precision number : optional, how precise the averaged result should be (as per lume.round)
---@return number : the average based on the provided numbers
local function calculateAverage(window_size, existing_value, new_value, precision)
    -- This effectively gives weight to previous data equal to '(window_size - 1) /window_size'. If window_size is 4, the previous data get 75% weight. If window_size is 10, the previous data get 90% weight.
    return lume.round(((existing_value * (window_size - 1)) + new_value) / window_size, precision)
end

---@param line_name string The name of the line for there is the line rule designator.
---@return string : line rule designator string extracted from line_name
---Return the line rule given the name of the line.
local function getLineRuleFromName(line_name)
    for key, _ in pairs(rules.line_rules) do
        local line_identifier = rules.IDENTIFIER_START .. key
        if string.find(line_name, line_identifier, 1, true) ~= nil then
            return key
        end
    end

    return ""
end

---@param line_type string The type of the line.
---@return string : line rule designator string based on line_type
---Return the line rule given the name and type of the line.
local function getLineRuleFromType(line_type)
    -- Start with default PASSENGER rule
    local resultRule = rules.defaultPassengerLineRule

    -- Change to CARGO rule if applicable
    if line_type == "CARGO" then
        resultRule = rules.defaultCargoLineRule
    end

    return resultRule
end

---@param line_rule string : the rule of the line
---@param line_name string : the name of the line for there are the parameters
---@return table | nil : table of parameters, or nil if error
---returns the parameters for the line
local function getLineParameters(line_name, line_rule)
    -- Check that parameters have been provided
    if line_name ~= nil and line_rule ~= nil and rules.line_rules[line_rule] and rules.line_rules[line_rule].parameters then
        -- Make a copy of the default parameters
        local has_required_parameters = false
        local line_parameters = {}
        for i = 1, #rules.line_rules[line_rule].parameters do
            line_parameters[i] = {
                name = rules.line_rules[line_rule].parameters[i].name,
                required = rules.line_rules[line_rule].parameters[i].required,
                value = rules.line_rules[line_rule].parameters[i].default,
                min = rules.line_rules[line_rule].parameters[i].min,
                max = rules.line_rules[line_rule].parameters[i].max,
            }

            if line_parameters[i].required then
                has_required_parameters = true
            end
        end

        -- Set search strings
        local identifier_start_text = rules.IDENTIFIER_START .. line_rule
        local identifier_end_text = rules.IDENTIFIER_END
        local parameter_separator_text = rules.PARAMETER_SEPARATOR

        -- Locate identifier beginning and continue processing if found
        local _, identifier_start_end_pos = string.find(line_name, identifier_start_text, 1, true)
        if (identifier_start_end_pos ~= nil) then
            -- Locate identifier ending and continue processing if found
            local identifier_end_start_pos, _ = string.find(line_name, identifier_end_text, identifier_start_end_pos + 1, true)
            if (identifier_end_start_pos ~= nil) then
                -- Check that there's actually space between the starting and ending identifiers
                -- Use +2 for the starting identifier as there should be a PARAMETER_SEPARATOR first before getting to the first parameter
                if identifier_start_end_pos + 2 <= identifier_end_start_pos - 1 then
                    local parameter_string = string.sub(line_name, identifier_start_end_pos + 2, identifier_end_start_pos - 1)
                    local parsed_string = lume.split(parameter_string, parameter_separator_text)
                    -- Process the parsed string against the possible number of line parameters (based on the rules)
                    for i = 1, #line_parameters do
                        local parsed_value = tonumber(parsed_string[i])
                        if parsed_string[i] ~= nil and parsed_value == nil then
                            -- First check if an attempt to enter a number was made unsuccessfully, then fail if so
                            log.warn("Line '" .. line_name .. "' has incorrectly formatted parameters!")
                            return nil
                        elseif type(parsed_value) == "number" then
                            -- Use parsed value if exists
                            -- Check first if the value is within range
                            if (line_parameters[i].min and parsed_value < line_parameters[i].min) or (line_parameters[i].max and parsed_value > line_parameters[i].max) then
                                log.warn("Line '" .. line_name .. "' parameter #" .. i .. " (" .. line_parameters[i].name .. ") is outside of permitted range: " .. line_parameters[i].min .. "-" .. line_parameters[i].max)
                                return nil
                            end
                            -- Clean up no longer needed parameters and set the parsed_value
                            line_parameters[i].value = parsed_value
                        elseif line_parameters[i].required then
                            -- If parsed value doesn't exist but is required, then fail
                            log.warn("Line '" .. line_name .. "' is missing required parameter #" .. i .. " (" .. line_parameters[i].name .. ")!")
                            return nil
                        end
                    end
                    -- All has completed successfully
                    return line_parameters
                elseif identifier_start_end_pos + 1 == identifier_end_start_pos then
                    if has_required_parameters then
                        -- If the line name is correctly formatted, but simply missing parameters that are required, then fail
                        log.warn("Line '" .. line_name .. "' is missing required parameters!")
                        return nil
                    else
                        -- Maybe the line only does not have any required parameters and just uses defaults, just return the existing parameters
                        return line_parameters
                    end
                end
            end
        end

        if not has_required_parameters then
            return line_parameters
        else
            -- If we made it here, something is wrong
            log.warn("Line '" .. line_name .. "' is incorrectly formatted, unable to parse data from the name!")
            return nil
        end
    end

    return {}
end

---@param rule string : the rule
---@param rule_manual boolean : whether the rule has been set manually
---@param type string : the type i.e. "PASSENGER" or "CARGO"
---@param carrier string : the carrier i.e. "ROAD", "TRAM", "RAIL", "WATER" or "AIR"
---@return boolean : whether the line is managed
---checks if the line should be managed
local function checkIfManagedLine(rule, rule_manual, type, carrier)
    -- Ignore Manual lines
    if rule == "M" then
        return false
    end

    -- Check if it was a manually assigned rule
    if rule_manual then
        return true
    end

    -- If automatic line management is enabled for the type and carrier, then it is supported
    if stateAutoSettings and stateAutoSettings[type] and stateAutoSettings[type][carrier] and stateAutoSettings[type][carrier] == true then
        return true
    end

    return false
end

---@param line_id number : the id of the line
---@param line_vehicles table : the id's of the vehicles on the line
---@return boolean : whether the line has a problem
---checks if the line, or any vehicles on the line, has a problem
local function checkIfLineHasProblem(line_id, line_vehicles)
    -- Check if this is a problem line
    for i = 1, #problemLineCache do
        if problemLineCache[i] == line_id then
            return true
        end
    end

    -- Check if any of the vehicles on the line has a problem
    for i = 1, #problemVehicleCache do
        for j = 1, #line_vehicles do
            if problemVehicleCache[i] == line_vehicles[j] then
                return true
            end
        end
    end

    return false
end

---resets all sampling variables and sets STATE_WAITING, thus restarting the sampling process
local function restart()
    log.debug("sampling: restart()")
    vehicleOccupancyCache = {}
    problemLineCache = {}
    problemVehicleCache = {}
    sampledLineData = {}
    simEntityAtTerminalCache = {}
    lineSimPersonCache = {}
    lineSimCargoCache = {}
    setStateWaiting()
end

local function prepareInitialData()
    log.debug("sampling: prepareInitialData() starting")

    -- Get the player lines
    local playerLines = api_helper.getPlayerLines()

    -- Stop here if there are no player lines
    if not playerLines or #playerLines <= 0 then
        return false
    end

    -- Get a fresh vehicle2cargoMap
    local vehicle2cargoMap = api_helper.getVehicle2Cargo2SimEntitesMap()

    -- Stop here if there's no cargo map data
    if not vehicle2cargoMap or #vehicle2cargoMap <= 0 then
        return false
    end

    -- Both playerLines and vehicle2cargoMap is ready, start initiating data

    -- Set up the playerLineCache, starting with indication whether the line has been processed
    for _, line_id in pairs(playerLines) do
        sampledLineData[line_id] = {
            TO_BE_PREPARED = true, -- This is used by prepareLineData() to confirm this item needs processing
        }
    end

    -- Set up vehicle occupancies
    for vehicle_id, cargo_table in pairs(vehicle2cargoMap) do
        local passengers = #cargo_table[enums.CargoTypes.PASSENGERS] -- = 1, which is PASSENGERS
        local cargoes = 0

        -- These are all other cargo items, 2-17 by default
        for i = 2, #cargo_table do
            cargoes = cargoes + #cargo_table[i]
        end

        vehicleOccupancyCache[vehicle_id] = {
            PASSENGER = passengers,
            CARGO = cargoes,
            TOTAL = passengers + cargoes,
        }
    end

    -- Prepare problem line/vehicle caches
    problemLineCache = api_helper.getProblemLines()
    problemVehicleCache = api_helper.getNoPathVehicles()

    return true
end

local function prepareLineData()
    log.debug("sampling: prepareLineData() starting")
    local finished = true
    local processed_lines = 0
    local processed_vehicles = 0

    -- Prepare sampledLineData with detailed data of each line
    for line_id, line_data in pairs(sampledLineData) do
        if line_data.TO_BE_PREPARED then
            local lineVehicles = api_helper.getLineVehicles(line_id) -- Start by getting the vehicles to check if any further processing needs to be done at all
            local lineVehiclesInDepot = 0 -- This is used as an indicator of a line problem

            -- If no line vehicles, then set this record to nil and continue without further processing
            if #lineVehicles <= 0 then
                sampledLineData[line_id] = nil
            else
                local lineName = ""
                local lineCarrier = api_helper.getCarrierFromVehicle(lineVehicles[1]) -- Retrieve the carrier from the first vehicle of the line
                local lineDepotId = nil
                local lineType = ""
                local lineRule = "P" -- Same as above, use this as a default. This will be overwritten below.
                local lineRuleManual = false -- Keeps track if the line rule was assigned manually
                local lineRate = 0
                local lineFrequency = 0
                local lineParameters = {}
                local lineCapacity = 0
                local lineCapacityPerVehicle = 0
                local lineOccupancy = 0
                local lineOccupancyPeak = 0
                local lineDemand = 0
                local lineUsage = 0
                local lineManaged = false
                local lineHasProblem = false
                local lineStops = 0
                local lineTransportedLastMonth = 0
                local lineTransportedLastYear = 0

                -- Get all passengers planning to use the line (and cache the data to process later by sampleWaitingCargo())
                local simPersons = api_helper.getSimPersonsForLine(line_id)
                lineSimPersonCache[line_id] = simPersons
                local lineDemandPassengers = #simPersons
                -- Get all cargo planning to use the line (and cache the data to process later by sampleWaitingCargo())
                local simCargos = api_helper.getSimCargosForLine(line_id)
                lineSimCargoCache[line_id] = simCargos
                local lineDemandCargo = #simCargos

                -- Use the most demanded type as the lineType
                if lineDemandPassengers > lineDemandCargo then
                    lineType = "PASSENGER"
                    lineDemand = lineDemandPassengers
                elseif lineDemandCargo > lineDemandPassengers then
                    lineType = "CARGO"
                    lineDemand = lineDemandCargo
                    -- If neither of the previous rules have stuck (either no cargo, or the same amount of cargo for each type), then re-use previous type if data exists
                elseif stateLineData[line_id] then
                    lineType = stateLineData[line_id].type
                    -- If all else fails, set to PASSENGER to have a starting point (avoid lines being indicated as ignored when there's no current demand)
                else
                    lineType = "PASSENGER"
                end

                lineName = api_helper.getEntityName(line_id)

                -- Determine line rule
                lineRule = getLineRuleFromName(lineName)

                -- If lineRule has not been extracted from the lineName already, then set the default rule and indicate automatic assignment
                if lineRule == "" then
                    lineRule = getLineRuleFromType(lineType)
                else
                    lineRuleManual = true
                end

                -- RATE, FREQUENCY, TRANSPORTED_LAST_MONTH, TRANSPORTED_LAST_YEAR, STOPS
                local lineInformation = api_helper.getLineInformation(line_id)

                lineRate = lineInformation.rate
                lineFrequency = lineInformation.frequency
                lineStops = lineInformation.stops
                lineTransportedLastMonth = lineInformation.transported_last_month
                lineTransportedLastYear = lineInformation.transported_last_year

                -- Convert frequency to seconds
                -- Check first if lineFrequency is actually set, otherwise it'll be 'inf' after the conversion
                if lineFrequency > 0 then
                    lineFrequency = lume.round(1 / lineFrequency)
                end

                -- PARAMETERS (where applicable i.e. a rule uses parameters)
                lineParameters = getLineParameters(lineName, lineRule)
                -- If nil was returned then there's a problem (check the getLineParameters function for when nil will be returned)
                if not lineParameters then
                    lineParameters = "ERROR"
                    lineHasProblem = true
                end

                -- CAPACITY, OCCUPANCY, DEPOT
                local newestVehiclePurchaseTime = 0

                for _, vehicle_id in pairs(lineVehicles) do
                    local vehicle = api_helper.getVehicle(vehicle_id)
                    if vehicle then
                        for _, capacity in pairs(vehicle.config.capacities) do
                            lineCapacity = lineCapacity + capacity
                        end
                        if api_helper.isVehicleInDepot(vehicle) or api_helper.isVehicleIsGoingToDepot(vehicle) then
                            lineVehiclesInDepot = lineVehiclesInDepot + 1
                        end
                        -- Determine line depot by the newest vehicle (if the depot exists/can be retrieved)
                        if vehicle.transportVehicleConfig.vehicles[1].purchaseTime > newestVehiclePurchaseTime and api_helper.getDepot(vehicle.depot) then
                            newestVehiclePurchaseTime = vehicle.transportVehicleConfig.vehicles[1].purchaseTime
                            lineDepotId = vehicle.depot
                        end
                    end
                    -- Need to check for this, not all vehicles might have had cargo when the data was prepared and thus not exist here
                    if vehicleOccupancyCache[vehicle_id] then
                        lineOccupancy = lineOccupancy + vehicleOccupancyCache[vehicle_id].TOTAL -- Calculated/prepared in prepareInitialData()
                        lineOccupancyPeak = math.max(vehicleOccupancyCache[vehicle_id].TOTAL, lineOccupancyPeak)
                    end

                    processed_vehicles = processed_vehicles + 1
                end

                if #lineVehicles > 0 and lineCapacity > 0 then
                    lineCapacityPerVehicle = lineCapacity / #lineVehicles
                end

                -- USAGE
                lineUsage = roundPercentage(lineOccupancy, lineCapacity)

                -- MANAGED
                lineManaged = checkIfManagedLine(lineRule, lineRuleManual, lineType, lineCarrier)

                -- HAS_PROBLEM (if a vehicle is IN_DEPOT or GOING_TO_DEPOT, it is considered a marker for a possible problem)
                lineHasProblem = lineHasProblem or lineVehiclesInDepot > 0 or checkIfLineHasProblem(line_id, lineVehicles)
                if lineHasProblem then
                    lineDepotId = nil
                end

                sampledLineData[line_id] = {
                    SAMPLE_WAITING_CARGO = true, -- Set marker for next step (this will be used by mergeLineData() to confirm this item needs processing)
                    name = lineName,
                    carrier = lineCarrier,
                    depot_id = lineDepotId,
                    type = lineType,
                    rule = lineRule,
                    rule_manual = lineRuleManual,
                    rate = lineRate,
                    frequency = lineFrequency,
                    parameters = lineParameters,
                    vehicles = #lineVehicles,
                    capacity = lineCapacity,
                    capacity_per_vehicle = lineCapacityPerVehicle,
                    occupancy = lineOccupancy,
                    occupancy_peak = lineOccupancyPeak,
                    demand = lineDemand,
                    usage = lineUsage,
                    managed = lineManaged,
                    has_problem = lineHasProblem,
                    stops = lineStops,
                    transported_last_month = lineTransportedLastMonth,
                    transported_last_year = lineTransportedLastYear,
                }

                -- Update counters
                processed_lines = processed_lines + 1
            end

            -- Stop the processing if processing limit has been reached.
            if processed_lines >= MAX_LINES_TO_PROCESS_PER_RUN or processed_vehicles >= MAX_VEHICLES_TO_PROCESS_PER_RUN then
                finished = false -- This state can't be completed (for sure) if we reached this, run it one more time
                log.debug("sampling: prepareLineData() processing limit reached, stopping")
                break
            end
        end
    end

    log.debug("sampling: prepareLineData() processed " .. processed_lines .. " lines and " .. processed_vehicles .. " vehicles")
    return finished
end

---this functions samples the waiting cargo for each lines and adds the information to the sampled line data
local function sampleWaitingCargo()
    log.debug("sampling: sampleWaitingCargo() starting")
    local finished = true
    local stopProcessing = false
    local processed_lines = 0
    local processed_items = 0

    for line_id, line_data in pairs(sampledLineData) do
        -- Check for marker
        if line_data.SAMPLE_WAITING_CARGO then
            local lineWaiting = 0
            local lineWaitingPeak = 0
            local stopsWithWaiting = 0
            local waitingEntitiesPerStop = {}
            local lineEntities = {}

            -- Start by setting the lineEntities as per already cached data
            if line_data.type == "PASSENGER" and lineSimPersonCache[line_id] then
                lineEntities = lineSimPersonCache[line_id]
            elseif line_data.type == "CARGO" and lineSimCargoCache[line_id] then
                lineEntities = lineSimCargoCache[line_id]
            end

            if #lineEntities > 0 then
                for _, value in pairs(lineEntities) do
                    local currentEntityId = value

                    -- Get the SIM_ENTITY_AT_TERMINAL unless already cached
                    if not simEntityAtTerminalCache[currentEntityId] then
                        local entity_at_terminal = api_helper.getEntityAtTerminal(currentEntityId)
                        if entity_at_terminal then
                            simEntityAtTerminalCache[currentEntityId] = entity_at_terminal
                        else
                            simEntityAtTerminalCache[currentEntityId] = NO_ENTITY -- Set a value in case the entity is not at terminal (nil returned)
                        end

                        -- Check if we've processed too many items, then stop and restart next tick
                        processed_items = processed_items + 1
                        if processed_items >= MAX_ENTITIES_TO_PROCESS_PER_RUN then
                            finished = false
                            stopProcessing = true
                            log.debug("sampling: sampleWaitingCargo() processing limit reached, stopping")
                            break
                        end
                    end

                    -- Process the entity for the line, if it exists in the cache
                    if simEntityAtTerminalCache[currentEntityId] and simEntityAtTerminalCache[currentEntityId] ~= NO_ENTITY then
                        local currentEntity = simEntityAtTerminalCache[currentEntityId]

                        -- First check if the entity is waiting for this line, process it if so
                        if currentEntity.line == line_id then
                            -- If previous entry in the table created, then increase it, otherwise create and initialize it
                            if waitingEntitiesPerStop[currentEntity.lineStop0] then
                                waitingEntitiesPerStop[currentEntity.lineStop0] = waitingEntitiesPerStop[currentEntity.lineStop0] + 1
                            else
                                waitingEntitiesPerStop[currentEntity.lineStop0] = 1
                            end
                        end
                    end
                end

                -- If stop processing has been triggered, break this loop here
                if stopProcessing then
                    break
                end

                for _, value in pairs(waitingEntitiesPerStop) do
                    -- Count number of stops with anything waiting
                    if value > 0 then
                        stopsWithWaiting = stopsWithWaiting + 1
                    end

                    lineWaiting = lineWaiting + value
                    if value > lineWaitingPeak then
                        lineWaitingPeak = value
                    end
                end
            end

            -- Add sampled data to sampledLineData
            sampledLineData[line_id].waiting = lineWaiting
            sampledLineData[line_id].waiting_peak = lineWaitingPeak
            sampledLineData[line_id].stops_with_waiting = stopsWithWaiting

            -- Update markers
            sampledLineData[line_id].SAMPLE_WAITING_CARGO = nil
            sampledLineData[line_id].MERGE = true

            -- Update counters
            processed_lines = processed_lines + 1

            if processed_lines >= MAX_LINES_TO_PROCESS_PER_RUN then
                finished = false -- This state can't be completed (for sure) if we reached this, run it one more time
                log.debug("sampling: mergeLineData() processing limit reached, stopping")
                break
            end
        end
    end

    log.debug("sampling: sampleWaitingCargo() processed " .. processed_lines .. " lines and " .. processed_items .. " new items")
    return finished
end

---merges the sampled line data with the previously existing line data to return updated line data
local function mergeLineData()
    log.debug("sampling: mergeLineData() starting")
    local finished = true
    local processed_lines = 0

    -- Merge existing line_data into the sampled line_data
    for line_id, line_data in pairs(sampledLineData) do
        -- Check for marker
        if line_data.MERGE then
            -- Check if stateLineData already has this line
            if stateLineData[line_id] then
                -- Add to existing samples
                sampledLineData[line_id].samples = stateLineData[line_id].samples + 1
                -- Preserve last_action
                sampledLineData[line_id].last_action = stateLineData[line_id].last_action
                -- Check whether any manual vehicle management happened since last sampling
                if sampledLineData[line_id].vehicles ~= stateLineData[line_id].vehicles then
                    sampledLineData[line_id].last_action = "MANUAL"
                    sampledLineData[line_id].samples = 1
                end
                -- First, preserve depot_update_required if set. If not, then:
                -- Preserve depot_id and depot_stop_id if depot_stop_id exists.
                -- If depot_stop_id exists, it is an indication that a depot has been found by sending a vehicle to a depot and checking for success (in linemanager.lua).
                -- It is more likely that this will be successful for future vehicle additions, so keep the depot_id and depot_stop_id if the depot still exists.
                if stateLineData[line_id].depot_update_required then
                    sampledLineData[line_id].depot_update_required = stateLineData[line_id].depot_update_required
                elseif stateLineData[line_id].depot_stop_id and stateLineData[line_id].depot_id and api_helper.getDepot(stateLineData[line_id].depot_id) then
                    sampledLineData[line_id].depot_id = stateLineData[line_id].depot_id
                    sampledLineData[line_id].depot_stop_id = stateLineData[line_id].depot_stop_id
                end
                -- Calculate averages for demand, usage, rate, frequency, waiting, and waiting_peak.
                sampledLineData[line_id].demand = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].demand, line_data.demand, 0.1)
                sampledLineData[line_id].usage = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].usage, line_data.usage, 0.1)
                sampledLineData[line_id].rate = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].rate, line_data.rate, 0.1)
                sampledLineData[line_id].frequency = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].frequency, line_data.frequency, 0.1)
                sampledLineData[line_id].waiting = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].waiting, line_data.waiting, 0.1)
                sampledLineData[line_id].stops_with_waiting = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].stops_with_waiting, line_data.stops_with_waiting, 0.01)
                -- Calculate waiting_peak_clamped before waiting_peak
                sampledLineData[line_id].waiting_peak_clamped = lume.clamp(calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].waiting_peak_clamped, line_data.waiting_peak, 0.1), 0, line_data.capacity_per_vehicle * 1.5)
                sampledLineData[line_id].waiting_peak = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].waiting_peak, line_data.waiting_peak, 0.1)
            else
                -- If not already existing, then start samples from 1. No need to process the data further.
                sampledLineData[line_id].samples = 1
                -- Set a blank last_action
                sampledLineData[line_id].last_action = ""
                -- Set a waiting_peak_clamped
                sampledLineData[line_id].waiting_peak_clamped = lume.clamp(line_data.waiting_peak, 0, line_data.capacity_per_vehicle * 2)
            end

            -- Update markers
            sampledLineData[line_id].MERGE = nil
            sampledLineData[line_id].APPLY_RULES = true

            -- Update counters
            processed_lines = processed_lines + 1

            -- Stop the processing if processing limit has been reached.
            if processed_lines >= MAX_LINES_TO_PROCESS_PER_RUN then
                finished = false -- This state can't be completed (for sure) if we reached this, run it one more time
                log.debug("sampling: mergeLineData() processing limit reached, stopping")
                break
            end
        end
    end

    log.debug("sampling: mergeLineData() processed " .. processed_lines .. " lines")
    return finished
end

---applies rules to the sampled lines and adds an action
local function applyRules()
    log.debug("sampling: applyRules() starting")
    local finished = true
    local processed_lines = 0

    -- Apply rules to the finalized line_data
    for line_id, line_data in pairs(sampledLineData) do
        if line_data.APPLY_RULES then
            -- Set action to "" by default, then change it as required
            sampledLineData[line_id].action = ""
            -- If the line is managed, has stops, and does not have a problem, then apply rules
            if line_data.managed and line_data.stops > 0 and not line_data.has_problem then
                -- Check if a vehicle should be added to a Line.
                if rules.moreVehicleConditions(line_data) then
                    sampledLineData[line_id].action = "ADD"
                    -- If not, then check whether a vehicle should be removed from a Line.
                elseif rules.lessVehiclesConditions(line_data) then
                    sampledLineData[line_id].action = "REMOVE"
                end
            end

            -- Update markers
            sampledLineData[line_id].APPLY_RULES = nil

            -- Update counters
            processed_lines = processed_lines + 1

            -- Stop the processing if processing limit has been reached.
            if processed_lines >= MAX_LINES_TO_PROCESS_PER_RUN then
                finished = false -- This state can't be completed if we reached this
                break
            end
        end
    end

    log.debug("sampling: applyRules() processed " .. processed_lines .. " lines")
    return finished
end

---@param state_line_data table : a reference to state.line_data
---@param state_auto_settings table : a reference to state.auto_settings
---@return boolean : whether the sampling process was started
---starts the sampling process (if state is STATE_FINISHED, and parameters are provided)
function sampling.start(state_line_data, state_auto_settings)
    log.debug("sampling: start()")
    if (isStateStopped() or isStateFinished()) and state_line_data and state_auto_settings then
        stateLineData = state_line_data
        stateAutoSettings = state_auto_settings
        restart() -- Reset all variables and set STATE_WAITING

        return true
    else
        return false
    end
end

---stops the sampling process
function sampling.stop()
    log.debug("sampling: stop()")
    setStateStopped()
end

---process sampling if required, doing it one step at a time to spread the workload out. This function needs to be called on each update.
function sampling.process()
    -- Start debug timer
    timer.start()

    -- Don't do any processing if state is finished
    if isStateStopped() or isStateFinished() then
        return
    end

    -- If not finished, work our way through the data preparation until completed
    if isStateWaiting() then
        setStatePreparingInitialData()
    elseif isStatePreparingInitialData() then
        if prepareInitialData() then
            log.debug("sampling: prepareInitialData() completed successfully")
            setStatePreparingLineData()
        else
            log.debug("sampling: prepareInitialData() no data to process yet, stopping sampling")
            setStateStopped()
        end
    elseif isStatePreparingLineData() and prepareLineData() then
        log.debug("sampling: prepareLineData() completed successfully")
        setStateSamplingWaitingCargo()
    elseif isStateSamplingWaitingCargo() and sampleWaitingCargo() then
        log.debug("sampling: sampleWaitingCargo() completed successfully")
        setStateMergingLineData()
    elseif isStateMergingLineData() and mergeLineData() then
        log.debug("sampling: mergeLineData() completed successfully")
        setStateApplyingRules()
    elseif isStateApplyingRules() and applyRules() then
        log.debug("sampling: applyRules() completed successfully")
        setStateFinished()
    end

    -- Stop debug timer
    local time_used = timer.stop()
    log.debug("sampling: CPU time used: " .. time_used)
end

---returns the sampled line data
function sampling.getSampledLineData()
    if isStateFinished() then
        return sampledLineData
    else
        return nil
    end
end

---@param vehicle_ids table array of VEHICLE ids
---@return number id of the emptiest vehicle of the provided vehicle_ids
---returns the id of the (cached) emptiest vehicle in the provided vehicle_ids
function sampling.getEmptiestVehicle(vehicle_ids)
    log.debug("sampling: getEmptiestVehicle() started")
    local emptiestVehicleLoad = 9999999999
    local emptiestVehicleId = nil

    if vehicleOccupancyCache and vehicle_ids and #vehicle_ids > 0 then
        for _, vehicle_id in pairs(vehicle_ids) do
            -- If vehicle is not cached, assume it is because of no load and stop here
            if not vehicleOccupancyCache[vehicle_id] then
                emptiestVehicleId = vehicle_id
                emptiestVehicleLoad = 0
                break
                -- If vehicle is cached, then use it
            elseif vehicleOccupancyCache[vehicle_id] and vehicleOccupancyCache[vehicle_id].TOTAL < emptiestVehicleLoad then
                emptiestVehicleId = vehicle_id
                emptiestVehicleLoad = vehicleOccupancyCache[vehicle_id].TOTAL
            end
        end
        log.debug("sampling: getEmptiestVehicle() found vehicle '" .. api_helper.getEntityName(emptiestVehicleId) .. "' with current load: " .. emptiestVehicleLoad)
    end

    return emptiestVehicleId
end

---@param vehicle_ids table array of VEHICLE ids
---@return table empty_vehicles_id array of empty VEHICLE ids
---returns the ids of the (cached) empty vehicles in the provided vehicle_ids
function sampling.getEmptyVehicles(vehicle_ids)
    log.debug("sampling: getEmptyVehicles() started")
    local emptyVehicles = {}

    if vehicleOccupancyCache and vehicle_ids and #vehicle_ids > 0 then
        for _, vehicle_id in pairs(vehicle_ids) do
            -- If vehicle is not cached, assume it is because of no load
            if not vehicleOccupancyCache[vehicle_id] or vehicleOccupancyCache[vehicle_id].TOTAL == 0 then
                emptyVehicles[#emptyVehicles + 1] = vehicle_id
            end
        end
        log.debug("sampling: getEmptyVehicles() found " .. #emptyVehicles .. " empty vehicles")
    end

    return emptyVehicles
end

return sampling
