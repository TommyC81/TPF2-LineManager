local departureBoard = {}

local options = {}
local i18n = {}
local displayWindow = {}
local textView = nil
local lineDataTable = nil
local stationData = nil

local msgPrev = ""
local vehiclesList = {}  -- list of vehicleID to VData records
local WINDOW_HEIGHT = 42  -- plus text lines
local WINDOW_LINE_HEIGHT = 17
local WINDOW_MIN_LINES = 2
local PLATFORM_TIMER = 10000  -- mS, keep destination display after train leaves the platform


local TERMINUS = 1
local TERMINUS2 = 2
local SHORT = 3
local VIA_SHORT = 5
local VIA = 6


local function makeVData(vid)
	return{vehicleID=vid, -- vehicle entity
	terminal=0,
	vstate=0,  -- 0 none, 1 approaching, 2 at station, 3 departing
	appearance=0, -- time vehicle appears on departure board
	distSq=0,  -- distance (squared) from the station
	text="",   -- destination text
	carrier=1,
	capacity=0,
	occupancy=0,
	timer=0}
end


local function getDistanceFromStation(vehicleID, vdata)
	-- find coords of the vehicle
	if not api.engine.entityExists(vehicleID) then
		return nil
	end

	local entity
	
	if vdata.carrier == 1 then  -- RAIL, there is no bounding box for the vehicle, so find the track segment
		local vehiclePath = api.engine.getComponent(vehicleID, api.type.ComponentType.MOVE_PATH)
		if vehiclePath == nil or vehiclePath.dyn == nil then
			return nil
		end
		
		local index = vehiclePath.dyn.pathPos.edgeIndex
		if vehiclePath.path.edges[index] == nil then
			return nil
		end
		entity = vehiclePath.path.edges[index].edgeId.entity
	else
		entity = vehicleID
	end

	-- find the distance from the station
	local bounds = api.engine.getComponent(entity, api.type.ComponentType.BOUNDING_VOLUME)
	if bounds == nil then
		print("Can't find location of vehicle:", api.engine.getComponent(vehicleID, 63).name)
		return nil
	end
	
	local dx
	local dy
	if vdata.carrier == 1 and vdata.vstate == 3 and vdata.terminal > 0 then
		-- for rail, the terminal location is more accurate than station location, use it for departing trains
		dx = ((bounds.bbox.min.x + bounds.bbox.max.x) / 2) - stationData.tX[vdata.terminal]
		dy = ((bounds.bbox.min.y + bounds.bbox.max.y) / 2) - stationData.tY[vdata.terminal]
	else
		dx = ((bounds.bbox.min.x + bounds.bbox.max.x) / 2) - stationData.X
		dy = ((bounds.bbox.min.y + bounds.bbox.max.y) / 2) - stationData.Y
	end
	return (dx * dx) + (dy * dy)  -- distance squared
end



local function prevStop(line,stopNum)
	local n = stopNum - 1
	if n < 1 then
		n = #line.stops
	end
	return line.stops[n].stationGroup
end

local function nextStop(line,stopNum)
	local n = stopNum + 1
	if n > #line.stops then
		n = 1
	end
	return line.stops[n].stationGroup
end

