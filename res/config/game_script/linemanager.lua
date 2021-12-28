---@author CARTOK wrote the bulk of the code while
---@author RusteyBucket rearranged the code to improve readability and expandability

local log = require 'cartok/logging'
local helper = require 'cartok/helper'
local enums = require 'cartok/enums'

local last_sampled_month = -1 -- Keeps track of what month number the last sample was taken.
local sample_size = 6
local currentLineData = {}
local update_interval = 2 -- For every x sampling, do a vehicle update (check if a vehicle should be added or removed)
local sample_restart = 2 -- Following an update of a Line, the number of recorded samples will be reset to this value for the line to delay an update until sufficient data is available
local samples_since_last_update = 0

-- Set the logging level, uncomment the line below to change logging from default 'INFO' to 'DEBUG'
-- log.setLevel(log.levels.DEBUG)
-- Uncomment the line below to reduce debugging verbosity
-- log.setVerboseDebugging(false)

--- @param lineVehicles userdata
--- @return number id of the oldest vehicle
--- finds the oldest vehicle on a line
local function getOldestVehicle( lineVehicles )
	local oldestVehicleId = 0
	local oldestVehiclePurchaseTime = 999999999999

	for _, vehicle_id in pairs( lineVehicles ) do
		local vehicleInfo = api.engine.getComponent( vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE )
		if vehicleInfo.transportVehicleConfig.vehicles[1].purchaseTime < oldestVehiclePurchaseTime then
			oldestVehiclePurchaseTime = vehicleInfo.transportVehicleConfig.vehicles[1].purchaseTime
			oldestVehicleId = vehicle_id
		end
	end

	return oldestVehicleId
end

---@param line_id number
---removes oldest vehicle from the specified line
local function removeVehicle( line_id )
	local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles( line_id )

	-- Find the oldest vehicle on the line
	local oldestVehicleId = getOldestVehicle( lineVehicles )

	-- Remove/sell the oldest vehicle (instantly sells)
	api.cmd.sendCommand( api.cmd.make.sellVehicle( oldestVehicleId ) )
	log.info( "-    Sold 1: " .. helper.getEntityName( line_id ) .. " (" .. helper.printLineData( currentLineData, line_id ) .. ")" )
	log.debug( "vehicle_id: " .. oldestVehicleId .. " line_id: " .. line_id )
end

---@param line_id number
---clones a vehicle on line
local function addVehicle( line_id )
	local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles( line_id )
	local depot_id
	local stop_id
	local vehicleToDuplicate
	local purchaseTime = helper.getGameTime()

	-- TODO: Figure out a better way to find the closest depot (or one at all).
	-- This merely tries to send an existing vehicle on the line to the depot, checks if succeeds then cancel the depot call but uses the depot data.
	-- Unfortunately sending a vehicle to a depot empties the vehicle.
	for _, vehicle_id in pairs( lineVehicles ) do
		-- For now filter this to passenger transportation only.
		-- TODO: Extend to further types of cargo.
		if helper.vehicleTransportsPassengers( vehicle_id ) then
			api.cmd.sendCommand( api.cmd.make.sendToDepot( vehicle_id, false ) )
			vehicleToDuplicate = api.engine.getComponent( vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE )

			if vehicleToDuplicate.state == api.type.enum.TransportVehicleState.GOING_TO_DEPOT then
				depot_id = vehicleToDuplicate.depot
				stop_id = vehicleToDuplicate.stopIndex
				api.cmd.sendCommand( api.cmd.make.setLine( vehicle_id, line_id, stop_id ) )
				break
			end
		end
	end

	if depot_id then
		local transportVehicleConfig = vehicleToDuplicate.transportVehicleConfig

		-- Reset applicable parts of the transportVehicleConfig
		for _, vehicle in pairs( transportVehicleConfig.vehicles ) do
			vehicle.purchaseTime = purchaseTime
			vehicle.maintenanceState = 1
		end

		-- TODO: This doesn't return the id of the new vehicle, instead I check that the purchaseTime corresponds to the expected.
		-- This is not perfect, but shouldn't be a big issue.
		-- In the API documentation the below should return an id of the new vehicle, but can't figure out how to get that to work proper:
		-- api.type.BuyVehicle(playerEntity, depotEntity, config) return resultVehicleEntity
		api.cmd.sendCommand( api.cmd.make.buyVehicle( api.engine.util.getPlayer(), depot_id, transportVehicleConfig ) )
		local depot_vehicles = api.engine.system.transportVehicleSystem.getDepotVehicles( depot_id )
		for _, depot_vehicle_id in pairs( depot_vehicles ) do
			local depot_vehicle = api.engine.getComponent( depot_vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE )
			if depot_vehicle.transportVehicleConfig.vehicles[1].purchaseTime == purchaseTime then
				api.cmd.sendCommand( api.cmd.make.setLine( depot_vehicle_id, line_id, stop_id ) )
				log.info( "+  Bought 1: " .. helper.getEntityName( line_id ) .. " (" .. helper.printLineData( currentLineData, line_id ) .. ")" )
				log.debug( "vehicle_id: " .. depot_vehicle_id .. " line_id: " .. line_id .. " depot_id: " .. depot_id )
			end
		end
	else
		-- TODO: If this fails, it's not really reported back to the summary in the update function.
		log.warn( "Unable to add vehicle to line: " .. helper.getEntityName( line_id ) .. " - No available depot." )
		log.debug( "line_id: " .. line_id )
	end
