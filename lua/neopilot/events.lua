-- Event system for Neopilot extensibility
-- Provides a robust event-driven architecture for plugins and extensions
local M = {}

local log = require('neopilot.log')

-- Built-in event types
M.EVENT_TYPES = {
    -- Completion events
    BEFORE_REQUEST = 'completion:before_request',
    AFTER_REQUEST = 'completion:after_request',
    COMPLETION_RECEIVED = 'completion:received',
    COMPLETION_SHOWN = 'completion:shown',
    COMPLETION_ACCEPTED = 'completion:accepted',
    COMPLETION_REJECTED = 'completion:rejected',
    
    -- Server events
    SERVER_STARTING = 'server:starting',
    SERVER_STARTED = 'server:started',
    SERVER_STOPPING = 'server:stopping',
    SERVER_STOPPED = 'server:stopped',
    SERVER_ERROR = 'server:error',
    
    -- Error events
    ERROR_OCCURRED = 'error:occurred',
    ERROR_RECOVERED = 'error:recovered',
    
    -- UI events
    UI_OPENED = 'ui:opened',
    UI_CLOSED = 'ui:closed',
    UI_INTERACTION = 'ui:interaction',
    
    -- Configuration events
    CONFIG_CHANGED = 'config:changed',
    CONFIG_LOADED = 'config:loaded',
    
    -- Lifecycle events
    PLUGIN_LOADED = 'plugin:loaded',
    PLUGIN_UNLOADED = 'plugin:unloaded',
    BUFFER_ENTERED = 'buffer:entered',
    BUFFER_LEFT = 'buffer:left',
    
    -- Performance events
    PERFORMANCE_METRIC = 'performance:metric',
    CACHE_HIT = 'performance:cache_hit',
    CACHE_MISS = 'performance:cache_miss',
    
    -- Virtual text events
    VIRTUAL_TEXT_SHOWN = 'virtual_text:shown',
    VIRTUAL_TEXT_CLEARED = 'virtual_text:cleared',
    FLOATING_WINDOW_OPENED = 'virtual_text:floating_opened',
    FLOATING_WINDOW_CLOSED = 'virtual_text:floating_closed',
    DIFF_PREVIEW_SHOWN = 'virtual_text:diff_shown',
    PROGRESS_SHOWN = 'virtual_text:progress_shown',
    
    -- I/O events
    FILE_READ = 'io:file_read',
    FILE_WRITE = 'io:file_write',
    FILE_COPY = 'io:file_copy',
    FILE_READ_ERROR = 'io:file_read_error',
    FILE_WRITE_ERROR = 'io:file_write_error',
    NETWORK_REQUEST = 'io:network_request',
    NETWORK_ERROR = 'io:network_error',
    
    -- Server events
    SERVER_STARTED = 'server:started',
    SERVER_STOPPED = 'server:stopped',
    SERVER_DOWNLOADED = 'server:downloaded',
    SERVER_ERROR = 'server:error'
}

-- Event registry
local event_registry = {}
local event_history = {}
local event_listeners = {}
local middleware_stack = {}

-- Event configuration
local event_config = {
    max_history_size = 1000,
    enable_history = true,
    enable_middleware = true,
    async_events = true,
    event_timeout = 5000 -- 5 seconds
}

-- Initialize event system
function M.setup(opts)
    opts = opts or {}
    event_config = vim.tbl_extend('force', event_config, opts)
    
    event_registry = {}
    event_history = {}
    event_listeners = {}
    middleware_stack = {}
    
    log.info("Event system initialized")
end

-- Register an event listener
function M.on(event_name, callback, opts)
    opts = opts or {}
    
    if type(callback) ~= 'function' then
        error("Callback must be a function")
    end
    
    if not event_registry[event_name] then
        event_registry[event_name] = {}
    end
    
    local listener = {
        id = opts.id or M.generate_listener_id(),
        callback = callback,
        priority = opts.priority or 0,
        once = opts.once or false,
        async = opts.async ~= false, -- Default to async
        timeout = opts.timeout or event_config.event_timeout,
        filter = opts.filter
    }
    
    table.insert(event_registry[event_name], listener)
    
    -- Sort by priority (higher priority first)
    table.sort(event_registry[event_name], function(a, b)
        return a.priority > b.priority
    end)
    
    log.debug(string.format("Registered listener for event '%s' with id '%s'", event_name, listener.id))
    
    return listener.id
end

-- Register a one-time event listener
function M.once(event_name, callback, opts)
    opts = opts or {}
    opts.once = true
    return M.on(event_name, callback, opts)
end