local function findDestination(vehicle)
	local line = api.engine.getComponent(vehicle.line, api.type.ComponentType.LINE)
	local lineName = api.engine.getComponent(vehicle.line, 63).name
	local nStops = #line.stops
	local lineData = lineDataTable[lineName]
	local stopNum = vehicle.stopIndex + 1
	local thisStopNum = stopNum
	local nextStationName = nil
	local terminusName = nil
	local viaList = {}
	local originName = nil
	local omitOrigin = false
	local stn = nil
	local stnData = nil
	local choice = 0

	if lineData ~= nil then
		stnData = lineData[stationData.name]
		if stnData == TERMINUS or stnData == TERMINUS2 or type(stnData) == "table" then
			omitOrigin = true   -- don't show origin if we are at a terminus
		end
	end
	
	if options.showOrigin and omitOrigin == false then
		-- find the previous terminus on the line
		for n = 1,nStops do
			stopNum = stopNum - 1
			if stopNum < 1 then
				stopNum = nStops
			end
			stn = line.stops[stopNum].stationGroup
			local stnName = api.engine.getComponent(stn, 63).name
			
			if lineData == nil then
			-- no data for this line in the lineDataTable
			-- find terminus and origin by the same station for previous and next stops
				if nextStop(line, stopNum) == prevStop(line, stopNum) then
					originName = stnName
					break
				end
			else
				stnData = lineData[stnName]
				if stnData == TERMINUS2 then
					stnData = TERMINUS
				end
				if stnData == TERMINUS then
					originName = stnName
					break
				end
				if type(stnData) == "table" then  -- a FOR clause
					choice = stnData[2]  -- stnData[2] is the choice for origin
					if stationData.incDestinationChoice then
						choice = choice + 1
					end
					if choice > #stnData then
						choice = 4
					end
					originName = stnData[choice]
					local ix = string.find(originName, " VIA ")
					if ix ~= nil then
						originName = string.sub(originName, 1, ix - 1)  -- discard VIA part from origin
					end
					stnData[2] = choice
					break
				end
			end
		end
	
	end
	
	-- find the next terminus on the line
	stopNum = thisStopNum
	for n = 1,nStops do
		stopNum = stopNum + 1
		if stopNum > nStops then
			stopNum = 1
		end
		stn = line.stops[stopNum].stationGroup
		local stnName = api.engine.getComponent(stn, 63).name
		
		if n == 1 then
			nextStationName = stnName
			viaList[#viaList+1] = nextStationName
		end
		
		if lineData == nil then
		-- no data for this line in the lineDataTable
			if nextStop(line, stopNum) == prevStop(line, stopNum) then
				terminusName = stnName
				break
			end
		else
			stnData = lineData[stnName]

			if stnData == TERMINUS or stnData == TERMINUS2 then
				terminusName = stnName
				break
			end
			if stnData == SHORT or stnData == VIA_SHORT then
				-- treat this as terminus if previous station is the same as the following station
				if nextStop(line,stopNum) == prevStop(line,stopNum) then
					terminusName = stnName
					break
				end
			end
			if stnData == VIA or stnData == VIA_SHORT then
				if stnName ~= nextStationName then   -- nextStationName is already in viaList
					viaList[#viaList+1] = stnName
				end
			end
			if type(stnData) == "table" then  -- a FOR clause
				choice = stnData[3]  -- stnData[3] is the choice for destination
				if stationData.incDestinationChoice then
					choice = choice + 1
				end
				if choice > #stnData then
					choice = 4
				end
				terminusName = stnData[choice]
				
				local ix = string.find(terminusName," VIA ")
				if ix ~= nil then
					local viaName2 = nil
					local viaName = string.sub(terminusName, ix+5)
					terminusName = string.sub(terminusName, 1, ix-1)
					
					ix = string.find(viaName," VIA ")
					if ix ~= nil then
						viaName2 = string.sub(viaName, ix+5)
						viaName = string.sub(viaName, 1, ix-1)
					end
					if viaName ~= viaList[1] then   -- already in viaList as nextStationName ?
						viaList[#viaList+1] = viaName
					end
					if viaName2 ~= nil then
						viaList[#viaList+1] = viaName2
					end
				end
				stnData[3] = choice
				break
			end
		end
	end

	if #viaList == 0 and nextStationName ~= nil then
		viaList[1] = nextStationName
	end
	if viaList[1] == terminusName then
		viaList[1] = " "
	end
	
	if terminusName == originName then
		originName = nil
	end

	if vehicle.carrier == 0 or vehicle.carrier == 2 then -- road vehicle, use the line name 
		local ix = string.find(lineName,"_")
		if ix ~= nil then
			lineName = string.sub(lineName,ix+1)
		end
		if terminusName == nil then
			terminusName = lineName
		else
			if ix ~= nil or options.showLineName then
				terminusName = lineName .. ":  " .. terminusName
			end
		end
	elseif options.showLineName then
		if terminusName == nil then
			terminusName = lineName
		else
			terminusName = lineName .. ":  " .. terminusName
		end
	elseif terminusName == nil then
		-- terminus not found
		terminusName = lineName
	end
	
	return terminusName, viaList, originName
end



local function getTerminalNumber(lineID, stopIndex, groupID)
	local line = api.engine.getComponent(lineID, api.type.ComponentType.LINE)
	local stop = line.stops[stopIndex+1]
	local terminal = 0
	
	if stop == nil then
		return 0
	end
	
	if stop.stationGroup == groupID then
		terminal = stationData.startPlatforms[stop.station+1] + stop.terminal
	end
	return terminal
end



local function makeDestinationText(vehicle)
	local destination
	local viaList
	local originName

	destination, viaList, originName = findDestination(vehicle)

	local text = destination
	if text == nil then
		return "???"
	end
	
	if viaList ~= nil then
		local count = 0
		local skip = 0

		if viaList[1] == viaList[2] or #viaList > options.maxVia then
			skip = 1
		end
		for n = skip+1,#viaList do
			if n-skip > options.maxVia then
				break
			end
			local v = viaList[n]
			if v ~= nil and v ~= " " then
				if count == 0 then
					text = text .. i18n.via .. v
				else
					text = text .. ", " .. v
				end
				count = count + 1
			end
		end
	end
	if vehicle.carrier ~= 0 and originName ~= nil and originName ~= stationData.name and originName ~= destination then
		text = text .. i18n.from .. originName   -- don't use origin for road vehicles
	end
	
	return text
end


local function findVehicles(groupID)
	if groupID == nil or not api.engine.entityExists(groupID) then
		return
	end
	
	local stationGroup = api.engine.getComponent(groupID, api.type.ComponentType.STATION_GROUP)

	local gametime = api.engine.getComponent(0,16).gameTime
	local vdata
	local vehicle

	local function initVehicle()
		vdata.appearance = gametime
		vdata.terminal = getTerminalNumber(vehicle.line, vehicle.stopIndex, groupID)
		vdata.text = makeDestinationText(vehicle)
		vdata.capacity = vehicle.config.capacities[1]  -- passenger capacity
		if vdata.capacity == 0 then
			for n = 2,17 do
				vdata.capacity = vdata.capacity + vehicle.config.capacities[n]  -- cargo types
			end
		end
	end
	

	local linesHere = {}	
	for n = 1,#stationGroup.stations do
		local lineStops = api.engine.system.lineSystem.getLineStopsForStation(stationGroup.stations[n])
		for _,lineID in pairs(lineStops) do
			linesHere[lineID] = true      -- examine each line only once at the station
		end
	end
	
	local simMap
	if options.showOccupancy and stationData.useSimMap then
		simMap = api.engine.system.simEntityAtVehicleSystem.getVehicle2Cargo2SimEntitesMap()
	end

	for lineID,_ in pairs(linesHere) do
		local sims
		local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(lineID)
		
		if #vehicles > 0 then
			if options.showOccupancy and stationData.useSimMap == false then
				sims = api.engine.system.simPersonSystem.getSimPersonsForLine(lineID)
			end
		
			for v = 1,#vehicles do
				-- Find the destination data for this vehicle
				local vid = vehicles[v]
				vdata = vehiclesList[vid]
				if vdata == nil then
					vdata = makeVData(vid)
					vehiclesList[vid] = vdata
				end
				
				vehicle = api.engine.getComponent(vid, api.type.ComponentType.TRANSPORT_VEHICLE)
				local carrier = vehicle.carrier
				vdata.carrier = carrier
				
				if options.showOccupancy then
					local occupancy = 0
					
					if stationData.useSimMap then
					-- This method of finding occupancy works for both passengers and cargo, but may cause
					-- stutter in the game display.  So only use it for cargo, unless there is a better method.
						if simMap then
							local cargo = simMap[vid]
							if cargo then
								occupancy = #cargo[1]  -- passengers
								if occupancy == 0 then
									for n = 2,17 do
										occupancy = occupancy + #cargo[n]  -- cargo types
									end
								end
							end
						end
					else
						if sims then
							for _,simID in pairs(sims) do
								local sim = api.engine.getComponent(simID, 33)  -- api.type.ComponentType.SIM_ENTITY_AT_VEHICLE
								if sim and sim.vehicle == vid then
									occupancy = occupancy + 1
								end
							end
						end
					end
					vdata.occupancy = occupancy
				end
			
				if vehicle.state == 2 and getTerminalNumber(vehicle.line, vehicle.stopIndex, groupID) > 0 then
					if vdata.vstate == 0 then
						initVehicle()
					end
					vdata.vstate = 2   -- at the station terminal
					vdata.distSq = 0
					
				elseif vehicle.state == 1 then
					vdata.distSq = getDistanceFromStation(vid, vdata)

					if vdata.distSq ~= nil and vdata.distSq < stationData.maxDistanceSq[carrier+1] then
						if vdata.vstate == 0 then
							if getTerminalNumber(vehicle.line, vehicle.stopIndex, groupID) > 0 then
								initVehicle()
								vdata.vstate = 1
							end
						elseif vdata.vstate == 2 then
							vdata.vstate = 3   -- vehicle has just left the station
							vdata.timer = gametime + PLATFORM_TIMER
						elseif vdata.vstate == 3 then
							if gametime > vdata.timer and vdata.distSq >= stationData.departDistanceSq[carrier+1] then
								if vdata.text == "" then
									vdata.vstate = 0
								else
									vdata.text = ""
									vdata.timer = gametime + 500  -- show 500mS of blank line
								end
							end
						else
							vdata.vstate = 1
						end
					else
						vdata.vstate = 0
					end
					
				else
					vdata.vstate = 0
				end
			end
		end
	end
end


local function vehicleSorter(a, b)
	if a.vstate ~= b.vstate then
		return a.vstate > b.vstate
	end
	if a.appearance ~= b.appearance then
		return a.appearance < b.appearance
	end
	return a.distSq < b.distSq
end


local function vehiclePlatformSorter(a, b)
	if a.terminal ~= b.terminal then
		return a.terminal < b.terminal
	end
	if a.vstate ~= b.vstate then
		return a.vstate > b.vstate
	end
	return a.distSq < b.distSq
end


local function displayDepartures()
	local vehiclesSorted = {}  -- sorted list of vehicle data records
	
	for _,vdata in pairs(vehiclesList) do
		if vdata.vstate > 0 and vdata.terminal > 0 and vdata.distSq ~= nil then
			vehiclesSorted[#vehiclesSorted+1] = vdata
		end
	end
	
	if options.sortByPlatform then
		table.sort(vehiclesSorted, vehiclePlatformSorter)
	else
		table.sort(vehiclesSorted, vehicleSorter)
	end
	
	local msg = ""
	local prevTerminal = 0
	local count = 0
	local nTextLines = 0
	
	for _,vdata in pairs(vehiclesSorted) do
		if vdata.text == "" then
			msg = msg .. "\n"
			nTextLines = nTextLines + 1
		else
			if options.sortByPlatform and vdata.terminal == prevTerminal then
				count = count + 1  -- count of vehicles for this terminal
			else
				count = 0
			end
			prevTerminal = vdata.terminal

			local prefix = "\xe2\x80\x87"  -- UTF-8 U+2007 (figure space)
			if vdata.vstate == 2 then
--				prefix = utf8.char(9679)   -- UTF-8 needs lua version 5.3
				prefix = "\xe2\x97\x8f"  -- solid circle
			elseif vdata.vstate == 3 then
--				prefix = utf8.char(9675)
				prefix = "\xe2\x97\x8b"  -- hollow circle
			end
			
			if stationData.numPlatforms >= 10 and (vdata.terminal < 10 or count > 0) then  -- 2 digit platform numbers
				prefix = prefix .. "\xe2\x80\x87"  -- U+2007 (figure space)
			end
			
			local occupancy = " "
			if options.showOccupancy then
				occupancy = string.format("%3d/%3d ",vdata.occupancy,vdata.capacity)
				occupancy = string.gsub(occupancy, ' ', "\xe2\x80\x87")  -- replace spaces by U+2007 (figure space)
			end
			
			if count < 3 then
				if count == 0 then
					msg = msg .. string.format("%s %d %s%s\n", prefix, vdata.terminal, occupancy, vdata.text)
				else
					msg = msg .. string.format("%s \xe2\x80\x87 %s%s\n", prefix, occupancy, vdata.text)  -- don't include terminal number
				end
				nTextLines = nTextLines + 1
			end
		end
	end


	if msg ~= msgPrev then
		if nTextLines < WINDOW_MIN_LINES then
			nTextLines = WINDOW_MIN_LINES
		end
		
		local rect = displayWindow:getContentRect()
		displayWindow:setSize(api.gui.util.Size.new(rect.w, WINDOW_HEIGHT + nTextLines*17))			
		textView:setText(msg)

		msgPrev = msg
	end
end

function departureBoard.resetVehiclesList(stationData2, control)
-- control 0 = just display the departures
-- control 1 = delete vehicle records except state 3 (departing)
-- control 2 = delete all vehicle records

	stationData = stationData2
	if stationData == nil then
		vehiclesList = {}
		return
	end
	
	if control == 2 then
		vehiclesList = {}
	elseif control == 1 then
		-- delete all vehicle records, except those departing the station
		for vid,vdata in  pairs(vehiclesList) do
			if vdata.vstate ~= 3 then
				vehiclesList[vid] = nil
			end
		end
		findVehicles(stationData.groupID)
	end

	displayDepartures()
	stationData.incDestinationChoice = true

end


function departureBoard.DoDepartures(stationData2, lineDataTable2)
	stationData = stationData2
	lineDataTable = lineDataTable2
	if stationData ~= nil then
		findVehicles(stationData.groupID)
		displayDepartures()
		stationData.incDestinationChoice = true
	end
end


function departureBoard.Options(options2)
	options = options2
end

function departureBoard.Init(i18n2, displayWindow2, textView2)
	i18n = i18n2
	lineDataTable = lineDataTable2
	displayWindow = displayWindow2
	textView = textView2
end

return departureBoard
