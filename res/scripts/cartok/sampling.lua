local rules = require 'cartok/rules'
local enums = require 'cartok/enums'
local api_helper = require 'cartok/api_helper'
local lume = require 'cartok/lume'
local timer = require 'cartok/timer'

local sampling = {}

local log = nil --require 'cartok/logging'

local SAMPLING_WINDOW_SIZE = 5 -- This must be 2 or greater, or...danger. Lower number means quicker changes to data and vice versa.

local NO_ENTITY = -1

local MAX_LINES_TO_PROCESS_PER_RUN = 20 -- Maximum lines to process per run
local MAX_VEHICLES_TO_PROCESS_PER_RUN = 50 -- Maximum vehicles to process per run
local MAX_ENTITIES_TO_PROCESS_PER_RUN = 200 -- Maximum entities to process per run

local STATE_STOPPED = 1
local STATE_WAITING = 2
local STATE_PREPARING_INITIAL_DATA = 3
local STATE_PREPARING_LINE_DATA = 4
local STATE_SAMPLING_WAITING_CARGO = 5
local STATE_MERGING_LINE_DATA = 6
local STATE_APPLYING_RULES = 7
local STATE_FINISHED = 8

local sampling_state = STATE_STOPPED -- To track the progress of the sampling

local finishedOnce = nil

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
    finishedOnce = true
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

---checks whether the sampling is currently finished - only returns true on the first check (if finished)
function sampling.isFinishedOnce()
    if finishedOnce and sampling_state == STATE_FINISHED then
        finishedOnce = false
        return true
    end

    return false
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
    for key, value in pairs(rules.line_rules) do
        if value.identifier and string.find(line_name, value.identifier, 1, true) ~= nil then
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

---@param line_name string : the name of the line for there is the target
---@param identifier string : the identifier to look for to find the target within the line_name
---@return integer : the target
---Returns the target based on line_name and identifier, or 0 if not found or incorrectly formatted.
local function getTarget(line_name, identifier)
    if (line_name ~= nil and identifier ~= nil) then
        local _, identifier_start_end = string.find(line_name, identifier, 1, true)
        if (identifier_start_end ~= nil) then
            -- rules.IDENTIFIER_END is the rule ending character(s), what is between the starting identifier and this character(s) is the number we're looking for.
            local text_end = string.find(line_name, rules.IDENTIFIER_END, identifier_start_end + 1, true)
            if (text_end ~= nil) then
                local target = tonumber(string.sub(line_name, identifier_start_end + 1, text_end - 1))
                if (type(target) == "number") then
                    return target
                end
            end
        end
    end

    return 0
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
    for i=1, #problemLineCache do
        if problemLineCache[i] == line_id then
            return true
        end
    end

    -- Check if any of the vehicles on the line has a problem
    for i=1, #problemVehicleCache do
        for j=1, #line_vehicles do
            if problemVehicleCache[i] == line_vehicles[j] then
                return true
            end
        end
    end

    return false
end

---@param short_period number : the short period
---@param long_period number : the long period
---@param previous_trend number : (optional) the previous trend value
---@return number : the updated trend value, positive numbers is for how long the short_period has remained above the long_period and vice versa
---checks for how long the short_period has remained above/below the long_period and returns an updated trend value
local function calculateTrend(short_period, long_period, previous_trend)
    previous_trend = previous_trend or 0
    local new_trend = 0

    if previous_trend == 0 then
        if short_period < long_period then
            new_trend = -1
        elseif short_period > long_period then
            new_trend = 1
        end
    elseif previous_trend > 0 then
        if short_period < long_period then
            new_trend = -1
        elseif short_period > long_period then
            new_trend = previous_trend + 1
        end
    elseif previous_trend < 0 then
        if short_period < long_period then
            new_trend = previous_trend - 1
        elseif short_period > long_period then
            new_trend = 1
        end
    end

    return new_trend
end

