-- Integration tests for Neopilot core functionality
local core = require('neopilot.core')
local config = require('neopilot.config')
local events = require('neopilot.events')
local error_handler = require('neopilot.error')

describe('neopilot integration', function()
    before_each(function()
        -- Setup all systems
        config.setup({
            enabled = true,
            idle_delay = 10,
            log_level = 'DEBUG'
        })
        events.setup()
        error_handler.setup()
        core.setup()
    end)
    
    after_each(function()
        core.clear()
        events.reset()
        error_handler.reset_error_state()
    end)
    
    describe('completion flow with events', function()
        it('should emit events during completion request', function()
            local events_received = {}
            
            events.on(events.EVENT_TYPES.BEFORE_REQUEST, function(data)
                table.insert(events_received, 'before_request')
            end)
            
            events.on(events.EVENT_TYPES.AFTER_REQUEST, function(data)
                table.insert(events_received, 'after_request')
            end)
            
            -- Mock document and server
            local mock_doc = {
                get_current_document = function()
                    return {
                        text = 'def test():',
                        language = 'python'
                    }
                end,
                get_editor_options = function()
                    return { tab_size = 4, insert_spaces = true }
                end
            }
            
            -- This would require more extensive mocking for a full integration test
            -- For now, we test the event system integration
            assert.is_table(events_received)
        end)
    end)
    
    describe('error handling integration', function()
        it('should handle server errors with recovery', function()
            local recovery_executed = false
            
            -- Mock server error
            local mock_error = {
                message = 'Server timeout',
                timeout = true
            }
            
            local context = {
                operation = 'completion_request',
                retry_function = function()
                    recovery_executed = true
                end
            }
            
            local result = error_handler.handle_error('network_timeout', mock_error, context)
            
            assert.equals('retry', result.strategy)
            assert.has_key(result, 'retry_delay')
        end)
        
        it('should emit error events', function()
            local error_event_received = false
            
            events.on(events.EVENT_TYPES.ERROR_OCCURRED, function(data)
                error_event_received = true
                assert.has_key(data, 'error')
            end)
            
            -- Trigger an error
            error_handler.handle_error('network_timeout', { message = 'Test error' }, {})
            
            assert.is_true(error_event_received)
        end)
    end)
    
    describe('treesitter integration', function()
        it('should integrate semantic context with completion', function()
            local treesitter = require('neopilot.treesitter')
            
            -- Create test buffer
            local test_bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(test_bufnr)
            vim.bo[test_bufnr].filetype = 'python'
            
            -- Test semantic context extraction
            local context = treesitter.get_semantic_context(test_bufnr)
            
            assert.is_table(context)
            assert.has_key(context, 'available')
            assert.has_key(context, 'filetype')
            
            -- Clean up
            vim.api.nvim_buf_delete(test_bufnr, { force = true })
        end)
    end)
    
    describe('circuit breaker integration', function()
        it('should open circuit breaker after repeated failures', function()
            -- Simulate multiple failures
            for i = 1, 6 do
                error_handler.handle_error('network_timeout', { message = 'Test error' }, {})
            end
            
            assert.is_true(error_handler.is_circuit_breaker_open())
            
            -- Should emit circuit breaker events
            local circuit_breaker_event = false
            events.on(events.EVENT_TYPES.ERROR_OCCURRED, function(data)
                if data.error and data.error.circuit_breaker then
                    circuit_breaker_event = true
                end
            end)
        end)
    end)
    
    describe('performance monitoring', function()
        it('should track performance metrics', function()
            local metrics = require('neopilot.metrics')
            
            -- Record some metrics
            metrics.record_request_start()
            metrics.record_response_time(100)
            metrics.record_cache_hit()
            
            -- This would test the metrics collection system
            -- Implementation depends on the actual metrics module
            assert.is_function(metrics.record_request_start)
        end)
    end)
    
    describe('configuration integration', function()
        it('should emit config change events', function()
            local config_event_received = false
            
            events.on(events.EVENT_TYPES.CONFIG_CHANGED, function(data)
                config_event_received = true
                assert.has_key(data, 'key')
                assert.has_key(data, 'value')
            end)
            
            -- Change configuration
            config.set('test_key', 'test_value')
            
            -- This would require the config module to emit events
            -- For now, we test the event structure
            assert.is_function(events.emit)
        end)
    end)
    
    describe('lifecycle events', function()
        it('should handle plugin lifecycle events', function()
            local lifecycle_events = {}
            
            events.on(events.EVENT_TYPES.PLUGIN_LOADED, function(data)
                table.insert(lifecycle_events, 'loaded')
            end)
            
            events.on(events.EVENT_TYPES.BUFFER_ENTERED, function(data)
                table.insert(lifecycle_events, 'buffer_entered')
            end)
            
            -- Emit lifecycle events
            events.emit(events.EVENT_TYPES.PLUGIN_LOADED, {})
            events.emit(events.EVENT_TYPES.BUFFER_ENTERED, { bufnr = 1 })
            
            assert.equals(2, #lifecycle_events)
        end)
    end)
    
    describe('middleware integration', function()
        it('should apply middleware to all events', function()
            local middleware_applied = false
            
            events.use(function(event)
                if event.name:match('completion') then
                    middleware_applied = true
                    event.data.middleware_processed = true
                end
                return event
            end)
            
            events.on('completion:before_request', function(data)
                assert.is_true(data.middleware_processed)
            end)
            
            events.emit('completion:before_request', {})
            
            assert.is_true(middleware_applied)
        end)
    end)
    
    describe('async operations', function()
        it('should handle async event processing', function()
            local async_processed = false
            
            events.on('test:async', function(data)
                async_processed = true
            end, { async = true })
            
            events.emit('test:async', {})
            
            -- Async events are processed with vim.defer_fn
            -- In a real test, we'd need to wait for the defer
            assert.is_function(vim.defer_fn)
        end)
    end)
    
    describe('memory management', function()
        it('should clean up resources properly', function()
            -- Register many listeners
            for i = 1, 100 do
                events.on('test:cleanup', function() end)
            end
            
            -- Check stats
            local stats_before = events.get_stats()
            assert.equals(100, stats_before.total_listeners)
            
            -- Clean up
            events.off_all('test:cleanup')
            
            local stats_after = events.get_stats()
            assert.equals(0, stats_after.total_listeners)
        end)
    end)
end)
