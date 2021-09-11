local log = require 'cartok/logging'
local helper = require 'cartok/helper'

local last_sampled_month = -1 -- Keeps track of what month number the last sample was taken.
local sample_size = 6
local sampledLineData = {}
local update_interval = 2 -- For every x sampling, do a vehicle update (check if a vehicle should be added or removed)
local sample_restart = 2 -- Following an update of a Line, the number of recorded samples will be reset to this value for the line to delay an update until sufficient data is available
local samples_since_last_update = 0

local function removeVehicle(line_id)	
	local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
	local oldestVehicleId = 0
	local oldestVehiclePurchaseTime = 999999999999
	
	-- Find the oldest vehicle on the line
	for _, vehicle_id in pairs(lineVehicles) do
		local vehicleInfo = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
		if vehicleInfo.transportVehicleConfig.vehicles[1].purchaseTime < oldestVehiclePurchaseTime then
			oldestVehiclePurchaseTime = vehicleInfo.transportVehicleConfig.vehicles[1].purchaseTime
			oldestVehicleId = vehicle_id
		end
	end
	
	-- Remove/sell the oldest vehicle (instantly sells)
	api.cmd.sendCommand(api.cmd.make.sellVehicle(oldestVehicleId))
	print("      Removed vehicle: " .. oldestVehicleId .. " from line: " .. line_id)
end
	
