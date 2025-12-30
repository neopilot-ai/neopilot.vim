-- Tests for event system
local events = require('neopilot.events')

describe('neopilot.events', function()
    before_each(function()
        events.setup()
    end)
    
    after_each(function()
        events.reset()
    end)
    
    describe('setup', function()
        it('should initialize event system correctly', function()
            events.setup()
            local stats = events.get_stats()
            assert.equals(0, stats.registered_events)
            assert.equals(0, stats.total_listeners)
        end)
    end)
    
    describe('event registration', function()
        it('should register event listener correctly', function()
            local callback = function() end
            local listener_id = events.on('test:event', callback)
            
            assert.is_string(listener_id)
            assert.is_true(listener_id:match('listener_') ~= nil)
            
            local listeners = events.get_listeners('test:event')
            assert.equals(1, #listeners)
            assert.equals(listener_id, listeners[1].id)
        end)
        
        it('should register one-time listener correctly', function()
            local callback = function() end
            local listener_id = events.once('test:event', callback)
            
            local listeners = events.get_listeners('test:event')
            assert.equals(1, #listeners)
            assert.is_true(listeners[1].once)
        end)
        
        it('should remove event listener correctly', function()
            local callback = function() end
            local listener_id = events.on('test:event', callback)
            
            local removed = events.off('test:event', listener_id)
            assert.is_true(removed)
            
            local listeners = events.get_listeners('test:event')
            assert.equals(0, #listeners)
        end)
        
        it('should remove all listeners for an event', function()
            events.on('test:event', function() end)
            events.on('test:event', function() end)
            events.on('test:event', function() end)
            
            events.off_all('test:event')
            
            local listeners = events.get_listeners('test:event')
            assert.equals(0, #listeners)
        end)
    end)
    
    describe('event emission', function()
        it('should emit event to registered listeners', function()
            local received_data = nil
            local callback = function(data)
                received_data = data
            end
            
            events.on('test:event', callback)
            local event = events.emit('test:event', { message = 'test' })
            
            assert.equals('test', received_data.message)
            assert.equals('test:event', event.name)
            assert.has_key(event, 'timestamp')
            assert.has_key(event, 'id')
        end)
        
        it('should handle multiple listeners for same event', function()
            local call_count = 0
            local callback = function()
                call_count = call_count + 1
            end
            
            events.on('test:event', callback)
            events.on('test:event', callback)
            events.on('test:event', callback)
            
            events.emit('test:event', {})
            
            assert.equals(3, call_count)
        end)
        
        it('should respect listener priority', function()
            local call_order = {}
            
            events.on('test:event', function()
                table.insert(call_order, 'low')
            end, { priority = 1 })
            
            events.on('test:event', function()
                table.insert(call_order, 'high')
            end, { priority = 10 })
            
            events.on('test:event', function()
                table.insert(call_order, 'medium')
            end, { priority = 5 })
            
            events.emit('test:event', {})
            
            assert.equals('high', call_order[1])
            assert.equals('medium', call_order[2])
            assert.equals('low', call_order[3])
        end)
        
        it('should apply filter correctly', function()
            local call_count = 0
            local callback = function()
                call_count = call_count + 1
            end
            
            local filter = function(data)
                return data.allow
            end
            
            events.on('test:event', callback, { filter = filter })
            
            events.emit('test:event', { allow = false })
            assert.equals(0, call_count)
            
            events.emit('test:event', { allow = true })
            assert.equals(1, call_count)
        end)
        
        it('should remove one-time listeners after execution', function()
            local call_count = 0
            local callback = function()
                call_count = call_count + 1
            end
            
            events.once('test:event', callback)
            
            events.emit('test:event', {})
            assert.equals(1, call_count)
            
            events.emit('test:event', {})
            assert.equals(1, call_count) -- Should not be called again
        end)
    end)
    
    describe('middleware', function()
        it('should apply middleware to events', function()
            local transformed_data = nil
            local middleware = function(event)
                event.data.transformed = true
                return event
            end
            
            local callback = function(data)
                transformed_data = data
            end
            
            events.use(middleware)
            events.on('test:event', callback)
            
            events.emit('test:event', { original = true })
            
            assert.is_true(transformed_data.transformed)
            assert.is_true(transformed_data.original)
        end)
        
        it('should respect middleware priority', function()
            local transformations = {}
            
            events.use(function(event)
                table.insert(transformations, 'first')
                return event
            end, { priority = 10 })
            
            events.use(function(event)
                table.insert(transformations, 'second')
                return event
            end, { priority = 5 })
            
            events.emit('test:event', {})
            
            assert.equals('first', transformations[1])
            assert.equals('second', transformations[2])
        end)
        
        it('should filter events with middleware', function()
            local call_count = 0
            local callback = function()
                call_count = call_count + 1
            end
            
            local filter_middleware = function(event)
                if event.data.block then
                    return nil -- Filter out
                end
                return event
            end
            
            events.use(filter_middleware)
            events.on('test:event', callback)
            
            events.emit('test:event', { block = true })
            assert.equals(0, call_count)
            
            events.emit('test:event', { block = false })
            assert.equals(1, call_count)
        end)
    end)
    
    describe('event history', function()
        it('should record events in history', function()
            events.emit('test:event', { data = 'test' })
            
            local history = events.get_history()
            assert.equals(1, #history)
            assert.equals('test:event', history[1].name)
        end)
        
        it('should filter history by event name', function()
            events.emit('event1', {})
            events.emit('event2', {})
            events.emit('event1', {})
            
            local history = events.get_history({ event_name = 'event1' })
            assert.equals(2, #history)
            
            for _, event in ipairs(history) do
                assert.equals('event1', event.name)
            end
        end)
        
        it('should limit history size', function()
            events.setup({ max_history_size = 2 })
            
            events.emit('event1', {})
            events.emit('event2', {})
            events.emit('event3', {})
            
            local history = events.get_history()
            assert.equals(2, #history)
            assert.equals('event2', history[1].name)
            assert.equals('event3', history[2].name)
        end)
    end)
    
    describe('event emitter', function()
        it('should create emitter with source', function()
            local emitter = events.create_emitter('test_source')
            
            local received_source = nil
            events.on('test:event', function(data, event)
                received_source = event.source
            end)
            
            emitter.emit('test:event', {})
            
            assert.equals('test_source', received_source)
        end)
    end)
    
    describe('built-in middleware', function()
        it('should create logging middleware', function()
            local middleware = events.create_logging_middleware({ level = 'info' })
            assert.is_function(middleware)
        end)
        
        it('should create performance middleware', function()
            local middleware = events.create_performance_middleware()
            assert.is_function(middleware)
        end)
        
        it('should create filter middleware', function()
            local filter = function(event) return true end
            local middleware = events.create_filter_middleware(filter)
            assert.is_function(middleware)
        end)
        
        it('should create transform middleware', function()
            local transform = function(event) return event end
            local middleware = events.create_transform_middleware(transform)
            assert.is_function(middleware)
        end)
    end)
    
    describe('error handling', function()
        it('should handle listener errors gracefully', function()
            local error_count = 0
            
            -- Mock log.error to count errors
            local original_error = require('neopilot.log').error
            require('neopilot.log').error = function() error_count = error_count + 1 end
            
            events.on('test:event', function()
                error('Test error')
            end)
            
            events.emit('test:event', {})
            
            assert.equals(1, error_count)
            
            -- Restore
            require('neopilot.log').error = original_error
        end)
    end)
    
    describe('health status', function()
        it('should return healthy status with listeners', function()
            events.on('test:event', function() end)
            
            local status, message = events.get_health_status()
            assert.equals('healthy', status)
        end)
        
        it('should return warning status with no listeners', function()
            local status, message = events.get_health_status()
            assert.equals('warning', status)
        end)
    end)
end)
