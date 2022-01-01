---@author CARTOK
---@author RusteyBucket
local log = require 'cartok/logging'
local helper = require 'cartok/helper'
local enums = require 'cartok/enums'

local last_sampled_month = -1 -- Keeps track of what month number the last sample was taken.
local sample_size = 6
local currentLineData = {}
local update_interval = 2 -- For every x sampling, do a vehicle update (check if a vehicle should be added or removed)
local sample_restart = 2 -- Following an update of a Line, the number of recorded samples will be reset to this value for the line to delay an update until sufficient data is available
local samples_since_last_update = 0

-- TODO: make these options load menu toggleable (And make that button actually work)
-- Set the logging level, uncomment the line below to change logging from default 'INFO' to 'DEBUG'
-- log.setLevel(log.levels.DEBUG)
-- Uncomment the line below to reduce debugging verbosity
-- log.setVerboseDebugging(false)

--- @param lineVehicles table array of VEHICLE ids
--- @return number id of the oldest vehicle on the line
--- finds the oldest vehicle on a line
local function getOldestVehicle(lineVehicles)
    local oldestVehicleId = 0
    local oldestVehiclePurchaseTime = 999999999999

    for _, vehicle_id in pairs(lineVehicles) do
        local vehicleInfo = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
        if vehicleInfo.transportVehicleConfig.vehicles[1].purchaseTime < oldestVehiclePurchaseTime then
            oldestVehiclePurchaseTime = vehicleInfo.transportVehicleConfig.vehicles[1].purchaseTime
            oldestVehicleId = vehicle_id
        end
    end

    return oldestVehicleId
end

---@param line_id number
---@return boolean success whether a vehicle was removed
---removes the oldest vehicle from the specified line
local function removeVehicleFromLine(line_id)
    local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)

    -- Find the oldest vehicle on the line
    local oldestVehicleId = getOldestVehicle(lineVehicles)

    -- Remove/sell the oldest vehicle (instantly sells)
    api.cmd.sendCommand(api.cmd.make.sellVehicle(oldestVehicleId))
    log.info(" -1 vehicle: " .. helper.getEntityName(line_id) .. " (" .. helper.printLineData(currentLineData, line_id) .. ")")
    log.debug("vehicle_id: " .. oldestVehicleId .. " line_id: " .. line_id)

    return true
end

---@param line_id number
---@return boolean success whether a vehicle was added
---adds a vehicle to the specified line_id by cloning an existing vehicle
local function addVehicleToLine(line_id)
    local success = false
    local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
    local depot_id
    local stop_id
    local vehicleToDuplicate

    -- TODO: Test whether enough money is available or don't empty the vehicle when it's hopeless anyway
    -- TODO: Figure out a better way to find the closest depot (or one at all).
    -- This merely tries to send an existing vehicle on the line to the depot, checks if succeeds then cancel the depot call but uses the depot data.
    -- Unfortunately sending a vehicle to a depot empties the vehicle.
    for _, vehicle_id in pairs(lineVehicles) do
        -- For now filter this to passenger transportation only.
        -- TODO: Extend to further types of cargo.
        if helper.vehicleTransportsPassengers(vehicle_id) then
            api.cmd.sendCommand(api.cmd.make.sendToDepot(vehicle_id, false))
            vehicleToDuplicate = api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)

            if vehicleToDuplicate.state == api.type.enum.TransportVehicleState.GOING_TO_DEPOT then
                depot_id = vehicleToDuplicate.depot
                stop_id = vehicleToDuplicate.stopIndex

                local lineCommand = api.cmd.make.setLine(vehicle_id, line_id, stop_id)
                api.cmd.sendCommand(lineCommand)
                break
            end
        end
    end

    if depot_id then
        local transportVehicleConfig = vehicleToDuplicate.transportVehicleConfig
        local purchaseTime = helper.getGameTime()

        -- Reset applicable parts of the transportVehicleConfig
        for _, vehicle in pairs(transportVehicleConfig.vehicles) do
            vehicle.purchaseTime = purchaseTime
            vehicle.maintenanceState = 1
        end

        local buyCommand = api.cmd.make.buyVehicle(api.engine.util.getPlayer(), depot_id, transportVehicleConfig)
        api.cmd.sendCommand(buyCommand, function(cmd, res)
            if (res and cmd.resultVehicleEntity) then
                success = true

                local lineCommand = api.cmd.make.setLine(cmd.resultVehicleEntity, line_id, stop_id)
                api.cmd.sendCommand(lineCommand)

                log.info(" +1 vehicle: " .. helper.getEntityName(line_id) .. " (" .. helper.printLineData(currentLineData, line_id) .. ")")
                log.debug("vehicle_id: " .. cmd.resultVehicleEntity .. " line_id: " .. line_id .. " depot_id: " .. depot_id)
            else
                log.warn("Unable to add vehicle to line: " .. helper.getEntityName(line_id) .. " - Insufficient cash?")
            end
        end)
    else
        log.warn("Unable to add vehicle to line: " .. helper.getEntityName(line_id) .. " - No available depot.")
        log.debug("line_id: " .. line_id)
    end

    return success
