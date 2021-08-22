-- Contains code from https://github.com/IncredibleHannes/TPF2-Timetables

local helper = {}

---@param line number | string
-- returns lineRate : Number
function helper.getLineRate(line)
    if type(line) == "string" then line = tonumber(line) end
    if not(type(line) == "number") then return 0 end

    local lineEntity = game.interface.getEntity(line)
    if lineEntity and lineEntity.rate then
        return lineEntity.rate
    else
        return 0
    end
end

---@param line number | string
-- returns lineName : String
function helper.getLineName(line)
    if type(line) == "string" then line = tonumber(line) end
    if not(type(line) == "number") then return "ERROR" end

    local err, res = pcall(function()
        return api.engine.getComponent(line, api.type.ComponentType.NAME)
    end)
    local component = res
    if err and component and component.name then
        return component.name
    else
        return "ERROR"
    end
end

-- returns Number, current GameTime in milliseconds
function helper.getGameTime()
    local time = api.engine.getComponent(0,api.type.ComponentType.GAME_TIME).gameTime
    if time then
        return time
    else
        return 0
    end
end

-- returns Number, current GameTime in seconds
function helper.getGameTimeInSeconds()
    local time = api.engine.getComponent(0,api.type.ComponentType.GAME_TIME).gameTime
    if time then
        time = math.floor(time/1000)
        return time
    else
        return 0
    end
end

-- api.engine.getComponent(line_id, api.type.ComponentType.LINE)
-- vehicleInfo = {
--    transportModes = {
--      [1] = 0,
--      [2] = 0,
--      [3] = 0,
--      [4] = 0, BUS
--      [5] = 0,
--      [6] = 0,
--      [7] = 0,
--      [8] = 0,
--      [9] = 1,  TRAIN
--      [10] = 0,
--      [11] = 0,
--      [12] = 0,
--      [13] = 0,
--      [14] = 0,
--      [15] = 0,
--      [16] = 0,
--    },

-- returns Array, containing line_id, vehicles, capacity, occupancy, usage, demand and rate
function helper.getBusPassengerLinesData()
    local lines = api.engine.system.lineSystem.getLines()
	local lineData = {}
	local totalVehicleCount = 0
	
	for _, line_id in pairs(lines) do
		-- Check type of line first
		local lineInfo = api.engine.getComponent(line_id, api.type.ComponentType.LINE)
		if lineInfo and lineInfo.vehicleInfo and lineInfo.vehicleInfo.transportModes and lineInfo.vehicleInfo.transportModes[4] == 1 then
			local lineVehicleCount = 0
			local lineCapacity = 0
			local lineOccupancy = 0
			local lineTravellerCount = 0
		
			local lineTravellers = api.engine.system.simPersonSystem.getSimPersonsForLine(line_id)
			for _, traveller_id in pairs(lineTravellers) do
				lineTravellerCount = lineTravellerCount + 1
			end
			
			if lineTravellerCount > 0 then
				local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
				for _, vehicle_id in pairs(lineVehicles) do		
					local vehicleInfo = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
					if vehicleInfo and vehicleInfo.config and vehicleInfo.config.capacities[1] then
						lineVehicleCount = lineVehicleCount + 1
						lineCapacity = lineCapacity + vehicleInfo.config.capacities[1]
					end
					
					for _, traveller_id in pairs(lineTravellers) do
						local traveller = api.engine.getComponent(traveller_id, api.type.ComponentType.SIM_PERSON_AT_VEHICLE)
						if traveller and traveller.vehicle == vehicle_id then	
							lineOccupancy = lineOccupancy + 1
						end
					end
				end				

				lineData[line_id] = {vehicles = lineVehicleCount, capacity = lineCapacity, occupancy = lineOccupancy, demand = lineTravellerCount, usage = math.round(100*lineOccupancy/lineCapacity), rate = helper.getLineRate(line_id)}
			end			
		end
	end

	return lineData
end

return helper