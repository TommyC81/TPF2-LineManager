---@author CARTOK
-- Contains code from 'TPF2-Timetables' created by Celmi, available here: https://steamcommunity.com/workshop/filedetails/?id=2408373260 and source https://github.com/IncredibleHannes/TPF2-Timetables
-- General Transport Fever 2 API documentation can be found here: https://transportfever2.com/wiki/api/index.html
local logging = {}

local TRACE = 1
local DEBUG = 2
local INFO = 3
local WARN = 4
local ERROR = 5

local DEFAULT = INFO

logging.levelNames = {
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

logging.currentLogLevel = INFO
logging.verboseDebugging = true

---@param level number (Optional) The logging level, refer to logging.levels for applicable levels, default is 'INFO' (3).
---Set the logging level to be used, this filters what messages are shown in the in-game console.
function logging.setLevel(level)
    logging.currentLogLevel = level or DEFAULT
    logging.info("Logging level set to " .. logging.levelNames[logging.currentLogLevel] .. ".")
end

---@param debugging boolean (Optional) Toggles logging level between DEBUG (true) and INFO (false), default is DEBUG (true).
---Set the logging level to be used, this filters what messages are shown in the in-game console.
function logging.setDebugging(debugging)
    if (debugging) then
        logging.setLevel(logging.levels.DEBUG)
    else
        logging.setLevel(logging.levels.INFO)
    end
end

---@param verbose boolean (Optional) Whether verbose debug messages should be used, default is true.
---Set whether verbose debugging messages should be used.
function logging.setVerboseDebugging(verbose)
    if (verbose ~= nil ) then
        logging.verboseDebugging = verbose
    else
        logging.verboseDebugging = true
    end
    logging.info("VerboseDebugging set to " .. tostring(logging.verboseDebugging) .. ".")
end

---@return boolean isDebugging Whether current logging level is 'DEBUG' or greater.
---Used to check if logging level is debugging or greater. Useful for determining if extended debug messages should be prepared for displaying in the in-game console.
function logging.isDebugging()
    return logging.currentLogLevel >= DEBUG
end

---@return boolean isVerboseDebugging Whether current logging level is 'DEBUG' or greater.
---Used to check if logging level is debugging or greater and verbose debugging messages should be used. Useful for determining if extended debug messages should be prepared for displaying in the in-game console.
function logging.isVerboseDebugging()
    return logging.currentLogLevel >= DEBUG and logging.verboseDebugging
end

---@param level number message level
---@param message string the message
---Sends a message of the specified level to the in-game console. Refer to logging.levels for applicable levels.
function logging.log(level, message)
    if level >= logging.currentLogLevel then
        print('[LineManager][' .. os.date('%H:%M:%S') .. '][' .. logging.levelNames[level] .. '] ' .. message) -- Date/time output shortened from %Y-%m-%d %H:%M:%S
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
