-- Comprehensive error handling and recovery system for Neopilot
local M = {}

local config = require('neopilot.config')
local log = require('neopilot.log')
local metrics = require('neopilot.metrics')

-- Error types and their handling strategies
local ERROR_TYPES = {
    NETWORK_TIMEOUT = 'network_timeout',
    AUTH_FAILURE = 'auth_failure',
    PARSE_ERROR = 'parse_error',
    SERVER_ERROR = 'server_error',
    RATE_LIMIT = 'rate_limit',
    INVALID_RESPONSE = 'invalid_response',
    CANCELLED_REQUEST = 'cancelled_request',
    UNKNOWN_ERROR = 'unknown_error'
}

-- Error recovery strategies
local RECOVERY_STRATEGIES = {
    RETRY = 'retry',
    FALLBACK = 'fallback',
    DEGRADE = 'degrade',
    ABORT = 'abort',
    USER_INTERVENTION = 'user_intervention'
}

-- Error state tracking
local error_state = {
    consecutive_failures = 0,
    last_error_time = 0,
    error_history = {},
    recovery_attempts = {},
    circuit_breaker_open = false,
    circuit_breaker_open_time = 0
}

-- Circuit breaker configuration
local CIRCUIT_BREAKER = {
    failure_threshold = 5,
    recovery_timeout = 30000, -- 30 seconds
    half_open_max_calls = 3
}

-- Error handlers for different error types
local error_handlers = {}

-- Initialize error handling system
function M.setup()
    error_state.consecutive_failures = 0
    error_state.last_error_time = 0
    error_state.error_history = {}
    error_state.recovery_attempts = {}
    error_state.circuit_breaker_open = false
    error_state.circuit_breaker_open_time = 0
    
    M.register_error_handlers()
    log.info("Error handling system initialized")
end

-- Register default error handlers
function M.register_error_handlers()
    error_handlers[ERROR_TYPES.NETWORK_TIMEOUT] = M.handle_network_timeout
    error_handlers[ERROR_TYPES.AUTH_FAILURE] = M.handle_auth_failure
    error_handlers[ERROR_TYPES.PARSE_ERROR] = M.handle_parse_error
    error_handlers[ERROR_TYPES.SERVER_ERROR] = M.handle_server_error
    error_handlers[ERROR_TYPES.RATE_LIMIT] = M.handle_rate_limit
    error_handlers[ERROR_TYPES.INVALID_RESPONSE] = M.handle_invalid_response
    error_handlers[ERROR_TYPES.CANCELLED_REQUEST] = M.handle_cancelled_request
    error_handlers[ERROR_TYPES.UNKNOWN_ERROR] = M.handle_unknown_error
end

-- Main error handling function
function M.handle_error(error_type, error_data, context)
    context = context or {}
    
    -- Record the error
    M.record_error(error_type, error_data, context)
    
    -- Check circuit breaker
    if M.is_circuit_breaker_open() then
        log.warn("Circuit breaker is open, rejecting request")
        return M.handle_circuit_breaker_open(error_type, error_data, context)
    end
    
    -- Get appropriate error handler
    local handler = error_handlers[error_type]
    if not handler then
        handler = error_handlers[ERROR_TYPES.UNKNOWN_ERROR]
    end
    
    -- Execute error handler
    local success, result = pcall(handler, error_data, context)
    if not success then
        log.error("Error handler failed: " .. tostring(result))
        return M.handle_unknown_error(error_data, context)
    end
    
    return result
end

-- Record error for tracking and metrics
function M.record_error(error_type, error_data, context)
    local timestamp = vim.loop.now()
    
    -- Update error state
    error_state.consecutive_failures = error_state.consecutive_failures + 1
    error_state.last_error_time = timestamp
    
    -- Add to error history
    table.insert(error_state.error_history, {
        type = error_type,
        data = error_data,
        context = context,
        timestamp = timestamp
    })
    
    -- Limit error history size
    if #error_state.error_history > 100 then
        table.remove(error_state.error_history, 1)
    end
    
    -- Record metrics
    metrics.record_error(error_type)
    
    -- Log the error
    log.error(string.format("Error occurred: %s - %s", error_type, vim.inspect(error_data)))
    
    -- Check if circuit breaker should be opened
    if error_state.consecutive_failures >= CIRCUIT_BREAKER.failure_threshold then
        M.open_circuit_breaker()
    end
end

-- Circuit breaker management
function M.is_circuit_breaker_open()
    if not error_state.circuit_breaker_open then
        return false
    end
    
    local current_time = vim.loop.now()
    if current_time - error_state.circuit_breaker_open_time > CIRCUIT_BREAKER.recovery_timeout then
        -- Circuit breaker timeout, move to half-open state
        error_state.circuit_breaker_open = false
        log.info("Circuit breaker moving to half-open state")
        return false
    end
    
    return true
end

function M.open_circuit_breaker()
    error_state.circuit_breaker_open = true
    error_state.circuit_breaker_open_time = vim.loop.now()
    log.warn("Circuit breaker opened due to consecutive failures")
    metrics.record_circuit_breaker_open()
