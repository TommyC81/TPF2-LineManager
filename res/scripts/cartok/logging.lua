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

---@param level number (Optional) The logging level, refer to logging.levels for applicable levels, default is 'INFO' (3).
---Set the logging level to be used, this filters what messages are shown in the in-game console.
function logging.setLevel(level)
    currentLogLevel = level or DEFAULT
end

---@param verbose boolean (Optional) Whether verbose debug messages should be used, default is true.
---Set whether verbose debugging messages should be used.
function logging.setVerboseDebugging(verbose)
    verboseDebugging = verbose or true
end

---@return boolean isDebugging Whether current logging level is 'DEBUG' or greater.
---Used to check if logging level is debugging or greater. Useful for determining if extended debug messages should be prepared for displaying in the in-game console.
function logging.isDebugging()
    return currentLogLevel >= DEBUG
end

---@return boolean isVerboseDebugging Whether current logging level is 'DEBUG' or greater.
---Used to check if logging level is debugging or greater and verbose debugging messages should be used. Useful for determining if extended debug messages should be prepared for displaying in the in-game console.
function logging.isVerboseDebugging()
    return currentLogLevel >= DEBUG and verboseDebugging
end

---@param level number message level
---@param message string the message
---Sends a message of the specified level to the in-game console. Refer to logging.levels for applicable levels.
function logging.log(level, message)
    if level >= currentLogLevel then
        print('[LineManager][' .. os.date('%H:%M:%S') .. '][' .. levelNames[level] .. '] ' .. message) -- Date/time output shortened from %Y-%m-%d %H:%M:%S
    end
end

---@param message string The message.
---Send a 'TRACE' message to the in-game console (only displayed if logging level is 'TRACE').
function logging.trace(message)
    logging.log(TRACE, message)
end

---@param message string The message.
---Send a 'DEBUG' message to the in-game console (only displayed if logging level is 'DEBUG' or greater).
function logging.debug(message)
    logging.log(DEBUG, message)
end

---@param message string The message.
---Send a 'INFO' message to the in-game console (only displayed if logging level is 'INFO' or greater).
function logging.info(message)
    logging.log(INFO, message)
end

---@param message string The message.
---Send a 'WARN' message to the in-game console (only displayed if logging level is 'WARN' or greater).
function logging.warn(message)
    logging.log(WARN, message)
end

---@param message string The message.
---Send a 'ERROR' message to the in-game console (only displayed if logging level is 'ERROR' or greater).
function logging.error(message)
    logging.log(ERROR, message)
end

return logging