-- Remove an event listener
function M.off(event_name, listener_id)
    if not event_registry[event_name] then
        return false
    end
    
    for i, listener in ipairs(event_registry[event_name]) do
        if listener.id == listener_id then
            table.remove(event_registry[event_name], i)
            log.debug(string.format("Removed listener '%s' for event '%s'", listener_id, event_name))
            return true
        end
    end
    
    return false
end

-- Remove all listeners for an event
function M.off_all(event_name)
    if event_name then
        event_registry[event_name] = nil
        log.debug(string.format("Removed all listeners for event '%s'", event_name))
    else
        event_registry = {}
        log.debug("Removed all event listeners")
    end
end

-- Emit an event
function M.emit(event_name, data, opts)
    opts = opts or {}
    
    local event = {
        name = event_name,
        data = data or {},
        timestamp = vim.loop.now(),
        id = M.generate_event_id(),
        source = opts.source or 'neopilot',
        async = opts.async ~= false and event_config.async_events
    }
    
    -- Add to history if enabled
    if event_config.enable_history then
        M.add_to_history(event)
    end
    
    -- Apply middleware if enabled
    if event_config.enable_middleware then
        event = M.apply_middleware(event)
    end
    
    -- Get listeners for this event
    local listeners = event_registry[event_name] or {}
    
    if #listeners == 0 then
        log.debug(string.format("No listeners for event '%s'", event_name))
        return event
    end
    
    log.debug(string.format("Emitting event '%s' to %d listeners", event_name, #listeners))
    
    -- Execute listeners
    for _, listener in ipairs(listeners) do
        -- Apply filter if present
        if listener.filter and not listener.filter(event.data) then
            goto continue
        end
        
        -- Execute listener
        if event.async then
            M.execute_listener_async(listener, event)
        else
            M.execute_listener_sync(listener, event)
        end
        
        -- Remove if once
        if listener.once then
            M.off(event_name, listener.id)
        end
        
        ::continue::
    end
    
    return event
end

-- Execute listener asynchronously
function M.execute_listener_async(listener, event)
    vim.defer_fn(function()
        M.execute_listener(listener, event)
    end, 0)
end

-- Execute listener synchronously
function M.execute_listener_sync(listener, event)
    M.execute_listener(listener, event)
end

-- Execute a single listener with error handling
function M.execute_listener(listener, event)
    local success, result = pcall(function()
        if listener.timeout and listener.timeout > 0 then
            -- Execute with timeout
            local timer = vim.loop.new_timer()
            local completed = false
            
            timer:start(listener.timeout, 0, function()
                if not completed then
                    log.warn(string.format("Listener '%s' for event '%s' timed out", listener.id, event.name))
                end
                timer:close()
            end)
            
            local function execute()
                completed = true
                timer:stop()
                timer:close()
                return listener.callback(event.data, event)
            end
            
            return execute()
        else
            return listener.callback(event.data, event)
        end
    end)
    
    if not success then
        log.error(string.format("Listener '%s' for event '%s' failed: %s", listener.id, event.name, tostring(result)))
        
        -- Emit error event
        M.emit(M.EVENT_TYPES.ERROR_OCCURRED, {
            listener_id = listener.id,
            event_name = event.name,
            error = result
        }, { source = 'event_system' })
    end
    
    return result
end

-- Add middleware to the processing stack
function M.use(middleware, opts)
    opts = opts or {}
    
    if type(middleware) ~= 'function' then
        error("Middleware must be a function")
    end
    
    local middleware_item = {
        fn = middleware,
        priority = opts.priority or 0,
        id = opts.id or M.generate_middleware_id()
    }
    
    table.insert(middleware_stack, middleware_item)
    
    -- Sort by priority (higher priority first)
    table.sort(middleware_stack, function(a, b)
        return a.priority > b.priority
    end)
    
    log.debug(string.format("Added middleware '%s' to stack", middleware_item.id))
    
    return middleware_item.id
end

-- Apply middleware to an event
function M.apply_middleware(event)
    local modified_event = vim.deepcopy(event)
    
    for _, middleware in ipairs(middleware_stack) do
        local success, result = pcall(middleware.fn, modified_event)
        if success then
            if result then
                modified_event = result
            end
        else
            log.error(string.format("Middleware '%s' failed: %s", middleware.id, tostring(result)))
        end
    end
    
    return modified_event
end

-- Add event to history
function M.add_to_history(event)
    table.insert(event_history, event)
    
    -- Limit history size
    if #event_history > event_config.max_history_size then
        table.remove(event_history, 1)
    end
end

-- Get event history
function M.get_history(opts)
    opts = opts or {}
    
    local history = event_history
    
    -- Filter by event name
    if opts.event_name then
        history = vim.tbl_filter(function(event)
            return event.name == opts.event_name
        end, history)
    end
    
    -- Filter by time range
    if opts.since then
        history = vim.tbl_filter(function(event)
            return event.timestamp >= opts.since
        end, history)
    end
    
    if opts.until_time then
        history = vim.tbl_filter(function(event)
            return event.timestamp <= opts.until_time
        end, history)
    end
    
    -- Limit results
    if opts.limit then
        history = vim.list_slice(history, 1, opts.limit)
    end
    
    return history
end

-- Get listeners for an event
function M.get_listeners(event_name)
    return vim.deepcopy(event_registry[event_name] or {})
end

-- Get all registered events
function M.get_registered_events()
    local events = {}
    for event_name, _ in pairs(event_registry) do
        table.insert(events, event_name)
    end
    return events
end

-- Wait for an event to occur
function M.wait_for(event_name, timeout, filter)
    timeout = timeout or 5000
    local start_time = vim.loop.now()
    
    return coroutine.yield(function(resolve, reject)
        local listener_id
        
        local function check_timeout()
            if vim.loop.now() - start_time >= timeout then
                M.off(event_name, listener_id)
                reject("Timeout waiting for event: " .. event_name)
            else
                vim.defer_fn(check_timeout, 100)
            end
        end
        
        listener_id = M.on(event_name, function(data, event)
            if not filter or filter(data, event) then
                M.off(event_name, listener_id)
                resolve({ data = data, event = event })
            end
        end)
        
        check_timeout()
    end)
end

-- Create an event emitter object
function M.create_emitter(source)
    source = source or 'unknown'
    
    return {
        emit = function(event_name, data, opts)
            opts = opts or {}
            opts.source = source
            return M.emit(event_name, data, opts)
        end,
        
        on = function(event_name, callback, opts)
            return M.on(event_name, callback, opts)
        end,
        
        once = function(event_name, callback, opts)
            return M.once(event_name, callback, opts)
        end,
        
        off = function(event_name, listener_id)
            return M.off(event_name, listener_id)
        end
    }
end

-- Utility functions
function M.generate_listener_id()
    return 'listener_' .. vim.loop.hrtime()
end

function M.generate_event_id()
    return 'event_' .. vim.loop.hrtime()
end

function M.generate_middleware_id()
    return 'middleware_' .. vim.loop.hrtime()
end

-- Debug and diagnostics
function M.get_stats()
    local total_listeners = 0
    for _, listeners in pairs(event_registry) do
        total_listeners = total_listeners + #listeners
    end
    
    return {
        registered_events = #M.get_registered_events(),
        total_listeners = total_listeners,
        history_size = #event_history,
        middleware_count = #middleware_stack,
        config = event_config
    }
end

function M.get_health_status()
    local stats = M.get_stats()
    
    if stats.total_listeners == 0 then
        return "warning", "No event listeners registered"
    elseif stats.total_listeners > 100 then
        return "warning", string.format("High number of listeners: %d", stats.total_listeners)
    else
        return "healthy", string.format("Event system operational with %d listeners", stats.total_listeners)
    end
end

-- Clear event history
function M.clear_history()
    event_history = {}
    log.debug("Event history cleared")
end

-- Reset the entire event system
function M.reset()
    event_registry = {}
    event_history = {}
    event_listeners = {}
    middleware_stack = {}
    log.info("Event system reset")
end

-- Built-in middleware examples

-- Logging middleware
function M.create_logging_middleware(opts)
    opts = opts or {}
    local level = opts.level or 'debug'
    
    return function(event)
        log[level](string.format("Event: %s from %s", event.name, event.source))
        return event
    end
end

-- Performance monitoring middleware
function M.create_performance_middleware()
    return function(event)
        if event.name:match('performance') then
            -- Don't monitor performance events to avoid infinite loops
            return event
        end
        
        local start_time = vim.loop.now()
        
        -- Return a modified event that will track completion
        return vim.tbl_extend('force', event, {
            _performance_start = start_time,
            _performance_callback = function()
                local duration = vim.loop.now() - start_time
                M.emit(M.EVENT_TYPES.PERFORMANCE_METRIC, {
                    event_name = event.name,
                    duration = duration,
                    source = event.source
                }, { source = 'performance_middleware' })
            end
        })
    end
end

-- Filter middleware
function M.create_filter_middleware(filter_fn)
    return function(event)
        if filter_fn(event) then
            return event
        else
            return nil -- Filter out this event
        end
    end
end

-- Transform middleware
function M.create_transform_middleware(transform_fn)
    return function(event)
        return transform_fn(event) or event
    end
end

-- Setup default middleware
function M.setup_default_middleware()
    M.use(M.create_logging_middleware({ level = 'debug' }), { priority = -100 })
    M.use(M.create_performance_middleware(), { priority = -50 })
end

return M
