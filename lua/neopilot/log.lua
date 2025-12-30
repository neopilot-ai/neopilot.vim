-- Neopilot logging module
local M = {}

local config = require('neopilot.config')

-- Log levels
local levels = {
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    DEBUG = 4,
    TRACE = 5,
}

local current_level = levels.WARN
local log_file = nil

-- Setup function to initialize logging
function M.setup()
    local level_name = config.get('log_level') or 'WARN'
    current_level = levels[level_name:upper()] or levels.WARN

    local file_path = config.get('log_file')
    if file_path and file_path ~= '' then
        log_file = file_path
    end
end

-- Internal log function
local function log(level, message)
    if level > current_level then
        return
    end

    local level_name = 'UNKNOWN'
    for name, value in pairs(levels) do
        if value == level then
            level_name = name
            break
        end
    end

    local msg = string.format('[%s] [%s] %s', os.date('%Y-%m-%d %H:%M:%S'), level_name, message)

    if log_file then
        local file = io.open(log_file, 'a')
        if file then
            file:write(msg .. '\n')
            file:close()
        else
            vim.notify('Neopilot: Could not write to log file: ' .. log_file, vim.log.levels.ERROR)
        end
    else
        -- Fallback to vim.notify for important messages if no log file is set
        if level <= levels.WARN then
            vim.notify('Neopilot: ' .. message, level == levels.ERROR and vim.log.levels.ERROR or vim.log.levels.WARN)
        end
    end
end

-- Public log functions
function M.error(message)
    log(levels.ERROR, message)
end

function M.warn(message)
    log(levels.WARN, message)
end

function M.info(message)
    log(levels.INFO, message)
end

function M.debug(message)
    log(levels.DEBUG, message)
end

function M.trace(message)
    log(levels.TRACE, message)
end

-- Initialize logging
M.setup()

return M
