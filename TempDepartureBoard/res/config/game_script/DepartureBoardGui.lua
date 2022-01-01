local departureBoard = require "departure_board"
local gui = require "gui"

-- initial default options. These can be changed by GUI and are stored in saved games.
local options = {
	lineDataFile="",
	moveCamera=true,
	sortByPlatform=true,
	showLineName=false,
	showOccupancy=true,
	showOrigin=true,
	maxVia=2,
	minimumLines=1,
	displayWindowWidth=450,
	selectRoad = false,
	selectTram = false,
	selectRail = true,
	selectAir = false,
	selectWater = false,
	cargoStations = 0,
	}

-- from strings.lua
local i18n = {
	title         = _('title_i18n'),
	taskbar       = _('taskbar_i18n'),
	error_list    = _('error_list_i18n'),
	err_line      = _('err_line_i18n'),
	err_station   = _('err_station_i18n'),
	err_twice     = _('err_twice_i18n'),
	err_notOnLine = _('err_not_on_line_i18n'),
	err_failed_read = _('err_failed_read_i18n'),
	error_dump      = _('error_dump_i18n'),
	err_no_linedata = _('err_no_linedata_i18n'),
	
	from  = _('from_i18n'),
	via   = _('via_i18n'),
	passengers = _('passengers_i18n'),
	cargo = _('cargo_i18n'),
	both =  _('both_i18n'),
	no_station    = _('no_station_i18n'),
	none_found    = _('none_found_i18n'),
	load_file     = _('load_file_i18n'),
	sort          = _('sort_i18n'),
	show_linename = _('show_linename_i18n'),
	show_origins  = _('show_origins_i18n'),
	show_occupancy= _('show_occupancy_i18n'),
	station_camera = _('station_camera_i18n'),
	maximum_via   = _('maximum_via_i18n'),
	minimum_lines = _('minimum_lines_i18n'),
	reset_camera  = _('reset_camera_i18n'),
}


local lineDataTable = {}
local stationData = nil
local displayWindow = nil
local textView = nil

local savedata = {}
local savedataChanged = false
local stationsMenuClicked = false
local fileNameField
local errorField
local errorTimeout = 0
local lineTableErrors = ""


local TERMINUS = 1
local TERMINUS2 = 2
local SHORT = 3
local VIA_SHORT = 5
local VIA = 6


local keys = {FROM=1, TO=2, SHORT=3, VIA_SHORT=5, VIA=6}
local keyName = {"FROM", "TO", "SHORT", "??", "VIA_SHORT", "VIA"}


local controlWindow = nil
local textInput1
local stationsMenu = nil
local stationsMenuList = {}
local stationGroupList = {}   -- includes town prefix for road stations
local stationGroupNames = {}  -- without town prefix
local stationGroupIdList = {}
local cameraController
local modPath = nil
local lineNames = {}
local nextTime = 0


local approachDistanceSq = {-- Distance squared. Ignore vehicles beyond this distance from the station
	 600*600,   -- ROAD
	1000*1000,  -- RAIL
	 600*600,   -- TRAM
	2200*2200,  -- AIR
	1500*1500,  -- WATER
	}

local departDistanceSq = {-- show departing vehicles up this distance (and a timeout)
	 70*70,   -- ROAD
	120*120,  -- RAIL
	 70*70,   -- TRAM
	220*220,  -- AIR
	220*220,  -- WATER
	}
	
