---@author CARTOK
local enums = {}

--- Enumerators for TransportModes
-- This is based on data from testing and here: https://transportfever2.com/wiki/api/modules/api.type.html#enum.TransportMode
-- Adjusted by 1 to account for LUA arrays starting at 1, as returned when using the following call: api.engine.getComponent(line_id, api.type.ComponentType.LINE)
-- This is useful when you want to identify the type of a line.
--
-- api.engine.getComponent(line_id, api.type.ComponentType.LINE)
-- vehicleInfo = {
--    transportModes = {
--      [1]  = 0, PERSON
--      [2]  = 0, CARGO
--      [3]  = 0, CAR
--      [4]  = 0, BUS
--      [5]  = 0, TRUCK
--      [6]  = 0, TRAM
--      [7]  = 0, ELECTRIC_TRAM
--      [8]  = 0, TRAIN
--      [9]  = 0, ELECTRIC_TRAIN
--      [10] = 0, AIRCRAFT
--      [11] = 0, SHIP
--      [12] = 0, SMALL_AIRCRAFT
--      [13] = 0, SMALL_SHIP
--      [14] = 0, (UNKNOWN14)
--      [15] = 0, (UNKNOWN15)
--      [16] = 0, (UNKNOWN16)
--    },
--
-- TODO: For some reason I'm unable to use the api.type.enum value directly, and must thus use hardcoded values. Why?
enums.TransportModes = {
    PERSON = 1, -- api.type.enum.TransportMode.PERSON + 1
    CARGO = 2, -- api.type.enum.TransportMode.CARGO + 1
    CAR = 3, -- api.type.enum.TransportMode.CAR + 1
    BUS = 4, -- api.type.enum.TransportMode.BUS + 1
    TRUCK = 5, -- api.type.enum.TransportMode.TRUCK + 1
    TRAM = 6, -- api.type.enum.TransportMode.TRAM + 1
    ELECTRIC_TRAM = 7, -- api.type.enum.TransportMode.ELECTRIC_TRAM + 1
    TRAIN = 8, -- api.type.enum.TransportMode.TRAIN + 1
    ELECTRIC_TRAIN = 9, -- api.type.enum.TransportMode.ELECTRIC_TRAIN + 1
    AIRCRAFT = 10, -- api.type.enum.TransportMode.AIRCRAFT + 1
    SHIP = 11, -- api.type.enum.TransportMode.SHIP + 1
    SMALL_AIRCRAFT = 12, -- api.type.enum.TransportMode.SMALL_AIRCRAFT + 1
    SMALL_SHIP = 13, -- api.type.enum.TransportMode.SMALL_SHIP + 1
}

-- Enumerator for CargoTypes
--
-- api.engine.getComponent(vehicle_id, api.type.ComponentType.TRANSPORT_VEHICLE)
-- config = {
--    capacities = {
--      [1]  = 0, PASSENGERS
--      [2]  = 0, LOGS
--      [3]  = 0, COAL
--      [4]  = 0, IRON_ORE
--      [5]  = 0, STONE
--      [6]  = 0, GRAIN
--      [7]  = 0, CRUDE_OIL
--      [8]  = 0, STEEL
--      [9]  = 0, PLANKS
--      [10] = 0, PLASTIC
--      [11] = 0, OIL
--      [12] = 0, CONSTRUCTION_MATERIAL
--      [13] = 0, MACHINES
--      [14] = 0, FUEL
--      [15] = 0, TOOLS
--      [16] = 0, FOOD
--      [17] = 0, GOODS
--    },
--
enums.CargoTypes = {
    PASSENGERS = 1,
    LOGS = 2,
    COAL = 3,
    IRON_ORE = 4,
    STONE = 5,
    GRAIN = 6,
    CRUDE_OIL = 7,
    STEEL = 8,
    PLANKS = 9,
    PLASTIC = 10,
    OIL = 11,
    CONSTRUCTION_MATERIAL = 12,
    MACHINES = 13,
    FUEL = 14,
    TOOLS = 15,
    FOOD = 16,
    GOODS = 17,
}

return enums
