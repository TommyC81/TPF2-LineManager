local api_helper = {}

local enums = require 'cartok/enums'

---@param entity_id number | string : the id of the entity
---@return string : entityName
function api_helper.getEntityName(entity_id)
    local err, res = pcall(function()
        return api.engine.getComponent(entity_id, api.type.ComponentType.NAME)
    end)
    if err and res and res.name then
        return res.name
    else
        return "ERROR"
    end
end

---@return table : all lines for the Player
function api_helper.getPlayerLines()
    return api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
end

---@return table : details of the vehicle
function api_helper.getVehicle(vehicle_id)
    return api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
end

---@param line_id table id of the line
---@return string carrier The carrier of the line i.e. "ROAD", "TRAM", "RAIL", "WATER" or "AIR".
---returns the line TransportMode given the provided line_info.
function api_helper.getCarrierFromLine(line_id)
    local carrier = ""
    local vehicles = api_helper.getLineVehicles(line_id)

    if vehicles and vehicles[1] then
        local component = api_helper.getVehicle(vehicles[1])
        if component and component.carrier then
            carrier = enums.Carrier[component.carrier]
        end
    end

    return carrier
end

---@param vehicle_id table id of the vehicle
---@return string carrier the carrier of the line i.e. "ROAD", "TRAM", "RAIL", "WATER" or "AIR"
---returns the line TransportMode given the provided line_info.
function api_helper.getCarrierFromVehicle(vehicle_id)
    local carrier = ""

    if vehicle_id then
        local component = api_helper.getVehicle(vehicle_id)
        if component and component.carrier then
            carrier = enums.Carrier[component.carrier]
        end
    end

    return carrier
end

---@return table : vehicle indexed cargo map
function api_helper.getVehicle2Cargo2SimEntitesMap()
    return api.engine.system.simEntityAtVehicleSystem.getVehicle2Cargo2SimEntitesMap()
end

---@return table : line indexed vehicle map
function api_helper.getLine2VehicleMap()
    return api.engine.system.transportVehicleSystem.getLine2VehicleMap()
end

---@return number : gameMonth
function api_helper.getGameMonth()
    return game.interface.getGameTime().date.month
end

---@return number : current GameTime (milliseconds)
function api_helper.getGameTime()
    local time = api.engine.getComponent(0, api.type.ComponentType.GAME_TIME).gameTime
    if time then
        return time
    else
        return 0
    end
end

---@param line_id number : the id of the line
---@return number : line rate (or 0 if not found)
---@return number : line frequency (or 0 if not found)
function api_helper.getLineRateAndFrequency(line_id)
    local lineEntity = game.interface.getEntity(line_id)
    if lineEntity and lineEntity.rate then
        return lineEntity.rate, lineEntity.frequency
    else
        return 0, 0
    end
end

---@param line_id number : the id of the line
---@return table : the id's of the vehicles on the line
---returns the id's of vehicles assigned to a line
function api_helper.getLineVehicles(line_id)
    return api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
end

---@param vehicle_id number : the id of the vehicle
---@param sell_on_arrival boolean : sell the vehicle when it arrives in the depot, defaults to false
---sends a vehicle to the closest depot
function api_helper.sendVehicleToDepot(vehicle_id, sell_on_arrival)
    sell_on_arrival = sell_on_arrival or false

    api.cmd.sendCommand(api.cmd.make.sendToDepot(vehicle_id, sell_on_arrival))
end

---@param vehicle_id number : the id of the vehicle
---sells a vehicle
function api_helper.sellVehicle(vehicle_id)
    api.cmd.sendCommand(api.cmd.make.sellVehicle(vehicle_id))
end

---@param depot_id number : the id of the depot
---@param transportVehicleConfig table : the configuration of the vehicle
---@param callback function : the callback to be used for the function, uses parameters 'cmd' and 'res'
---buys a vehicle
function api_helper.buyVehicle(depot_id, transportVehicleConfig, callback)
    local buyCommand = api.cmd.make.buyVehicle(api.engine.util.getPlayer(), depot_id, transportVehicleConfig)
    api.cmd.sendCommand(buyCommand, callback)
end