local function makeStation(stationName)
	if stationGroupList == nil or stationName == nil then
		return nil
	end
	
	local groupID = stationGroupList[stationName]
	if groupID == nil or not api.engine.entityExists(groupID) then
		return nil
	end
	
	local bounds = api.engine.getComponent(groupID, api.type.ComponentType.BOUNDING_VOLUME)
	local group = api.engine.getComponent(groupID, api.type.ComponentType.STATION_GROUP)
	
	local platforms = {}
	local pnum = 1
	local cargo = false
	local X = {}
	local Y = {}
	local numPlatforms = 0

	for n = 1,#group.stations do
		local stn = api.engine.getComponent(group.stations[n], api.type.ComponentType.STATION)
		if stn.cargo then
			cargo = true
		end

		numPlatforms = numPlatforms + #stn.terminals
		for t = 1,#stn.terminals do  -- get location for each terminal for each station of the station group
			local vNode = stn.terminals[t].vehicleNodeId
			if vNode and vNode.entity then
				local terminalBounds = api.engine.getComponent(vNode.entity, api.type.ComponentType.BOUNDING_VOLUME)
				X[#X + 1] = (terminalBounds.bbox.min.x + terminalBounds.bbox.max.x) / 2
				Y[#Y + 1] = (terminalBounds.bbox.min.y + terminalBounds.bbox.max.y) / 2
			end
		end
		platforms[n] = pnum
		pnum = pnum + #X
	end
	
	return {
		groupID = groupID,
		stationGroup = group,
		name = stationName,
		useSimMap = cargo,   -- use Sim Map method only for cargo ?
--		useSimMap = true,
		numPlatforms = numPlatforms,
		startPlatforms = platforms,   -- the platform number of the first terminal of each station in the station group
		tX = X,
		tY = Y,
		X = (bounds.bbox.min.x + bounds.bbox.max.x) / 2,
		Y = (bounds.bbox.min.y + bounds.bbox.max.y) / 2,
		incDestinationChoice = true,
		maxDistanceSq = approachDistanceSq,
		departDistanceSq = departDistanceSq,
		}
end



local function checkLineForVehicleType(line, vtype)   -- not currently used
	local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(line)
	if #vehicles > 0 then
		for v = 1,#vehicles do
			vehicle = api.engine.getComponent(vehicles[v], api.type.ComponentType.TRANSPORT_VEHICLE)
			if vehicle.carrier == vtype then
				return true
			end
		end
	end
	return false
end


local function callbackStations(stnID)
	-- called for every station
	-- add to the station menu if it has lines with the required vehicle types
	
	local groupID = api.engine.system.stationGroupSystem.getStationGroup(stnID)
	local name = api.engine.getComponent(groupID, 63).name
	local lineStops = api.engine.system.lineSystem.getLineStopsForStation(stnID)
	local station = api.engine.getComponent(stnID, api.type.ComponentType.STATION)
	
	local linesHere = {}
	local lineCount = 0
	local addStation = false
	local townName = nil
	
	for n = 1,#lineStops do
		local stop = lineStops[n]
		if not linesHere[stop] then
			linesHere[stop] = true   -- count each line only once
			lineCount = lineCount + 1
			
			local line = api.engine.getComponent(stop, api.type.ComponentType.LINE)
			local modes = line.vehicleInfo.transportModes
			
			if options.selectRoad and (modes[4] == 1 or modes[5] == 1)
				or options.selectTram and (modes[6] == 1 or modes[7] == 1) then
				-- add a town prefix (if found in the lineName) to the station name
				local lineName = api.engine.getComponent(stop, 63).name
				local j = string.find(lineName, '_')
				if j ~= nil then
					townName = string.sub(lineName, 1, j)
				end
				addStation = true
			elseif options.selectRail and (modes[8] == 1 or modes[9] == 1) then
				addStation = true
			elseif options.selectAir and (modes[10] == 1 or modes[12] == 1)
				or options.selectWater and (modes[11] == 1 or modes[13] == 1) then
				addStation = true
			end
		end
	end

	if stationGroupIdList[groupID] == true then
		return  -- this stationGroup already found
	end

	if station.cargo then
		if options.cargoStations == 0 then
			addStation = false
		end
	else  -- passenger station
		if options.cargoStations == 1 then
			addStation = false
		end
	end
	
	local name2 = name
	if addStation == true then
		if townName ~= nil then
			name2 = townName .. name
		end
		if stationGroupList[name2] ~= nil then
			name2 = name2 .. "+"
		end
		if lineCount >= options.minimumLines then
			stationsMenuList[#stationsMenuList+1] = name2  -- ignore stations with fewer than the specified number of lines
		end
	end
	stationGroupNames[name] = groupID  -- without town prefix
	stationGroupList[name2] = groupID
	stationGroupIdList[groupID] = true
end


local function makeStationsList()
	stationsMenuList = {}
	stationGroupList = {}
	stationGroupNames = {}
	stationGroupIdList = {}
	stationsMenu:clear(true)

	api.engine.system.stationSystem.forEach(callbackStations)

	if #stationsMenuList == 0 then
		stationsMenu:addItem(i18n.none_found)
	else
		table.sort(stationsMenuList)
		for n = 1,#stationsMenuList do
			stationsMenu:addItem(stationsMenuList[n])
		end
	end
end



local function getAllLineNames()
	lineNames = {}
	allLines = api.engine.system.lineSystem.getLines()
	for n = 1,#allLines do
		local lineID = allLines[n]
		lineNames[api.engine.getComponent(lineID, 63).name] = lineID
	end
end


local function compileTerminusLine(lineName, text)
	local out = {}
	local onto = {}
	local stnName = nil
	local line = nil

	function checkStation()
		if not stationGroupNames[stnName] and not stationGroupList[stnName] then
			lineTableErrors = lineTableErrors .. string.format(i18n.err_station, lineName, stnName)
		elseif out[stnName] ~= nil then
			lineTableErrors = lineTableErrors .. string.format(i18n.err_twice, lineName, stnName)
			stnName = "?" .. stnName
		end
		local found = false
		if line then
			for n = 1,#line.stops do
				local name = api.engine.getComponent(line.stops[n].stationGroup, 63).name
				if name == stnName then
					found = true
					break
				end
			end
			if not found then
				lineTableErrors = lineTableErrors .. string.format(i18n.err_notOnLine, lineName, stnName)
			end
		end
	end
	
	local t = {}
    for w in string.gmatch(text, "[%w_%-%)%(]+") do
       t[#t+1] = w
     end
		
	local op = TERMINUS
	local order = TERMINUS
	local name2 = nil

	local lineId = lineNames[lineName]
	if lineId then
		line = api.engine.getComponent(lineId, api.type.ComponentType.LINE)
	else
		lineTableErrors = lineTableErrors .. string.format(i18n.err_line, lineName)
	end
	
	local n = 1
	local bracket = false
	while n <= #t do
		if t[n] == "FOR" or t[n] == "(FOR" then
			if t[n] == "(FOR" then
				bracket = true
			end
			onto = {2,4,4}
			onto[1] = order
			order = TERMINUS2
			name2 = nil
			n = n + 1
			while n <= #t do
				if keys[t[n]] and bracket == false then
					n = n - 1   -- end of FOR clause
					onto[#onto+1] = name2
					onto[2] = math.random(4,#onto)
					onto[3] = math.random(4,#onto)
					checkStation()					
					out[stnName] = onto
					stnName = nil
					name2 = nil
					break
				end
				if t[n] == "OR" then
					onto[#onto+1] = name2
					name2 = nil
				elseif t[n] == "XVIA" then
					name2 = name2 .. string.format(" VIA %s",t[n+1])
					n = n + 1
				else
					if name2 == nil then
						name2 = t[n]
					else
						name2 = name2 .. " " .. t[n]
					end
					if string.sub(name2,-1) == ')' then
						name2 = string.sub(name2, 1, -2)
						bracket = false
					end
				end
				n = n + 1
			end
		elseif keys[t[n]] then
			if stnName ~= nil then
				checkStation()					
				out[stnName] = op
				order = TERMINUS2
				stnName = nil
			end
			op = keys[t[n]]
		else
			if stnName == nil then
				stnName = t[n]
			else
				stnName = stnName .. " " .. t[n]
			end
		end
		
		n = n + 1
	end
	if name2 ~= nil then
		onto[#onto+1] = name2
		onto[2] = math.random(3,#onto)
		onto[3] = math.random(3,#onto)
		op = onto
	end
	if stnName ~= nil then
		checkStation()					
		out[stnName] = op
	end

	return out
end


local function writeLineDataTable()
	local file = io.open(modPath .. "lineData_dump","w")
	
	if lineTableErrors ~= "" then
		local errors = i18n.error_list .. lineTableErrors
		print(errors)
		file:write(errors .. "\n")
	end
	
	local temp = {}
	for linename,linedata in pairs(lineDataTable) do
		temp[#temp+1] = {linename, linedata}
	end
	
	table.sort(temp, function(a,b)
		local ax = a[1]
		local bx = b[1]
		return ax < bx
		end
	)
	
	for n = 1,#temp do
		local linename = temp[n][1]
		local linedata = temp[n][2]

		if linedata == nil then
			file:write(string.format("%s\n", linename))
		else
			local dataStr = ""
			local strTO = ""
			local temp = {}
			for stnName,stnData in pairs(linedata) do
				temp[#temp+1] = {stnName, stnData}
			end
			table.sort(temp, function(a,b)
				local ax = a[2]
				local bx = b[2]
				if type(ax) == "table" then
					ax = ax[1]
				end
				if type(bx) == "table" then
					bx = bx[1]
				end
				return ax < bx
				end )
			
			for ix = 1,#temp do
				item = temp[ix]
				local stnName = temp[ix][1]
				local stnData = temp[ix][2]

				if type(stnData) == "table" then
					dataStr = dataStr .. string.format(" %s%s (FOR %s", strTO, stnName,stnData[4])
					strTO = "TO "
					for ix = 5,#stnData do
						dataStr = dataStr .. string.format(" OR %s", stnData[ix])
					end
					dataStr = dataStr .. ')'
				elseif stnData == TERMINUS or stnData == TERMINUS2 then
					dataStr = dataStr .. string.format(" %s%s", strTO, stnName)
					strTO = "TO "
				else
					dataStr = dataStr .. string.format(" %s %s", keyName[stnData], stnName)
				end
			end
			if lineNames[linename] then
				file:write(string.format("%d  %s = %s\n", lineNames[linename], linename, dataStr))
			else
				file:write(string.format("%s = %s\n", linename, dataStr))
			end
		end
	end
	
	file:close()
end


local function getFilePath()
	local info = debug.getinfo(1,'S')
	local filePath = info.source
	local res =  string.find(filePath, '/res/')
	local scriptPath = string.sub(filePath, res)  -- /res/config/game_script/DepartureBoard.lua
	modPath = string.sub(filePath, 1, res)
end


local function compileData(fileName)
	lineTableErrors = ""
	
	if fileName == nil then
		return false
	end
	
	if fileName == "" then
		lineDataTable = {}
		return true
	end

	file = io.open(modPath .. "data/" .. fileName,"r")
	if file == nil then
		file = io.open(modPath .. "data/" .. fileName .. ".txt","r")
		if file == nil then
			print("DepartureBoard: Failed to read file: data/" .. fileName)
			return false
		end
	end
	
	getAllLineNames()
	lineDataTable = {}

	while true do
		local textline = file:read()
		if textline == nil then
			break  -- end of file
		end
		while string.sub(textline,-1) == "\\" do
			-- text line ends in \  Join it to the next line
			local textline2 = file:read()
			if textline2 == nil then
				break
			end
			local ix = string.find(textline2,"%g")  -- find the first non-space character
			if ix ~= nil then
				textline = string.sub(textline,1,-2) ..' '.. string.sub(textline2,ix)
			end
		end

		local ix = string.find(textline,"--",1,true)
		if ix ~= nil then
			textline = string.sub(textline, 1, ix-1)
		end

		ix = string.find(textline,"=")
		if ix ~= nil then
			local text = string.sub(textline, ix+1)
			local name = string.sub(textline, 1, ix-1)
			ix = string.find(name,"%w")
			local name2 = string.reverse(name)
			local ix2 = string.find(name2,"%w")
			local name2 = string.sub(name,ix,-ix2)
			local data = compileTerminusLine(name2, text)
			lineDataTable[name2] = data
		end
	end
	file:close()

	writeLineDataTable()

	return true
end


local function buttonClick()
	if not controlWindow:isVisible() then
--		controlWindow:setPosition(options.displayWindowWidth,0)
		controlWindow:setVisible(true,false)
	else
		if stationData ~= nil then
			displayWindow:setSize(api.gui.util.Size.new(options.displayWindowWidth,76))  -- 2 lines
			displayWindow:setPosition(0,0)
			displayWindow:setPinned(true)
			displayWindow:setVisible(true,false)
		end
	end
end

local function initData(filename)
	getFilePath()
	stationData = nil
	makeStationsList()
	return compileData(filename)
end				




local function changeStation(index)
	local stationName = ""
	
	nextTime = 0
	if index == -1 then
		return   --  stations menu has changed
	end

	if index < 0 then
		if stationData ~= nil then
			stationName = stationData.name
		end
	else
		stationName = stationsMenuList[index+1]
		stationsMenuClicked = true -- ignore a false clicks on options underneath the stations menu
	end

	stationData = makeStation(stationName)
	departureBoard.resetVehiclesList(stationData, 2)
	if stationData == nil then
		stationName = i18n.no_station
	end
	
	displayWindow:setTitle(string.format("%s", stationName))
	textView:setText("")

--	displayWindow:setPosition(0,0)
	displayWindow:setPinned(true)
	displayWindow:setVisible(true,false)

	if stationData and stationData.X then
		if options.moveCamera and index >= 0 then
			local posn = api.type.Vec2f.new(stationData.X, stationData.Y)
			cameraController:focus(stationData.groupID)
			cameraController:setCameraData(posn, 0.0, 0, 0)
		end
	end
	departureBoard.DoDepartures(stationData, lineDataTable)
end


local function updateStatonList()
	makeStationsList()
	savedataChanged = true
end


local function showError(msg)
	errorField:setText(msg)
	errorTimeout = 16   --  x 0.5s
end


local function reloadClick()
	local stationName = nil
	local fileName
	if stationData ~= nil then
		stationName = stationData.name
	end

	fileName = fileNameField:getText()
	if initData(fileName) == true then
		options.lineDataFile = fileName
		savedataChanged = true
		if fileName == "" then
			showError(i18n.err_no_linedata)
		elseif lineTableErrors == "" then
			showError("OK")
		else
			showError(i18n.error_dump)
		end
	else
		showError(i18n.err_failed_read)
	end
	stationData = makeStation(stationName)
	changeStation(-2)
end


local function initGUI()
	local buttonLabel = gui.textView_create("gameInfo.destinations.label", i18n.taskbar)
	local button = gui.button_create("gameInfo.destinations.button", buttonLabel)
	button:onClick(buttonClick)
	
	game.gui.boxLayout_addItem("gameInfo.layout", button.id)

	textView = api.gui.comp.TextView.new("")
	displayWindow = api.gui.comp.Window.new(i18n.title, textView)
	displayWindow:setTitle(i18n.no_station)
	displayWindow:addHideOnCloseHandler()
	displayWindow:setMovable(true)
	displayWindow:setPinButtonVisible(true)
	displayWindow:setResizable(false)
	if not options.displayWindowWidth then
		options.displayWindowWidth = 450
	end
	displayWindow:setSize(api.gui.util.Size.new(options.displayWindowWidth,76))  -- 2 lines
	displayWindow:setPosition(0,0)
	displayWindow:setPinned(true)
	displayWindow:setResizable(true)
	displayWindow:setVisible(false,false)
	textView:setText("")


	local selectModes = api.gui.comp.Table.new(5, 'None')
	local selectRoad  = api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new("ui/icons/game-menu/hud_filter_road_vehicles.tga"))
	local selectTram  = api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new("ui/button/medium/vehicle_tram.tga"))
	local selectRail  = api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new("ui/button/medium/vehicle_train_electric.tga"))
	local selectWater = api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new("ui/icons/game-menu/hud_filter_ships.tga"))
	local selectAir   = api.gui.comp.ToggleButton.new(api.gui.comp.ImageView.new("ui/icons/game-menu/hud_filter_planes.tga"))
	selectModes:addRow({selectRoad,selectTram,selectRail,selectWater,selectAir})
	
	selectRoad:setSelected(options.selectRoad, false)
	selectTram:setSelected(options.selectTram, false)
	selectRail:setSelected(options.selectRail, false)
	selectWater:setSelected(options.selectWater, false)
	selectAir:setSelected(options.selectAir, false)
	
	selectRoad:onToggle(function(selected)
		options.selectRoad = selected
		updateStatonList()
		end)
	selectTram:onToggle(function(selected)
		options.selectTram = selected
		updateStatonList()
		end)
	selectRail:onToggle(function(selected)
		options.selectRail = selected
		updateStatonList()
		end)
	selectWater:onToggle(function(selected)
		options.selectWater = selected
		updateStatonList()
		end)
	selectAir:onToggle(function(selected)
		options.selectAir = selected
		updateStatonList()
		end)
		
					
	local layoutBox = api.gui.layout.BoxLayout.new("VERTICAL")
	local layoutBox2 = api.gui.layout.BoxLayout.new("HORIZONTAL")
	local layoutBox3 = api.gui.layout.BoxLayout.new("HORIZONTAL")
	local layoutBox4 = api.gui.layout.BoxLayout.new("HORIZONTAL")
	local reloadButton = api.gui.comp.Button.new(api.gui.comp.TextView.new(i18n.load_file), true)
	reloadButton:onClick(reloadClick)
	
	local cameraButton = api.gui.comp.Button.new(api.gui.comp.TextView.new(i18n.reset_camera), true)
	cameraButton:onClick(function()
			if stationData and stationData.X then
				local posn = api.type.Vec2f.new(stationData.X, stationData.Y)
				cameraController:focus(stationData.groupID)
				cameraController:setCameraData(posn, 0.0, 0, 0)
			end
		end)

	local checkBox_platforms = api.gui.comp.CheckBox.new(i18n.sort)
	checkBox_platforms:setSelected(options.sortByPlatform, false)
	checkBox_platforms:onToggle(function(selected)
		if stationsMenuClicked then
			checkBox_platforms:setSelected(options.sortByPlatform, false)
			return
		end
		options.sortByPlatform = selected
		departureBoard.resetVehiclesList(stationData, 0)
		savedataChanged = true
		end)
	
	local checkBox_origin = api.gui.comp.CheckBox.new(i18n.show_origins)
	checkBox_origin:setSelected(options.showOrigin, false)
	checkBox_origin:onToggle(function(selected)
		if stationsMenuClicked then   -- ignore a false click on an option underneath the stations menu
			checkBox_origin:setSelected(options.showOrigin, false)
			return
		end
		options.showOrigin = selected
		if stationData then
			stationData.incDestinationChoice = false
		end
		departureBoard.resetVehiclesList(stationData, 1)
		savedataChanged = true
		end)

	local checkBox_linename = api.gui.comp.CheckBox.new(i18n.show_linename)
	checkBox_linename:setSelected(options.showLineName, false)
	checkBox_linename:onToggle(function(selected)
		if stationsMenuClicked then   -- ignore a false click on an option underneath the stations menu
			checkBox_linename:setSelected(options.showLineName, false)
			return
		end
		options.showLineName = selected
		if stationData then
			stationData.incDestinationChoice = false
		end
		departureBoard.resetVehiclesList(stationData, 1)
		savedataChanged = true
		end)

	local checkBox_camera = api.gui.comp.CheckBox.new(i18n.station_camera)
	checkBox_camera:setSelected(options.moveCamera, false)
	checkBox_camera:onToggle(function(selected)
		if stationsMenuClicked then
			checkBox_camera:setSelected(options.moveCamera, false)
			return
		end
		options.moveCamera = selected
		savedataChanged = true
		end)

	local checkBox_occupancy = api.gui.comp.CheckBox.new(i18n.show_occupancy)
	checkBox_occupancy:setSelected(options.showOccupancy, false)
	checkBox_occupancy:onToggle(function(selected)
		if stationsMenuClicked then
			checkBox_occupancy:setSelected(options.showOccupancy, false)
			return
		end
		options.showOccupancy = selected
		departureBoard.resetVehiclesList(stationData, 0)
		savedataChanged = true
		end)

	local cargoToggleGroup = api.gui.comp.ToggleButtonGroup.new(0, 0, false)
	cargoToggleGroup:add(api.gui.comp.ToggleButton.new(api.gui.comp.TextView.new(i18n.passengers)))
	cargoToggleGroup:add(api.gui.comp.ToggleButton.new(api.gui.comp.TextView.new(i18n.cargo)))
	cargoToggleGroup:add(api.gui.comp.ToggleButton.new(api.gui.comp.TextView.new(i18n.both)))
	cargoToggleGroup:setOneButtonMustAlwaysBeSelected(true)
	if options.cargoStations == nil then
		options.cargoStations = 2
	end
	local selectedButton = cargoToggleGroup:getButton(options.cargoStations)
	selectedButton:setSelected(true, false)
	cargoToggleGroup:onCurrentIndexChanged(function(index)
		options.cargoStations = index
		updateStatonList()
		end)
	
	local spinSize = api.gui.util.Size.new(50,24)
	local textLabel1 = api.gui.comp.TextView.new(i18n.minimum_lines)
	local spinMinLines = api.gui.comp.DoubleSpinBox.new()
	spinMinLines:setMinimum(1, false)
	spinMinLines:setMaximum(20, false)
	spinMinLines:setMaximumSize(spinSize)
	if options.minimumLines == nil then
		options.minimumLines = 1
	end
	spinMinLines:setValue(options.minimumLines, false)
	spinMinLines:onChange(function(value)
		options.minimumLines = value
		updateStatonList()
		end)
	layoutBox3:addItem(spinMinLines)
	layoutBox3:addItem(textLabel1)
	
	local textLabel2 = api.gui.comp.TextView.new(i18n.maximum_via)
	local spinMaxVia = api.gui.comp.DoubleSpinBox.new()
	spinMaxVia:setMinimum(0, false)
	spinMaxVia:setMaximum(3, false)
	spinMaxVia:setMaximumSize(spinSize)
	if options.maxVia == nil then
		options.maxVia = 2
	end
	spinMaxVia:setValue(options.maxVia, false)
	spinMaxVia:onChange(function(value)
		options.maxVia = value
		if stationData then
			stationData.incDestinationChoice = false
		end
		departureBoard.resetVehiclesList(stationData, 1)
		end)
	layoutBox4:addItem(spinMaxVia)
	layoutBox4:addItem(textLabel2)
	
	stationsMenu = api.gui.comp.ComboBox.new()
	local comboSize = api.gui.util.Size.new(160,32)
	stationsMenu:setMinimumSize(comboSize)
	fileNameField = api.gui.comp.TextInputField.new("<filename>")
	fileNameField:onEnter(reloadClick)
	fileNameField:setText(options.lineDataFile,true)
	errorField = api.gui.comp.TextView.new("")
	
	controlWindow = api.gui.comp.Window.new(i18n.title, layoutBox)
	layoutBox:addItem(stationsMenu)
	layoutBox:addItem(selectModes)
	layoutBox:addItem(cargoToggleGroup)
	
	layoutBox2:addItem(reloadButton)
	layoutBox2:addItem(fileNameField)
	layoutBox:addItem(layoutBox2)
	layoutBox:addItem(cameraButton)
	
	layoutBox:addItem(checkBox_platforms)
	layoutBox:addItem(checkBox_linename)
	layoutBox:addItem(checkBox_origin)
	layoutBox:addItem(checkBox_occupancy)
	layoutBox:addItem(checkBox_camera)
	layoutBox:addItem(layoutBox4)
	layoutBox:addItem(layoutBox3)
	layoutBox:addItem(errorField)
	stationsMenu:onIndexChanged(changeStation)
	controlWindow:addHideOnCloseHandler()
	controlWindow:setMovable(true)
	controlWindow:setResizable(true)
	controlWindow:setVisible(false,false)

	local gameui = api.gui.util.getGameUI()
	local renderer = gameui:getMainRendererComponent()
	cameraController = renderer:getCameraController()
end


function data()
    return {       
        handleEvent = function (filename, id, name, param)
            if name == "savedataUpdate" then
                if savedata == nil then savedata = {options = {}} end
                savedata.options = param
            end
        end,

        save = function()
			return savedata
        end,

        load = function(loaddata)
			if displayWindow and displayWindow:isVisible() then return end
            if loaddata ~= nil and savedataChanged == false then
				if loaddata.options ~= nil then
					savedata = loaddata
					options = loaddata.options
					departureBoard.Options(options)
				end
			end
        end,
		
        guiUpdate = function()
            if not displayWindow then
				initGUI()
				initData(options.lineDataFile)
				departureBoard.Init(i18n, displayWindow, textView)
				departureBoard.Options(options)
            end

			if savedataChanged == true then
				savedataChanged = false
				api.cmd.sendCommand(
					api.cmd.make.sendScriptEvent("DepartureBoard", "update", "savedataUpdate", options),
					function() savedataChanged = false end)
				departureBoard.Options(options)
				nextTime = 0
			end
			local now = api.engine.getComponent(0,16).gameTime
			if now > nextTime then    -- only run the mod code every 500mS
				local speedup = api.engine.getComponent(0,15).speedup
				if speedup == 0 then
					speedup = 1
				end
				nextTime = now + 500 * speedup    -- mS 
				stationsMenuClicked = false
				if displayWindow:isVisible() then
					departureBoard.DoDepartures(stationData, lineDataTable)
					
					local rect = displayWindow:getContentRect()
					if rect.w ~= options.displayWindowWidth then
						options.displayWindowWidth = rect.w
						savedataChanged = true   -- display Window width has changed
					end
				end
				if errorTimeout >0 then
					errorTimeout = errorTimeout - 1
					if errorTimeout == 0 then
						errorField:setText("")
					end
				end
			end
        end
    }
end
