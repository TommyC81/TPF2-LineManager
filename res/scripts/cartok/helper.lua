---@author CARTOK
---@author RusteyBucket
-- Contains code and inspiration from 'TPF2-Timetables' created by Celmi, available here: https://steamcommunity.com/workshop/filedetails/?id=2408373260 and source https://github.com/IncredibleHannes/TPF2-Timetables
-- General Transport Fever 2 API documentation can be found here: https://transportfever2.com/wiki/api/index.html

local helper = {}

local api_helper = require 'cartok/api_helper'
local enums = require 'cartok/enums'

-------------------------------------------------------------
--------------------- GENERAL HELPER ------------------------
-------------------------------------------------------------

---@param var number | string : the variable that ought to be a number
---@return number : var as a number or -1
---checks and if necessary converts a string to a number
function helper.numberify(var)
    if type(var) == "string" then
        var = tonumber(var)
    end
    if type(var) == "number" then
        return var
    else
        print("Expected String or Number")
        return -1
    end
end

---@param dividend number : absolute number
---@param divisor number : absolute maximum
---@return number : relative ratio as percentage
function helper.roundPercentage(dividend, divisor)
    if (dividend > 0 and divisor > 0) then
        local factor = dividend / divisor
        local percentage = 100 * factor
        return math.round(percentage)
    else
        return 0
    end
end

-------------------------------------------------------------
--------------------- GAME STUFF ----------------------------
-------------------------------------------------------------

-- TODO: Get more rule options to be switchable as presets
---@param line_data userdata : the line_data (from helper.getLineData)
---@param line_id number : the id of the line
---@return boolean : whether a vehicle should be added to the line
function helper.moreVehicleConditions(line_data, line_id)
    -- Factors used in rules
    local carrier = line_data[line_id].carrier
    local usage = line_data[line_id].usage
    local demand = line_data[line_id].demand
    local rate = line_data[line_id].rate
    local rate_target = line_data[line_id].rate_target or 0
    local capacity = line_data[line_id].capacity
    local vehicles = line_data[line_id].vehicles
    local rule = line_data[line_id].rule
    local rules = {}

    if rule == "P" then
        -- make use of default PASSENGER rules
        rules = {
            usage > 50 and demand > rate * 2,
            usage > 80 and demand > rate * (vehicles + 1) / vehicles,
        }
    elseif rule == "PR" then
        -- make use of PASSENGER rules by RusteyBucket
        local d10 = demand * 1.1
        local oneVehicle = 1 / vehicles -- how much would one vehicle change
        local plusOneVehicle = 1 + oneVehicle -- add the rest of the vehicles
        local dv = demand * plusOneVehicle -- exaggerate demand by what one more vehicle could change
        local averageCapacity = capacity / vehicles

        rules = {
            rate < d10, -- get a safety margin of 10% over the real demand
            rate < dv, -- with low vehicle numbers, those 10% might not do the trick
            usage > 90,
            rate < averageCapacity --limits frequency to at most 12min
        }
    elseif rule == "C" then
        -- make use of default CARGO rules
        rules = {
            -- Usage filtering prevents racing in number of vehicles in some (not all) instances when there is blockage on the line.
            -- The filtering based on usage does however delay the increase of vehicles when a route is starting up until it has stabilized.
            -- For instance, this won't prevent the addition of more vehicles when existing and fully loaded vehicles are simply stuck in traffic.
            usage > 40 and (demand > capacity or demand > rate),
            demand > 2 * capacity or demand > 2 * rate,
        }
    elseif rule == "R" then
        -- make use of RATE rules
        rules = {
            rate < rate_target,
        }
    end

    -- figuring out whether at least one condition is fulfilled
    for i = 1, #rules do
        if rules[i] then
            return true
        end
    end

    -- If we made it here, then the conditions to add a vehicle were not met
    return false
end