local function addVehicle(line_id)
	local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
	local depot_id = nil
	local stop_id = nil
	local vehicleToDuplicate = nil
	local purchaseTime = helper.getGameTime()
	
	-- TODO: Figure out a better way to find the closest depot (or one at all).
	-- This merely tries to send an existing vehicle on the line to the depot, checks if succeeds then cancel the depot call but uses the depot data.
	-- Unfortunately sending a vehicle to a depot empties the vechicle.
	for _, vehicle_id in pairs(lineVehicles) do
		-- For now filter this to passenger transportation only.
		-- TODO: Extend to further types of cargo.
		if helper.vehicleTransportsPassengers(vehicle_id) then
			api.cmd.sendCommand(api.cmd.make.sendToDepot(vehicle_id, false))
			vehicleToDuplicate = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
		
			if vehicleToDuplicate.state == api.type.enum.TransportVehicleState.GOING_TO_DEPOT then
				depot_id = vehicleToDuplicate.depot
				api.cmd.sendCommand(api.cmd.make.setLine(vehicle_id, line_id, vehicleToDuplicate.stopIndex))
				break
			end
		end
	end

	if depot_id then
		local transportVehicleConfig = vehicleToDuplicate.transportVehicleConfig
		
		-- Reset applicable parts of the transportVehicleConfig
		for _, vehicle in pairs(transportVehicleConfig.vehicles) do
			vehicle.purchaseTime = purchaseTime
			vehicle.maintenanceState = 1
		end
		
		-- TODO: This doesn't return the id of the new vehicle, instead I check that the purchaseTime corresponds to the expected.
		-- This is not perfect, but shouldn't be a big issue. In the API documentation this should return an id.
		-- api.type.BuyVehicle(playerEntity, depotEntity, config) return resultVehicleEntity
		api.cmd.sendCommand(api.cmd.make.buyVehicle(api.engine.util.getPlayer(), depot_id, transportVehicleConfig))
		local depot_vehicles = api.engine.system.transportVehicleSystem.getDepotVehicles(depot_id)
		for _, depot_vehicle_id in pairs(depot_vehicles) do
			local depot_vehicle = api.engine.getComponent(depot_vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
			if depot_vehicle.transportVehicleConfig.vehicles[1].purchaseTime == purchaseTime then			
				api.cmd.sendCommand(api.cmd.make.setLine(depot_vehicle_id, line_id, 1))
				print("      Added vehicle: " .. depot_vehicle_id .. " to line: " .. line_id .. " via depot: " .. depot_id)
			end
		end
	else
		print("Unable to add vehicle to line: " .. line_id .. " No available depot.")
	end	
end

local function sampleLines()
	log.info("============ Sampling ============")
	local lineData = helper.getLineData()
	
	for line_id, line_data in pairs(lineData) do
		if sampledLineData[line_id] then
			lineData[line_id].samples = sampledLineData[line_id].samples + 1
			-- lineData[line_id].vehicles = line_data.vehicles
			-- lineData[line_id].capacity = line_data.capacity
			-- lineData[line_id].occupancy = line_data.occupancy
			lineData[line_id].demand = math.round(((sampledLineData[line_id].demand * (sample_size - 1)) + line_data.demand)/sample_size)
			lineData[line_id].usage = math.round(((sampledLineData[line_id].usage * (sample_size - 1)) + line_data.usage)/sample_size)
			lineData[line_id].rate = line_data.rate
		else
			lineData[line_id].samples = 1
		end
	end
	
	-- By initially just using the fresh lineData, no longer existing lines are removed. Does this cause increased memory/CPU usage?
	sampledLineData = lineData
end

local function updateLines()
	log.info("============ Updating ============")
	local lines = helper.getPlayerLines()
	local lineCount = 0
	local totalVehicleCount = 0
	
	for _, line_id in pairs(lines) do
		-- TODO: Should check that the line still exists, and still transports passengers.
		if sampledLineData[line_id] then
			lineCount = lineCount + 1
			totalVehicleCount = totalVehicleCount + sampledLineData[line_id].vehicles			
			
			-- If a line has sufficient samples, then check whether vehicles should be added/removed.
			if sampledLineData[line_id].samples and sampledLineData[line_id].samples >= sample_size then
				-- Check if a vehicle should be added to a Line.
				if (sampledLineData[line_id].usage > 50 and sampledLineData[line_id].demand > sampledLineData[line_id].rate * 2) or (sampledLineData[line_id].usage > 80 and sampledLineData[line_id].demand > sampledLineData[line_id].rate * (sampledLineData[line_id].vehicles + 1) / sampledLineData[line_id].vehicles) then
					print("Line: " .. helper.getEntityName(line_id) .. " (" .. line_id .. ") - Usage: " .. sampledLineData[line_id].usage .. "% (" .. sampledLineData[line_id].occupancy .. "/" .. sampledLineData[line_id].capacity .. ") Veh: " .. sampledLineData[line_id].vehicles .. " Demand: " .. sampledLineData[line_id].demand .. " Rate: " .. sampledLineData[line_id].rate)
					sampledLineData[line_id].samples = sample_restart
					addVehicle(line_id)
					totalVehicleCount = totalVehicleCount + 1
				-- Check instead whether a vehicle should be removed from a Line.
				elseif sampledLineData[line_id].vehicles > 1 and sampledLineData[line_id].usage < 70 and sampledLineData[line_id].demand < sampledLineData[line_id].rate * (sampledLineData[line_id].vehicles - 1) / sampledLineData[line_id].vehicles then
					print("Line: " .. helper.getEntityName(line_id) .. " (" .. line_id .. ") - Usage: " .. sampledLineData[line_id].usage .. "% (" .. sampledLineData[line_id].occupancy .. "/" .. sampledLineData[line_id].capacity .. ") Veh: " .. sampledLineData[line_id].vehicles .. " Demand: " .. sampledLineData[line_id].demand .. " Rate: " .. sampledLineData[line_id].rate)
					sampledLineData[line_id].samples = sample_restart
					removeVehicle(line_id)
					totalVehicleCount = totalVehicleCount - 1
				end
			end
		end
	end
	log.info("Total Lines: " .. lineCount .. " Total Vehicles: " .. totalVehicleCount)
end

local function checkIfUpdateIsDue()
	local current_month = helper.getGameMonth()
	
	-- Check if the month has changed since last sample. If so, do another sample. 1 sample/month.
	if last_sampled_month ~= current_month then
		last_sampled_month = current_month
		
		sampleLines()
		samples_since_last_update = samples_since_last_update + 1
		
		if samples_since_last_update >= update_interval then
			updateLines()			
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