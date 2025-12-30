-- Neopilot configuration module
local M = {}

-- Default configuration
local defaults = {
    enabled = true,
    filetypes = {
        help = false,
        gitcommit = false,
        gitrebase = false,
    },
    idle_delay = 75,
    log_level = 'WARN',
    log_file = '',
    tab_fallback = '', -- Special handling for this one
    cache_ttl = 30000,
    min_request_interval = 50,
    max_cache_size = 50,
    server_path = '',
    log_dir = '',
    ide_name = 'neovim',
}

-- Merged configuration
local config = {}

-- Setup function to merge user config with defaults
function M.setup(user_config)
    user_config = user_config or {}
    config = vim.tbl_deep_extend('force', defaults, vim.g.neopilot_config or {}, user_config)

    -- Also read global variables for non-Lua setup
    config.enabled = vim.g.neopilot_enabled or config.enabled
    config.filetypes = vim.g.neopilot_filetypes or config.filetypes
    config.idle_delay = vim.g.neopilot_idle_delay or config.idle_delay
    config.log_level = vim.g.neopilot_log_level or config.log_level
    config.log_file = vim.g.neopilot_log_file or config.log_file
    config.tab_fallback = vim.g.neopilot_tab_fallback or config.tab_fallback
end

-- Get a configuration value
function M.get(key)
    return config[key]
end

-- Set a configuration value (for testing or runtime changes)
function M.set(key, value)
    config[key] = value
end

-- Check if Neopilot is enabled for the current buffer
function M.is_enabled()
    if not config.enabled or not vim.b.neopilot_enabled then
        return false
    end

    local ft = vim.bo.filetype
    if config.filetypes[ft] == false then
        return false
    end

    if config.filetypes[ft] == true then
        return true
    end

    -- Default to enabled if not specified
    return true
end

-- Initialize with default values
M.setup()

return M