---resets all sampling variables and sets STATE_WAITING, thus restarting the sampling process
local function restart()
    log.debug("sampling: restart()")
    finishedOnce = false
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

        for i = 2, #cargo_table do -- These are all other cargo items, 2-17 by default
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
                local lineType = ""
                local lineRule = "P" -- Same as above, use this as a default. This will be overwritten below.
                local lineRuleManual = false -- Keeps track if the line rule was assigned manually
                local lineRate = 0
                local lineFrequency = 0
                local lineTarget = 0
                local lineCapacity = 0
                local lineCapacityPerVehicle = 0
                local lineOccupancy = 0
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
                if lineFrequency > 0 then -- Check if lineFrequency is actually set, otherwise it'll be 'inf' after the conversion
                    lineFrequency = lume.round(1/lineFrequency)
                end

                -- TARGET (where applicable)
                if rules.line_rules[lineRule].uses_target then
                    lineTarget = getTarget(lineName, rules.line_rules[lineRule].identifier)

                    if lineTarget <= 0 then
                        log.warn("Line '" .. lineName .. "' uses rule '" .. lineRule .. "', but target is incorrectly formatted!")
                    end
                end

                -- CAPACITY and OCCUPANCY
                for _, vehicle_id in pairs(lineVehicles) do
                    local vehicle = api_helper.getVehicle(vehicle_id)
                    if vehicle then
                        for _, capacity in pairs(vehicle.config.capacities) do
                            lineCapacity = lineCapacity + capacity
                        end
                        if api_helper.isVehicleInDepot(vehicle) or api_helper.isVehicleIsGoingToDepot(vehicle) then
                            lineVehiclesInDepot = lineVehiclesInDepot + 1
                        end
                    end
                    if vehicleOccupancyCache[vehicle_id] then -- Need to check for this, not all vehicles might have had cargo when the data was prepared and thus not exist here
                        lineOccupancy = lineOccupancy + vehicleOccupancyCache[vehicle_id].TOTAL -- Calculated/prepared in prepareInitialData()
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
                lineHasProblem = lineVehiclesInDepot > 0 or checkIfLineHasProblem(line_id, lineVehicles)

                sampledLineData[line_id] = {
                    SAMPLE_WAITING_CARGO = true, -- Set marker for next step (this will be used by mergeLineData() to confirm this item needs processing)
                    name = lineName,
                    carrier = lineCarrier,
                    type = lineType,
                    rule = lineRule,
                    rule_manual = lineRuleManual,
                    rate = lineRate,
                    frequency = lineFrequency,
                    target = lineTarget,
                    vehicles = #lineVehicles,
                    capacity = lineCapacity,
                    capacity_per_vehicle = lineCapacityPerVehicle,
                    occupancy = lineOccupancy,
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
    local lineWaiting = 0
    local lineWaitingPeak = 0

    for line_id, line_data in pairs(sampledLineData) do
        if line_data.SAMPLE_WAITING_CARGO then -- Check for marker
            local waitingEntitiesPerStop = {}
            local lineEntities = {}

            -- Start by setting the lineEntities as per already cached data
            if line_data.type == "PASSENGER" and lineSimPersonCache[line_id] then
                lineEntities = lineSimPersonCache[line_id]
            elseif line_data.type == "CARGO" and lineSimCargoCache[line_id] then
                lineEntities = lineSimCargoCache[line_id]
            end

            if #lineEntities > 0 then
                for _, value in pairs(lineEntities) do -- i = 1, #lineEntities do
                    local currentEntityId = value

                    -- Get the SIM_ENTITY_AT_TERMINAL unless already cached
                    if not simEntityAtTerminalCache[currentEntityId] then
                        local entity_at_terminal = api_helper.getEntityAtTerminal(currentEntityId)
                        if entity_at_terminal ~= nil then
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

                if #waitingEntitiesPerStop > 0 then
                    for _, value in pairs(waitingEntitiesPerStop) do
                        lineWaiting = lineWaiting + value
                        if value > lineWaitingPeak then
                            lineWaitingPeak = value
                        end
                    end
                end
            end

            -- Add sampled data to sampledLineData
            sampledLineData[line_id].waiting = lineWaiting
            sampledLineData[line_id].waiting_peak = lineWaitingPeak

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
        if line_data.MERGE then -- Check for marker
            if stateLineData[line_id] then
                -- Add to existing samples
                sampledLineData[line_id].samples = stateLineData[line_id].samples + 1
                -- Preserve last_action
                sampledLineData[line_id].last_action = stateLineData[line_id].last_action
                -- Calculate averages for demand, usage, rate, frequency, waiting, and waiting_peak.
                sampledLineData[line_id].demand = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].demand, line_data.demand, 0.1)
                sampledLineData[line_id].usage = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].usage, line_data.usage, 0.1)
                sampledLineData[line_id].rate = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].rate, line_data.rate, 0.1)
                sampledLineData[line_id].frequency = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].frequency, line_data.frequency, 0.1)
                sampledLineData[line_id].waiting = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].waiting, line_data.waiting, 0.1)
                sampledLineData[line_id].waiting_peak = calculateAverage(SAMPLING_WINDOW_SIZE, stateLineData[line_id].waiting_peak, line_data.waiting_peak, 0.1)
            else
                -- If not already existing, then start samples from 1. No need to process the data further.
                sampledLineData[line_id].samples = 1
                -- Set a blank last_action
                sampledLineData[line_id].last_action = ""
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
            -- If line is managed and does not have a problem, then apply rules
            if line_data.managed and not line_data.has_problem then
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

    if isStateFinished() and vehicle_ids and #vehicle_ids > 0 then
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

return sampling
