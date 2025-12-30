-- Neopilot metrics and observability module
local M = {}

local log = require('neopilot.log')

-- Metrics storage
local metrics = {
    cache_hits = 0,
    cache_misses = 0,
    requests_total = 0,
    requests_cancelled = 0,
    requests_dropped = 0,
    response_times = {},
    completion_accepts = 0,
    completion_cycles = 0,
    errors_total = 0,
    start_time = vim.loop.now()
}

-- Configuration
local MAX_RESPONSE_TIME_SAMPLES = 100

-- Record cache hit
function M.record_cache_hit()
    metrics.cache_hits = metrics.cache_hits + 1
end

-- Record cache miss
function M.record_cache_miss()
    metrics.cache_misses = metrics.cache_misses + 1
end

-- Record request start
function M.record_request_start()
    metrics.requests_total = metrics.requests_total + 1
end

-- Record request cancellation
function M.record_request_cancelled()
    metrics.requests_cancelled = metrics.requests_cancelled + 1
end

-- Record request dropped (rate limited)
function M.record_request_dropped()
    metrics.requests_dropped = metrics.requests_dropped + 1
end

-- Record response time
function M.record_response_time(ms)
    table.insert(metrics.response_times, ms)
    if #metrics.response_times > MAX_RESPONSE_TIME_SAMPLES then
        table.remove(metrics.response_times, 1)
    end
end

-- Record completion accept
function M.record_completion_accept()
    metrics.completion_accepts = metrics.completion_accepts + 1
end

-- Record completion cycle
function M.record_completion_cycle()
    metrics.completion_cycles = metrics.completion_cycles + 1
end

-- Record error
function M.record_error(error_type)
    metrics.errors_total = metrics.errors_total + 1
    log.warn(string.format("Error recorded: %s", error_type))
end

-- Get cache hit ratio
function M.get_cache_hit_ratio()
    local total = metrics.cache_hits + metrics.cache_misses
    return total > 0 and (metrics.cache_hits / total) or 0
end

-- Get average response time
function M.get_average_response_time()
    if #metrics.response_times == 0 then
        return 0
    end

    local sum = 0
    for _, time in ipairs(metrics.response_times) do
        sum = sum + time
    end
    return sum / #metrics.response_times
end

-- Get uptime
function M.get_uptime()
    return vim.loop.now() - metrics.start_time
end

-- Get completion acceptance rate
function M.get_completion_acceptance_rate()
    local total_completions = metrics.completion_cycles
    return total_completions > 0 and (metrics.completion_accepts / total_completions) or 0
end

-- Get all metrics
function M.get_all_metrics()
    return {
        cache = {
            hits = metrics.cache_hits,
            misses = metrics.cache_misses,
            hit_ratio = M.get_cache_hit_ratio()
        },
        requests = {
            total = metrics.requests_total,
            cancelled = metrics.requests_cancelled,
            dropped = metrics.requests_dropped,
            active = metrics.requests_total - metrics.requests_cancelled - metrics.requests_dropped
        },
        performance = {
            avg_response_time = M.get_average_response_time(),
            uptime = M.get_uptime()
        },
        completions = {
            accepts = metrics.completion_accepts,
            cycles = metrics.completion_cycles,
            acceptance_rate = M.get_completion_acceptance_rate()
        },
        errors = {
            total = metrics.errors_total
        }
    }
end

-- Format metrics for display
function M.format_stats()
    local m = M.get_all_metrics()
    local lines = {
        "Neopilot Statistics",
        "==================",
        "",
        string.format("Cache Hit Ratio: %.1f%% (%d/%d)",
            m.cache.hit_ratio * 100, m.cache.hits, m.cache.hits + m.cache.misses),
        string.format("Requests: %d total, %d cancelled, %d dropped",
            m.requests.total, m.requests.cancelled, m.requests.dropped),
        string.format("Avg Response Time: %.0fms", m.performance.avg_response_time),
        string.format("Uptime: %.1fs", m.performance.uptime / 1000),
        string.format("Completion Rate: %.1f%% (%d/%d)",
            m.completions.acceptance_rate * 100, m.completions.accepts, m.completions.cycles),
        string.format("Errors: %d", m.errors.total)
    }
    return table.concat(lines, "\n")
end

-- Reset metrics
function M.reset()
    metrics = {
        cache_hits = 0,
        cache_misses = 0,
        requests_total = 0,
        requests_cancelled = 0,
        requests_dropped = 0,
        response_times = {},
        completion_accepts = 0,
        completion_cycles = 0,
        errors_total = 0,
        start_time = vim.loop.now()
    }
    log.info("Metrics reset")
end

-- Export metrics for external monitoring
function M.export()
    return vim.deepcopy(metrics)
end

return M