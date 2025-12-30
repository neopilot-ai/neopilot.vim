-- Performance optimization module for Neopilot
-- Provides intelligent caching, throttling, and adaptive performance management
local M = {}

local log = require('neopilot.log')
local events = require('neopilot.events')

-- Performance metrics tracking
local metrics = {
    request_times = {},
    cache_hits = 0,
    cache_misses = 0,
    total_requests = 0,
    error_count = 0,
    memory_usage = {},
    performance_scores = {}
}

-- Performance configuration
local config = {
    enable_adaptive_throttling = true,
    enable_intelligent_caching = true,
    enable_memory_optimization = true,
    cache_ttl = 30000,
    max_cache_size = 100,
    request_timeout = 5000,
    performance_window = 60000, -- 1 minute
    memory_threshold = 50 * 1024 * 1024, -- 50MB
    adaptive_thresholds = {
        fast_response = 100, -- ms
        slow_response = 1000, -- ms
        high_error_rate = 0.1, -- 10%
        memory_pressure = 0.8 -- 80%
    }
}

-- Intelligent cache with LRU eviction
local IntelligentCache = {}
IntelligentCache.__index = IntelligentCache

function IntelligentCache.new(opts)
    opts = opts or {}
    local self = setmetatable({}, IntelligentCache)
    
    self.cache = {}
    self.access_order = {}
    self.max_size = opts.max_size or config.max_cache_size
    self.ttl = opts.ttl or config.cache_ttl
    self.hit_count = 0
    self.miss_count = 0
    
    return self
end

function IntelligentCache:get(key)
    local entry = self.cache[key]
    
    if not entry then
        self.miss_count = self.miss_count + 1
        events.emit(events.EVENT_TYPES.CACHE_MISS, { key = key }, { source = 'performance' })
        return nil
    end
    
    -- Check TTL
    if vim.loop.now() - entry.timestamp > self.ttl then
        self:remove(key)
        self.miss_count = self.miss_count + 1
        events.emit(events.EVENT_TYPES.CACHE_MISS, { key = key }, { source = 'performance' })
        return nil
    end
    
    -- Update access order (LRU)
    self:update_access_order(key)
    self.hit_count = self.hit_count + 1
    events.emit(events.EVENT_TYPES.CACHE_HIT, { key = key }, { source = 'performance' })
    
    return entry.data
end

function IntelligentCache:set(key, data)
    -- Remove existing entry if present
    if self.cache[key] then
        self:remove(key)
    end
    
    -- Evict if necessary
    while #self.access_order >= self.max_size do
        local oldest_key = table.remove(self.access_order, 1)
        self.cache[oldest_key] = nil
    end
    
    -- Add new entry
    self.cache[key] = {
        data = data,
        timestamp = vim.loop.now()
    }
    table.insert(self.access_order, key)
end

function IntelligentCache:remove(key)
    self.cache[key] = nil
    for i, k in ipairs(self.access_order) do
        if k == key then
            table.remove(self.access_order, i)
            break
        end
    end
end

function IntelligentCache:update_access_order(key)
    for i, k in ipairs(self.access_order) do
        if k == key then
            table.remove(self.access_order, i)
            table.insert(self.access_order, key)
            break
        end
    end
end

function IntelligentCache:clear()
    self.cache = {}
    self.access_order = {}
end

function IntelligentCache:get_stats()
    local total = self.hit_count + self.miss_count
    local hit_rate = total > 0 and (self.hit_count / total) or 0
    
    return {
        size = #self.access_order,
        hit_count = self.hit_count,
        miss_count = self.miss_count,
        hit_rate = hit_rate,
        max_size = self.max_size
    }
end

-- Adaptive request throttling
local AdaptiveThrottler = {}
AdaptiveThrottler.__index = AdaptiveThrottler

function AdaptiveThrottler.new(opts)
    opts = opts or {}
    local self = setmetatable({}, AdaptiveThrottler)
    
    self.min_interval = opts.min_interval or 50
    self.max_interval = opts.max_interval or 5000
    self.current_interval = self.min_interval
    self.last_request = 0
    self.response_times = {}
    self.error_count = 0
    self.success_count = 0
    
    return self
end

function AdaptiveThrottler:should_throttle()
    local now = vim.loop.now()
    return (now - self.last_request) < self.current_interval
end

function AdaptiveThrottler:record_response(response_time, success)
    table.insert(self.response_times, response_time)
    
    -- Keep only recent responses
    if #self.response_times > 10 then
        table.remove(self.response_times, 1)
    end
    
    if success then
        self.success_count = self.success_count + 1
        self.error_count = 0
    else
        self.error_count = self.error_count + 1
    end
    
    self:adjust_interval()
end

