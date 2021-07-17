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

function logging.setLevel(level)
  currentLogLevel = level
end

function logging.log(level, message)
  if level >= currentLogLevel then
    print('[LineManager][' .. os.date('%Y-%m-%d %H:%M:%S') .. '][' .. levelNames[level] .. '] ' .. message)
  end
end

function logging.trace(message)
  logging.log(TRACE, message)
end

function logging.debug(message)
  logging.log(DEBUG, message)
end

function logging.info(message)
  logging.log(INFO, message)
end

function logging.warn(message)
  logging.log(WARN, message)
end

function logging.error(message)
  logging.log(ERROR, message)
end

return logging