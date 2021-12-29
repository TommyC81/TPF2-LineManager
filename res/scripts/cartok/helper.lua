-- Contains code from https://github.com/IncredibleHannes/TPF2-Timetables
---@author CARTOK wrote the bulk of the code while
---@author RusteyBucket rearranged the code to improve readability and expandability

local enums = require 'cartok/enums'

local helper = {}

--TODO: Get more rule options to be switchable as presets
---@param data userdata : the LineData (from helper.getLineData)
---@param id number : the id of the line
---@return boolean : whether a vehicle should be added to the line
function helper.moreVehicleConditions(data, id)
    -- a bunch of factors
    local usage = data[id].usage
    local demand = data[id].demand
    local rate = data[id].rate
    local vehicles = data[id].vehicles

    -- an array with conditions that warrant more vehicles
    local rules = {
        usage > 50 and demand > rate * 2,
        usage > 80 and demand > rate * (vehicles + 1) / vehicles,
    }

    -- figuring out whether at least one condition is fulfilled
    local res = false
    for i = 1, #rules do
        if rules[i] then
            res = true
        end
    end
    return res
end

---@param data userdata : the LineData (from helper.getLineData)
---@param id number : the id of the line
---@return boolean : whether a vehicle should be removed from the line
function helper.lessVehiclesConditions(data, id)
    -- a bunch of factors
    local usage = data[id].usage
    local demand = data[id].demand
    local rate = data[id].rate
    local vehicles = data[id].vehicles

    -- an array with conditions that warrant less vehicles
    local rules = {
        vehicles > 1 and usage < 70 and demand < rate * (vehicles - 1) / vehicles,
    }

    -- figuring out whether at least one condition is fulfilled
    local res = false
    for i = 1, #rules do
        if rules[i] then
            res = true
        end
    end
    return res
end

---@param line_id number : the id of the line
---@return boolean : whether the line type is supported by the mod
function helper.supportedLine(line_id)
    -- get the line info
    local line = api.engine.getComponent(line_id, api.type.ComponentType.LINE)
    local info = line.vehicleInfo.transportModes

    -- check whether the required parameters exists
    if not line and line.vehicleInfo and line.vehicleInfo.transportModes then
        return false
    end

    local transportModes = {
        info[enums.TransportModes.BUS],
        info[enums.TransportModes.TRAM],
        info[enums.TransportModes.ELECTRIC_TRAM],
        info[enums.TransportModes.AIRCRAFT],
        info[enums.TransportModes.SHIP],
        info[enums.TransportModes.SMALL_AIRCRAFT],
        info[enums.TransportModes.SMALL_SHIP],
    }

    local res = false
    for i = 1, #transportModes do
        if transportModes[i] == 1 then
            res = true
        end
    end
    return res
end

---@param data userdata : the LineData (from helper.getLineData)
---@param line_id number : the id of the line
---@return string
---returns usage data string
function helper.printLineData(data, line_id)
    local use = "Usage: " .. data[line_id].usage .. "% "
    use = use .. "Demand: " .. data[line_id].demand .. " "
    use = use .. "Rate: " .. data[line_id].rate .. " "
    use = use .. "Vehicles: " .. data[line_id].vehicles
    return use
end

---@param line_id number | string : the id of the line
---@return number : lineRate
function helper.getLineRate(line_id)
    if type(line_id) == "string" then
        line_id = tonumber(line_id)
    end
    if not (type(line_id) == "number") then
        return 0
    end

    local lineEntity = game.interface.getEntity(line_id)
    if lineEntity and lineEntity.rate then
        return lineEntity.rate
    else
        return 0
    end
end

---@param vehicle_id number | string : the id of the vehicle
---@return boolean : transportsPassengers
function helper.vehicleTransportsPassengers(vehicle_id)
    if type(vehicle_id) == "string" then
        vehicle_id = tonumber(vehicle_id)
    end
    if not (type(vehicle_id) == "number") then
        return false
    end

    local vehicleInfo = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
    if vehicleInfo and vehicleInfo.config and vehicleInfo.config.capacities[1] and vehicleInfo.config.capacities[1] > 0 then
        return true
    else
        return false
    end
end

---@return number : gameMonth
function helper.getGameMonth()
    return game.interface.getGameTime().date.month
end

