---@author CARTOK
---@author RusteyBucket
-- Contains code and inspiration from 'TPF2-Timetables' created by Celmi, available here: https://steamcommunity.com/workshop/filedetails/?id=2408373260 and source https://github.com/IncredibleHannes/TPF2-Timetables
-- General Transport Fever 2 API documentation can be found here: https://transportfever2.com/wiki/api/index.html

local helper = {}

local api_helper = require 'cartok/api_helper'
local lume = require 'cartok/lume'

local log = nil

function helper.setLog(input_log)
    log = input_log
end

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
        return lume.round(percentage)
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

---@param line_id number : id of the line
---@param vehicle_id number : id of the vehicle (optional)
---@return number depot_id : the id of the depot
---@return number stop_id : the id of the stop
---Finds a usable depot and stop for the vehicle.
function helper.findDepotAndStop(line_id, vehicle_id)
    log.debug("helper: findDepotAndStop(line_id: " .. tostring(line_id) .. " vehicle_id:" .. tostring(vehicle_id) .. ") starting")

    local depot_id = nil
    local stop_id = nil
    local vehicle = nil

    if not vehicle_id then
        local lineVehicles = api_helper.getLineVehicles(line_id)
        if #lineVehicles > 0 then
            vehicle_id = lineVehicles[1]
        end
    end

    if vehicle_id then
        vehicle = api_helper.getVehicle(vehicle_id)
    end

    if line_id and vehicle then
        -- Now send the vehicle to depot and then check if it succeeded
        api_helper.sendVehicleToDepot(vehicle_id)
        vehicle = api_helper.getVehicle(vehicle_id)
        if vehicle and api_helper.isVehicleIsGoingToDepot(vehicle) then
            depot_id = vehicle.depot
            stop_id = vehicle.stopIndex

            api_helper.sendVehicleToLine(vehicle_id, line_id, stop_id)
        end
    end

    log.debug("helper: findDepotAndStop(...) finished. depot_id=" .. tostring(depot_id) .. " stop_id=" .. tostring(stop_id))

    return depot_id, stop_id
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

function helper.lineInfoString(line_data, line_id)
    local rule = line_data[line_id].rule
    if line_data[line_id].parameters and #line_data[line_id].parameters > 0 then
        local first = true
        local text = ""
        rule = rule .. " ("
        for i = 1, #line_data[line_id].parameters do
            if line_data[line_id].parameters[i].value then
                text = line_data[line_id].parameters[i].value
            else
                text = "-"
            end
            if first then
                first = false
                rule = rule .. text
            else
                rule = rule .. " : " .. text
            end
        end
        rule = rule .. ")"
    end

    local managed = "AUTOMATIC"
    if line_data[line_id].rule_manual then
        managed = "MANUAL"
    end

    local str = line_data[line_id].type
    str = str .. " - " .. line_data[line_id].carrier
    str = str .. " - Rule: " .. rule
    str = str .. " - " .. managed
    str = str .. " (Samples: " .. line_data[line_id].samples .. ")"
    return str
end

function helper.lineDataString(line_data, line_id)
    local str = "Usage: " .. lume.round(line_data[line_id].usage) .. "%"
    str = str .. " Rate: " .. lume.round(line_data[line_id].rate)
    str = str .. " Frequency: " .. lume.round(line_data[line_id].frequency)
    str = str .. " WaitingPeak: " .. lume.round(line_data[line_id].waiting_peak)
    str = str .. " CapPerVeh: " .. line_data[line_id].capacity_per_vehicle
    str = str .. " Vehicles: " .. line_data[line_id].vehicles
    return str
end

function helper.printSoldVehicleInfo(line_data, line_id, vehicle_id)
    log.info(" -1 vehicle: " .. line_data[line_id].name)
    log.info("             " .. helper.lineInfoString(line_data, line_id))
    log.info("             " .. helper.lineDataString(line_data, line_id))
    log.debug("vehicle_id: " .. vehicle_id .. " line_id: " .. line_id)
end

function helper.printBoughtVehicleInfo(line_data, line_id, vehicle_id, depot_id)
    log.info(" +1 vehicle: " .. line_data[line_id].name)
    log.info("             " .. helper.lineInfoString(line_data, line_id))
    log.info("             " .. helper.lineDataString(line_data, line_id))
    log.debug("vehicle_id: " .. vehicle_id .. " line_id: " .. line_id .. " depot_id: " .. depot_id)
end

return helper
