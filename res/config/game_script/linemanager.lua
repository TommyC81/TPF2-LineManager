local log = require 'cartok/logging'
local helper = require 'cartok/helper'

local time_prev_sample = nil
-- Seems like the time is in ms, and 2 "seconds" pass per game day i.e. if the below is more than 730, then more than 365 game days have passed
local sample_interval = 73
local sample_size = 6
local sampledLineData = {}
local update_interval = 2 -- For every x sampling, do a vehicle update (check if a vehicle should be added or removed)
local sample_restart = 2 -- Following an update of a Line, the number of recorded samples will be reset to this value for the line to delay an update until sufficient data is available
local samples_since_last_update = 0

local function removeVehicle(line_id)	
	local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
	local oldestVehicleId = 0
	local oldestVehiclePurchaseTime = 999999999999
	
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
	local purchaseTime = helper.getGameTime()
	
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
			local depot_vehicle = api.engine.getComponent(depot_vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
			if depot_vehicle.transportVehicleConfig.vehicles[1].purchaseTime == purchaseTime then			
				api.cmd.sendCommand(api.cmd.make.setLine(depot_vehicle_id, line_id, vehicleToDuplicate.stopIndex))
				print("      Added vehicle: " .. depot_vehicle_id .. " to line: " .. line_id .. " via depot: " .. depot_id)
			end
		end
	else
		print("Unable to add vehicle to line: " .. line_id .. " No available depot.")
	end	
end

local function samplePassengerLines()
	log.info("============ Sampling ============")
	local lineData = helper.getBusPassengerLinesData()
	
	for line_id, line_data in pairs(lineData) do
		if sampledLineData[line_id] then
			sampledLineData[line_id].samples = sampledLineData[line_id].samples + 1
			sampledLineData[line_id].vehicles = line_data.vehicles
			sampledLineData[line_id].capacity = line_data.capacity
			sampledLineData[line_id].occupancy = line_data.occupancy
			sampledLineData[line_id].demand = math.round(((sampledLineData[line_id].demand * (sample_size - 1)) + line_data.demand)/sample_size)
			sampledLineData[line_id].usage = math.round(((sampledLineData[line_id].usage * (sample_size - 1)) + line_data.usage)/sample_size)
			sampledLineData[line_id].rate = line_data.rate
		else
			sampledLineData[line_id] = { samples = 1, vehicles = line_data.vehicles, capacity = line_data.capacity, occupancy = line_data.occupancy, demand = line_data.demand, usage = line_data.usage, rate = line_data.rate}
		end
	end
end

local function updatePassengerLines()
	log.info("============ Updating ============")
	local lines = api.engine.system.lineSystem.getLines()
	local lineCount = 0
	local totalVehicleCount = 0
	
	for _, line_id in pairs(lines) do
		if sampledLineData[line_id] then
			lineCount = lineCount + 1
			totalVehicleCount = totalVehicleCount + sampledLineData[line_id].vehicles			
			
			if sampledLineData[line_id].samples and sampledLineData[line_id].samples >= sample_size then
				--if (sampledLineData[line_id].usage > 70 and sampledLineData[line_id].demand > 2 * sampledLineData[line_id].rate) or (sampledLineData[line_id].usage > 95 and sampledLineData[line_id].demand > sampledLineData[line_id].rate) or (sampledLineData[line_id].usage > 85 and sampledLineData[line_id].demand > sampledLineData[line_id].rate * (sampledLineData[line_id].vehicles + 1) / sampledLineData[line_id].vehicles) then
				if sampledLineData[line_id].usage > 95 then
					print("Line: " .. helper.getLineName(line_id) .. " (" .. line_id .. ") - Usage: " .. sampledLineData[line_id].usage .. "% (" .. sampledLineData[line_id].occupancy .. "/" .. sampledLineData[line_id].capacity .. ") Veh: " .. sampledLineData[line_id].vehicles .. " Demand: " .. sampledLineData[line_id].demand .. " Rate: " .. sampledLineData[line_id].rate)
					sampledLineData[line_id].samples = sample_restart
					addVehicle(line_id)
					totalVehicleCount = totalVehicleCount + 1
				-- elseif (sampledLineData[line_id].vehicles > 1 and sampledLineData[line_id].usage < 50 and sampledLineData[line_id].demand < sampledLineData[line_id].rate) or (sampledLineData[line_id].vehicles > 2 and sampledLineData[line_id].usage < 75 and sampledLineData[line_id].demand < sampledLineData[line_id].rate * (sampledLineData[line_id].vehicles - 1) / sampledLineData[line_id].vehicles) then
				elseif sampledLineData[line_id].vehicles > 1 and sampledLineData[line_id].usage < 90 * (sampledLineData[line_id].vehicles - 1) / sampledLineData[line_id].vehicles then
					print("Line: " .. helper.getLineName(line_id) .. " (" .. line_id .. ") - Usage: " .. sampledLineData[line_id].usage .. "% (" .. sampledLineData[line_id].occupancy .. "/" .. sampledLineData[line_id].capacity .. ") Veh: " .. sampledLineData[line_id].vehicles .. " Demand: " .. sampledLineData[line_id].demand .. " Rate: " .. sampledLineData[line_id].rate)
					sampledLineData[line_id].samples = sample_restart
					removeVehicle(line_id)
					totalVehicleCount = totalVehicleCount - 1
				end
			end
		end
	end
	log.info("Total number of lines: " .. lineCount .. " Total number of vehicles: " .. totalVehicleCount)
end

local function checkIfUpdateIsDue()
	if not time_prev_sample then
		time_prev_sample = helper.getGameTimeInSeconds()
	end

	local time = helper.getGameTimeInSeconds()
	local time_passed = math.floor((time-time_prev_sample))
	if time_passed > sample_interval then
		samplePassengerLines()
		time_prev_sample = helper.getGameTimeInSeconds()
		
		samples_since_last_update = samples_since_last_update + 1
		if samples_since_last_update >= update_interval then
			updatePassengerLines()			
			samples_since_last_update = 0
		end
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