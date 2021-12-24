-- Contains code from https://github.com/IncredibleHannes/TPF2-Timetables
---@author CARTOK wrote the bulk of the code while
---@author RusteyBucket rearranged it for readability with minor logic modifications where necessary for largely debug

local helper = {}

---@param data userdata : the sampledLineData
---@param id number : the internal line number
---@return boolean : whether there shall be a new vehicle added or not
function helper.moreVehicleConditions( data, id )
    -- a bunch of factors
	local usage    = data[id].usage
	local demand   = data[id].demand
	local rate     = data[id].rate
    local vehicles = data[id].vehicles

    -- an array with conditions that warrant more vehicles
	local rules    = {
		usage > 50 and demand > rate * 2,
		usage > 80 and demand > rate * (vehicles + 1) / vehicles
	}

    -- figuring out whether at least one condition is fulfilled
    local res      = false
    for i = 0, #rules do
        if rules[i] then
            res = true
        end
    end
    return res
end

---@param data userdata : the sampledLineData variable
---@param id number : the internal line number
---@return boolean : whether the line warrants less vehicles
function helper.lessVehiclesConditions( data, id )
    -- a bunch of factors
	local usage    = data[id].usage
	local demand   = data[id].demand
	local rate     = data[id].rate
    local vehicles = data[id].vehicles

    -- an array with conditions that warrant less vehicles
	local rules    = {
		vehicles > 1 and usage < 70 and demand < rate * (vehicles - 1) / vehicles
	}

    -- figuring out whether at least one condition is fulfilled
    local res      = false
    for i = 0, #rules do
        if rules[i] then
            res = true
        end
    end
    return res
end

---@param id number : general line info
---@return boolean : or error, thus unsafe
function helper.supportedRoute( id )
    local line = api.engine.getComponent( id, api.type.ComponentType.LINE )
    local info = line.vehicleInfo.transportModes

    -- check whether the parameters actually work
    if not line and line.vehicleInfo and line.vehicleInfo.transportModes then
        return false
    end
    -- 4 = ROAD, 6 = TRAM, 7 = ELECTRIC_TRAM, 10 = AIR, 13 = WATER
	local modes = {
		info[4],
		info[6],
		info[7],
		info[10],
		info[13]
	}

    local res = false
    for i = 0, #modes do
        if modes[i] == 1 then
            res = true
        end
    end
    return res
end

---@param data userdata
---@param id number
---@return string
---returns usage data string
function helper.lineDump( data, id )
    local use = "Usage: " .. data[id].usage .. "% "
    use       = use .. "(" .. data[id].occupancy .. "/" .. data[id].capacity .. ") "
    use       = use .. "Veh: " .. data[id].vehicles .. " "
    use       = use .. "Demand: " .. data[id].demand .. " "
    use       = use .. "Rate: " .. data[id].rate
    return use
end

---@param line_id number | string
---@return number : lineRate
function helper.getLineRate( line_id )
    if type( line_id ) == "string" then
        line_id = tonumber( line_id )
    end
    if not (type( line_id ) == "number") then
        return 0
    end

    local lineEntity = game.interface.getEntity( line_id )
    if lineEntity and lineEntity.rate then
        return lineEntity.rate
    else
        return 0
    end
end

---@param vehicle_id number | string
---@return boolean : transportsPassengers
function helper.vehicleTransportsPassengers( vehicle_id )
    if type( vehicle_id ) == "string" then
        vehicle_id = tonumber( vehicle_id )
    end
    if not (type( vehicle_id ) == "number") then
        return false
    end

    local vehicleInfo = api.engine.getComponent( vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE )
    if vehicleInfo and
       vehicleInfo.config and
       vehicleInfo.config.capacities[1] and
       vehicleInfo.config.capacities[1] > 0 then
        return true
    else
        return false
    end
end

---@return number : gameMonth
function helper.getGameMonth()
    return game.interface.getGameTime().date.month
end

---@param entity_id number | string
---@return string : entityName
function helper.getEntityName( entity_id )
    if type( entity_id ) == "string" then
        entity_id = tonumber( entity_id )
    end
    if not (type( entity_id ) == "number") then
        return "ERROR"
    end

    local err, res = pcall( function()
        return api.engine.getComponent( entity_id, api.type.ComponentType.NAME )
    end )
    if err and res and res.name then
        return res.name
    else
        return "ERROR"
    end
