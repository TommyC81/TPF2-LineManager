---@author CARTOK
-- Contains code from 'TPF2-Timetables' created by Celmi, available here: https://steamcommunity.com/workshop/filedetails/?id=2408373260 and source https://github.com/IncredibleHannes/TPF2-Timetables
-- General Transport Fever 2 API documentation can be found here: https://transportfever2.com/wiki/api/index.html
local log = {}

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

local currentLogLevel = DEFAULT
local showExtendedLineInfo = false

log.levels = {
    TRACE = TRACE,
    DEBUG = DEBUG,
    INFO = INFO,
    WARN = WARN,
    ERROR = ERROR,
}

---@param level number (Optional) The logging level, refer to log.levels for applicable levels, default is 'INFO' (3).
---Set the logging level to be used, this filters what messages are shown in the in-game console.
function log.setLevel(level)
    currentLogLevel = level or DEFAULT
    log.info("Logging level set to: " .. levelNames[currentLogLevel])
end

---@param param boolean (optional) whether extended line info should used, default is false
---set whether extended line info should be used
function log.setShowExtendedLineInfo(param)
    if (param ~= nil ) then
        showExtendedLineInfo = param
    else
        showExtendedLineInfo = false
    end
    log.info("ShowExtendedLineInfo set to: " .. tostring(showExtendedLineInfo))
end

---@return boolean : whether current logging level is 'DEBUG' or greater
---used to determine whether debug messages should be displayed in the in-game console
function log.isDebugging()
    return currentLogLevel <= DEBUG
end

---@return boolean : whether the option to show extended line info is selected
---used to determine whether extended line info messages should be displayed in the in-game console
function log.isShowExtendedLineInfo()
    return currentLogLevel <= INFO and showExtendedLineInfo
end

---@param level number message level
---@param message string the message
---Sends a message of the specified level to the in-game console. Refer to log.levels for applicable levels.
function log.log(level, message)
    if level >= currentLogLevel then
        print('[LineManager][' .. os.date('%H:%M:%S') .. '][' .. levelNames[level] .. '] ' .. message) -- Date/time output shortened from %Y-%m-%d %H:%M:%S
    end
end

---@param message string The message.
---Send a 'TRACE' message to the in-game console (only displayed if logging level is 'TRACE').
function log.trace(message)
    log.log(TRACE, message)
end

---@param message string The message.
---Send a 'DEBUG' message to the in-game console (only displayed if logging level is 'DEBUG' or greater).
function log.debug(message)
    log.log(DEBUG, message)
end

---@param message string The message.
---Send a 'INFO' message to the in-game console (only displayed if logging level is 'INFO' or greater).
function log.info(message)
    log.log(INFO, message)
end

---@param message string The message.
---Send a 'INFO' message to the in-game console (only displayed if logging level is 'INFO' or greater, and showExtendedLineInfo is true).
function log.lineInfo(message)
    if showExtendedLineInfo then
        log.log(INFO, message)
    end
end

---@param message string The message.
---Send a 'WARN' message to the in-game console (only displayed if logging level is 'WARN' or greater).
function log.warn(message)
    log.log(WARN, message)
end

---@param message string The message.
---Send a 'ERROR' message to the in-game console (only displayed if logging level is 'ERROR' or greater).
function log.error(message)
    log.log(ERROR, message)
end

return log
