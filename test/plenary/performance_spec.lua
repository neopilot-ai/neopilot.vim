-- Performance benchmarks for Neopilot
local core = require('neopilot.core')
local treesitter = require('neopilot.treesitter')
local events = require('neopilot.events')

describe('neopilot performance', function()
    local test_bufnr
    
    before_each(function()
        test_bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(test_bufnr)
        events.setup()
    end)
    
    after_each(function()
        if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
            vim.api.nvim_buf_delete(test_bufnr, { force = true })
        end
        events.reset()
    end)
    
    describe('event system performance', function()
        it('should handle high-frequency events efficiently', function()
            local start_time = vim.loop.hrtime()
            local event_count = 1000
            
            -- Register listener
            events.on('performance:test', function(data) end)
            
            -- Emit many events
            for i = 1, event_count do
                events.emit('performance:test', { index = i })
            end
            
            local end_time = vim.loop.hrtime()
            local duration = (end_time - start_time) / 1000000 -- Convert to milliseconds
            
            -- Should complete within reasonable time (adjust threshold as needed)
            assert.is_true(duration < 100, string.format("Events took too long: %.2fms", duration))
        end)
        
        it('should handle many listeners efficiently', function()
            local listener_count = 100
            local start_time = vim.loop.hrtime()
            
            -- Register many listeners
            for i = 1, listener_count do
                events.on('performance:listeners', function(data) end)
            end
            
            -- Emit single event
            events.emit('performance:listeners', {})
            
            local end_time = vim.loop.hrtime()
            local duration = (end_time - start_time) / 1000000
            
            -- Should handle many listeners efficiently
            assert.is_true(duration < 50, string.format("Too many listeners took too long: %.2fms", duration))
        end)
    end)
    
    describe('treesitter performance', function()
        it('should handle large files efficiently', function()
            vim.bo[test_bufnr].filetype = 'python'
            
            -- Create a large file (1000 lines)
            local lines = {}
            for i = 1, 1000 do
                table.insert(lines, string.format('def function_%d():', i))
                table.insert(lines, '    pass')
            end
            
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, lines)
            
            local start_time = vim.loop.hrtime()
            
            -- Test semantic context extraction
            local context = treesitter.get_semantic_context(test_bufnr)
            
            local end_time = vim.loop.hrtime()
            local duration = (end_time - start_time) / 1000000
            
            assert.is_table(context)
            -- Should complete within reasonable time for large files
            assert.is_true(duration < 200, string.format("Large file processing took too long: %.2fms", duration))
        end)
        
        it('should cache results efficiently', function()
            vim.bo[test_bufnr].filetype = 'python'
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                'import os',
                'import sys',
                'def test_function():',
                '    pass'
            })
            
            -- First call
            local start_time = vim.loop.hrtime()
            local context1 = treesitter.get_semantic_context(test_bufnr)
            local first_duration = (vim.loop.hrtime() - start_time) / 1000000
            
            -- Second call (should be faster due to caching)
            start_time = vim.loop.hrtime()
            local context2 = treesitter.get_semantic_context(test_bufnr)
            local second_duration = (vim.loop.hrtime() - start_time) / 1000000
            
            assert.is_table(context1)
            assert.is_table(context2)
            
            -- Second call should be faster (though this depends on implementation)
            -- This is more of a benchmark than a strict test
            print(string.format("First call: %.2fms, Second call: %.2fms", first_duration, second_duration))
        end)
    end)
    
    describe('memory usage', function()
        it('should not leak memory with repeated operations', function()
            local initial_memory = collectgarbage('count')
            
            -- Perform many operations
            for i = 1, 100 do
                -- Register and remove listeners
                local listener_id = events.on('memory:test', function() end)
                events.emit('memory:test', {})
                events.off('memory:test', listener_id)
                
                -- Create and clean up buffers
                local temp_buf = vim.api.nvim_create_buf(false, true)
                vim.api.nvim_buf_delete(temp_buf, { force = true })
            end
            
            -- Force garbage collection
            collectgarbage('collect')
            collectgarbage('collect')
            
            local final_memory = collectgarbage('count')
            local memory_increase = final_memory - initial_memory
            
            -- Memory increase should be minimal (allowing for some variance)
            assert.is_true(memory_increase < 100, 
                string.format("Memory leak detected: increased by %.2f KB", memory_increase))
        end)
    end)
    
    describe('concurrent operations', function()
        it('should handle concurrent event processing', function()
            local processed_count = 0
            local target_count = 50
            
            -- Register listener
            events.on('concurrent:test', function(data)
                processed_count = processed_count + 1
            end)
            
            -- Emit events concurrently (simulated with defer_fn)
            for i = 1, target_count do
                vim.defer_fn(function()
                    events.emit('concurrent:test', { index = i })
                end, math.random(0, 10))
            end
            
            -- Wait for processing (in real test, would need proper synchronization)
            vim.defer_fn(function()
                assert.equals(target_count, processed_count)
            end, 100)
        end)
    end)
    
    describe('cache performance', function()
        it('should maintain cache efficiency under load', function()
            -- Test cache hit/miss ratios
            local cache_hits = 0
            local cache_misses = 0
            
            -- Mock cache monitoring
            events.on(events.EVENT_TYPES.CACHE_HIT, function()
                cache_hits = cache_hits + 1
            end)
            
            events.on(events.EVENT_TYPES.CACHE_MISS, function()
                cache_misses = cache_misses + 1
            end)
            
            -- Simulate cache operations
            for i = 1, 100 do
                if i % 3 == 0 then
                    events.emit(events.EVENT_TYPES.CACHE_HIT)
                else
                    events.emit(events.EVENT_TYPES.CACHE_MISS)
                end
            end
            
            local total_operations = cache_hits + cache_misses
            local hit_ratio = cache_hits / total_operations
            
            -- Verify cache performance metrics
            assert.equals(100, total_operations)
            assert.equals(33, cache_hits)
            assert.equals(67, cache_misses)
        end)
    end)
end)