function AdaptiveThrottler:adjust_interval()
    local avg_response_time = 0
    if #self.response_times > 0 then
        local sum = 0
        for _, time in ipairs(self.response_times) do
            sum = sum + time
        end
        avg_response_time = sum / #self.response_times
    end
    
    -- Adjust based on response time and error rate
    if avg_response_time > config.adaptive_thresholds.slow_response then
        self.current_interval = math.min(self.current_interval * 1.5, self.max_interval)
    elseif avg_response_time < config.adaptive_thresholds.fast_response then
        self.current_interval = math.max(self.current_interval * 0.8, self.min_interval)
    end
    
    -- Adjust for errors
    local error_rate = self.error_count / (self.success_count + self.error_count + 1)
    if error_rate > config.adaptive_thresholds.high_error_rate then
        self.current_interval = math.min(self.current_interval * 2, self.max_interval)
    end
end

function AdaptiveThrottler:get_wait_time()
    local now = vim.loop.now()
    local time_since_last = now - self.last_request
    local wait_time = math.max(0, self.current_interval - time_since_last)
    
    self.last_request = now + wait_time
    return wait_time
end

-- Memory optimization manager
local MemoryManager = {}
MemoryManager.__index = MemoryManager

function MemoryManager.new(opts)
    opts = opts or {}
    local self = setmetatable({}, MemoryManager)
    
    self.threshold = opts.threshold or config.memory_threshold
    self.cleanup_interval = opts.cleanup_interval or 30000
    self.last_cleanup = 0
    
    return self
end

function MemoryManager:check_memory_pressure()
    local current_memory = collectgarbage('count') * 1024 -- Convert to bytes
    return current_memory > self.threshold
end

function MemoryManager:optimize_memory()
    local now = vim.loop.now()
    
    -- Don't cleanup too frequently
    if now - self.last_cleanup < self.cleanup_interval then
        return false
    end
    
    self.last_cleanup = now
    
    -- Force garbage collection
    collectgarbage('collect')
    collectgarbage('collect')
    
    -- Emit memory optimization event
    events.emit(events.EVENT_TYPES.MEMORY_OPTIMIZED, {
        memory_before = collectgarbage('count') * 1024,
        memory_after = collectgarbage('count') * 1024
    }, { source = 'performance' })
    
    return true
end

-- Performance score calculator
local PerformanceScorer = {}
PerformanceScorer.__index = PerformanceScorer

function PerformanceScorer.new()
    local self = setmetatable({}, PerformanceScorer)
    self.scores = {}
    return self
end

function PerformanceScorer:calculate_score(operation, metrics)
    local score = 100 -- Start with perfect score
    
    -- Deduct points for slow response times
    if metrics.response_time then
        if metrics.response_time > config.adaptive_thresholds.slow_response then
            score = score - 30
        elseif metrics.response_time > config.adaptive_thresholds.fast_response then
            score = score - 10
        end
    end
    
    -- Deduct points for errors
    if metrics.error then
        score = score - 50
    end
    
    -- Deduct points for cache misses
    if metrics.cache_miss then
        score = score - 5
    end
    
    -- Ensure score is within bounds
    score = math.max(0, math.min(100, score))
    
    self.scores[operation] = score
    return score
end

function PerformanceScorer:get_score(operation)
    return self.scores[operation] or 100
end

function PerformanceScorer:get_average_score()
    local total = 0
    local count = 0
    
    for _, score in pairs(self.scores) do
        total = total + score
        count = count + 1
    end
    
    return count > 0 and (total / count) or 100
end

-- Main performance manager
local performance_manager = {
    cache = IntelligentCache.new(),
    throttler = AdaptiveThrottler.new(),
    memory_manager = MemoryManager.new(),
    scorer = PerformanceScorer.new()
}

-- Initialize performance system
function M.setup(opts)
    opts = opts or {}
    config = vim.tbl_extend('force', config, opts)
    
    -- Setup periodic cleanup
    vim.defer_fn(function()
        M.periodic_cleanup()
    end, config.cleanup_interval or 60000)
    
    log.info("Performance optimization system initialized")
end

-- Get performance manager instance
function M.get_manager()
    return performance_manager
end

-- Cache operations
function M.cache_get(key)
    if not config.enable_intelligent_caching then
        return nil
    end
    
    return performance_manager.cache:get(key)
end

function M.cache_set(key, data)
    if not config.enable_intelligent_caching then
        return
    end
    
    performance_manager.cache:set(key, data)
end

function M.cache_clear()
    performance_manager.cache:clear()
end

function M.cache_stats()
    return performance_manager.cache:get_stats()
end

-- Throttling operations
function M.should_throttle()
    if not config.enable_adaptive_throttling then
        return false
    end
    
    return performance_manager.throttler:should_throttle()
end

function M.get_throttle_wait_time()
    if not config.enable_adaptive_throttling then
        return 0
    end
    
    return performance_manager.throttler:get_wait_time()
end

