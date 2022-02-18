local rules = require 'cartok/rules'
local enums = require 'cartok/enums'
local api_helper = require 'cartok/api_helper'
local lume = require 'cartok/lume'

local sampling = {}

local log = nil --require 'cartok/logging'

local SAMPLING_WINDOW_SIZE = 4 -- This must be 2 or greater, or...danger. Lower number means quicker changes to data and vice versa.

local MAX_LINES_TO_PROCESS_PER_RUN = 3 -- How many lines to process per run
local MAX_VEHICLES_TO_PROCESS_PER_RUN = 10 -- How many vehicles to process per run

local STATE_STOPPED = 1
local STATE_WAITING = 2
local STATE_PREPARING_INITIAL_DATA = 3
local STATE_PREPARING_LINE_DATA = 4
local STATE_MERGING_LINE_DATA = 5
local STATE_APPLYING_RULES = 6
local STATE_FINISHED = 7

local sampling_state = STATE_STOPPED -- To track the progress of the sampling

local finishedOnce = nil

local vehicleOccupancyCache = nil
local problemLineCache = nil
local problemVehicleCache = nil

local sampledLineData = nil

local autoSettings = nil
local lineDataReference = nil

function sampling.setLog(input_log)
    log = input_log
end

local function setStateStopped()
    sampling_state = STATE_STOPPED
end

function sampling.isStateStopped()
    return sampling_state == STATE_STOPPED
end

local function setStateWaiting()
    sampling_state = STATE_WAITING
end

function sampling.isStateWaiting()
    return sampling_state == STATE_WAITING
end

local function setStatePreparingInitialData()
    sampling_state = STATE_PREPARING_INITIAL_DATA
end

function sampling.isStatePreparingInitialData()
    return sampling_state == STATE_PREPARING_INITIAL_DATA
end

local function setStatePreparingLineData()
    sampling_state = STATE_PREPARING_LINE_DATA
end

function sampling.isStatePreparingLineData()
    return sampling_state == STATE_PREPARING_LINE_DATA
end

local function setStateMergingLineData()
    sampling_state = STATE_MERGING_LINE_DATA
end

function sampling.isStateMergingLineData()
    return sampling_state == STATE_MERGING_LINE_DATA
end

local function setStateApplyingRules()
    sampling_state = STATE_APPLYING_RULES
end

function sampling.isStateApplyingRules()
    return sampling_state == STATE_APPLYING_RULES
end

local function setStateFinished()
    sampling_state = STATE_FINISHED
    finishedOnce = true
end

function sampling.isStateFinished()
    return sampling_state == STATE_FINISHED
end

---this returns true only on the first if the state is finished
function sampling.isStateFinishedOnce()
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

---@param existing_value number : the existing value
---@param new_value number : the new value to be averaged into the existing value
---@param precision number : optional, how precise the averaged result should be (as per lume.round)
---@return number : the average based on the provided numbers
local function calculateAverage(existing_value, new_value, precision)
    -- This effectively gives weight to previous data equal to '(SAMPLING_WINDOW_SIZE - 1) / SAMPLING_WINDOW_SIZE'. If SAMPLING_WINDOW_SIZE is 4, the previous data get 75% weight
    return lume.round(((existing_value * (SAMPLING_WINDOW_SIZE - 1)) + new_value) / SAMPLING_WINDOW_SIZE, precision)
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
    if autoSettings and autoSettings[type] and autoSettings[type][carrier] and autoSettings[type][carrier] == true then
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

