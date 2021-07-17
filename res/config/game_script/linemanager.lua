local log = require 'cartok/logging'
local helper = require 'cartok/helper'

local time_prev_update = nil
local time_prev_sample = nil
local update_interval 365
local samples = {}
local samples_taken = 0
local sample_size = 12
local sample_interval = 73

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
	local vehicleToDuplicate = nil
	local purchaseTime = helper.getGameTime
	
	for _, vehicle_id in pairs(lineVehicles) do
		api.cmd.sendCommand(api.cmd.make.sendToDepot(vehicle_id, false))
		vehicleToDuplicate = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
		
		if vehicleToDuplicate.state == 3 then
			depot_id = vehicleToDuplicate.depot
			stop_id = vehicleToDuplicate.stopIndex
			api.cmd.sendCommand(api.cmd.make.setLine(vehicle_id, line_id, vehicleToDuplicate.stopIndex))
 			break
		end
	end

	if depot_id then
		local transportVehicleConfig = api.type.TransportVehicleConfig.new()
		local vehicleCount = 0
		
		for _, vehicle_section in pairs(vehicleToDuplicate.transportVehicleConfig.vehicles) do
			vehicleCount = vehicleCount + 1
			
			local vehicle = api.type.TransportVehiclePart.new()
			vehicle.purchaseTime = purchaseTime
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
	
		transportVehicleConfig.vehicleGroups = vehicleToDuplicate.transportVehicleConfig.vehicleGroups
		
		-- TODO: This doesn't return the id of the new vehicle, instead I check that the purchaseTime corresponds to the expected.
		-- This is not perfecet, but shouldn't be a big issue.
		api.cmd.sendCommand(api.cmd.make.buyVehicle(api.engine.util.getPlayer(), depot_id, transportVehicleConfig))
		local depot_vehicles = api.engine.system.transportVehicleSystem.getDepotVehicles(depot_id)
		for _, depot_vehicle_id in pairs(depot_vehicles) do
			depot_vehicle = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
			if depot_vehicle.transportVehicleConfig.vehicles[1].purchaseTime == purchaseTime then			
				api.cmd.sendCommand(api.cmd.make.setLine(new_vehicle_id, line_id, vehicleToDuplicate.stopIndex))
				print("      Added vehicle: " .. new_vehicle_id .. " to line: " .. line_id .. " via depot: " .. depot_id)
			end
		end
	else
		print("Unable to add vehicle to line: " .. line_id .. " No available depot.")
	end	
end

local function samplePassengerLines()
	log.info("============ Sampling ============")
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
			
			if lineTravellerCount/lineCapacity > 2 or (lineTravellerCount/lineCapacity > (lineVehicleCount + 1) / lineVehicleCount and lineOccupancy/lineCapacity > 0.95) then
				print("Line: " .. api.engine.getComponent(line_id, api.type.ComponentType.NAME).name .. " (" .. line_id .. ") - Usage: " .. math.round(100 * lineOccupancy/lineCapacity) .. "% (" .. lineOccupancy .. "/" .. lineCapacity .. ") Veh: " .. lineVehicleCount .. " Trav: " .. lineTravellerCount .. " Rate: " .. helper.getLineRate(line_id))
				addVehicle(line_id)			
			elseif lineVehicleCount > 1 and (lineTravellerCount/lineCapacity < (lineVehicleCount - 1) / lineVehicleCount and lineOccupancy/lineCapacity < (lineVehicleCount - 1) / lineVehicleCount) then
				print("Line: " .. api.engine.getComponent(line_id, api.type.ComponentType.NAME).name .. " (" .. line_id .. ") - Usage: " .. math.round(100 * lineOccupancy/lineCapacity) .. "% (" .. lineOccupancy .. "/" .. lineCapacity .. ") Veh: " .. lineVehicleCount .. " Trav: " .. lineTravellerCount .. " Rate: " .. helper.getLineRate(line_id))
				removeVehicle(line_id)
			end
		end
	end
	log.info("Total number of lines: " .. lineCount .. " Total number of vehicles: " .. totalVehicleCount)
end

local function checkIfUpdateIsDue()
	if not time_prev_update then
		time_prev_update = api.engine.getComponent(0,api.type.ComponentType.GAME_TIME).gameTime
	end

	local time = api.engine.getComponent(0,api.type.ComponentType.GAME_TIME).gameTime
	-- Seems like the time is in ms, and 2 "seconds" pass per game day i.e. if the below is more than 730, then more than 365 game days have passed
	local time_passed = math.floor((time-time_prev_update)/1000)
	if time_passed > 365 then
		checkPassengerLines()
		time_prev_update = api.engine.getComponent(0,api.type.ComponentType.GAME_TIME).gameTime
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