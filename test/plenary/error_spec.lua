-- Tests for comprehensive error handling system
local error_handler = require('neopilot.error')

describe('neopilot.error', function()
    before_each(function()
        error_handler.setup()
    end)
    
    after_each(function()
        error_handler.reset_error_state()
    end)
    
    describe('setup', function()
        it('should initialize error state correctly', function()
            error_handler.setup()
            local summary = error_handler.get_error_summary()
            assert.equals(0, summary.consecutive_failures)
            assert.is_false(summary.circuit_breaker_open)
        end)
    end)
    
    describe('handle_error', function()
        it('should record error correctly', function()
            local error_data = { message = 'Test error' }
            local context = { operation = 'test' }
            
            local result = error_handler.handle_error('network_timeout', error_data, context)
            
            local summary = error_handler.get_error_summary()
            assert.equals(1, summary.consecutive_failures)
            assert.equals(1, #summary.error_history)
        end)
        
        it('should return recovery strategy', function()
            local error_data = { message = 'Test timeout' }
            local result = error_handler.handle_error('network_timeout', error_data, {})
            
            assert.has_key(result, 'strategy')
            assert.has_key(result, 'retry_delay')
        end)
    end)
    
    describe('circuit breaker', function()
        it('should open circuit breaker after threshold failures', function()
            -- Trigger multiple failures
            for i = 1, 6 do
                error_handler.handle_error('network_timeout', { message = 'Test error' }, {})
            end
            
            assert.is_true(error_handler.is_circuit_breaker_open())
        end)
        
        it('should close circuit breaker after timeout', function()
            -- Open circuit breaker
            for i = 1, 6 do
                error_handler.handle_error('network_timeout', { message = 'Test error' }, {})
            end
            
            -- Mock time passing
            local original_now = vim.loop.now
            vim.loop.now = function() return original_now() + 40000 end
            
            assert.is_false(error_handler.is_circuit_breaker_open())
            
            -- Restore
            vim.loop.now = original_now
        end)
    end)
    
    describe('error classification', function()
        it('should classify timeout errors correctly', function()
            local error_type = error_handler.classify_error('Request timeout')
            assert.equals('network_timeout', error_type)
        end)
        
        it('should classify auth errors correctly', function()
            local error_type = error_handler.classify_error('401 Unauthorized')
            assert.equals('auth_failure', error_type)
        end)
        
        it('should classify unknown errors correctly', function()
            local error_type = error_handler.classify_error('Something weird happened')
            assert.equals('unknown_error', error_type)
        end)
    end)
    
    describe('safe_call', function()
        it('should return result on successful function call', function()
            local function success_func()
                return 'success'
            end
            
            local result = error_handler.safe_call(success_func, {})
            assert.equals('success', result)
        end)
        
        it('should handle function errors and return recovery result', function()
            local function error_func()
                error('Test error')
            end
            
            local result = error_handler.safe_call(error_func, {})
            assert.has_key(result, 'strategy')
        end)
    end)
    
    describe('recovery strategies', function()
        it('should execute retry strategy correctly', function()
            local recovery_result = {
                strategy = 'retry',
                retry_delay = 1000,
                max_retries = 3
            }
            
            local context = {
                retry_function = function() end
            }
            
            local result = error_handler.execute_recovery(recovery_result, context)
            assert.equals('retry_scheduled', result.action)
        end)
        
        it('should execute fallback strategy correctly', function()
            local recovery_result = {
                strategy = 'fallback'
            }
            
            local context = {
                fallback_function = function()
                    return 'fallback_result'
                end
            }
            
            local result = error_handler.execute_recovery(recovery_result, context)
            assert.equals('fallback_executed', result.action)
        end)
        
        it('should execute degrade strategy correctly', function()
            local recovery_result = {
                strategy = 'degrade',
                message = 'Degrading service'
            }
            
            local result = error_handler.execute_recovery(recovery_result, {})
            assert.equals('degraded_mode', result.action)
        end)
    end)
    
    describe('health status', function()
        it('should return healthy status when no errors', function()
            local status, message = error_handler.get_health_status()
            assert.equals('healthy', status)
        end)
        
        it('should return unhealthy status when circuit breaker is open', function()
            -- Open circuit breaker
            for i = 1, 6 do
                error_handler.handle_error('network_timeout', { message = 'Test error' }, {})
            end
            
            local status, message = error_handler.get_health_status()
            assert.equals('unhealthy', status)
        end)
    end)
    
    describe('error handlers', function()
        it('should handle network timeout with retry strategy', function()
            local error_data = { timeout = 5000 }
            local result = error_handler.handle_network_timeout(error_data, { retry_count = 0 })
            
            assert.equals('retry', result.strategy)
            assert.has_key(result, 'retry_delay')
        end)
        
        it('should handle auth failure with user intervention', function()
            local error_data = { status_code = 401 }
            local result = error_handler.handle_auth_failure(error_data, {})
            
            assert.equals('user_intervention', result.strategy)
            assert.has_key(result, 'message')
        end)
        
        it('should handle server error based on status code', function()
            local error_data = { status_code = 500 }
            local result = error_handler.handle_server_error(error_data, {})
            
            assert.equals('retry', result.strategy)
        end)
    end)
end)