---resets all sampling variables and sets STATE_WAITING, thus restarting the sampling process
local function restart()
    log.debug("sampling: restart()")
    finishedOnce = false
    vehicleOccupancyCache = {}
    problemLineCache = {}
    problemVehicleCache = {}
    sampledLineData = {}
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

        for i = 2, 17 do -- These are all other cargo items
            cargoes = cargoes + #cargo_table[i]
        end

        vehicleOccupancyCache[vehicle_id] = {
            PASSENGER = passengers,
            CARGO = cargoes,
            TOTAL = passengers + cargoes
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
        if line_data and line_data.TO_BE_PREPARED then
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
                local lineOccupancy = 0
                local lineDemand = 0
                local lineUsage = 0
                local lineManaged = false
                local lineHasProblem = false

                -- Get all passengers planning to use the line
                local lineDemandPassengers = #api_helper.getSimPersonsForLine(line_id)
                -- Get all cargo planning to use the line
                local lineDemandCargo = #api_helper.getSimCargosForLine(line_id)

                -- Use the most demanded type as the lineType
                if lineDemandPassengers > lineDemandCargo then
                    lineType = "PASSENGER"
                    lineDemand = lineDemandPassengers
                elseif lineDemandCargo > lineDemandPassengers then
                    lineType = "CARGO"
                    lineDemand = lineDemandCargo
                -- If neither of the previous rules have stuck, then re-use previous type (if set to a sensible value)
                elseif lineDataReference[line_id] and lineDataReference[line_id].type and (lineDataReference[line_id].type == "PASSENGER" or lineDataReference[line_id].type == "CARGO") then
                    lineType = lineDataReference[line_id].type
                -- If all else fails, set to PASSENGER to have a starting point
                else
                    lineType = "PASSENGER" -- Use this as a default to avoid lines being indicated as ignored when there's no current demand
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

                -- RATE and FREQUENCY
                lineRate, lineFrequency = api_helper.getLineRateAndFrequency(line_id)

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

                -- USAGE
                lineUsage = roundPercentage(lineOccupancy, lineCapacity)

                -- MANAGED
                lineManaged = checkIfManagedLine(lineRule, lineRuleManual, lineType, lineCarrier)

                -- HAS_PROBLEM (if a vehicle is IN_DEPOT or GOING_TO_DEPOT, it is considered a marker for a possible problem)
                lineHasProblem = lineVehiclesInDepot > 0 or checkIfLineHasProblem(line_id, lineVehicles)

                sampledLineData[line_id] = {
                    TO_BE_MERGED = true, -- This is used by mergeLineData() to confirm this item needs processing
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
                    occupancy = lineOccupancy,
                    demand = lineDemand,
                    usage = lineUsage,
                    managed = lineManaged,
                    has_problem = lineHasProblem,
                }

                -- Update counters
                processed_lines = processed_lines + 1
            end

            -- Stop the processing if processing limit has been reached.
            if processed_lines >= MAX_LINES_TO_PROCESS_PER_RUN or processed_vehicles >= MAX_VEHICLES_TO_PROCESS_PER_RUN then
                finished = false -- This state can't be completed if we reached this
                break
            end
        end
    end

    log.debug("sampling: prepareLineData() processed " .. processed_lines .. " lines and " .. processed_vehicles .. " vehicles")
    return finished
end

---merges the sampled line data with the previously existing line data to return updated line data
local function mergeLineData()
    log.debug("sampling: mergeLineData() starting")
    local finished = true
    local processed_lines = 0

    -- Merge existing line_data into the sampled line_data
    for line_id, line_data in pairs(sampledLineData) do
        if line_data and line_data.TO_BE_MERGED then
            if lineDataReference[line_id] then
                -- Add to existing samples
                sampledLineData[line_id].samples = lineDataReference[line_id].samples + 1
                -- Preserve last_action
                sampledLineData[line_id].last_action = lineDataReference[line_id].last_action
                -- Calculate moving average for demand, usage and rate to even out the numbers.
                sampledLineData[line_id].demand = calculateAverage(lineDataReference[line_id].demand, line_data.demand)
                sampledLineData[line_id].usage = calculateAverage(lineDataReference[line_id].usage, line_data.usage)
                sampledLineData[line_id].rate = calculateAverage(lineDataReference[line_id].rate, line_data.rate)
                sampledLineData[line_id].frequency = calculateAverage(lineDataReference[line_id].frequency, line_data.frequency, 0.1) -- Round this to better precision as the numbers tend to be smaller
            else
                -- If not already existing, then start samples from 1. No need to process the data further.
                sampledLineData[line_id].samples = 1
                -- Set a blank last_action
                sampledLineData[line_id].last_action = ""
            end

            -- Update markers
            sampledLineData[line_id].TO_BE_MERGED = nil
            sampledLineData[line_id].TO_APPLY_RULES = true

            -- Update counters
            processed_lines = processed_lines + 1

            -- Stop the processing if processing limit has been reached.
            if processed_lines >= MAX_LINES_TO_PROCESS_PER_RUN then
                finished = false -- This state can't be completed if we reached this
                break
            end
        end
    end

    log.debug("sampling: mergeLineData() processed " .. processed_lines .. " lines")
    return finished
end

local function applyRules()
    log.debug("sampling: applyRules() starting")
    local finished = true
    local processed_lines = 0

    -- Apply rules to the finalized line_data
    for line_id, line_data in pairs(sampledLineData) do
        if line_data.TO_APPLY_RULES then
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
            sampledLineData[line_id].TO_APPLY_RULES = nil

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

---@param line_data_reference table : a reference to state.line_data
---@param auto_settings table : a reference to state.auto_settings
---@return boolean : whether the sampling process was started
---starts the sampling process (if state is STATE_FINISHED, and parameters are provided)
function sampling.start(line_data_reference, auto_settings)
    log.debug("sampling: start()")
    if (sampling.isStateStopped() or sampling.isStateFinished()) and line_data_reference and auto_settings then
        lineDataReference = line_data_reference
        autoSettings = auto_settings
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
    -- Don't do any processing if state is finished
    if sampling.isStateStopped() or sampling.isStateFinished() then
        return
    end

    -- If not finished, work our way through the data preparation until completed
    if sampling.isStateWaiting() then
        setStatePreparingInitialData()
    elseif sampling.isStatePreparingInitialData() then
        if prepareInitialData() then
            log.debug("sampling: prepareInitialData() completed successfully")
            setStatePreparingLineData()
        else
            log.debug("sampling: prepareInitialData() no data to process yet, stopping sampling")
            setStateStopped()
        end
    elseif sampling.isStatePreparingLineData() and prepareLineData() then
        log.debug("sampling: prepareLineData() completed successfully")
        setStateMergingLineData()
    elseif sampling.isStateMergingLineData() and mergeLineData() then
        log.debug("sampling: mergeLineData() completed successfully")
        setStateApplyingRules()
    elseif sampling.isStateApplyingRules() and applyRules() then
        log.debug("sampling: applyRules() completed successfully")
        setStateFinished()
    end
end

---returns the sampled line data
function sampling.getSampledLineData()
    if sampling.isStateFinished() then
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

    if sampling.isStateFinished() and vehicle_ids and #vehicle_ids > 0 then
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