---@param vehicle_id number : the id of the vehicle
---@param line_id number : the id of the line
---@param stop_id number : the id of the stop
---sends a vehicle to specified line, starting at a specified stop
function api_helper.sendVehicleToLine(vehicle_id, line_id, stop_id)
    api.cmd.sendCommand(api.cmd.make.setLine(vehicle_id, line_id, stop_id))
end

---@param line_id number : the id of the line
---@return table : the id's of the PASSENGER scheduled to use the line
---returns the id's of PASSENGER that are scheduled to use a line
function api_helper.getSimPersonsForLine(line_id)
    return api.engine.system.simPersonSystem.getSimPersonsForLine(line_id)
end

---@param line_id number : the id of the line
---@return table : the id's of the CARGO scheduled to use the line
---returns the id's of CARGO that are scheduled to use a line
function api_helper.getSimCargosForLine(line_id)
    return api.engine.system.simCargoSystem.getSimCargosForLine(line_id)
end

---sends a script command for "LineManager"
function api_helper.sendScriptCommand(id, name, param)
    api.cmd.sendCommand(api.cmd.make.sendScriptEvent("LineManager", id, name, param))
end

---@return table : the id's of the problem lines
---returns all lines with problem
function api_helper.getProblemLines()
    return api.engine.system.lineSystem.getProblemLines(api.engine.util.getPlayer())
end

---@return table : the id's of the vehicles with no path
---returns all vehicles that has no path
function api_helper.getNoPathVehicles()
    return api.engine.system.transportVehicleSystem.getNoPathVehicles()
end

---@return table : the id's of the trains with no path
---returns the id's of all trains that has no path
function api_helper.getNoPathTrains()
    return api.engine.system.transportVehicleSystem.getNoPathVehicles(api.type.enum.Carrier.RAIL)
end

---@param vehicle_id number : the id of the vehicle
function api_helper.reverseVehicle(vehicle_id)
    api.cmd.sendCommand(api.cmd.make.reverseVehicle(vehicle_id))
end

---@param vehicle table | number : either a vehicle object or vehicle_id
---returns whether a vehicle object is IN_DEPOT
function api_helper.isVehicleInDepot(vehicle)
    -- If a number was provided, then retrieve the vehicle first
    if type(vehicle) == "number" then
        vehicle = api_helper.getVehicle(vehicle)
    end

    -- Check whether state corresponds to IN_DEPOT
    if vehicle and vehicle.state and vehicle.state == api.type.enum.TransportVehicleState.IN_DEPOT then
        return true
    else
        return false
    end
end

---@param vehicle table | number : either a vehicle object or vehicle_id
---returns whether a vehicle object is GOING_TO_DEPOT
function api_helper.isVehicleIsGoingToDepot(vehicle)
    -- If a number was provided, then retrieve the vehicle first
    if type(vehicle) == "number" then
        vehicle = api_helper.getVehicle(vehicle)
    end

    -- Check whether state corresponds to GOING_TO_DEPOT
    if vehicle and vehicle.state and vehicle.state == api.type.enum.TransportVehicleState.GOING_TO_DEPOT then
        return true
    else
        return false
    end
end

---@param vehicle table | number : either a vehicle object or vehicle_id
---returns whether a vehicle object is EN_ROUTE
function api_helper.isVehicleEnRoute(vehicle)
    -- If a number was provided, then retrieve the vehicle first
    if type(vehicle) == "number" then
        vehicle = api_helper.getVehicle(vehicle)
    end

    -- Check whether state corresponds to EN_ROUTE
    if vehicle and vehicle.state and vehicle.state == api.type.enum.TransportVehicleState.EN_ROUTE then
        return true
    else
        return false
    end
end

---@param vehicle table | number : either a vehicle object or vehicle_id
---returns whether a vehicle object is AT_TERMINAL
function api_helper.isVehicleAtTerminal(vehicle)
    -- If a number was provided, then retrieve the vehicle first
    if type(vehicle) == "number" then
        vehicle = api_helper.getVehicle(vehicle)
    end

    -- Check whether state corresponds to AT_TERMINAL
    if vehicle and vehicle.state and vehicle.state == api.type.enum.TransportVehicleState.AT_TERMINAL then
        return true
    else
        return false
    end
end

return api_helper
