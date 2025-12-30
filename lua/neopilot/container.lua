-- Dependency injection container for Neopilot
-- Provides modern, testable architecture with proper separation of concerns
local M = {}

local log = require('neopilot.log')

-- Dependency container
local container = {}
local service_registry = {}
local factory_registry = {}
local instance_registry = {}
local singleton_registry = {}

-- Service lifecycle types
M.LIFECYCLE = {
    SINGLETON = 'singleton',
    TRANSIENT = 'transient',
    SCOPED = 'scoped'
}

-- Initialize the container
function M.setup()
    container = {}
    service_registry = {}
    factory_registry = {}
    instance_registry = {}
    singleton_registry = {}
    
    log.info("Dependency injection container initialized")
end

-- Register a service with the container
function M.register(name, factory, opts)
    opts = opts or {}
    
    if type(factory) ~= 'function' then
        error("Factory must be a function")
    end
    
    service_registry[name] = {
        factory = factory,
        lifecycle = opts.lifecycle or M.LIFECYCLE.TRANSIENT,
        dependencies = opts.dependencies or {},
        tags = opts.tags or {}
    }
    
    log.debug(string.format("Registered service '%s' with lifecycle '%s'", name, opts.lifecycle or M.LIFECYCLE.TRANSIENT))
    
    return M
end

-- Register a singleton service
function M.register_singleton(name, factory, opts)
    opts = opts or {}
    opts.lifecycle = M.LIFECYCLE.SINGLETON
    return M.register(name, factory, opts)
end

-- Register a transient service
function M.register_transient(name, factory, opts)
    opts = opts or {}
    opts.lifecycle = M.LIFECYCLE.TRANSIENT
    return M.register(name, factory, opts)
end

-- Register a scoped service
function M.register_scoped(name, factory, opts)
    opts = opts or {}
    opts.lifecycle = M.LIFECYCLE.SCOPED
    return M.register(name, factory, opts)
end

-- Register a factory function for complex construction
function M.register_factory(name, factory_fn)
    factory_registry[name] = factory_fn
    log.debug(string.format("Registered factory '%s'", name))
    return M
end

-- Resolve a service from the container
function M.resolve(name, context)
    context = context or {}
    
    -- Check factory registry first
    if factory_registry[name] then
        return factory_registry[name](context)
    end
    
    -- Check service registry
    local service_def = service_registry[name]
    if not service_def then
        error(string.format("Service '%s' not registered", name))
    end
    
    -- Handle singleton lifecycle
    if service_def.lifecycle == M.LIFECYCLE.SINGLETON then
        if not singleton_registry[name] then
            singleton_registry[name] = M.create_instance(name, service_def, context)
        end
        return singleton_registry[name]
    end
    
    -- Handle transient lifecycle
    if service_def.lifecycle == M.LIFECYCLE.TRANSIENT then
        return M.create_instance(name, service_def, context)
    end
    
    -- Handle scoped lifecycle
    if service_def.lifecycle == M.LIFECYCLE.SCOPED then
        local scope_key = context.scope or 'default'
        if not instance_registry[scope_key] then
            instance_registry[scope_key] = {}
        end
        
        if not instance_registry[scope_key][name] then
            instance_registry[scope_key][name] = M.create_instance(name, service_def, context)
        end
        
        return instance_registry[scope_key][name]
    end
    
    error(string.format("Unknown lifecycle type: %s", service_def.lifecycle))
end

-- Create an instance of a service
function M.create_instance(name, service_def, context)
    local dependencies = {}
    
    -- Resolve dependencies
    for _, dep_name in ipairs(service_def.dependencies) do
        dependencies[dep_name] = M.resolve(dep_name, context)
    end
    
    -- Create instance
    local success, instance = pcall(service_def.factory, dependencies, context)
    if not success then
        error(string.format("Failed to create instance of '%s': %s", name, tostring(instance)))
    end
    
    log.debug(string.format("Created instance of '%s'", name))
    return instance
end

-- Check if a service is registered
function M.is_registered(name)
    return service_registry[name] ~= nil or factory_registry[name] ~= nil
end

-- Get service definition
function M.get_definition(name)
    return service_registry[name]
end

-- Get all registered services
function M.get_services()
    local services = {}
    for name, _ in pairs(service_registry) do
        table.insert(services, name)
    end
    for name, _ in pairs(factory_registry) do
        table.insert(services, name)
    end
    return services
end

-- Get services by tag
function M.get_services_by_tag(tag)
    local services = {}
    for name, def in pairs(service_registry) do
        for _, service_tag in ipairs(def.tags) do
            if service_tag == tag then
                table.insert(services, name)
                break
            end
        end
    end
    return services
end

-- Clear scoped instances
function M.clear_scope(scope)
    scope = scope or 'default'
    instance_registry[scope] = nil
    log.debug(string.format("Cleared scope '%s'", scope))
end

-- Clear all instances
function M.clear_all_instances()
    instance_registry = {}
    singleton_registry = {}
    log.debug("Cleared all instances")
end

-- Remove a service registration
function M.unregister(name)
    service_registry[name] = nil
    factory_registry[name] = nil
    singleton_registry[name] = nil
    
    -- Clear from all scopes
    for scope, instances in pairs(instance_registry) do
        instances[name] = nil
    end
    
    log.debug(string.format("Unregistered service '%s'", name))
end