function M.record_request_performance(response_time, success)
    if config.enable_adaptive_throttling then
        performance_manager.throttler:record_response(response_time, success)
    end
    
    -- Update metrics
    table.insert(metrics.request_times, {
        time = response_time,
        success = success,
        timestamp = vim.loop.now()
    })
    
    -- Keep only recent metrics
    local cutoff = vim.loop.now() - config.performance_window
    metrics.request_times = vim.tbl_filter(function(m)
        return m.timestamp > cutoff
    end, metrics.request_times)
    
    -- Update counters
    metrics.total_requests = metrics.total_requests + 1
    if not success then
        metrics.error_count = metrics.error_count + 1
    end
    
    -- Calculate performance score
    local score = performance_manager.scorer:calculate_score('completion', {
        response_time = response_time,
        error = not success
    })
    
    events.emit(events.EVENT_TYPES.PERFORMANCE_METRIC, {
        operation = 'completion',
        response_time = response_time,
        success = success,
        score = score
    }, { source = 'performance' })
end

-- Memory management
function M.check_memory_pressure()
    if not config.enable_memory_optimization then
        return false
    end
    
    return performance_manager.memory_manager:check_memory_pressure()
end

function M.optimize_memory()
    if not config.enable_memory_optimization then
        return false
    end
    
    return performance_manager.memory_manager:optimize_memory()
end

-- Performance metrics
function M.get_performance_metrics()
    local cache_stats = performance_manager.cache:get_stats()
    local avg_response_time = 0
    local recent_requests = 0
    local recent_errors = 0
    
    if #metrics.request_times > 0 then
        local total_time = 0
        local cutoff = vim.loop.now() - config.performance_window
        
        for _, req in ipairs(metrics.request_times) do
            if req.timestamp > cutoff then
                total_time = total_time + req.time
                recent_requests = recent_requests + 1
                if not req.success then
                    recent_errors = recent_errors + 1
                end
            end
        end
        
        avg_response_time = recent_requests > 0 and (total_time / recent_requests) or 0
    end
    
    return {
        cache = cache_stats,
        requests = {
            total = metrics.total_requests,
            recent = recent_requests,
            recent_errors = recent_errors,
            avg_response_time = avg_response_time
        },
        memory = {
            current = collectgarbage('count') * 1024,
            threshold = config.memory_threshold
        },
        performance_score = performance_manager.scorer:get_average_score()
    }
end

-- Performance optimization for large files
function M.optimize_for_large_files(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    
    if line_count > 1000 then
        -- Enable performance optimizations for large files
        log.info(string.format("Enabling large file optimizations for %d lines", line_count))
        
        -- Increase cache TTL for large files
        performance_manager.cache.ttl = config.cache_ttl * 2
        
        -- Reduce context window
        -- This would need to be implemented in the core module
        
        -- Enable more aggressive caching
        performance_manager.cache.max_size = config.max_cache_size * 2
        
        return true
    end
    
    return false
end

-- Adaptive request throttling based on system performance
function M.adaptive_throttle()
    local perf_metrics = M.get_performance_metrics()
    
    -- Adjust throttling based on performance score
    if perf_metrics.performance_score < 50 then
        -- Poor performance, increase throttling
        performance_manager.throttler.current_interval = 
            math.min(performance_manager.throttler.current_interval * 1.5, 
                    performance_manager.throttler.max_interval)
    elseif perf_metrics.performance_score > 80 then
        -- Good performance, reduce throttling
        performance_manager.throttler.current_interval = 
            math.max(performance_manager.throttler.current_interval * 0.8, 
                    performance_manager.throttler.min_interval)
    end
    
    -- Adjust for memory pressure
    if M.check_memory_pressure() then
        performance_manager.throttler.current_interval = 
            math.min(performance_manager.throttler.current_interval * 2, 
                    performance_manager.throttler.max_interval)
        M.optimize_memory()
    end
end

-- Periodic cleanup and optimization
function M.periodic_cleanup()
    -- Clean up old metrics
    local cutoff = vim.loop.now() - config.performance_window * 2
    metrics.request_times = vim.tbl_filter(function(m)
        return m.timestamp > cutoff
    end, metrics.request_times)
    
    -- Memory optimization
    M.optimize_memory()
    
    -- Adaptive throttling
    M.adaptive_throttle()
    
    -- Schedule next cleanup
    vim.defer_fn(function()
        M.periodic_cleanup()
    end, config.cleanup_interval or 60000)
end

-- Performance health check
function M.get_health_status()
    local perf_metrics = M.get_performance_metrics()
    local status = 'healthy'
    local message = 'Performance is optimal'
    
    if perf_metrics.performance_score < 30 then
        status = 'critical'
        message = 'Performance is severely degraded'
    elseif perf_metrics.performance_score < 60 then
        status = 'warning'
        message = 'Performance is degraded'
    elseif perf_metrics.cache.hit_rate < 0.5 then
        status = 'warning'
        message = 'Low cache hit rate'
    elseif perf_metrics.memory.current > perf_metrics.memory.threshold then
        status = 'warning'
        message = 'High memory usage'
    end
    
    return status, message, perf_metrics
end

-- Performance profiling
function M.start_profiling(operation)
    return {
        operation = operation,
        start_time = vim.loop.hrtime()
    }
end

function M.end_profiling(profile)
    local end_time = vim.loop.hrtime()
    local duration = (end_time - profile.start_time) / 1000000 -- Convert to ms
    
    M.record_request_performance(duration, true)
    
    return {
        operation = profile.operation,
        duration = duration
    }
end

return M
