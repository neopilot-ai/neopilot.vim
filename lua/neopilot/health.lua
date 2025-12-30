-- Neopilot health check module
local M = {}

local config = require('neopilot.config')
local util = require('neopilot.util')
local log = require('neopilot.log')

local checks = {}

-- Check Neovim version
local function check_neovim_version()
    if util.has_supported_version() then
        return { status = 'OK', message = 'Neovim version is supported (>= 0.6.0)' }
    else
        return { status = 'ERROR', message = 'Neovim version is not supported. Please upgrade to 0.6.0 or later.' }
    end
end

-- Check for curl dependency
local function check_curl()
    if vim.fn.executable('curl') == 1 then
        return { status = 'OK', message = 'curl executable found.' }
    else
        return { status = 'ERROR', message = 'curl executable not found. It is required for authentication.' }
    end
end

-- Check authentication status
local function check_auth()
    local api_key = config.get('api_key')
    if api_key and api_key ~= '' then
        return { status = 'OK', message = 'API key is configured.' }
    else
        return { status = 'WARN', message = 'API key is not configured. Run :Neopilot Auth to authenticate.' }
    end
end

-- Check server status (placeholder)
local function check_server()
    -- This is a placeholder until server.lua is implemented
    -- In the future, this will call server.is_running()
    return { status = 'INFO', message = 'Server status check is not yet implemented.' }
end

-- Check configuration loading
local function check_config()
    if config.get('idle_delay') then
        return { status = 'OK', message = 'Configuration loaded successfully.' }
    else
        return { status = 'ERROR', message = 'Configuration could not be loaded.' }
    end
end

-- Run all health checks
function M.check()
    log.info('Running Neopilot health check')
    local report = {
        { name = 'Neovim Version', check_func = check_neovim_version },
        { name = 'Dependencies', check_func = check_curl },
        { name = 'Configuration', check_func = check_config },
        { name = 'Authentication', check_func = check_auth },
        { name = 'Server', check_func = check_server },
    }

    local results = {}
    local has_error = false

    for _, item in ipairs(report) do
        local result = item.check_func()
        table.insert(results, string.format('[%s] %s: %s', result.status, item.name, result.message))
        if result.status == 'ERROR' then
            has_error = true
        end
    end

    -- Display the report in a new buffer
    vim.api.nvim_command('new')
    vim.api.nvim_buf_set_option(0, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(0, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(0, 'swapfile', false)
    vim.api.nvim_buf_set_name(0, 'Neopilot Health')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, results)

    if has_error then
        vim.notify('Neopilot health check found errors.', vim.log.levels.ERROR)
    else
        vim.notify('Neopilot health check complete.', vim.log.levels.INFO)
    end
end

return M