end

---@return number : current GameTime (milliseconds)
function helper.getGameTime()
    local time = api.engine.getComponent( 0, api.type.ComponentType.GAME_TIME ).gameTime
    if time then
        return time
    else
        return 0
    end
end

---@param line_id  number | string
---@param lineType string, eg "RAIL", "ROAD", "TRAM", "WATER", "AIR"
---@return boolean : is lineType correct
function helper.lineHasType( line_id, lineType )
    if type( line_id ) == "string" then
        line_id = tonumber( line_id )
    end
    if not (type( line_id ) == "number") then
        print( "Expected String or Number" )
        return -1
    end

    local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles( line_id )
    if vehicles and vehicles[1] then
        local component = api.engine.getComponent( vehicles[1], api.type.ComponentType.TRANSPORT_VEHICLE )
        if component and component.carrier then
            return component.carrier == api.type.enum.Carrier[lineType]
        end
    end
    return false
end

---@return table : all lines for the Player
function helper.getPlayerLines()
    return api.engine.system.lineSystem.getLinesForPlayer( api.engine.util.getPlayer() )
end

---@return table : containing line_id, vehicles, capacity, occupancy, usage, demand and rate
function helper.getLineData()
	local lines             = helper.getPlayerLines()
	local lineData          = {}
    local totalVehicleCount = 0

    for _, line_id in pairs( lines ) do
        -- Check type of line first
		if helper.supportedRoute(line_id) then
			local lineVehicleCount   = 0
			local lineCapacity       = 0
			local lineOccupancy      = 0
            local lineTravellerCount = 0

            local lineTravellers     = api.engine.system.simPersonSystem.getSimPersonsForLine( line_id )
            for _, traveller_id in pairs( lineTravellers ) do
                lineTravellerCount = lineTravellerCount + 1
            end

            if lineTravellerCount > 0 then
                local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles( line_id )
                for _, vehicle_id in pairs( lineVehicles ) do
                    local vehicle = api.engine.getComponent( vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE )
                    if vehicle and vehicle.config and vehicle.config.capacities[1] and vehicle.config.capacities[1] > 0 then
                        lineVehicleCount = lineVehicleCount + 1
                        lineCapacity = lineCapacity + vehicle.config.capacities[1]
                    end

                    for _, traveller_id in pairs( lineTravellers ) do
                        local traveller = api.engine.getComponent( traveller_id, api.type.ComponentType.SIM_PERSON_AT_VEHICLE )
                        if traveller and traveller.vehicle and traveller.vehicle == vehicle_id then
                            lineOccupancy = lineOccupancy + 1
                        end
                    end
                end

                lineData[line_id] = {
                    vehicles  = lineVehicleCount,
                    capacity  = lineCapacity,
                    occupancy = lineOccupancy,
                    demand    = lineTravellerCount,
                    usage     = math.round(100 * lineOccupancy / lineCapacity),
                    rate      = helper.getLineRate(line_id),
                    name      = helper.getEntityName(line_id),
				}
            end
        end
    end

    return lineData
end

return helper

-- api.engine.getComponent(line_id, api.type.ComponentType.LINE)
-- vehicleInfo = {
--    transportModes = {
--      [1] = 0,
--      [2] = 0,
--      [3] = 0,
--      [4] = 0, ROAD
--      [5] = 0,
--      [6] = 0,
--      [7] = 0, TRAM
--      [8] = 0,
--      [9] = 0, RAIL
--      [10] = 0, AIR
--      [11] = 0,
--      [12] = 0,
--      [13] = 0, WATER
--      [14] = 0,
--      [15] = 0,
--      [16] = 0,
--    },
--
-- api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
-- config = {
--    capacities = {
--      [1] = 0, PASSENGERS
--      [2] = 0,
--      [3] = 0,
--      [4] = 0,
--      [5] = 0,
--      [6] = 0,
--      [7] = 0,
--      [8] = 0,
--      [9] = 0,
--      [10] = 0,
--      [11] = 0,
--      [12] = 0,
--      [13] = 0,
--      [14] = 0,
--      [15] = 0,
--      [16] = 0,
--      [17] = 0,
--    },