---@param line_data userdata : the line_data (from helper.getLineData)
---@param line_id number : the id of the line
---@return boolean : whether a vehicle should be removed from the line
function helper.lessVehiclesConditions(line_data, line_id)
    -- Factors used in rules
    local carrier = line_data[line_id].carrier
    local usage = line_data[line_id].usage
    local demand = line_data[line_id].demand
    local rate = line_data[line_id].rate
    local rate_target = line_data[line_id].rate_target or 0
    local capacity = line_data[line_id].capacity
    local vehicles = line_data[line_id].vehicles
    local rule = line_data[line_id].rule
    local rules = {}

    -- Ensure there's always 1 vehicle retained per line.
    if vehicles <= 1 then
        return false
    end

    if rule == "P" then
        -- make use of default PASSENGER rules
        local modifier = (vehicles - 1) / vehicles
        local inverse_modifier = vehicles / (vehicles - 1)

        rules = {
            usage < 70 and demand < rate * modifier and usage * inverse_modifier < 100,
        }
    elseif rule == "P" then
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
        rules = {
            --            vehicles > 1 and usage < 40 and d10 < newRate and size > newRate,
                vehicles > 1
                    and usage < 40
                    and d10 < newRate
                    and dv < newRate
                    and newUsage < 80
                    and newRate > averageCapacity
        }
    elseif rule == "C" then
        -- make use of default CARGO rules
        local modifier = (vehicles - 1) / vehicles

        rules = {
            usage < 20,
            usage < 40 and demand < capacity * modifier and demand < rate * modifier,
        }
    elseif rule == "R" then
        -- make use of RATE rules
        -- Only process this if a rate_target has actually been set properly.
        -- Errors in formatting the rate in the line name can lead to weird results otherwise as rate_target is set to 0 in case of formatting error.
        -- TODO: Should output a warning in case of formatting error.
        if (rate_target > 0) then
            local modifier = (vehicles - 1) / vehicles

            rules = {
                rate * modifier > rate_target,
            }
        end
    end

    -- Check whether at least one condition is fulfilled
    for i = 1, #rules do
        if rules[i] then
            return true
        end
    end

    -- If we made it here, then the conditions to remove a vehicle were not met
    return false
end

---@param vehicle_id_table table array of VEHICLE ids
---@return number id of the oldest vehicle on the line
---Finds the oldest vehicle among the provided vehicle id.
function helper.getOldestVehicleId(vehicle_id_table)
    local oldestVehicleId = nil
    local oldestVehiclePurchaseTime = 999999999999

    for _, vehicle_id in pairs(vehicle_id_table) do
        local vehicle = api_helper.getVehicle(vehicle_id)
        if vehicle and vehicle.transportVehicleConfig.vehicles[1].purchaseTime < oldestVehiclePurchaseTime then
            oldestVehiclePurchaseTime = vehicle.transportVehicleConfig.vehicles[1].purchaseTime
            oldestVehicleId = vehicle_id
        end
    end

    return oldestVehicleId
end

---@param vehicle_id_table table array of VEHICLE ids
---@return number id of the emptiest vehicle on the line
---Finds the emptiest vehicle among the provided vehicle id.
function helper.getEmptiestVehicleId(vehicle_id_table)
    local emptiestVehicleId = nil
    local emptiestVehicleOccupancy = 999999999999
    local vehicle2cargoMap = api_helper.getVehicle2Cargo2SimEntitesMap()

    for _, vehicle_id in pairs(vehicle_id_table) do
        if vehicle2cargoMap[vehicle_id] then
            local vehicleOccupancy = helper.reduceOccupancyTable(vehicle2cargoMap[vehicle_id])
            if vehicleOccupancy < emptiestVehicleOccupancy then
                emptiestVehicleOccupancy = vehicleOccupancy
                emptiestVehicleId = vehicle_id
            end
        end
    end

    return emptiestVehicleId
end

-------------------------------------------------------------
--------------------- PRINT STUFF ---------------------------
-------------------------------------------------------------

---Converts array to string and optionally inserts a line break whenever the first word in the array changes
---@param array table : the array to be strung up
---@param prefixSplit string : (optional) the divider between prefix and individual name, default " " (blank space)
---@param insertLineBreak boolean : (optional) whether to insert line breaks or not, default true
---@return string : array + some line breaks if applicable
function helper.printArrayWithBreaks(array, prefixSplit, insertLineBreak)
    prefixSplit = prefixSplit or " "
    insertLineBreak = insertLineBreak or true

    local output = ""
    local previousPrefix = ""

    -- space the lines by prefix
    for i = 1, #array do
        local currentItem = tostring(array[i])
        if (insertLineBreak) then
            local prefixEnd = string.find(currentItem, prefixSplit)
            local currentPrefix = string.sub(currentItem, 1, prefixEnd)
            if previousPrefix == currentPrefix then
                output = output .. currentItem .. ", "
            else
                previousPrefix = currentPrefix
                output = output .. "\n" .. currentItem .. ", "
            end
        else
            output = output .. currentItem .. ", "
        end
    end

    return output
end

return helper