---@param entity_id number | string : the id of the entity
---@return string : entityName
function helper.getEntityName(entity_id)
    if type(entity_id) == "string" then
        entity_id = tonumber(entity_id)
    end
    if not (type(entity_id) == "number") then
        return "ERROR"
    end

    local err, res = pcall(function()
        return api.engine.getComponent(entity_id, api.type.ComponentType.NAME)
    end)
    if err and res and res.name then
        return res.name
    else
        return "ERROR"
    end
end

---@return number : current GameTime (milliseconds)
function helper.getGameTime()
    local time = api.engine.getComponent(0, api.type.ComponentType.GAME_TIME).gameTime
    if time then
        return time
    else
        return 0
    end
end

---@param line_id  number | string : the id of the line
---@param lineType string : eg "RAIL", "ROAD", "TRAM", "WATER", "AIR"
---@return boolean : whether the line of the provided lineType
function helper.lineHasType(line_id, lineType)
    if type(line_id) == "string" then
        line_id = tonumber(line_id)
    end
    if not (type(line_id) == "number") then
        print("Expected String or Number")
        return -1
    end

    local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
    if vehicles and vehicles[1] then
        local component = api.engine.getComponent(vehicles[1], api.type.ComponentType.TRANSPORT_VEHICLE)
        if component and component.carrier then
            return component.carrier == api.type.enum.Carrier[lineType]
        end
    end
    return false
end

---@return table : all lines for the Player
function helper.getPlayerLines()
    return api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
end

---@return table : containing line_id, vehicles, capacity, occupancy, usage, demand and rate
---@return table : id of ignored lines
function helper.getLineData()
    local lines = helper.getPlayerLines()
    local lineData = {}
    local ignoredLines = {}

    for _, line_id in pairs(lines) do
        local ignoredLine = true

        -- Check type of line first
        if helper.supportedLine(line_id) then
            local lineVehicleCount = 0
            local lineCapacity = 0
            local lineOccupancy = 0
            local lineTravellerCount = 0

            local lineTravellers = api.engine.system.simPersonSystem.getSimPersonsForLine(line_id)
            for _, traveller_id in pairs(lineTravellers) do
                lineTravellerCount = lineTravellerCount + 1
            end

            if lineTravellerCount > 0 then
                ignoredLine = false -- This line is supported and has passengers, and is thus not ignored

                local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
                for _, vehicle_id in pairs(lineVehicles) do
                    local vehicle = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
                    if vehicle and vehicle.config and vehicle.config.capacities[1] and vehicle.config.capacities[1] > 0 then
                        lineVehicleCount = lineVehicleCount + 1
                        lineCapacity = lineCapacity + vehicle.config.capacities[1]
                    end

                    for _, traveller_id in pairs(lineTravellers) do
                        local traveller = api.engine.getComponent(traveller_id, api.type.ComponentType.SIM_PERSON_AT_VEHICLE)
                        if traveller and traveller.vehicle and traveller.vehicle == vehicle_id then
                            lineOccupancy = lineOccupancy + 1
                        end
                    end
                end

                lineData[line_id] = {
                    vehicles = lineVehicleCount,
                    capacity = lineCapacity,
                    occupancy = lineOccupancy,
                    demand = lineTravellerCount,
                    usage = math.round(100 * lineOccupancy / lineCapacity),
                    rate = helper.getLineRate(line_id),
                    name = helper.getEntityName(line_id),
                }
            end
        end

        if ignoredLine then
            table.insert(ignoredLines, line_id)
        end
    end

    return lineData, ignoredLines
end

---strings together line name and line id depending on the provided settings
---@param line_id number : the id of the line
---@param printLineNumber boolean : (optional) whether to print the line number, default true
---@param printLineName boolean : (optional) whether to print the line name, default true
---@return string : the line name in desired form
function helper.printLine(line_id, printLineNumber, printLineName)
    printLineNumber = printLineNumber or true
    printLineName = printLineName or true

    local output = ""
    local name = helper.getEntityName(line_id)

    if (printLineNumber and printLineName) then
        output = name .. " (" .. line_id .. ")"
    elseif (printLineName) then
        output = name
    elseif (printLineNumber) then
        output = line_id
    end

    return output
end

---Converts array to string and optionally inserts a line break whenever the first word in the array changes
---@param array table : the array to be strung up
---@param prefixSplit string : (optional) the divider between prefix and individual name, default " "
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
