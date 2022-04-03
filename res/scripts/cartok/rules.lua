-- This file is "owned" by sampling.lua and separates out all the rule specific logic into an easily 
local lume = require 'cartok/lume'

local rules = {}

local log = nil

function rules.setLog(input_log)
    log = input_log
end

-- If you need to change what identifier delimiters are being used, perhaps for compatibility with another mod, change these
rules.IDENTIFIER_START = "["
rules.IDENTIFIER_END = "]"
rules.PARAMETER_SEPARATOR = ":"

-- The rule definitions
-- These must be in order from longest to shortest rule acronym (otherwise only the first shorter acronym will be found i.e. P will be used before PR, so PR must be higher up in the list)
rules.line_rules = {
    M = { -- Manual management
        name = "MANUAL",
        description = "Manual line management - no automatic line management features will be used for this line.",
    },
    PR = { -- PASSENGER (RUSTEYBUCKET)
        name = "PASSENGER (RusteyBucket)",
        description = "PASSENGER line management rules by RusteyBucket.",
    },
    P = { -- PASSENGER
        name = "PASSENGER",
        description = "A balanced set of default rules for PASSENGER line management.",
        parameters = {
            { -- Parameter 1, (aggressiveness) level = how focused the line should be on capacity/rate rather than (economic) balance. Useful for feeder lines for instance.
                name = "level",
                default = 0,
                min = 0,
                max = 1,
            },
        },
    },
    C = { -- CARGO
        name = "CARGO",
        description = "A balanced set of default rules for CARGO line management.",
        parameters = {
            { -- Parameter 1, (aggressiveness) level = how focused the line should be on capacity/rate rather than (economic) balance. Useful for feeder lines for instance.
                name = "level",
                default = 0,
                min = 0,
                max = 1,
            },
        },
    },
    R = { -- RATE
        name = "RATE",
        description = "Ensures that a configured minimum rate (or range) is achieved.",
        parameters = {
            { -- Parameter 1, the minimum required rate for the line
                name = "rate_target",
                required = true, -- Use either this or a default value
                -- default = 200, -- Only use a default value for non-required parameters or weird things will happen. Kept here for reference only.
                min = 50, -- Optional, to limit min-value (values lower than this will indicate that the line has a problem and it won't be managed)
                max = 2000, -- Optional, to limit max-value (values higher than this will indicate that the line has problem and it won't be managed)
            },
            { -- Parameter 2, the acceptable max waiting peak % compared to capacity_per_vehicle. This will try to keep the waiting_peak below this level, effectively allowing the line to increase capacity when required (but never decrease below the rate).
                name = "waiting_peak_max",
                min = 0,
                max = 300,
            },
        },
    },
}

-- The default rules that are applied automatically (when enabled for a category of lines)
rules.defaultPassengerLineRule = "P"
rules.defaultCargoLineRule = "C"

---@param line_data_single table : the line_data for a single line
---@return boolean : whether a vehicle should be added to the line
function rules.moreVehicleConditions(line_data_single)
    -- Factors that can be used in rules
    local name = line_data_single.name -- the name of the line
    local carrier = line_data_single.carrier -- "ROAD", "TRAM", "RAIL", "WATER" or "AIR"
    local type = line_data_single.type -- "PASSENGER" or "CARGO" (if the line handles both PASSENGER and CARGO, then the greater demand will determine type). Will default to "PASSENGER" if no demand is detected.
    local rule = line_data_single.rule -- the line rule
    local rule_manual = line_data_single.rule_manual -- whether the line rule was assigned manually (rather than automatically)
    local rate = line_data_single.rate -- *average* line rate
    local frequency = line_data_single.frequency -- *average* line frequency in seconds
    local parameters = line_data_single.parameters -- the parameters for the line (this is indexed as per the rules)
    local vehicles = line_data_single.vehicles -- number of vehicles currently on the line
    local capacity = line_data_single.capacity -- total current capacity of the vehicles on the line
    local occupancy = line_data_single.occupancy -- total current occupancy on the vehicles on the line
    local occupancy_peak = line_data_single.occupancy_peak -- current peak amount of passengers on any vehicle on the line
    local demand = line_data_single.demand -- *average* line demand i.e. total number of PASSENGER or CARGO intending to use the line, including already on the line
    local usage = line_data_single.usage -- *average* line usage i.e. occupancy/capacity
    local samples = line_data_single.samples -- number of samples collected for the line since last action taken (this is reset after each action)
    local last_action = line_data_single.last_action -- the last action taken to manage the line; "ADD", "REMOVE" or "MANUAL" if a vehicle was manually added or removed ("" if no previous action exists)
    local waiting = line_data_single.waiting -- *average* total number of items waiting at stations for this line
    local waiting_peak = line_data_single.waiting_peak -- *average* the highest number of items waiting at a station for this line
    local waiting_peak_clamped = line_data_single.waiting_peak_clamped -- *average* the highest number of items waiting at a station for this line, but clamped to 0.5 - 1.5 times the capacity_per_vehicle
    local transported_last_month = line_data_single.transported_last_month -- the amount of items transported last month NOTE: this will only be useful if 1x GameTime is used (otherwise 0, it seems)
    local transported_last_year = line_data_single.transported_last_year -- the amount of items transported last year NOTE: this will only be useful if 1x GameTime is used (otherwise 0, it seems)
    local capacity_per_vehicle = line_data_single.capacity_per_vehicle -- the average capacity per vehicle on the line
    local stops = line_data_single.stops -- number of stops for the line
    local stops_with_waiting = line_data_single.stops_with_waiting -- *average* number of stops that has waiting entities for this line

    local line_rules = {}

    if rule == "P" then
        -- Make use of default PASSENGER rules
        local level = parameters[1].value

        -- USAGE SCORE
        local usageBaseline = {
            ROAD = 50,
            TRAM = 50,
            WATER = 50,
            RAIL = 60,
            AIR = 70,
        }

        -- This will yield a value between 0.0 and 1.2
        local usageScore = lume.clamp(usage / lume.clamp(100 * stops_with_waiting / stops, usageBaseline[carrier], 85), 0, 1.2)

        -- WAITING SCORE
        -- This will yield a value between 0 and 1.5 (0 and 1.5 are the waiting_peak_clamped min/max values relative to capacity_per_vehicle)
        local waitingScore = waiting_peak_clamped / capacity_per_vehicle

        -- FINAL SCORE
        local usageWeight = 100
        local waitingWeight = 100

        if level == 1 then
            usageWeight = 80
            waitingWeight = 120
        end

        -- Usage equal to the expected and waiting equal to capacity_per_vehicle will yield 100 for each
        local finalScore = usageScore * usageWeight + waitingScore * waitingWeight

        -- REQUIRED SCORE
        -- Usage    120 110 100 90  80
        -- Waiting  110 120 130 140 150
        local requiredScore = 230

        -- REQUIRED SAMPLES
        local requiredSamples = 5
        if carrier == "AIR" or carrier == "RAIL" or carrier == "WATER" then
            requiredSamples = requiredSamples + 3
        end
        if last_action == "REMOVE" then
            requiredSamples = requiredSamples + 3
        end

        line_rules = {
            samples > requiredSamples and frequency > 720, -- This is to ensure a that a minimum sensible frequency is maintained
            samples > requiredSamples and finalScore > requiredScore,
        }
    elseif rule == "C" then
        -- Make use of default CARGO rules
        local level = parameters[1].value

        -- USAGE SCORE
        local usageBaseline = {
            ROAD = 50,
            TRAM = 50,
            WATER = 50,
            RAIL = 60,
            AIR = 70,
        }

        -- This will yield a value between 0.0 and 1.2
        local usageScore = lume.clamp(usage / lume.clamp(100 * stops_with_waiting / stops, usageBaseline[carrier], 85), 0, 1.2)

        -- WAITING SCORE
        -- This will yield a value between 0 and 1.5 (0 and 1.5 are the waiting_peak_clamped min/max values relative to capacity_per_vehicle)
        local waitingScore = waiting_peak_clamped / capacity_per_vehicle

        -- FINAL SCORE
        local usageWeight = 100
        local waitingWeight = 100

        if level == 1 then
            usageWeight = 80
            waitingWeight = 120
        end

        -- Usage equal to the expected and waiting equal to capacity_per_vehicle will yield 100 for each
        local finalScore = usageScore * usageWeight + waitingScore * waitingWeight

        -- REQUIRED SCORE
        -- Usage    120 110 100 90  80
        -- Waiting  110 120 130 140 150
        local requiredScore = 230

        -- REQUIRED SAMPLES
        local requiredSamples = 5
        if carrier == "AIR" or carrier == "RAIL" or carrier == "WATER" then
            requiredSamples = requiredSamples + 3
        end
        if last_action == "REMOVE" then
            requiredSamples = requiredSamples + 3
        end

        line_rules = {
            samples > requiredSamples and frequency > 720, -- This is to ensure a that a minimum sensible frequency is maintained
            samples > requiredSamples and finalScore > requiredScore,
        }
    elseif rule == "PR" then
        -- Make use of PASSENGER rules by RusteyBucket
        local d10 = demand * 1.05
        local oneVehicle = 1 / vehicles -- how much would one vehicle change
        local plusOneVehicle = 1 + oneVehicle -- add the rest of the vehicles
        local dv = demand * plusOneVehicle -- exaggerate demand by what one more vehicle could change
        local waitFactor = waiting_peak / capacity_per_vehicle -- how likely is it the vehicles can cope with the demand

        line_rules = {
            samples > 5 and rate < d10, -- get a safety margin of 10% over the real demand
            samples > 5 and rate < dv, -- with low vehicle numbers, those 10% might not do the trick
            samples > 5 and usage > 90,
            samples > 5 and frequency > 720, -- limits frequency to at most 12min (720 seconds)
            samples > 5 and waitFactor > 1.1, -- if there's overcrowding, get more vehicles
        }
    elseif rule == "R" then
        -- Make use of RATE rules
        local modifier = math.max(1.25, 1.1 * (vehicles + 1) / vehicles)
        local rate_target = parameters[1].value
        local waiting_peak_target = parameters[2].value or nil

        -- Adjust required samples
        local requiredSamples = 5
        if carrier == "AIR" or carrier == "RAIL" or carrier == "WATER" then
            requiredSamples = requiredSamples + 3
        end
        if last_action == "REMOVE" then
            requiredSamples = requiredSamples + 3
        end

        -- Always ensure the minimum rate is achieved
        line_rules[#line_rules + 1] = samples > requiredSamples and rate < rate_target

        -- Add additional rules for peak usage
        if waiting_peak_target then
            line_rules[#line_rules + 1] = samples > requiredSamples and waiting_peak / capacity_per_vehicle > modifier * waiting_peak_target / 100
        end

    elseif rule == "F" then
        -- Make use of FREQUENCY rules
        local modifier = math.max(1.25, 1.1 * (vehicles + 1) / vehicles)
        local freq_target = parameters[1].value
        local waiting_peak_target = parameters[2].value or nil

        -- Adjust required samples
        local requiredSamples = 5
        if carrier == "AIR" or carrier == "RAIL" or carrier == "WATER" then
            requiredSamples = requiredSamples + 3
        end
        if last_action == "REMOVE" then
            requiredSamples = requiredSamples + 3
        end

        -- Always ensure the minimum frequency is achieved
        line_rules[#line_rules + 1] = samples > requiredSamples and frequency > freq_target

        -- Add additional rules for peak usage
        if waiting_peak_target then
            line_rules[#line_rules + 1] = samples > requiredSamples and waiting_peak / capacity_per_vehicle > modifier * waiting_peak_target / 100
        end
    end

    -- Check whether at least one condition is fulfilled
    for i = 1, #line_rules do
        if line_rules[i] then
            return true
        end
    end

    -- If we made it here, then the conditions to add a vehicle were not met
    return false
end

---@param line_data_single table : the line_data for a single line
---@return boolean : whether a vehicle should be removed from the line
function rules.lessVehiclesConditions(line_data_single)
    -- Factors that can be used in rules
    local name = line_data_single.name -- the name of the line
    local carrier = line_data_single.carrier -- "ROAD", "TRAM", "RAIL", "WATER" or "AIR"
    local type = line_data_single.type -- "PASSENGER" or "CARGO" (if the line handles both PASSENGER and CARGO, then the greater demand will determine type). Will default to "PASSENGER" if no demand is detected.
    local rule = line_data_single.rule -- the line rule
    local rule_manual = line_data_single.rule_manual -- whether the line rule was assigned manually (rather than automatically)
    local rate = line_data_single.rate -- *average* line rate
    local frequency = line_data_single.frequency -- *average* line frequency in seconds
    local parameters = line_data_single.parameters -- the parameters for the line (this is indexed as per the rules)
    local vehicles = line_data_single.vehicles -- number of vehicles currently on the line
    local capacity = line_data_single.capacity -- total current capacity of the vehicles on the line
    local occupancy = line_data_single.occupancy -- total current occupancy on the vehicles on the line
    local occupancy_peak = line_data_single.occupancy_peak -- current peak amount of passengers on any vehicle on the line
    local demand = line_data_single.demand -- *average* line demand i.e. total number of PASSENGER or CARGO intending to use the line, including already on the line
    local usage = line_data_single.usage -- *average* line usage i.e. occupancy/capacity
    local samples = line_data_single.samples -- number of samples collected for the line since last action taken (this is reset after each action)
    local last_action = line_data_single.last_action -- the last action taken to manage the line; "ADD", "REMOVE" or "MANUAL" if a vehicle was manually added or removed ("" if no previous action exists)
    local waiting = line_data_single.waiting -- *average* total number of items waiting at stations for this line
    local waiting_peak = line_data_single.waiting_peak -- *average* the highest number of items waiting at a station for this line
    local waiting_peak_clamped = line_data_single.waiting_peak_clamped -- *average* the highest number of items waiting at a station for this line, but clamped to 0.5 - 1.5 times the capacity_per_vehicle
    local transported_last_month = line_data_single.transported_last_month -- the amount of items transported last month NOTE: this will only be useful if 1x GameTime is used (otherwise 0, it seems)
    local transported_last_year = line_data_single.transported_last_year -- the amount of items transported last year NOTE: this will only be useful if 1x GameTime is used (otherwise 0, it seems)
    local capacity_per_vehicle = line_data_single.capacity_per_vehicle -- the average capacity per vehicle on the line
    local stops = line_data_single.stops -- total number of stops for the line
    local stops_with_waiting = line_data_single.stops_with_waiting -- *average* number of stops that has waiting entities for this line

    local line_rules = {}

    -- Ensure there's always 1 vehicle retained per line.
    if vehicles <= 1 then
        return false
    end

    if rule == "P" then
        -- Make use of default PASSENGER rules
        local level = parameters[1].value
        local inverse_modifier = math.max(1.5, 1.25 * vehicles / (vehicles - 1))

        -- USAGE SCORE
        local usageBaseline = {
            ROAD = 50,
            TRAM = 50,
            WATER = 50,
            RAIL = 60,
            AIR = 70,
        }

        -- This will yield a value between 0.0 and 1.2
        local usageScore = lume.clamp(usage / lume.clamp(100 * stops_with_waiting / stops, usageBaseline[carrier], 85), 0, 1.2)

        -- WAITING SCORE
        -- This will yield a value between 0 and 1.5 (0 and 1.5 are the waiting_peak_clamped min/max values relative to capacity_per_vehicle)
        local waitingScore = waiting_peak_clamped / capacity_per_vehicle

        -- FINAL SCORE
        local usageWeight = 100
        local waitingWeight = 100

        if level == 1 then
            usageWeight = 80
            waitingWeight = 120
        end

        -- Usage equal to the expected and waiting equal to capacity_per_vehicle will yield 100 for each
        local finalScore = usageScore * usageWeight + waitingScore * waitingWeight

        -- REQUIRED SCORE
        -- Usage    10  20  30 40 50 60 70 80 90 100 110
        -- Waiting  110 100 90 80 70 60 50 40 30 20  10
        local requiredScore = 120

        -- REQUIRED SAMPLES
        local requiredSamples = 5
        if carrier == "AIR" or carrier == "RAIL" or carrier == "WATER" then
            requiredSamples = requiredSamples + 3
        end
        if last_action == "ADD" then
            requiredSamples = requiredSamples + 3
        end

        line_rules = { samples > requiredSamples and frequency * inverse_modifier < 720 and finalScore < requiredScore, samples > 3 * requiredSamples and frequency * inverse_modifier < 720 and waiting_peak * inverse_modifier < capacity_per_vehicle }
    elseif rule == "C" then
        -- Make use of default CARGO rules
        local level = parameters[1].value
        local inverse_modifier = math.max(1.5, 1.25 * vehicles / (vehicles - 1))

        -- USAGE SCORE
        local usageBaseline = {
            ROAD = 50,
            TRAM = 50,
            WATER = 50,
            RAIL = 60,
            AIR = 70,
        }

        -- This will yield a value between 0.0 and 1.2
        local usageScore = lume.clamp(usage / lume.clamp(100 * stops_with_waiting / stops, usageBaseline[carrier], 85), 0, 1.2)

        -- WAITING SCORE
        -- This will yield a value between 0 and 1.5 (0 and 1.5 are the waiting_peak_clamped min/max values relative to capacity_per_vehicle)
        local waitingScore = waiting_peak_clamped / capacity_per_vehicle

        -- FINAL SCORE
        local usageWeight = 100
        local waitingWeight = 100

        if level == 1 then
            usageWeight = 80
            waitingWeight = 120
        end

        -- Usage equal to the expected and waiting equal to capacity_per_vehicle will yield 100 for each
        local finalScore = usageScore * usageWeight + waitingScore * waitingWeight

        -- REQUIRED SCORE
        -- Usage    10  20  30 40 50 60 70 80 90 100 110
        -- Waiting  110 100 90 80 70 60 50 40 30 20  10
        local requiredScore = 120

        -- REQUIRED SAMPLES
        local requiredSamples = 5
        if carrier == "AIR" or carrier == "RAIL" or carrier == "WATER" then
            requiredSamples = requiredSamples + 3
        end
        if last_action == "ADD" then
            requiredSamples = requiredSamples + 3
        end

        line_rules = { samples > requiredSamples and frequency * inverse_modifier < 720 and finalScore < requiredScore, samples > 3 * requiredSamples and frequency * inverse_modifier < 720 and waiting_peak * inverse_modifier < capacity_per_vehicle }
    elseif rule == "PR" then
        -- Make use of PASSENGER rules by RusteyBucket
        local newVehicles = vehicles - 1
        local vehicleFactor = newVehicles / vehicles
        local newRate = rate * vehicleFactor
        local newUsage = usage * vehicles / newVehicles
        local averageCapacity = capacity / vehicles
        local d10 = demand * 1.1
        local oneVehicle = 1 / vehicles -- how much would one vehicle change
        local plusOneVehicle = 1 + oneVehicle -- add the rest of the vehicles
        local dv = demand * plusOneVehicle -- exaggerate demand by what one more vehicle could change
        local waitFactor = waiting_peak / capacity_per_vehicle -- no overcrowding

        line_rules = {
            samples > 5
                    and usage < 40
                    and d10 < newRate
                    and dv < newRate
                    and newUsage < 80
                    and newRate > averageCapacity
                    and waitFactor < 0.5
        }
    elseif rule == "R" then
        -- Make use of RATE rules
        local modifier = math.min(0.75, 0.9 * (vehicles - 1) / vehicles)
        local rate_target = parameters[1].value
        local waiting_peak_target = parameters[2].value or nil

        -- Adjust required samples
        local requiredSamples = 5
        if carrier == "AIR" or carrier == "RAIL" or carrier == "WATER" then
            requiredSamples = requiredSamples + 3
        end
        if last_action == "REMOVE" then
            requiredSamples = requiredSamples + 3
        end

        -- Prepare appropriate rules
        if waiting_peak_target then
            line_rules[#line_rules + 1] = samples > requiredSamples and rate * modifier > rate_target and waiting_peak / capacity_per_vehicle < modifier * waiting_peak_target / 100
        else
            line_rules[#line_rules + 1] = samples > requiredSamples and rate * modifier > rate_target
        end

    elseif rule == "F" then
        -- Make use of FREQUENCY rules
        local modifier = math.min(0.75, 0.9 * (vehicles - 1) / vehicles)
        local freq_target = parameters[1].value
        local waiting_peak_target = parameters[2].value or nil

        -- Adjust required samples
        local requiredSamples = 5
        if carrier == "AIR" or carrier == "RAIL" or carrier == "WATER" then
            requiredSamples = requiredSamples + 3
        end
        if last_action == "REMOVE" then
            requiredSamples = requiredSamples + 3
        end

        -- Prepare appropriate rules
        if waiting_peak_target then
            line_rules[#line_rules + 1] = samples > requiredSamples and frequency * modifier < freq_target and waiting_peak / capacity_per_vehicle < modifier * waiting_peak_target / 100
        else
            line_rules[#line_rules + 1] = samples > requiredSamples and frequency * modifier < freq_target
        end
    end

    -- Check whether at least one condition is fulfilled
    for i = 1, #line_rules do
        if line_rules[i] then
            return true
        end
    end

    -- If we made it here, then the conditions to remove a vehicle were not met
    return false
end

return rules
