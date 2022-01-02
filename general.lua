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

** OUTPUT/STRUCTURE FROM VARIOUS COMMANDS **

(All of the below examples are from an ELECTRIC_TRAM line with 1 vehicle on it)

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
    allCaps = {
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
    capacities = {
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

]]