end

function M.close_circuit_breaker()
    error_state.circuit_breaker_open = false
    error_state.consecutive_failures = 0
    log.info("Circuit breaker closed")
end

function M.handle_circuit_breaker_open(error_type, error_data, context)
    return {
        strategy = RECOVERY_STRATEGIES.FALLBACK,
        message = "Service temporarily unavailable due to repeated failures",
        retry_after = CIRCUIT_BREAKER.recovery_timeout
    }
end

-- Specific error handlers
function M.handle_network_timeout(error_data, context)
    local retry_count = context.retry_count or 0
    
    if retry_count < 3 then
        return {
            strategy = RECOVERY_STRATEGIES.RETRY,
            retry_delay = math.min(1000 * (2 ^ retry_count), 5000), -- Exponential backoff
            max_retries = 3
        }
    else
        return {
            strategy = RECOVERY_STRATEGIES.DEGRADE,
            message = "Network timeout after multiple retries, using cached results if available"
        }
    end
end

function M.handle_auth_failure(error_data, context)
    -- Authentication failures usually require user intervention
    return {
        strategy = RECOVERY_STRATEGIES.USER_INTERVENTION,
        message = "Authentication failed. Please check your API key.",
        action = "reauthenticate"
    }
end

function M.handle_parse_error(error_data, context)
    -- Parse errors might be recoverable with different parsing strategies
    return {
        strategy = RECOVERY_STRATEGIES.RETRY,
        retry_with_fallback_parser = true,
        message = "Response parsing failed, retrying with fallback parser"
    }
end

function M.handle_server_error(error_data, context)
    local status_code = error_data.status_code or 500
    
    if status_code >= 500 then
        -- Server errors might be temporary
        return {
            strategy = RECOVERY_STRATEGIES.RETRY,
            retry_delay = 2000,
            max_retries = 2
        }
    elseif status_code == 429 then
        -- Rate limited
        return M.handle_rate_limit(error_data, context)
    else
        -- Client errors (4xx) usually require user intervention
        return {
            strategy = RECOVERY_STRATEGIES.USER_INTERVENTION,
            message = string.format("Server error: %d - %s", status_code, error_data.message or "Unknown error")
        }
    end
end

function M.handle_rate_limit(error_data, context)
    local retry_after = error_data.retry_after or 60
    
    return {
        strategy = RECOVERY_STRATEGIES.RETRY,
        retry_delay = retry_after * 1000,
        message = string.format("Rate limited. Retrying after %d seconds", retry_after)
    }
end

function M.handle_invalid_response(error_data, context)
    -- Invalid responses might be due to server issues or parsing problems
    return {
        strategy = RECOVERY_STRATEGIES.RETRY,
        retry_delay = 1000,
        max_retries = 2,
        message = "Invalid server response, retrying"
    }
end

function M.handle_cancelled_request(error_data, context)
    -- Cancelled requests don't need recovery
    return {
        strategy = RECOVERY_STRATEGIES.ABORT,
        message = "Request was cancelled"
    }
end

function M.handle_unknown_error(error_data, context)
    -- Unknown errors get a safe fallback
    return {
        strategy = RECOVERY_STRATEGIES.DEGRADE,
        message = "Unknown error occurred, falling back to safe mode"
    }
end

-- Recovery execution
function M.execute_recovery(recovery_result, context)
    local strategy = recovery_result.strategy
    
    if strategy == RECOVERY_STRATEGIES.RETRY then
        return M.execute_retry(recovery_result, context)
    elseif strategy == RECOVERY_STRATEGIES.FALLBACK then
        return M.execute_fallback(recovery_result, context)
    elseif strategy == RECOVERY_STRATEGIES.DEGRADE then
        return M.execute_degrade(recovery_result, context)
    elseif strategy == RECOVERY_STRATEGIES.USER_INTERVENTION then
        return M.execute_user_intervention(recovery_result, context)
    elseif strategy == RECOVERY_STRATEGIES.ABORT then
        return M.execute_abort(recovery_result, context)
    else
        log.error("Unknown recovery strategy: " .. tostring(strategy))
        return M.execute_abort(recovery_result, context)
    end
end

function M.execute_retry(recovery_result, context)
    local retry_count = (context.retry_count or 0) + 1
    local max_retries = recovery_result.max_retries or 3
    
    if retry_count > max_retries then
        log.warn("Max retries exceeded, falling back")
        return M.execute_fallback(recovery_result, context)
    end
    
    -- Record recovery attempt
    table.insert(error_state.recovery_attempts, {
        strategy = RECOVERY_STRATEGIES.RETRY,
        timestamp = vim.loop.now(),
        retry_count = retry_count
    })
    
    -- Schedule retry
    local retry_delay = recovery_result.retry_delay or 1000
    vim.defer_fn(function()
        if context.retry_function then
            context.retry_function(vim.tbl_extend("force", context, { retry_count = retry_count }))
        end
    end, retry_delay)
    
    log.info(string.format("Scheduling retry %d/%d in %dms", retry_count, max_retries, retry_delay))
    
    return {
        action = "retry_scheduled",
        retry_count = retry_count,
        retry_delay = retry_delay
    }
