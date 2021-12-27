-- Contains code from https://github.com/IncredibleHannes/TPF2-Timetables
---@author CARTOK expanded with some additional functions and tweaks

local logging = {}

local TRACE = 1
local DEBUG = 2
local INFO = 3
local WARN = 4
local ERROR = 5

local DEFAULT = INFO

local levelNames = {
    [TRACE] = 'TRACE',
    [DEBUG] = 'DEBUG',
    [INFO] = 'INFO',
    [WARN] = 'WARN',
    [ERROR] = 'ERROR',
}

logging.levels = {
    TRACE = TRACE,
    DEBUG = DEBUG,
    INFO = INFO,
    WARN = WARN,
    ERROR = ERROR,
}

local currentLogLevel = INFO
local verboseDebugging = true

function logging.setLevel( level )
    currentLogLevel = level or DEFAULT
end

function setVerboseDebugging( verbose )
    verboseDebugging = verbose
end

function logging.isDebugging()
    return currentLogLevel >= DEBUG
end

function logging.isVerboseDebugging()
    return currentLogLevel >= DEBUG and verboseDebugging
end

function logging.log( level, message )
    if level >= currentLogLevel then
        print( '[LineManager][' .. os.date( '%H:%M:%S' ) .. '][' .. levelNames[level] .. '] ' .. message ) -- Date/time output shortened from %Y-%m-%d %H:%M:%S
    end
end

function logging.trace( message )
    logging.log( TRACE, message )
end

function logging.debug( message )
    logging.log( DEBUG, message )
end

function logging.info( message )
    logging.log( INFO, message )
end

function logging.warn( message )
    logging.log( WARN, message )
end

function logging.error( message )
    logging.log( ERROR, message )
end

return logging
