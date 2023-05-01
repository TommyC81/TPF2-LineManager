--[[

General Transport Fever 2 API documentation can be found here: https://transportfever2.com/wiki/api/index.html

** GENERAL USEFUL COMMANDS **

Get all player lines
  api.engine.system.lineSystem.getLinesForPlayer( api.engine.util.getPlayer() )

Get information about a specific line (make sure to replace "line_id")
  api.engine.getComponent(line_id, api.type.ComponentType.LINE)

Get vehicles of a specific line (make sure to replace "line_id")
  api.engine.system.transportVehicleSystem.getLineVehicles( line_id )

Get transport vehicle info (make sure to replace "vehicle_id")
  api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)

Or combine the above two commands into one call using the first line (make sure to replace "line_id")
  api.engine.getComponent( api.engine.system.transportVehicleSystem.getLineVehicles( line_id )[1], api.type.ComponentType.TRANSPORT_VEHICLE )

Get CARGO for a line (make sure to replace "line_id")
  api.engine.system.simCargoSystem.getSimCargosForLine(line_id)

Get PASSENGERS for a line (make sure to replace "line_id")
  api.engine.system.simPersonSystem.getSimPersonsForLine(line_id)

Get general information via game.interface
  game.interface.getEntity(entity_id)

game.interface functions:
addPlayer
book
buildConstruction
bulldoze
clearJournal
findPath
getBuildingType
getBuildingTypes
getCargoType
getCargoTypes
getCompanyScore
getConstructionEntity
getDateFromNowPlusOffsetDays
getDepots
getDestinationDataPerson
getEntities
getEntity
getGameDifficulty
getGameSpeed
getGameTime
getHeight
getIndustryProduction
getIndustryProductionLimit
getIndustryShipping
getIndustryTransportRating
getLines
getLog
getMillisPerDay
getName
getPlayer
getPlayerJournal
getStationTransportSamples
getStations
getTownCapacities
getTownCargoSupplyAndLimit
getTownEmission
getTownReachability
getTownTrafficRating
getTownTransportSamples
getTowns
getVehicles
getWorld
replaceVehicle
setBuildInPauseModeAllowed
setBulldozeable
setDate
setGameSpeed
setMarker
setMaximumLoan
setMillisPerDay
setMinimumLoan
setMissionState
setName
setPlayer
setTownCapacities
setTownDevelopmentActive
setZone
spawnAnimal
startEvent
upgradeConstruction

** OUTPUT/STRUCTURE FROM VARIOUS COMMANDS **

>> api.engine.getComponent( 27606, api.type.ComponentType.LINE )
{
    stops = {
      [1] = {
        stationGroup = 27600,
        station = 1,
        terminal = 0,
        loadMode = 0,
        minWaitingTime = 0,
        maxWaitingTime = 180,
        waypoints = {
        },
        stopConfig = userdata: 000001594A7AAAA8,
      },
      [2] = {
        stationGroup = 27613,
        station = 1,
        terminal = 0,
        loadMode = 0,
        minWaitingTime = 0,
        maxWaitingTime = 180,
        waypoints = {
        },
        stopConfig = userdata: 000001594A7AADA8,
      },
      [3] = {
        stationGroup = 27617,
        station = 0,
        terminal = 0,
        loadMode = 0,
        minWaitingTime = 0,
        maxWaitingTime = 180,
        waypoints = {
        },
        stopConfig = userdata: 000001594A7AABE8,
      },
    },
    waitingTime = 180,
    vehicleInfo = {
      transportModes = {
        [1]  = 0, (PERSON)
        [2]  = 0, (CARGO)
        [3]  = 0, (CAR)
        [4]  = 0, (BUS)
        [5]  = 0, (TRUCK)
        [6]  = 0, (TRAM)
        [7]  = 1, (ELECTRIC_TRAM)
        [8]  = 0, (TRAIN)
        [9]  = 0, (ELECTRIC_TRAIN)
        [10] = 0, (AIRCRAFT)
        [11] = 0, (SHIP)
        [12] = 0, (SMALL_AIRCRAFT)
        [13] = 0, (SMALL_SHIP)
        [14] = 0, (UNKNOWN)
        [15] = 0, (UNKNOWN)
        [16] = 0, (UNKNOWN)
      },
      defaultPrice = 28.375745773315,
    },
  }

>> api.engine.system.transportVehicleSystem.getLineVehicles( 27606 )
{
  [1] = 27602,
}

>> api.engine.getComponent( 27602, api.type.ComponentType.TRANSPORT_VEHICLE )
{
  carrier = 2,
  transportVehicleConfig = {
    vehicles = {
      [1] = {
        part = {
          modelId = 3576,
          reversed = false,
          loadConfig = {
            [1] = 0,
          },
          color = {
            x = -1,
            y = -1,
            z = -1,
          },
          logo = "",
        },
        purchaseTime = 12417800,
        maintenanceState = 0,
        targetMaintenanceState = 0,
        autoLoadConfig = {
          [1] = 1,
        },
      },
    },
    vehicleGroups = {
      [1] = 1,
    },
  },
  config = {
    allCaps = { (These are theoretical capacities that may not be in use)
      [1]  = 27, (PASSENGERS)
      [2]  = 0,
      [3]  = 0,
      [4]  = 0,
      [5]  = 0, (STONE)
      [6]  = 0,
      [7]  = 0, (CRUDE_OIL)
      [8]  = 0,
      [9]  = 0,
      [10] = 0,
      [11] = 0, (OIL)
      [12] = 0,
      [13] = 0,
      [14] = 0, (FUEL)
      [15] = 0,
      [16] = 0,
      [17] = 0,
    },
    capacities = { (These are capacities that are currently in use)
      [1]  = 27, (PASSENGERS)
      [2]  = 0,
      [3]  = 0,
      [4]  = 0,
      [5]  = 0, (STONE)
      [6]  = 0,
      [7]  = 0, (CRUDE_OIL)
      [8]  = 0,
      [9]  = 0,
      [10] = 0,
      [11] = 0, (OIL)
      [12] = 0,
      [13] = 0,
      [14] = 0, (FUEL)
      [15] = 0,
      [16] = 0,
      [17] = 0,
    },
    loadSpeeds = {
      [1]  = 7, (PASSENGERS)
      [2]  = 0,
      [3]  = 0,
      [4]  = 0,
      [5]  = 0, (STONE)
      [6]  = 0,
      [7]  = 0, (CRUDE_OIL)
      [8]  = 0,
      [9]  = 0,
      [10] = 0,
      [11] = 0, (OIL)
      [12] = 0,
      [13] = 0,
      [14] = 0, (FUEL)
      [15] = 0,
      [16] = 0,
      [17] = 0,
    },
    reversible = false,
  },
  state = 1,
  userStopped = false,
  depot = 26683,
  sellOnArrival = false,
  line = 27606,
  stopIndex = 2,
  lineStopDepartures = {
    [1] = 128385000,
    [2] = 128428000,
    [3] = 128307800,
  },
  lastLineStopDeparture = 128261400,
  sectionTimes = {
    [1] = 38.400001525879,
    [2] = 42.000003814697,
    [3] = 72,
  },
  timeUntilLoad = -2.3969392776489,
  timeUntilCloseDoors = -0.067628532648087,
  timeUntilDeparture = -0.067628294229507,
  noPath = false,
  daysInDepot = 0,
  daysAtTerminal = 3,
  doorsOpen = false,
  doorsTime = 128426800000,
  autoDeparture = true,
}

 >> game.interface.getEntity(49361) -- LINE
{
  frequency = 0.0051652891561389,
  id = 49361,
  itemsTransported = {
    TOOLS = 21078,
    _lastMonth = {
      TOOLS = 0,
      _sum = 0,
    },
    _lastYear = {
      TOOLS = 52,
      _sum = 52,
    },
    _sum = 21078,
  },
  name = "LINE_NAME_IS_HERE",
  rate = 113,
  stops = { 153626, 154288, 135644, },
  type = "LINE",
}

>> game.interface.getEntity(153626) -- STATION_GROUP
{
  cargoWaiting = {
    TOOLS = 13,
  },
  id = 153626,
  itemsLoaded = {
    TOOLS = 21624,
    _lastMonth = {
      TOOLS = 16,
      _sum = 16,
    },
    _lastYear = {
      TOOLS = 49,
      _sum = 49,
    },
    _sum = 21624,
  },
  itemsUnloaded = {
    _lastMonth = {
      _sum = 0,
    },
    _lastYear = {
      _sum = 0,
    },
    _sum = 0,
  },
  name = "Lower Lancaster",
  position = { -834.7138671875, 1089.4582519531, 6.6564912796021, },
  stations = { 154209, },
  type = "STATION_GROUP",
}

>> game.interface.getEntity(154209) -- STATION
{
  cargo = true,
  carriers = {
    ROAD = true,
  },
  id = 154209,
  name = "Lower Lancaster",
  position = { -834.7138671875, 1089.4582519531, 6.6564912796021, },
  stationGroup = 153626,
  town = 115551,
  type = "STATION",
}

>> api.engine.getComponent(153626, api.type.ComponentType.STATION_GROUP)
{
  stations = {
    [1] = 154209,
  },
}

>> api.engine.getComponent(154209, api.type.ComponentType.STATION)
{
  cargo = true,
  terminals = {
    [1] = {
      tag = -1,
      personNodes = {
        [1] = {
          new = nil,
          entity = 153918,
          index = 37,
        },
        [2] = {
          new = nil,
          entity = 153918,
          index = 41,
        },
        [3] = {
          new = nil,
          entity = 153918,
          index = 52,
        },
        [4] = {
          new = nil,
          entity = 153918,
          index = 60,
        },
        [5] = {
          new = nil,
          entity = 153918,
          index = 68,
        },
        [6] = {
          new = nil,
          entity = 153918,
          index = 76,
        },
      },
      personEdges = {
        [1] = {
          new = nil,
          entity = 153918,
          index = 43,
        },
        [2] = {
          new = nil,
          entity = 153918,
          index = 44,
        },
        [3] = {
          new = nil,
          entity = 153918,
          index = 56,
        },
        [4] = {
          new = nil,
          entity = 153918,
          index = 57,
        },
        [5] = {
          new = nil,
          entity = 153918,
          index = 64,
        },
        [6] = {
          new = nil,
          entity = 153918,
          index = 65,
        },
        [7] = {
          new = nil,
          entity = 153918,
          index = 72,
        },
        [8] = {
          new = nil,
          entity = 153918,
          index = 73,
        },
        [9] = {
          new = nil,
          entity = 153918,
          index = 83,
        },
        [10] = {
          new = nil,
          entity = 153918,
          index = 84,
        },
      },
      vehicleNodeId = {
        new = nil,
        entity = 153918,
        index = 59,
      },
    },
    [2] = {
      tag = 0,
      personNodes = {
        [1] = {
          new = nil,
          entity = 153918,
          index = 45,
        },
        [2] = {
          new = nil,
          entity = 153918,
          index = 48,
        },
        [3] = {
          new = nil,
          entity = 153918,
          index = 56,
        },
        [4] = {
          new = nil,
          entity = 153918,
          index = 64,
        },
        [5] = {
          new = nil,
          entity = 153918,
          index = 72,
        },
        [6] = {
          new = nil,
          entity = 153918,
          index = 79,
        },
      },
      personEdges = {
        [1] = {
          new = nil,
          entity = 153918,
          index = 50,
        },
        [2] = {
          new = nil,
          entity = 153918,
          index = 51,
        },
        [3] = {
          new = nil,
          entity = 153918,
          index = 60,
        },
        [4] = {
          new = nil,
          entity = 153918,
          index = 61,
        },
        [5] = {
          new = nil,
          entity = 153918,
          index = 68,
        },
        [6] = {
          new = nil,
          entity = 153918,
          index = 69,
        },
        [7] = {
          new = nil,
          entity = 153918,
          index = 76,
        },
        [8] = {
          new = nil,
          entity = 153918,
          index = 77,
        },
        [9] = {
          new = nil,
          entity = 153918,
          index = 90,
        },
        [10] = {
          new = nil,
          entity = 153918,
          index = 91,
        },
      },
      vehicleNodeId = {
        new = nil,
        entity = 153918,
        index = 62,
      },
    },
  },
  tag = 0,
}

>> api.engine.getComponent(167376, api.type.ComponentType.SIM_CARGO)
{
  cargoType = 6,
  targetEntity = 59452,
  sourceEntity = 26410,
  speed = 0,
  vehicleUsed = false,
  startTime = 411732800,
}

 >> api.engine.getComponent(167376, api.type.ComponentType.SIM_CARGO_AT_TERMINAL)
{
  edgeId = {
    new = nil,
    entity = 148820,
    index = 104,
  },
  place = 7,
}

>> api.engine.getComponent(139193, api.type.ComponentType.SIM_ENTITY_AT_TERMINAL)
{
  line = 172847,
  lineStop0 = 1,
  lineStop1 = 0,
  arrivalTime = 411731400,
  vehicle = -1,
}

]]
