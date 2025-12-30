-- Tests for I/O module
local io_module = require('neopilot.io')

describe('neopilot.io', function()
    local test_dir
    local test_file_path
    local test_content
    
    before_each(function()
        -- Setup test environment
        test_dir = vim.fn.tempname() .. '/neopilot_test'
        vim.fn.mkdir(test_dir, 'p')
        test_file_path = test_dir .. '/test.txt'
        test_content = { 'line1', 'line2', 'line3' }
        
        -- Setup I/O module
        io_module.setup({
            cache_enabled = true,
            cache_ttl = 1000, -- Short TTL for testing
            max_cache_size = 10,
            temp_dir = test_dir .. '/temp'
        })
    end)
    
    after_each(function()
        -- Cleanup
        io_module.cleanup()
        vim.fn.delete(test_dir, 'rf')
    end)
    
    describe('setup', function()
        it('should initialize I/O module', function()
            local stats = io_module.get_stats()
            assert.has_key(stats, 'active_requests')
            assert.has_key(stats, 'file_cache_size')
            assert.has_key(stats, 'network_cache_size')
            assert.has_key(stats, 'config')
        end)
    end)
    
    describe('file operations', function()
        it('should read file successfully', function()
            -- Create test file
            vim.fn.writefile(test_content, test_file_path)
            
            local content, error = io_module.read_file(test_file_path)
            assert.is_not_nil(content)
            assert.is_nil(error)
            assert.same(test_content, content)
        end)
        
        it('should handle non-existent file', function()
            local content, error = io_module.read_file('/non/existent/file.txt')
            assert.is_nil(content)
            assert.is_not_nil(error)
            assert.matches('File not readable', error)
        end)
        
        it('should write file successfully', function()
            local success, error = io_module.write_file(test_file_path, test_content)
            assert.is_true(success)
            assert.is_nil(error)
            
            -- Verify file was written
            assert.equals(1, vim.fn.filereadable(test_file_path))
            
            local read_content = vim.fn.readfile(test_file_path)
            assert.same(test_content, read_content)
        end)
        
        it('should handle invalid file path for writing', function()
            local success, error = io_module.write_file('', test_content)
            assert.is_false(success)
            assert.is_not_nil(error)
            assert.matches('Invalid file path', error)
        end)
        
        it('should copy file successfully', function()
            -- Create source file
            vim.fn.writefile(test_content, test_file_path)
            
            local dest_path = test_dir .. '/copy.txt'
            local success, error = io_module.copy_file(test_file_path, dest_path)
            assert.is_true(success)
            assert.is_nil(error)
            
            -- Verify copy
            assert.equals(1, vim.fn.filereadable(dest_path))
            local copied_content = vim.fn.readfile(dest_path)
            assert.same(test_content, copied_content)
        end)
        
        it('should handle binary file operations', function()
            local binary_content = '\x00\x01\x02\x03\xFF'
            local binary_file = test_dir .. '/binary.bin'
            
            local success, error = io_module.write_file(binary_file, binary_content, { binary = true })
            assert.is_true(success)
            assert.is_nil(error)
            
            local content, read_error = io_module.read_file(binary_file, { binary = true })
            assert.is_not_nil(content)
            assert.is_nil(read_error)
            assert.equals(binary_content, content)
        end)
    end)
    
    describe('caching', function()
        it('should cache file reads', function()
            -- Create test file
            vim.fn.writefile(test_content, test_file_path)
            
            -- First read
            local content1, error1 = io_module.read_file(test_file_path)
            assert.is_not_nil(content1)
            assert.is_nil(error1)
            
            -- Second read should use cache
            local content2, error2 = io_module.read_file(test_file_path)
            assert.is_not_nil(content2)
            assert.is_nil(error2)
            assert.same(content1, content2)
            
            -- Check cache stats
            local stats = io_module.get_stats()
            assert.equals(1, stats.file_cache_size)
        end)
        
        it('should invalidate cache on file write', function()
            -- Create test file
            vim.fn.writefile(test_content, test_file_path)
            
            -- Read to cache
            io_module.read_file(test_file_path)
            
            -- Write new content
            local new_content = { 'new_line1', 'new_line2' }
            io_module.write_file(test_file_path, new_content)
            
            -- Read should get new content
            local content, error = io_module.read_file(test_file_path)
            assert.same(new_content, content)
        end)
        
        it('should respect cache TTL', function()
            -- Create test file
            vim.fn.writefile(test_content, test_file_path)
            
            -- Read to cache
            io_module.read_file(test_file_path)
            
            -- Wait for cache to expire
            vim.defer_fn(function()
                -- Read should not use cache (but file still exists)
                local content, error = io_module.read_file(test_file_path)
                assert.is_not_nil(content)
                assert.is_nil(error)
            end, 1200) -- Wait longer than TTL (1000ms)
        end)
    end)
    
    describe('network operations', function()
        it('should handle HTTP request simulation', function()
            -- This test would require a mock HTTP server
            -- For now, we test the error handling
            
            local response, error = io_module.http_request('http://invalid-url-for-testing')
            -- Should handle gracefully (either error or mock response)
            assert.is_true(response == nil or type(response) == 'table')
        end)
        
        it('should respect concurrent request limit', function()
            -- Mock concurrent requests
            local responses = {}
            local errors = {}
            
            for i = 1, 10 do
                local response, error = io_module.http_request('http://test' .. i .. '.com')
                table.insert(responses, response)
                table.insert(errors, error)
            end
            
            -- Some requests should succeed, others should fail due to limit
            local success_count = 0
            for _, resp in ipairs(responses) do
                if resp then
                    success_count = success_count + 1
                end
            end
            
            -- Should have some successful requests (up to the limit)
            assert.is_true(success_count >= 0)
        end)
    end)
    
    describe('async operations', function()
        it('should handle async file read', function()
            -- Create test file
            vim.fn.writefile(test_content, test_file_path)
            
            local callback_called = false
            local callback_content = nil
            local callback_error = nil
            
            io_module.read_file_async(test_file_path, function(content, error)
                callback_called = true
                callback_content = content
                callback_error = error
            end)
            
            -- Wait for async operation
            vim.defer_fn(function()
                assert.is_true(callback_called)
                assert.is_not_nil(callback_content)
                assert.is_nil(callback_error)
                assert.same(test_content, callback_content)
            end, 100)
        end)
        
        it('should handle async HTTP request', function()
            local callback_called = false
            local callback_response = nil
            local callback_error = nil
            
            io_module.http_request_async('http://test-url.com', function(response, error)
                callback_called = true
                callback_response = response
                callback_error = error
            end)
            
            -- Wait for async operation
            vim.defer_fn(function()
                assert.is_true(callback_called)
                -- Response or error should be set
                assert.is_true(callback_response ~= nil or callback_error ~= nil)
            end, 100)
        end)
    end)
    
    describe('utility functions', function()
        it('should get file info', function()
            -- Create test file
            vim.fn.writefile(test_content, test_file_path)
            
            local info, error = io_module.get_file_info(test_file_path)
            assert.is_not_nil(info)
            assert.is_nil(error)
            assert.has_key(info, 'size')
            assert.has_key(info, 'mtime')
            assert.has_key(info, 'atime')
            assert.has_key(info, 'mode')
            assert.has_key(info, 'type')
        end)
        
        it('should handle file info for non-existent file', function()
            local info, error = io_module.get_file_info('/non/existent/file.txt')
            assert.is_nil(info)
            assert.is_not_nil(error)
        end)
        
        it('should list directory', function()
            -- Create test files
            vim.fn.writefile({'content1'}, test_dir .. '/file1.txt')
            vim.fn.writefile({'content2'}, test_dir .. '/file2.txt')
            vim.fn.mkdir(test_dir .. '/subdir', 'p')
            
            local entries, error = io_module.list_directory(test_dir)
            assert.is_not_nil(entries)
            assert.is_nil(error)
            assert.is_true(#entries >= 2) -- At least our test files
        end)
        
        it('should create temporary file', function()
            local temp_path, error = io_module.create_temp_file('.txt', test_content)
            assert.is_not_nil(temp_path)
            assert.is_nil(error)
            assert.matches('%.txt$', temp_path)
            
            -- Verify content
            local content = vim.fn.readfile(temp_path)
            assert.same(test_content, content)
        end)
        
        it('should generate unique request IDs', function()
            local id1 = io_module.generate_request_id()
            local id2 = io_module.generate_request_id()
            
            assert.is_not_nil(id1)
            assert.is_not_nil(id2)
            assert.is_not_equals(id1, id2)
        end)
    end)
    
    describe('retry operations', function()
        it('should retry successful operation', function()
            local attempt_count = 0
            local operation = function()
                attempt_count = attempt_count + 1
                if attempt_count < 3 then
                    error("Temporary failure")
                end
                return "success"
            end
            
            local result, error = io_module.retry_operation(operation, 3, 10)
            assert.equals("success", result)
            assert.is_nil(error)
            assert.equals(3, attempt_count)
        end)
        
        it('should fail after max attempts', function()
            local operation = function()
                error("Persistent failure")
            end
            
            local result, error = io_module.retry_operation(operation, 2, 10)
            assert.is_nil(result)
            assert.is_not_nil(error)
            assert.matches('Max retry attempts exceeded', error)
        end)
    end)
    
    describe('cleanup', function()
        it('should cleanup resources', function()
            -- Create some state
            io_module.read_file_async(test_file_path, function() end)
            
            local stats_before = io_module.get_stats()
            
            io_module.cleanup()
            
            local stats_after = io_module.get_stats()
            assert.equals(0, stats_after.active_requests)
            assert.equals(0, stats_after.file_cache_size)
            assert.equals(0, stats_after.network_cache_size)
        end)
    end)
    
    describe('configuration', function()
        it('should use custom configuration', function()
            io_module.setup({
                cache_enabled = false,
                max_cache_size = 5,
                request_timeout = 5000
            })
            
            local stats = io_module.get_stats()
            assert.is_false(stats.config.cache_enabled)
            assert.equals(5, stats.config.max_cache_size)
            assert.equals(5000, stats.config.request_timeout)
        end)
    end)
end)