end

function M.execute_fallback(recovery_result, context)
    log.info("Executing fallback strategy")
    
    if context.fallback_function then
        local success, result = pcall(context.fallback_function, context)
        if success then
            return {
                action = "fallback_executed",
                result = result
            }
        else
            log.error("Fallback function failed: " .. tostring(result))
            return M.execute_degrade(recovery_result, context)
        end
    else
        return M.execute_degrade(recovery_result, context)
    end
end

function M.execute_degrade(recovery_result, context)
    log.info("Executing degrade strategy")
    
    -- Reset consecutive failures on successful degrade
    error_state.consecutive_failures = 0
    
    return {
        action = "degraded_mode",
        message = recovery_result.message or "Operating in degraded mode"
    }
end

function M.execute_user_intervention(recovery_result, context)
    log.info("Requesting user intervention")
    
    -- Show notification to user
    local message = recovery_result.message or "User intervention required"
    vim.notify("Neopilot: " .. message, vim.log.levels.WARN)
    
    -- If there's a specific action, execute it
    if recovery_result.action == "reauthenticate" then
        -- Trigger reauthentication flow
        local auth = require('neopilot.auth')
        if auth and auth.reauthenticate then
            auth.reauthenticate()
        end
    end
    
    return {
        action = "user_intervention_requested",
        message = message
    }
end

function M.execute_abort(recovery_result, context)
    log.info("Aborting operation")
    
    return {
        action = "aborted",
        message = recovery_result.message or "Operation aborted"
    }
end

-- Error reporting and diagnostics
function M.get_error_summary()
    local recent_errors = {}
    local current_time = vim.loop.now()
    
    -- Get errors from last hour
    for _, error in ipairs(error_state.error_history) do
        if current_time - error.timestamp < 3600000 then -- 1 hour
            table.insert(recent_errors, error)
        end
    end
    
    return {
        consecutive_failures = error_state.consecutive_failures,
        circuit_breaker_open = error_state.circuit_breaker_open,
        circuit_breaker_open_time = error_state.circuit_breaker_open_time,
        recent_errors = recent_errors,
        total_errors = #error_state.error_history,
        recovery_attempts = #error_state.recovery_attempts
    }
end

function M.get_health_status()
    local summary = M.get_error_summary()
    
    if summary.circuit_breaker_open then
        return "unhealthy", "Circuit breaker is open"
    elseif summary.consecutive_failures >= CIRCUIT_BREAKER.failure_threshold - 1 then
        return "degraded", string.format("High error rate: %d consecutive failures", summary.consecutive_failures)
    elseif summary.recent_errors and #summary.recent_errors > 10 then
        return "warning", string.format("High error frequency: %d errors in last hour", #summary.recent_errors)
    else
        return "healthy", "No significant errors detected"
    end
end

-- Reset error state (for testing or manual recovery)
function M.reset_error_state()
    error_state.consecutive_failures = 0
    error_state.last_error_time = 0
    error_state.error_history = {}
    error_state.recovery_attempts = {}
    error_state.circuit_breaker_open = false
    error_state.circuit_breaker_open_time = 0
    
    log.info("Error state reset")
end

-- Utility functions for error classification
function M.classify_error(error)
    if not error then
        return ERROR_TYPES.UNKNOWN_ERROR
    end
    
    local error_string = tostring(error)
    
    if error_string:match("timeout") or error_string:match("ETIMEDOUT") then
        return ERROR_TYPES.NETWORK_TIMEOUT
    elseif error_string:match("auth") or error_string:match("401") or error_string:match("403") then
        return ERROR_TYPES.AUTH_FAILURE
    elseif error_string:match("parse") or error_string:match("JSON") then
        return ERROR_TYPES.PARSE_ERROR
    elseif error_string:match("rate") or error_string:match("429") then
        return ERROR_TYPES.RATE_LIMIT
    elseif error_string:match("500") or error_string:match("502") or error_string:match("503") then
        return ERROR_TYPES.SERVER_ERROR
    else
        return ERROR_TYPES.UNKNOWN_ERROR
    end
end

-- Safe function wrapper with error handling
function M.safe_call(func, context, error_handler)
    context = context or {}
    
    local success, result = pcall(func)
    if success then
        -- Reset consecutive failures on success
        error_state.consecutive_failures = 0
        return result
    else
        local error_type = M.classify_error(result)
        local recovery_result = M.handle_error(error_type, result, context)
        
        if error_handler then
            return error_handler(recovery_result, context)
        else
            return M.execute_recovery(recovery_result, context)
        end
    end
end

-- Async safe call wrapper
function M.safe_call_async(func, context, callback)
    context = context or {}
    
    local function wrapped_func()
        return M.safe_call(func, context)
    end
    
    vim.defer_fn(function()
        local result = wrapped_func()
        if callback then
            callback(result)
        end
    end, 0)
end

return M