-- Create a child container
function M.create_child()
    local child = {
        parent = M,
        service_registry = vim.deepcopy(service_registry),
        factory_registry = vim.deepcopy(factory_registry),
        instance_registry = {},
        singleton_registry = {}
    }
    
    -- Copy methods
    for method_name, method in pairs(M) do
        if type(method) == 'function' and method_name ~= 'create_child' then
            child[method_name] = function(...)
                return method(child, ...)
            end
        end
    end
    
    return child
end

-- Health check for the container
function M.get_health_status()
    local service_count = 0
    local singleton_count = 0
    local scoped_count = 0
    local transient_count = 0
    
    for _, def in pairs(service_registry) do
        service_count = service_count + 1
        if def.lifecycle == M.LIFECYCLE.SINGLETON then
            singleton_count = singleton_count + 1
        elseif def.lifecycle == M.LIFECYCLE.SCOPED then
            scoped_count = scoped_count + 1
        elseif def.lifecycle == M.LIFECYCLE.TRANSIENT then
            transient_count = transient_count + 1
        end
    end
    
    local active_singletons = 0
    for _, _ in pairs(singleton_registry) do
        active_singletons = active_singletons + 1
    end
    
    return {
        total_services = service_count,
        singleton_services = singleton_count,
        scoped_services = scoped_count,
        transient_services = transient_count,
        active_singletons = active_singletons,
        factory_count = vim.tbl_count(factory_registry)
    }
end

-- Dependency injection builder for fluent interface
local Builder = {}
Builder.__index = Builder

function M.builder()
    local self = setmetatable({}, Builder)
    self.services = {}
    return self
end

function Builder:add(name, factory, opts)
    table.insert(self.services, {
        name = name,
        factory = factory,
        opts = opts or {}
    })
    return self
end

function Builder:add_singleton(name, factory, opts)
    opts = opts or {}
    opts.lifecycle = M.LIFECYCLE.SINGLETON
    return self:add(name, factory, opts)
end

function Builder:add_transient(name, factory, opts)
    opts = opts or {}
    opts.lifecycle = M.LIFECYCLE.TRANSIENT
    return self:add(name, factory, opts)
end

function Builder:build()
    for _, service in ipairs(self.services) do
        M.register(service.name, service.factory, service.opts)
    end
    return M
end

-- Utility functions for common patterns

-- Create a service that depends on configuration
function M.create_config_service(config_module)
    return function(deps, context)
        return config_module
    end
end

-- Create a service that depends on logging
function M.create_logging_service(log_module)
    return function(deps, context)
        return log_module
    end
end

-- Create a service with event system integration
function M.create_event_service(events_module)
    return function(deps, context)
        return events_module.create_emitter(context.source or 'service')
    end
end

-- Create a service with error handling
function M.create_safe_service(factory, error_handler)
    return function(deps, context)
        local success, result = pcall(factory, deps, context)
        if not success then
            if error_handler then
                return error_handler(result, context)
            else
                error(result)
            end
        end
        return result
    end
end

-- Auto-wiring helper
function M.auto_wire(module_name, module_table)
    local services = {}
    
    for name, func in pairs(module_table) do
        if type(func) == 'function' and not name:match('^_') then
            local service_name = module_name .. '.' .. name
            
            -- Try to determine dependencies from function signature
            local dependencies = {}
            local func_info = debug.getinfo(func)
            if func_info and func_info.what == 'Lua' then
                -- This is a simplified approach - in practice, you might want
                -- more sophisticated dependency detection
                local params = M.get_function_parameters(func)
                dependencies = params
            end
            
            M.register(service_name, function(deps, context)
                return func(deps, context)
            end, {
                dependencies = dependencies,
                tags = { 'auto-wired', module_name }
            })
            
            table.insert(services, service_name)
        end
    end
    
    return services
end

-- Get function parameters (simplified implementation)
function M.get_function_parameters(func)
    -- This is a basic implementation - in practice, you might want
    -- to use more sophisticated parameter detection
    local params = {}
    local func_str = string.dump(func)
    
    -- This is a placeholder - real implementation would parse the bytecode
    -- or use other methods to extract parameter names
    
    return params
end

-- Setup default core services
function M.setup_core_services()
    -- Configuration service
    M.register_singleton('config', function(deps, context)
        return require('neopilot.config')
    end, { tags = { 'core' } })
    
    -- Logging service
    M.register_singleton('log', function(deps, context)
        return require('neopilot.log')
    end, { tags = { 'core' } })
    
    -- Event system
    M.register_singleton('events', function(deps, context)
        return require('neopilot.events')
    end, { tags = { 'core' } })
    
    -- Error handler
    M.register_singleton('error_handler', function(deps, context)
        return require('neopilot.error')
    end, { tags = { 'core' } })
    
    -- Treesitter integration
    M.register_transient('treesitter', function(deps, context)
        return require('neopilot.treesitter')
    end, { tags = { 'core' } })
    
    -- Server management
    M.register_singleton('server', function(deps, context)
        return require('neopilot.server')
    end, { tags = { 'core' } })
    
    -- Core completion service
    M.register_scoped('core', function(deps, context)
        local core = require('neopilot.core')
        -- Initialize with injected dependencies
        core.setup({
            config = deps.config,
            log = deps.log,
            events = deps.events,
            error_handler = deps.error_handler,
            treesitter = deps.treesitter,
            server = deps.server
        })
        return core
    end, { 
        dependencies = { 'config', 'log', 'events', 'error_handler', 'treesitter', 'server' },
        tags = { 'core' }
    })
    
    log.info("Core services registered with dependency injection")
end

return M