end

---takes data samples of all applicable lines
local function sampleLines()
    log.info("============ Sampling ============")

    local sampledLineData = {}
    local ignoredLines = {}
    sampledLineData, ignoredLines = helper.getLineData()

    local sampledLines = {}

    for line_id, line_data in pairs(sampledLineData) do
        if currentLineData[line_id] then
            sampledLineData[line_id].samples = currentLineData[line_id].samples + 1
            -- The below ones are already captured in the fresh sample taken, no need to overwrite those values.
            -- sampledLineData[line_id].vehicles = currentLineData[line_id].vehicles
            -- sampledLineData[line_id].capacity = currentLineData[line_id].capacity
            -- sampledLineData[line_id].occupancy = currentLineData[line_id].occupancy
            sampledLineData[line_id].demand = math.round(((currentLineData[line_id].demand * (sample_size - 1)) + line_data.demand) / sample_size)
            sampledLineData[line_id].usage = math.round(((currentLineData[line_id].usage * (sample_size - 1)) + line_data.usage) / sample_size)
            sampledLineData[line_id].rate = line_data.rate
        else
            sampledLineData[line_id].samples = 1
        end

        local name = helper.printLine(line_id)
        table.insert(sampledLines, name)
    end

    -- By initially just using the fresh sampledLineData, no longer existing lines are removed. Does this cause increased memory/CPU usage?
    currentLineData = sampledLineData

    -- print general summary for debugging purposes
    log.debug('Sampled Lines: ' .. #sampledLines .. ' (Ignored Lines: ' .. #ignoredLines .. ")")

    -- printing the list of lines sampled for additional debug info
    if (log.isVerboseDebugging()) then
        local debugOutput = ""

        -- Sampled lines
        if (#sampledLines > 0) then
            table.sort(sampledLines)
            debugOutput = "Sampled lines:\n"
            debugOutput = debugOutput .. helper.printArrayWithBreaks(sampledLines)
            log.debug(debugOutput)
        end

        -- Ignored lines
        if (#ignoredLines > 0) then
            local sampledIgnoredLines = {}
            for i = 1, #ignoredLines do
                local name = helper.printLine(ignoredLines[i])
                table.insert(sampledIgnoredLines, name)
            end
            table.sort(sampledIgnoredLines)

            debugOutput = "Ignored lines:\n"
            debugOutput = debugOutput .. helper.printArrayWithBreaks(sampledIgnoredLines)
            log.debug(debugOutput)
        end
    end
end

--- updates vehicle amount if applicable and line list in general
local function updateLines()
    log.info("============ Updating ============")

    local lines = helper.getPlayerLines()
    local lineCount = 0
    local totalVehicleCount = 0

    for _, line_id in pairs(lines) do
        -- TODO: Should check that the line still exists, and still transports passengers.
        if currentLineData[line_id] then
            lineCount = lineCount + 1
            totalVehicleCount = totalVehicleCount + currentLineData[line_id].vehicles

            -- If a line has sufficient samples, then check whether vehicles should be added/removed.
            if currentLineData[line_id].samples and currentLineData[line_id].samples >= sample_size then
                -- Check if a vehicle should be added to a Line.
                if helper.moreVehicleConditions(currentLineData, line_id) then
                    if addVehicleToLine(line_id) then
                        currentLineData[line_id].samples = sample_restart
                        totalVehicleCount = totalVehicleCount + 1
                    end
                    -- Check instead whether a vehicle should be removed from a Line.
                elseif helper.lessVehiclesConditions(currentLineData, line_id) then
                    if removeVehicleFromLine(line_id) then
                        currentLineData[line_id].samples = sample_restart
                        totalVehicleCount = totalVehicleCount - 1
                    end
                end
            end
        end
    end

    local ignored = #api.engine.system.lineSystem.getLines() - lineCount
    log.info("Total Lines: " .. lineCount .. " Total Vehicles: " .. totalVehicleCount .. " (Ignored Lines: " .. ignored .. ")")
end

-- TODO: get it to update periodically independently from the date, at least as an option
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
    return { update = update }
end
