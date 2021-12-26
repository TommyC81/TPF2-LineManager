---@author CARTOK wrote the bulk of the code while
---@author RusteyBucket rearranged it to lbe more readable and added some minor debugging improvements

local log = require 'cartok/logging'
local helper = require 'cartok/helper'

local last_sampled_month = -1 -- Keeps track of what month number the last sample was taken.
local sample_size = 6
local sampledLineData = {}
local sampledIgnoredLines = {}
local update_interval = 2 -- For every x sampling, do a vehicle update (check if a vehicle should be added or removed)
local sample_restart = 2 -- Following an update of a Line, the number of recorded samples will be reset to this value for the line to delay an update until sufficient data is available
local samples_since_last_update = 0

local debugging = true --Enables additional printouts in order to make debugging easier
local debName = true --prints the name of the lines being managed
local debNum = true --prints the EntityNumber of the lines being managed
local getIgnored = true --also prints a list of ignored lines

--- @param lineVehicles userdata
--- @return number
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
---removes oldest vehicle from said line
local function removeVehicle(line_id)
    local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)

    -- Find the oldest vehicle on the line
    local oldestVehicleId = getOldestVehicle(lineVehicles)

    -- Remove/sell the oldest vehicle (instantly sells)
    api.cmd.sendCommand(api.cmd.make.sellVehicle(oldestVehicleId))
    print("      Removed vehicle: " .. oldestVehicleId .. " from line: " .. line_id)
end

---@param line_id number
---clones a vehicle on line
local function addVehicle(line_id)
    local lineVehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line_id)
    local depot_id
    local stop_id
    local vehicleToDuplicate
    local purchaseTime = helper.getGameTime()

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
                api.cmd.sendCommand(api.cmd.make.setLine(vehicle_id, line_id, stop_id))
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
        -- This is not perfect, but shouldn't be a big issue.
        -- In the API documentation the below should return an id of the new vehicle, but can't figure out how to get that to work proper:
        -- api.type.BuyVehicle(playerEntity, depotEntity, config) return resultVehicleEntity
        api.cmd.sendCommand(api.cmd.make.buyVehicle(api.engine.util.getPlayer(), depot_id, transportVehicleConfig))
        local depot_vehicles = api.engine.system.transportVehicleSystem.getDepotVehicles(depot_id)
        for _, depot_vehicle_id in pairs(depot_vehicles) do
            local depot_vehicle = api.engine.getComponent(depot_vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
            if depot_vehicle.transportVehicleConfig.vehicles[1].purchaseTime == purchaseTime then
                api.cmd.sendCommand(api.cmd.make.setLine(depot_vehicle_id, line_id, stop_id))
                print("      Added vehicle: " .. depot_vehicle_id .. " to line: " .. line_id .. " via depot: " .. depot_id)
            end
        end
    else
        print("Unable to add vehicle to line: " .. line_id .. " No available depot.")
    end
end

---takes data samples of all applicable lines
local function sampleLines()
    log.info("============ Sampling ============")
    local lineData
    lineData, sampledIgnoredLines = helper.getLineData()
    local sampled = {}

    for line_id, line_data in pairs(lineData) do
        if sampledLineData[line_id] then
            lineData[line_id].samples = sampledLineData[line_id].samples + 1
            -- lineData[line_id].vehicles = line_data.vehicles
            -- lineData[line_id].capacity = line_data.capacity
            -- lineData[line_id].occupancy = line_data.occupancy
            lineData[line_id].demand = math.round(((sampledLineData[line_id].demand * (sample_size - 1)) + line_data.demand) / sample_size)
            lineData[line_id].usage = math.round(((sampledLineData[line_id].usage * (sample_size - 1)) + line_data.usage) / sample_size)
            lineData[line_id].rate = line_data.rate
        else
            lineData[line_id].samples = 1
        end
        local name = helper.identify(line_id, debNum, debName)
        table.insert(sampled, name)
    end

    -- By initially just using the fresh lineData, no longer existing lines are removed. Does this cause increased memory/CPU usage?
    sampledLineData = lineData

    -- printing the list of lines sampled for additional debug info
    if debugging then

        --sort sampled by letter
        table.sort(sampled)

        local res = helper.stringUp("Sampled: ", sampled, debName)

        --also print the ignored ones if desired
        if getIgnored then
            local igno = {}
            for i = 1, #sampledIgnoredLines do
                local name = helper.identify(sampledIgnoredLines[i], debNum, debName)
                table.insert(igno, name)
            end
            table.sort(igno)
            res = res .. "\nIgnored:"
            res = helper.stringUp(res, igno, debName)
        end

        print(res)
    end
end

---@param line_id number
---@return string
---returns the output string of a successful line adjustment
local function linePrint(line_id)
    local res = "Line: " .. helper.getEntityName(line_id)
    res = res .. " (" .. line_id .. ") - "
    res = res .. helper.lineDump(sampledLineData, line_id)
    return res
end

--- updates vehicle amount if applicable and line list in general
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
                if helper.moreVehicleConditions(sampledLineData, line_id) then
                    print(linePrint(line_id))
                    sampledLineData[line_id].samples = sample_restart
                    addVehicle(line_id)
                    totalVehicleCount = totalVehicleCount + 1
                    -- Check instead whether a vehicle should be removed from a Line.
                elseif helper.lessVehiclesConditions(sampledLineData, line_id) then
                    print(linePrint(line_id))
                    sampledLineData[line_id].samples = sample_restart
                    removeVehicle(line_id)
                    totalVehicleCount = totalVehicleCount - 1
                end
            end
        end
    end

    -- little extra info when debugging
    local deb = ""
    if (debugging) then
        local ignoredLines = #helper.getPlayerLines() - lineCount
        deb = " ignoring " .. ignoredLines .. " lines"
    end

    log.info("Total Lines: " .. lineCount .. " Total Vehicles: " .. totalVehicleCount .. deb)
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
