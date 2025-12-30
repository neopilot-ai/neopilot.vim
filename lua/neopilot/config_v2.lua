-- Enhanced configuration system with validation and schema support
-- Provides robust configuration management for Neopilot
local M = {}

local log = require('neopilot.log')
local events = require('neopilot.events')

-- Configuration schema with validation rules
local schema = {
    enabled = {
        type = 'boolean',
        default = true,
        description = 'Enable/disable Neopilot completion'
    },
    filetypes = {
        type = 'table',
        default = {
            help = false,
            gitcommit = false,
            gitrebase = false,
        },
        description = 'Filetype-specific settings',
        validate = function(value)
            if type(value) ~= 'table' then
                return false, 'filetypes must be a table'
            end
            return true
        end
    },
    idle_delay = {
        type = 'number',
        default = 75,
        min = 0,
        max = 1000,
        description = 'Delay in milliseconds before requesting completion'
    },
    log_level = {
        type = 'string',
        default = 'WARN',
        enum = {'DEBUG', 'INFO', 'WARN', 'ERROR'},
        description = 'Logging level'
    },
    log_file = {
        type = 'string',
        default = '',
        description = 'Path to log file (empty for stdout)'
    },
    tab_fallback = {
        type = 'string',
        default = '',
        description = 'Fallback action when no completion is available'
    },
    cache_ttl = {
        type = 'number',
        default = 30000,
        min = 1000,
        max = 300000,
        description = 'Cache time-to-live in milliseconds'
    },
    min_request_interval = {
        type = 'number',
        default = 50,
        min = 10,
        max = 1000,
        description = 'Minimum interval between requests in milliseconds'
    },
    max_cache_size = {
        type = 'number',
        default = 50,
        min = 1,
        max = 1000,
        description = 'Maximum number of cached completion results'
    },
    server_path = {
        type = 'string',
        default = '',
        description = 'Path to Neopilot server binary'
    },
    log_dir = {
        type = 'string',
        default = '',
        description = 'Directory for log files'
    },
    ide_name = {
        type = 'string',
        default = 'neovim',
        description = 'IDE identifier for server communication'
    },
    -- AI model settings
    model = {
        type = 'string',
        default = 'default',
        description = 'AI model to use for completions'
    },
    temperature = {
        type = 'number',
        default = 0.2,
        min = 0.0,
        max = 2.0,
        description = 'Temperature for AI model (0.0-2.0)'
    },
    max_tokens = {
        type = 'number',
        default = 256,
        min = 1,
        max = 2048,
        description = 'Maximum tokens in completion response'
    },
    top_p = {
        type = 'number',
        default = 0.9,
        min = 0.0,
        max = 1.0,
        description = 'Top-p sampling parameter'
    },
    top_k = {
        type = 'number',
        default = 40,
        min = 1,
        max = 100,
        description = 'Top-k sampling parameter'
    },
    -- Completion settings
    max_completions = {
        type = 'number',
        default = 5,
        min = 1,
        max = 20,
        description = 'Maximum number of completions to request'
    },
    max_newlines = {
        type = 'number',
        default = 5,
        min = 1,
        max = 50,
        description = 'Maximum new lines in completion'
    },
    min_log_probability = {
        type = 'number',
        default = -4.0,
        min = -10.0,
        max = 0.0,
        description = 'Minimum log probability for completions'
    },
    first_temperature = {
        type = 'number',
        default = 0.2,
        min = 0.0,
        max = 2.0,
        description = 'Temperature for first completion'
    },
    api_timeout_ms = {
        type = 'number',
        default = 5000,
        min = 1000,
        max = 30000,
        description = 'API request timeout in milliseconds'
    },
    -- UI settings
    virtual_text = {
        type = 'table',
        default = {},
        description = 'Virtual text configuration',
        validate = function(value)
            return type(value) == 'table', 'virtual_text must be a table'
        end
    },
    ui = {
        type = 'table',
        default = {},
        description = 'UI configuration',
        validate = function(value)
            return type(value) == 'table', 'ui must be a table'
        end
    },
    -- LSP integration
    lsp_integration = {
        type = 'boolean',
        default = true,
        description = 'Enable enhanced LSP integration'
    },
    lsp_context = {
        type = 'boolean',
        default = true,
        description = 'Include LSP context in completion requests'
    },
    -- Performance settings
    enable_caching = {
        type = 'boolean',
        default = true,
        description = 'Enable completion caching'
    },
    enable_debounce = {
        type = 'boolean',
        default = true,
        description = 'Enable request debouncing'
    },
    -- Experimental features
    experimental_features = {
        type = 'table',
        default = {},
        description = 'Experimental feature flags',
        validate = function(value)
            return type(value) == 'table', 'experimental_features must be a table'
        end
    }
}

-- Current configuration state
local config = {}
local config_sources = {} -- Track where each config value came from

