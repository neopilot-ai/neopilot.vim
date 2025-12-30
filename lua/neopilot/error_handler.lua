-- Enhanced error handling and recovery system
local M = {}

local log = require('neopilot.log')
local events = require('neopilot.events')

-- Error categories
local ERROR_CATEGORIES = {
    NETWORK = 'network',
    SERVER = 'server', 
    CONFIG = 'config',
    LSP = 'lsp',
    UI = 'ui',
    COMPLETION = 'completion',
    UNKNOWN = 'unknown'
}

-- Error tracking
local error_stats = {
    total = 0,
    by_category = {},
    recent = {},
    max_recent = 100
}

-- Recovery strategies
local recovery_strategies = {}

-- Initialize error handler
function M.setup()
    -- Setup error tracking
    for _, category in pairs(ERROR_CATEGORIES) do
        error_stats.by_category[category] = 0
    end
    
    -- Register default recovery strategies
    M.register_recovery_strategy('network', M.recover_network_error)
    M.register_recovery_strategy('server', M.recover_server_error)
    M.register_recovery_strategy('config', M.recover_config_error)
    
    log.info("Error handling system initialized")
end

-- Handle an error with categorization and recovery
function M.handle_error(error_msg, context, category)
    context = context or {}
    category = category or M.categorize_error(error_msg, context)
    
    -- Update error stats
    error_stats.total = error_stats.total + 1
    error_stats.by_category[category] = (error_stats.by_category[category] or 0) + 1
    
    -- Add to recent errors
    table.insert(error_stats.recent, {
        message = error_msg,
        context = context,
        category = category,
        timestamp = vim.loop.now()
    })
    
    -- Limit recent errors
    if #error_stats.recent > error_stats.max_recent then
        table.remove(error_stats.recent, 1)
    end
    
    -- Log the error
    log.error(string.format("[%s] %s", category:upper(), error_msg))
    
    -- Emit error event
    events.emit(events.EVENT_TYPES.ERROR_OCCURRED, {
        message = error_msg,
        context = context,
        category = category
    }, { source = 'error_handler' })
    
    -- Attempt recovery
    local recovered = M.attempt_recovery(category, error_msg, context)
    
    if recovered then
        log.info(string.format("Recovered from %s error: %s", category, error_msg))
        events.emit(events.EVENT_TYPES.ERROR_RECOVERED, {
            message = error_msg,
            category = category,
            recovery_strategy = recovered
        }, { source = 'error_handler' })
    end
    
    return recovered
end

-- Categorize error based on message and context
function M.categorize_error(error_msg, context)
    local msg_lower = error_msg:lower()
    
    -- Network errors
    if msg_lower:match('connection') or msg_lower:match('timeout') or msg_lower:match('network') then
        return ERROR_CATEGORIES.NETWORK
    end
    
    -- Server errors
    if msg_lower:match('server') or context.server_error or context.server_response then
        return ERROR_CATEGORIES.SERVER
    end
    
    -- Config errors
    if msg_lower:match('config') or context.config_key or context.validation_error then
        return ERROR_CATEGORIES.CONFIG
    end
    
    -- LSP errors
    if msg_lower:match('lsp') or context.lsp_client or context.lsp_method then
        return ERROR_CATEGORIES.LSP
    end
    
    -- UI errors
    if msg_lower:match('ui') or context.ui_component or context.render_error then
        return ERROR_CATEGORIES.UI
    end
    
    -- Completion errors
    if msg_lower:match('completion') or context.completion_request or context.completion_response then
        return ERROR_CATEGORIES.COMPLETION
    end
    
    return ERROR_CATEGORIES.UNKNOWN
end

-- Register a recovery strategy
function M.register_recovery_strategy(category, strategy_fn)
    if not recovery_strategies[category] then
        recovery_strategies[category] = {}
    end
    table.insert(recovery_strategies[category], strategy_fn)
end

-- Attempt recovery using registered strategies
function M.attempt_recovery(category, error_msg, context)
    local strategies = recovery_strategies[category]
    if not strategies then
        return false
    end
    
    for _, strategy in ipairs(strategies) do
        local ok, result = pcall(strategy, error_msg, context)
        if ok and result then
            return result
        end
    end
    
    return false
end

-- Recovery strategies
function M.recover_network_error(error_msg, context)
    -- Retry with exponential backoff
    if context.retry_count and context.retry_count < 3 then
        local delay = 1000 * (2 ^ context.retry_count)
        vim.defer_fn(function()
            -- Trigger retry
            events.emit('neopilot:retry_request', context)
        end, delay)
        return 'retry_with_backoff'
    end
    
    return false
end

function M.recover_server_error(error_msg, context)
    -- Restart server if needed
    if error_msg:match('server not running') then
        events.emit('neopilot:restart_server', {})
        return 'server_restart'
    end
    
    return false
end

function M.recover_config_error(error_msg, context)
    -- Reset to defaults for config errors
    if context.config_key then
        local config = require('neopilot.config_v2')
        config.reset()
        return 'config_reset'
    end
    
    return false
end

-- Get error statistics
function M.get_error_stats()
    return vim.deepcopy(error_stats)
end

-- Clear error statistics
function M.clear_error_stats()
    error_stats.total = 0
    error_stats.recent = {}
    for category, _ in pairs(error_stats.by_category) do
        error_stats.by_category[category] = 0
    end
end

-- Check if we're in error storm (too many errors recently)
function M.is_error_storm()
    local recent_count = 0
    local now = vim.loop.now()
    local storm_window = 30000 -- 30 seconds
    
    for _, error_info in ipairs(error_stats.recent) do
        if now - error_info.timestamp < storm_window then
            recent_count = recent_count + 1
        end
    end
    
    return recent_count > 10
end

-- Graceful degradation
function M.enable_graceful_degradation()
    -- Disable non-essential features
    local config = require('neopilot.config_v2')
    config.set('enable_caching', false, 'error_recovery')
    config.set('lsp_context', false, 'error_recovery')
    
    log.warn("Enabled graceful degradation mode")
end

return M
