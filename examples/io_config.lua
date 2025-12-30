-- I/O module configuration example
-- Add this to your Neopilot setup to customize I/O behavior

require('neopilot').setup({
    -- ... other config options
    
    -- I/O configuration
    io = {
        -- Enable/disable caching
        cache_enabled = true,
        
        -- Cache time-to-live in milliseconds (5 minutes)
        cache_ttl = 300000,
        
        -- Maximum cache size (number of entries)
        max_cache_size = 1000,
        
        -- Network request timeout in milliseconds (10 seconds)
        request_timeout = 10000,
        
        -- Number of retry attempts for failed operations
        retry_attempts = 3,
        
        -- Base delay between retries in milliseconds (exponential backoff)
        retry_delay = 1000,
        
        -- Maximum concurrent network requests
        concurrent_requests = 5,
        
        -- Chunk size for large file operations (8KB)
        chunk_size = 8192,
        
        -- Temporary directory for I/O operations
        temp_dir = vim.fn.expand('~/.cache/neopilot/temp')
    }
})

-- Example: Using the I/O module directly

-- Read a file with caching
local io_module = require('neopilot.io')
local content, error = io_module.read_file('/path/to/file.txt')
if content then
    print("File content:", vim.inspect(content))
else
    print("Error reading file:", error)
end

-- Write a file with backup
local success, error = io_module.write_file('/path/to/output.txt', {'line1', 'line2'}, {
    backup = true  -- Create .backup file
})

-- Make HTTP request
local response, error = io_module.http_request('https://api.example.com/data', {
    method = 'GET',
    headers = {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = 'Bearer your-token'
    },
    timeout = 5000
})

if response then
    print("Response status:", response.status_code)
    print("Response body:", response.body)
else
    print("HTTP request failed:", error)
end

-- Async file operations
io_module.read_file_async('/path/to/large_file.txt', function(content, error)
    if content then
        print("Async read completed, size:", #content)
        -- Process content...
    else
        print("Async read failed:", error)
    end
end)

-- Copy file with progress tracking
local success, error = io_module.copy_file('/source/file.txt', '/dest/file.txt')

-- Get file information
local file_info, error = io_module.get_file_info('/path/to/file.txt')
if file_info then
    print("File size:", file_info.size, "bytes")
    print("Last modified:", file_info.mtime)
end

-- List directory with filtering
local entries, error = io_module.list_directory('/path/to/directory', {
    pattern = '*.lua',  -- Only Lua files
    recursive = true   -- Include subdirectories
})

if entries then
    for _, entry in ipairs(entries) do
        print(entry.name, entry.type)
    end
end

-- Create temporary file
local temp_file, error = io_module.create_temp_file('.lua', 'print("hello")')
if temp_file then
    print("Temp file created:", temp_file)
    -- Use temp file...
end

-- Example: Custom event handlers for I/O operations
require('neopilot.events').on(require('neopilot.events').EVENT_TYPES.FILE_READ, function(data)
    -- Log file reads
    print("File read:", data.file_path, "Size:", data.size, "Duration:", data.duration)
end)

require('neopilot.events').on(require('neopilot.events').EVENT_TYPES.NETWORK_REQUEST, function(data)
    -- Log network requests
    print("HTTP request:", data.method, data.url, "Status:", data.status_code)
end)

require('neopilot.events').on(require('neopilot.events').EVENT_TYPES.NETWORK_ERROR, function(data)
    -- Handle network errors
    print("Network error:", data.url, data.error)
    
    -- Show error in virtual text
    require('neopilot.virtual_text').show_error('Network request failed: ' .. data.error)
end)

-- Example: Custom commands for I/O operations
vim.api.nvim_create_user_command('NeopilotReadFile', function(opts)
    local file_path = opts.args
    if not file_path or file_path == '' then
        file_path = vim.fn.input('File path: ')
    end
    
    local content, error = io_module.read_file(file_path)
    if content then
        -- Display content in a new buffer
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, type(content) == 'table' and content or vim.split(content, '\n'))
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_name(buf, file_path)
        print("File loaded successfully")
    else
        print("Error reading file:", error)
    end
end, { nargs = '?', complete = 'file', desc = 'Read file using Neopilot I/O' })

vim.api.nvim_create_user_command('NeopilotHttpRequest', function(opts)
    local url = opts.args
    if not url or url == '' then
        url = vim.fn.input('URL: ')
    end
    
    io_module.http_request_async(url, function(response, error)
        if response then
            -- Display response in a new buffer
            local buf = vim.api.nvim_create_buf(false, true)
            local lines = {
                'Status: ' .. response.status_code,
                'Headers: ' .. vim.inspect(response.headers),
                '',
                'Body:',
                vim.split(response.body, '\n')
            }
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.tbl_flatten(lines))
            vim.api.nvim_set_current_buf(buf)
            vim.api.nvim_buf_set_name(buf, 'HTTP Response')
            print("HTTP request completed")
        else
            print("HTTP request failed:", error)
        end
    end)
    
    require('neopilot.virtual_text').show_progress('Making HTTP request', 50)
end, { nargs = '?', desc = 'Make HTTP request using Neopilot I/O' })

vim.api.nvim_create_user_command('NeopilotClearIOCache', function()
    io_module.clear_caches()
    print("I/O caches cleared")
end, { desc = 'Clear Neopilot I/O caches' })

vim.api.nvim_create_user_command('NeopilotIOStats', function()
    local stats = io_module.get_stats()
    print("I/O Statistics:")
    print("  Active requests:", stats.active_requests)
    print("  File cache size:", stats.file_cache_size)
    print("  Network cache size:", stats.network_cache_size)
    print("  Cache enabled:", stats.config.cache_enabled)
    print("  Cache TTL:", stats.config.cache_ttl .. "ms")
    print("  Max cache size:", stats.config.max_cache_size)
end, { desc = 'Show Neopilot I/O statistics' })

-- Example: Integration with other Neopilot modules

-- Use I/O module for configuration persistence
local function save_config(config_data)
    local config_file = vim.fn.expand('~/.config/neopilot/user_config.json')
    local json_content = vim.fn.json_encode(config_data)
    local success, error = io_module.write_file(config_file, json_content)
    
    if success then
        require('neopilot.virtual_text').show_info('Configuration saved')
    else
        require('neopilot.virtual_text').show_error('Failed to save config: ' .. error)
    end
end

-- Use I/O module for logging
local function write_log_entry(level, message)
    local log_file = vim.fn.expand('~/.cache/neopilot/neopilot.log')
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local log_entry = string.format('[%s] %s: %s\n', timestamp, level, message)
    
    -- Append to log file
    local existing_content, error = io_module.read_file(log_file)
    if not existing_content and error:match('File not readable') then
        existing_content = {}  -- File doesn't exist yet
    end
    
    if existing_content then
        table.insert(existing_content, log_entry)
        io_module.write_file(log_file, existing_content)
    end
end

-- Example: Performance monitoring with I/O
require('neopilot.events').on(require('neopilot.events').EVENT_TYPES.FILE_READ, function(data)
    if data.duration > 1000 then  -- Slow file read (> 1s)
        require('neopilot.virtual_text').show_warning(
            'Slow file read: ' .. data.duration .. 'ms',
            data.file_path:match('([^/]+)$') and tonumber(data.file_path:match(':(%d+)')) or nil
        )
    end
end)