-- Configuration change listeners
local change_listeners = {}

-- Initialize configuration system
function M.setup()
    -- Load default configuration
    M.load_defaults()
    
    -- Load configuration from various sources
    M.load_from_global_vars()
    M.load_from_config_file()
    
    -- Validate final configuration
    local valid, errors = M.validate_config(config)
    if not valid then
        error('Configuration validation failed:\n' .. table.concat(errors, '\n'))
    end
    
    log.info("Enhanced configuration system initialized")
end

-- Load default configuration
function M.load_defaults()
    for key, spec in pairs(schema) do
        config[key] = spec.default
        config_sources[key] = 'default'
    end
end

-- Load configuration from global variables (Vimscript compatibility)
function M.load_from_global_vars()
    local global_mappings = {
        neopilot_enabled = 'enabled',
        neopilot_filetypes = 'filetypes',
        neopilot_idle_delay = 'idle_delay',
        neopilot_log_level = 'log_level',
        neopilot_log_file = 'log_file',
        neopilot_tab_fallback = 'tab_fallback',
        neopilot_cache_ttl = 'cache_ttl',
        neopilot_min_request_interval = 'min_request_interval',
        neopilot_max_cache_size = 'max_cache_size',
        neopilot_server_path = 'server_path',
        neopilot_log_dir = 'log_dir',
        neopilot_ide_name = 'ide_name'
    }
    
    for global_var, config_key in pairs(global_mappings) do
        if vim.g[global_var] ~= nil then
            config[config_key] = vim.g[global_var]
            config_sources[config_key] = 'global_var'
        end
    end
end

-- Load configuration from config file
function M.load_from_config_file()
    local config_files = {
        vim.fn.expand('~/.config/neopilot/config.lua'),
        vim.fn.getcwd() .. '/.neopilot.lua',
        vim.fn.stdpath('config') .. '/neopilot.lua'
    }
    
    for _, file in ipairs(config_files) do
        if vim.fn.filereadable(file) == 1 then
            local ok, user_config = pcall(dofile, file)
            if ok and user_config then
                M.merge_user_config(user_config, 'config_file')
                log.info("Loaded configuration from: " .. file)
                break
            else
                log.warn("Failed to load config from " .. file .. ": " .. tostring(user_config))
            end
        end
    end
end

-- Merge user configuration with validation
function M.merge_user_config(user_config, source)
    source = source or 'user'
    local errors = {}
    
    for key, value in pairs(user_config) do
        if not schema[key] then
            table.insert(errors, string.format("Unknown configuration key: %s", key))
        else
            local spec = schema[key]
            local valid, error_msg = M.validate_value(key, value, spec)
            
            if valid then
                local old_value = config[key]
                config[key] = value
                config_sources[key] = source
                
                -- Emit change event
                events.emit(events.EVENT_TYPES.CONFIG_CHANGED, {
                    key = key,
                    old_value = old_value,
                    new_value = value,
                    source = source
                }, { source = 'config' })
                
                -- Notify change listeners
                M.notify_change_listeners(key, old_value, value)
            else
                table.insert(errors, error_msg)
            end
        end
    end
    
    if #errors > 0 then
        error('Configuration merge failed:\n' .. table.concat(errors, '\n'))
    end
end

-- Validate a single configuration value
function M.validate_value(key, value, spec)
    spec = spec or schema[key]
    if not spec then
        return false, string.format("Unknown configuration key: %s", key)
    end
    
    -- Type validation
    if spec.type == 'boolean' and type(value) ~= 'boolean' then
        return false, string.format("%s must be boolean, got %s", key, type(value))
    elseif spec.type == 'number' and type(value) ~= 'number' then
        return false, string.format("%s must be number, got %s", key, type(value))
    elseif spec.type == 'string' and type(value) ~= 'string' then
        return false, string.format("%s must be string, got %s", key, type(value))
    elseif spec.type == 'table' and type(value) ~= 'table' then
        return false, string.format("%s must be table, got %s", key, type(value))
    end
    
    -- Range validation
    if spec.min and value < spec.min then
        return false, string.format("%s must be >= %s, got %s", key, tostring(spec.min), tostring(value))
    end
    if spec.max and value > spec.max then
        return false, string.format("%s must be <= %s, got %s", key, tostring(spec.max), tostring(value))
    end
    
    -- Enum validation
    if spec.enum and not vim.tbl_contains(spec.enum, value) then
        return false, string.format("%s must be one of [%s], got %s", 
            key, table.concat(spec.enum, ', '), tostring(value))
    end
    
    -- Custom validation
    if spec.validate then
        local valid, error_msg = spec.validate(value)
        if not valid then
            return false, string.format("%s validation failed: %s", key, error_msg or 'unknown error')
        end
    end
    
    return true
end

