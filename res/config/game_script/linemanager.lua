local log = require 'cartok/logging'

local time_prev = nil

local function removeVehicle(line_id)	
	local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
	local oldestVehicleId = 0
	local oldestVehiclePurchaseTime = 99999999999
	
	for _, vehicle_id in pairs(lineVehicles) do
		local vehicleInfo = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
		if vehicleInfo.transportVehicleConfig.vehicles[1].purchaseTime < oldestVehiclePurchaseTime then
			oldestVehiclePurchaseTime = vehicleInfo.transportVehicleConfig.vehicles[1].purchaseTime
			oldestVehicleId = vehicle_id
		end
	end
	
	api.cmd.sendCommand(api.cmd.make.sellVehicle(oldestVehicleId))
	print("      Removed vehicle: " .. oldestVehicleId .. " from line: " .. line_id)
end
	
local function addVehicle(line_id)
	local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
	local depot_id = nil
	local stop_id = nil
	local vehicleInfo = nil
	
	for _, vehicle_id in pairs(lineVehicles) do
		api.cmd.sendCommand(api.cmd.make.sendToDepot(vehicle_id, false))
		vehicleInfo = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
		
		if vehicleInfo.state == 3 then
			depot_id = vehicleInfo.depot
			stop_id = vehicleInfo.stopIndex
			api.cmd.sendCommand(api.cmd.make.setLine(vehicle_id, line_id, vehicleInfo.stopIndex))
 			break
		end
	end

	if depot_id then
		local transportVehicleConfig = api.type.TransportVehicleConfig.new()
		local vehicleCount = 0
		
		for _, vehicle_section in pairs(vehicleInfo.transportVehicleConfig.vehicles) do
			vehicleCount = vehicleCount + 1
			
			local vehicle = api.type.TransportVehiclePart.new()
			vehicle.purchaseTime = api.engine.getComponent(0,api.type.ComponentType.GAME_TIME).gameTime
			vehicle.maintenanceState = 1
			vehicle.targetMaintenanceState = vehicle_section.targetMaintenanceState
			vehicle.autoLoadConfig = { 1 }
						
			local part = api.type.VehiclePart.new()
			part.modelId = vehicle_section.part.modelId
			part.reversed = vehicle_section.part.reversed
			part.loadConfig[1] = vehicle_section.part.loadConfig[1]
			part.color = vehicle_section.part.color
			part.logo = vehicle_section.part.logo
			vehicle.part = part
			
			transportVehicleConfig.vehicles[vehicleCount] = vehicle
		end
	
		transportVehicleConfig.vehicleGroups = vehicleInfo.transportVehicleConfig.vehicleGroups
		
		-- TODO: This doesn't return the id of the new vehicle, so I just assign all vehicles in the depot
		-- to the line. This is bound to go wrong at some point, but shouldn't be a big issue.
		api.cmd.sendCommand(api.cmd.make.buyVehicle(api.engine.util.getPlayer(), depot_id, transportVehicleConfig))
		local new_vehicles = api.engine.system.transportVehicleSystem.getDepotVehicles(depot_id)
		for _, new_vehicle_id in pairs(new_vehicles) do		
			api.cmd.sendCommand(api.cmd.make.setLine(new_vehicle_id, line_id, vehicleInfo.stopIndex))
			print("      Added vehicle: " .. new_vehicle_id .. " to line: " .. line_id .. " via depot: " .. depot_id)	
		end
	else
		print("Unable to add vehicle to line: " .. line_id .. " No available depot.")
	end	
end

local function checkPassengerLines()
	log.info("============ Checking ============")
	local lines = api.engine.system.lineSystem.getLines()
	local lineCount = 0
	local totalVehicleCount = 0
	
	for _, line_id in pairs(lines) do
		local lineVehicleCount = 0
		local lineTravellerCount = 0		
		
		local lineTravellers = api.engine.system.simPersonSystem.getSimPersonsForLine(line_id)
		for _, traveller_id in pairs(lineTravellers) do
			lineTravellerCount = lineTravellerCount + 1
		end
		if lineTravellerCount > 0 then
			lineCount = lineCount + 1
		
			local lineCapacity = 0
			local lineOccupancy = 0

			local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
			for _, vehicle_id in pairs(lineVehicles) do
				lineVehicleCount = lineVehicleCount + 1
			
				local vehicleInfo = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)				
				lineCapacity = lineCapacity + vehicleInfo.config.capacities[1]
				
				for _, traveller_id in pairs(lineTravellers) do
					local traveller = api.engine.getComponent(traveller_id, api.type.ComponentType.SIM_PERSON_AT_VEHICLE)
					if traveller and traveller.vehicle == vehicle_id then
						lineOccupancy = lineOccupancy + 1
					end
				end
			end
			
			totalVehicleCount = totalVehicleCount + lineVehicleCount			
			
			if lineTravellerCount/lineCapacity > 2 or (lineTravellerCount/lineCapacity > (lineVehicleCount + 1) / lineVehicleCount and lineOccupancy/lineCapacity > 0.9) then
				print("Line: " .. api.engine.getComponent(line_id, api.type.ComponentType.NAME).name .. " (" .. line_id .. ") - Usage: " .. math.round(100 * lineOccupancy/lineCapacity) .. "% (" .. lineOccupancy .. "/" .. lineCapacity .. ") Veh: " .. lineVehicleCount .. " Trav: " .. lineTravellerCount)
				addVehicle(line_id)			
			elseif lineVehicleCount > 1 and (lineTravellerCount/lineCapacity < (lineVehicleCount - 1) / lineVehicleCount and lineOccupancy/lineCapacity < (lineVehicleCount - 1) / lineVehicleCount) then
				print("Line: " .. api.engine.getComponent(line_id, api.type.ComponentType.NAME).name .. " (" .. line_id .. ") - Usage: " .. math.round(100 * lineOccupancy/lineCapacity) .. "% (" .. lineOccupancy .. "/" .. lineCapacity .. ") Veh: " .. lineVehicleCount .. " Trav: " .. lineTravellerCount)
				removeVehicle(line_id)
			end
		end
	end
	log.info("Total number of lines: " .. lineCount .. " Total number of vehicles: " .. totalVehicleCount)
end

local function checkIfUpdateIsDue()
	if not time_prev then
		time_prev = api.engine.getComponent(0,api.type.ComponentType.GAME_TIME).gameTime
	end

	local time = api.engine.getComponent(0,api.type.ComponentType.GAME_TIME).gameTime
	-- Seems like the time is in ms, and 2 "seconds" pass per game day i.e. if the below is more than 730, then more than 365 game days have passed
	local time_passed = math.floor((time-time_prev)/1000)
	if time_passed > 365 then
		checkPassengerLines()
		time_prev = api.engine.getComponent(0,api.type.ComponentType.GAME_TIME).gameTime
	end
end

local function update()
	checkIfUpdateIsDue()
end

function data()
	return {
		update = update
	}
 end