end

---takes data samples of all applicable lines
local function sampleLines()
	log.info( "============ Sampling ============" )
	local sampledLineData = {}
	local ignoredLines = {}
	sampledLineData, ignoredLines = helper.getLineData()

	local sampledLines = {}

	for line_id, line_data in pairs( sampledLineData ) do
		if currentLineData[line_id] then
			sampledLineData[line_id].samples = currentLineData[line_id].samples + 1
			-- The below ones are already captured in the fresh sample taken, no need to overwrite those values.
			-- sampledLineData[line_id].vehicles = currentLineData[line_id].vehicles
			-- sampledLineData[line_id].capacity = currentLineData[line_id].capacity
			-- sampledLineData[line_id].occupancy = currentLineData[line_id].occupancy
			sampledLineData[line_id].demand = math.round( ((currentLineData[line_id].demand * (sample_size - 1)) + line_data.demand) / sample_size )
			sampledLineData[line_id].usage = math.round( ((currentLineData[line_id].usage * (sample_size - 1)) + line_data.usage) / sample_size )
			sampledLineData[line_id].rate = line_data.rate
		else
			sampledLineData[line_id].samples = 1
		end

		local name = helper.printLine( line_id )
		table.insert( sampledLines, name )
	end

	-- By initially just using the fresh sampledLineData, no longer existing lines are removed. Does this cause increased memory/CPU usage?
	currentLineData = sampledLineData

	-- print general summary for debugging purposes
	log.debug( 'Sampled ' .. #sampledLines .. ' lines. Ignored ' .. #ignoredLines .. ' lines.' )

	-- printing the list of lines sampled for additional debug info
	if (log.isVerboseDebugging()) then
		local debugOutput = ""

		-- Sampled lines
		if (#sampledLines > 0) then
			table.sort( sampledLines )
			debugOutput = "Sampled lines:\n"
			debugOutput = debugOutput .. helper.printArrayWithBreaks( sampledLines )
			log.debug( debugOutput )
		end

		-- Ignored lines
		if (#ignoredLines > 0) then
			local sampledIgnoredLines = {}
			for i = 1, #ignoredLines do
				local name = helper.printLine( ignoredLines[i] )
				table.insert( sampledIgnoredLines, name )
			end
			table.sort( sampledIgnoredLines )

			debugOutput = "Ignored lines:\n"
			debugOutput = debugOutput .. helper.printArrayWithBreaks( sampledIgnoredLines )
			log.debug( debugOutput )
		end
	end
end

--- updates vehicle amount if applicable and line list in general
local function updateLines()
	log.info( "============ Updating ============" )
	local lines = helper.getPlayerLines()
	local lineCount = 0
	local totalVehicleCount = 0

	for _, line_id in pairs( lines ) do
		-- TODO: Should check that the line still exists, and still transports passengers.
		if currentLineData[line_id] then
			lineCount = lineCount + 1
			totalVehicleCount = totalVehicleCount + currentLineData[line_id].vehicles

			-- If a line has sufficient samples, then check whether vehicles should be added/removed.
			if currentLineData[line_id].samples and currentLineData[line_id].samples >= sample_size then
				-- Check if a vehicle should be added to a Line.
				if helper.moreVehicleConditions( currentLineData, line_id ) then
					addVehicle( line_id )
					currentLineData[line_id].samples = sample_restart
					totalVehicleCount = totalVehicleCount + 1
					-- Check instead whether a vehicle should be removed from a Line.
				elseif helper.lessVehiclesConditions( currentLineData, line_id ) then
					removeVehicle( line_id )
					currentLineData[line_id].samples = sample_restart
					totalVehicleCount = totalVehicleCount - 1
				end
			end
		end
	end

	local ignored = #api.engine.system.lineSystem.getLines() - lineCount

	log.info( "Total Lines: " .. lineCount .. " Total Vehicles: " .. totalVehicleCount .. " (Ignored lines: " .. ignored .. ")" )
end

---updates the trackers of when the next update gets unlocked
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

---updates the counters when the last line adjustment happened
local function update()
	checkIfUpdateIsDue()
end

function data()
	return {
		update = update
	}
end