-- Validate entire configuration
function M.validate_config(cfg)
    cfg = cfg or config
    local errors = {}
    
    for key, spec in pairs(schema) do
        if cfg[key] ~= nil then
            local valid, error_msg = M.validate_value(key, cfg[key], spec)
            if not valid then
                table.insert(errors, error_msg)
            end
        end
    end
    
    return #errors == 0, errors
end

-- Get configuration value
function M.get(key)
    return config[key]
end

-- Set configuration value with validation
function M.set(key, value, source)
    source = source or 'runtime'
    
    local valid, error_msg = M.validate_value(key, value)
    if not valid then
        error(error_msg)
    end
    
    local old_value = config[key]
    config[key] = value
    config_sources[key] = source
    
    -- Emit change event
    events.emit(events.EVENT_TYPES.CONFIG_CHANGED, {
        key = key,
        old_value = old_value,
        new_value = value,
        source = source
    }, { source = 'config' })
    
    -- Notify change listeners
    M.notify_change_listeners(key, old_value, value)
end

-- Get all configuration
function M.get_all()
    return vim.deepcopy(config)
end

-- Get configuration schema
function M.get_schema()
    return vim.deepcopy(schema)
end

-- Get configuration source for a key
function M.get_source(key)
    return config_sources[key]
end

-- Reset configuration to defaults
function M.reset()
    local old_config = vim.deepcopy(config)
    M.load_defaults()
    
    -- Emit reset event
    events.emit(events.EVENT_TYPES.CONFIG_RESET, {
        old_config = old_config,
        new_config = vim.deepcopy(config)
    }, { source = 'config' })
end

-- Add configuration change listener
function M.on_change(key, callback)
    if not change_listeners[key] then
        change_listeners[key] = {}
    end
    
    table.insert(change_listeners[key], callback)
end

-- Remove configuration change listener
function M.remove_change_listener(key, callback)
    if change_listeners[key] then
        for i, listener in ipairs(change_listeners[key]) do
            if listener == callback then
                table.remove(change_listeners[key], i)
                break
            end
        end
    end
end

-- Notify change listeners
function M.notify_change_listeners(key, old_value, new_value)
    if change_listeners[key] then
        for _, callback in ipairs(change_listeners[key]) do
            local ok, err = pcall(callback, key, old_value, new_value)
            if not ok then
                log.error(string.format("Config change listener error for %s: %s", key, tostring(err)))
            end
        end
    end
end

-- Check if Neopilot is enabled for current buffer
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

    return true
end

-- Get filetype-specific configuration
function M.get_filetype_config(ft)
    ft = ft or vim.bo.filetype
    return config.filetypes[ft] or {}
end

-- Set filetype-specific configuration
function M.set_filetype_config(ft, ft_config)
    if not config.filetypes then
        config.filetypes = {}
    end
    
    config.filetypes[ft] = vim.tbl_extend('force', config.filetypes[ft] or {}, ft_config)
    
    events.emit(events.EVENT_TYPES.CONFIG_CHANGED, {
        key = 'filetypes.' .. ft,
        new_value = ft_config,
        source = 'runtime'
    }, { source = 'config' })
end

-- Export configuration for debugging
function M.export_config()
    return {
        config = vim.deepcopy(config),
        sources = vim.deepcopy(config_sources),
        schema = vim.deepcopy(schema)
    }
end

-- Get configuration documentation
function M.get_documentation()
    local docs = {}
    
    for key, spec in pairs(schema) do
        docs[key] = {
            type = spec.type,
            default = spec.default,
            description = spec.description,
            current = config[key],
            source = config_sources[key]
        }
        
        if spec.min then docs[key].min = spec.min end
        if spec.max then docs[key].max = spec.max end
        if spec.enum then docs[key].enum = spec.enum end
    end
    
    return docs
end

-- Health check for configuration
function M.health_check()
    local health = {
        status = 'ok',
        issues = {},
        warnings = {}
    }
    
    -- Check for required settings
    if not config.server_path or config.server_path == '' then
        table.insert(health.warnings, 'server_path not set - using default path')
    end
    
    -- Check for reasonable values
    if config.idle_delay > 500 then
        table.insert(health.warnings, string.format('High idle_delay (%dms) may cause slow completions', config.idle_delay))
    end
    
    if config.cache_ttl < 5000 then
        table.insert(health.warnings, string.format('Low cache_ttl (%dms) may reduce performance', config.cache_ttl))
    end
    
    -- Check experimental features
    for feature, enabled in pairs(config.experimental_features) do
        if enabled then
            table.insert(health.warnings, string.format('Experimental feature enabled: %s', feature))
        end
    end
    
    if #health.issues > 0 then
        health.status = 'error'
    elseif #health.warnings > 0 then
        health.status = 'warning'
    end
    
    return health
end

-- Legacy compatibility
function M.setup(user_config)
    if user_config then
        M.merge_user_config(user_config, 'setup')
    end
end

return M
