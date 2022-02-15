---@author CARTOK
---@author RusteyBucket
-- Contains code and inspiration from 'TPF2-Timetables' created by Celmi, available here: https://steamcommunity.com/workshop/filedetails/?id=2408373260 and source https://github.com/IncredibleHannes/TPF2-Timetables
-- General Transport Fever 2 API documentation can be found here: https://transportfever2.com/wiki/api/index.html

local helper = {}

local api_helper = require 'cartok/api_helper'

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

-------------------------------------------------------------
--------------------- PRINT STUFF ---------------------------
-------------------------------------------------------------

---Converts array to string and optionally inserts a line break whenever the first word in the array changes
---@param array table : the array to be strung up
---@param prefixSplit string : (optional) the divider between prefix and individual name, default " " (blank space)
---@param insertLineBreak boolean : (optional) whether to insert line breaks or not, default true
---@return string : array + some line breaks if applicable
function helper.tableToStringWithLineBreaks(array, prefixSplit, insertLineBreak)
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
                output = output .. ", " .. currentItem
            else
                previousPrefix = currentPrefix
                output = output .. "\n" .. currentItem
            end
        else
            output = output .. currentItem .. ", "
        end
    end

    return output
end

return helper
