-- Public Lua API for Neopilot
local M = {}

local core = require('neopilot.core')
local config = require('neopilot.config')
local server = require('neopilot.server')

function M.setup()
    -- No setup needed
end

-- Check if Neopilot is enabled
function M.is_enabled()
    return config.is_enabled()
end

-- Get the last completion item that was displayed
function M.get_last_completion()
    return core.get_current_completion_item()
end

-- Manually trigger a completion request
function M.request_completions()
    core.request_completions()
end

-- Get the status of the plugin and server
function M.get_status()
    return {
        enabled = config.is_enabled(),
        server_running = server.is_running(),
    }
end

return M
