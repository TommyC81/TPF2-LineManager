local rules = {}

rules.line_rules = {
    M = { -- Manual management
        name = "MANUAL",
        description = "Manual line management - no automatic line management features will be used for this line.",
        identifier = "(M)",
        uses_target = false,
    },
    P = { -- PASSENGER
        name = "PASSENGER",
        description = "A balanced set of default rules for PASSENGER line management.",
        identifier = "(P)",
        uses_target = false,
    },
    PR = { -- PASSENGER (RUSTEYBUCKET)
        name = "PASSENGER (RusteyBucket)",
        description = "PASSENGER line management rules by RusteyBucket.",
        identifier = "(PR)",
        uses_target = false,
    },
    C = { -- CARGO
        name = "CARGO",
        description = "A balanced set of default rules for CARGO line management.",
        identifier = "(C)",
        uses_target = false,
    },
    R = { -- RATE
        name = "RATE",
        description = "Ensures that a set rate is achieved. This is configured by adding the target rate behind the colon, like so: '(R:100)'.",
        -- This is an example of how a target can be used, make sure to set the identifier with only first part up to where the number is to start.
        -- Leave out the end parentis, it will be searched for automatically, and the number between the identifier and the end parentis will be used.
        -- If a line is incorrectly formatted by the user (i.e. can't interpret a number), then a warning will be shown in the game console.
        identifier = "(R:",
        uses_target = true,
    },
}

rules.defaultPassengerLineRule = "P"
rules.defaultCargoLineRule = "C"

---@param line_data_single table : the line_data for a single line
---@return boolean : whether a vehicle should be added to the line
function rules.moreVehicleConditions(line_data_single)
    -- Factors that can be used in rules
    local carrier = line_data_single.carrier -- "ROAD", "TRAM", "RAIL", "WATER" or "AIR"
    local type = line_data_single.type -- "PASSENGER" or "CARGO"
    local rule = line_data_single.rule -- the line rule
    local rule_manual = line_data_single.rule_manual -- whether the line rule was assigned manually (rather than automatically)
    local rate = line_data_single.rate -- *averaged* line rate
    local frequency = line_data_single.frequency -- *averaged* line frequency in seconds
    local target = line_data_single.target -- target for whatever has been set
    local vehicles = line_data_single.vehicles -- number of vehicles currently on the line
    local capacity = line_data_single.capacity -- total capacity of the vehicles on the line
    local occupancy = line_data_single.occupancy -- total current occupancy on the vehicles on the line
    local demand = line_data_single.demand -- *averaged* line demand i.e. number of PASSENGER or CARGO intending to use the line
    local usage = line_data_single.usage -- *averaged* line usage i.e. occupancy/capacity
    local samples = line_data_single.samples -- number of samples collected for the line since last update
    local last_action = line_data_single.samples -- the last action taken to manage the line; "ADD" or "REMOVE" (or "" if no previous action exists)

    local line_rules = {}

    if rule == "P" then
        -- make use of default PASSENGER rules
        local modifier = (vehicles + 1) / vehicles

        if carrier == "RAIL" or carrier == "AIR" then
            line_rules = {
                samples > 10 and usage > 60 and demand > rate * 2,
                samples > 10 and usage > 80 and demand > rate * modifier,
            }
        else
            line_rules = {
                samples > 5 and usage > 50 and demand > rate * 2,
                samples > 5 and usage > 80 and demand > rate * modifier,
            }
        end
    elseif rule == "PR" then
        -- make use of PASSENGER rules by RusteyBucket
        local d10 = demand * 1.1
        local oneVehicle = 1 / vehicles -- how much would one vehicle change
        local plusOneVehicle = 1 + oneVehicle -- add the rest of the vehicles
        local dv = demand * plusOneVehicle -- exaggerate demand by what one more vehicle could change
        local averageCapacity = capacity / vehicles

        line_rules = {
            samples > 5 and rate < d10, -- get a safety margin of 10% over the real demand
            samples > 5 and rate < dv, -- with low vehicle numbers, those 10% might not do the trick
            samples > 5 and usage > 90,
            samples > 5 and frequency > 720 --limits frequency to at most 12min (720 seconds)
        }
    elseif rule == "C" then
        -- make use of default CARGO rules
        line_rules = {
            -- Usage filtering prevents racing in number of vehicles in some (not all) instances when there is blockage on the line.
            -- The filtering based on usage does however delay the increase of vehicles when a route is starting up until it has stabilized.
            -- For instance, this won't prevent the addition of more vehicles when existing and fully loaded vehicles are simply stuck in traffic.
            samples > 5 and usage > 40 and (demand > capacity or demand > rate),
            samples > 5 and demand > 2 * capacity or demand > 2 * rate,
        }
    elseif rule == "R" then
        -- make use of RATE rules
        line_rules = {
            samples > 5 and rate < target,
        }
    end

    -- figuring out whether at least one condition is fulfilled
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
    local carrier = line_data_single.carrier -- "ROAD", "TRAM", "RAIL", "WATER" or "AIR"
    local type = line_data_single.type -- "PASSENGER" or "CARGO"
    local rule = line_data_single.rule -- the line rule
    local rule_manual = line_data_single.rule_manual -- whether the line rule was assigned manually (rather than automatically)
    local rate = line_data_single.rate -- *averaged* line rate
    local frequency = line_data_single.frequency -- *averaged* line frequency in seconds
    local target = line_data_single.target -- target for whatever has been set
    local vehicles = line_data_single.vehicles -- number of vehicles currently on the line
    local capacity = line_data_single.capacity -- total capacity of the vehicles on the line
    local occupancy = line_data_single.occupancy -- total current occupancy on the vehicles on the line
    local demand = line_data_single.demand -- *averaged* line demand i.e. number of PASSENGER or CARGO intending to use the line
    local usage = line_data_single.usage -- *averaged* line usage i.e. occupancy/capacity
    local samples = line_data_single.samples -- number of samples collected for the line since last update
    local last_action = line_data_single.samples -- the last action taken to manage the line; "ADD" or "REMOVE" (or "" if no previous action exists)

    local line_rules = {}

    -- Ensure there's always 1 vehicle retained per line.
    if vehicles <= 1 then
        return false
    end

    if rule == "P" then
        -- make use of default PASSENGER rules
        local modifier = (vehicles - 1) / vehicles
        local inverse_modifier = vehicles / (vehicles - 1)

        line_rules = {
            samples > 5 and usage < 70 and demand < rate * modifier and usage * inverse_modifier < 100,
            samples > 10 and usage < 50 and demand < rate,
        }
    elseif rule == "PR" then
        -- make use of PASSENGER rules by RusteyBucket
        local newVehicles = vehicles - 1
        local vehicleFactor = newVehicles / vehicles
        local newRate = rate * vehicleFactor
        local newUsage = usage * vehicles / newVehicles
        local averageCapacity = capacity / vehicles
        local d10 = demand * 1.1
        local oneVehicle = 1 / vehicles -- how much would one vehicle change
        local plusOneVehicle = 1 + oneVehicle -- add the rest of the vehicles
        local dv = demand * plusOneVehicle -- exaggerate demand by what one more vehicle could change
        line_rules = {
            --            vehicles > 1 and usage < 40 and d10 < newRate and size > newRate,
            samples > 5
            and vehicles > 1
            and usage < 40
            and d10 < newRate
            and dv < newRate
            and newUsage < 80
            and newRate > averageCapacity
        }
    elseif rule == "C" then
        -- make use of default CARGO rules
        local modifier = (vehicles - 1) / vehicles

        line_rules = {
            samples > 5 and usage < 20,
            samples > 5 and usage < 40 and demand < capacity * modifier and demand < rate * modifier,
        }
    elseif rule == "R" then
        -- make use of RATE rules
        -- Only process this if a target has actually been set properly.
        -- Errors in formatting the rate in the line name can lead to weird results otherwise as target is set to 0 in case of formatting error.
        -- TODO: Should output a warning in case of formatting error.
        if (target > 0) then
            local modifier = (vehicles - 1) / vehicles

            line_rules = {
                samples > 5 and rate * modifier > target,
            }
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