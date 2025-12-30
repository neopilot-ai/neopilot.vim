-- Modernized core module with dependency injection
-- Replaces global state with proper dependency injection
local M = {}

-- Dependencies will be injected
local config, log, events, error_handler, treesitter, server

-- Completion state (now scoped to instance)
local function create_completion_state()
    return {
        items = {},
        index = 0,
        request_id = 0,
        job = nil,
        request_data = nil
    }
end

-- Performance optimizations (now scoped)
local function create_performance_state()
    return {
        cache = {},
        debounce_timer = nil,
        last_request_time = 0,
        request_queue = {}
    }
end

-- Create a new core instance with injected dependencies
function M.new(dependencies)
    dependencies = dependencies or {}
    
    local self = setmetatable({}, { __index = M })
    
    -- Inject dependencies
    self.config = dependencies.config or require('neopilot.config')
    self.log = dependencies.log or require('neopilot.log')
    self.events = dependencies.events or require('neopilot.events')
    self.error_handler = dependencies.error_handler or require('neopilot.error')
    self.treesitter = dependencies.treesitter or require('neopilot.treesitter')
    self.server = dependencies.server or require('neopilot.server')
    
    -- Initialize state
    self.completion_state = create_completion_state()
    self.performance_state = create_performance_state()
    
    -- Setup event listeners
    self:setup_event_listeners()
    
    self.log.info("Core instance created with dependency injection")
    return self
end

-- Setup event listeners for this instance
function M:setup_event_listeners()
    -- Listen for configuration changes
    self.events.on(self.events.EVENT_TYPES.CONFIG_CHANGED, function(data)
        if data.key == 'idle_delay' or data.key == 'cache_ttl' then
            self.log.info("Configuration changed, updating core behavior")
        end
    end, { source = 'core' })
    
    -- Listen for error events
    self.events.on(self.events.EVENT_TYPES.ERROR_OCCURRED, function(data)
        if data.context and data.context.operation == 'completion_request' then
            self.log.warn("Completion request failed, checking recovery options")
        end
    end, { source = 'core' })
    
    -- Listen for server events
    self.events.on(self.events.EVENT_TYPES.SERVER_STOPPED, function(data)
        self:clear()
    end, { source = 'core' })
end

-- Setup the core module
function M:setup(opts)
    opts = opts or {}
    
    -- Initialize cache cleanup
    vim.defer_fn(function()
        self:cleanup_cache()
    end, self.config.get('cache_ttl') or 30000)
    
    self.log.info("Core module setup completed")
end

-- Check if Neopilot is enabled
function M:is_enabled()
    return self.config.is_enabled()
end

-- Clear current completions with request cancellation
function M:clear()
    -- Cancel any active request
    self.completion_state.request_id = nil

    -- Cancel debounce timer
    if self.performance_state.debounce_timer then
        vim.fn.timer_stop(self.performance_state.debounce_timer)
        self.performance_state.debounce_timer = nil
    end

    -- Reset state
    self.completion_state = create_completion_state()
    
    -- Emit completion cleared event
    self.events.emit(self.events.EVENT_TYPES.COMPLETION_REJECTED, {}, { source = 'core' })
end

-- Get completion context with semantic awareness
function M:get_completion_context()
    local context = {
        filetype = vim.bo.filetype,
        mode = vim.fn.mode(),
        cursor_offset = self:get_cursor_offset(),
        has_selection = vim.fn.mode() == 'v' or vim.fn.mode() == 'V',
        model_id = self.config.get('model_id') or 'default',
        prompt_type = 'completion'
    }

    -- Add selection information
    if context.has_selection then
        local start_pos = vim.fn.getpos("'<")
        local end_pos = vim.fn.getpos("'>")
        local util = require('neopilot.util')
        context.selection_start = util.position_to_offset(start_pos[2], start_pos[3])
        context.selection_end = util.position_to_offset(end_pos[2], end_pos[3])
    end

    -- Add semantic context using injected treesitter
    context.semantic_context = self.treesitter.get_semantic_context()
    
    -- Add function boundary hash for fuzzy caching
    context.function_boundary_hash = self.treesitter.get_function_boundary_hash()

    -- Add LSP diagnostics
    local lsp = require('neopilot.lsp')
    context.diagnostics = lsp.get_diagnostics()

    return context
end

-- Get cursor offset (extracted from doc module)
function M:get_cursor_offset()
    local util = require('neopilot.util')
    local cursor = vim.api.nvim_win_get_cursor(0)
    return util.position_to_offset(cursor[1], cursor[2])
end

-- Get current document (extracted from doc module)
function M:get_current_document()
    local doc = require('neopilot.doc')
    return doc.get_current_document()
end

-- Get editor options (extracted from doc module)
function M:get_editor_options()
    local doc = require('neopilot.doc')
    return doc.get_editor_options()
end

-- Cache key generation with semantic dimensions
function M:generate_cache_key(document, editor_options, context)
    local key_components = {
        document.language or 'unknown',
        document.cursor_offset or 0,
        document.selection_start or document.cursor_offset or 0,
        document.selection_end or document.cursor_offset or 0,
        vim.api.nvim_buf_get_changedtick(0),
        editor_options.tab_size .. ':' .. (editor_options.insert_spaces and '1' or '0'),
        context.filetype or '',
        context.mode or 'insert',
        context.has_selection and '1' or '0',
        context.model_id or 'default',
        context.prompt_type or 'completion'
    }

    return table.concat(key_components, '|')
end

-- Enhanced cache with semantic tiers
function M:check_cache(cache_key, context)
    local cached = self.performance_state.cache[cache_key]
    if not cached then
        return nil
    end

    local age = vim.loop.now() - cached.timestamp
    if age > (self.config.get('cache_ttl') or 30000) then
        return nil
    end

    -- Check if cache entry is appropriate for current context
    local cache_context = cached.context or {}
    local current_context = context or {}

    -- Strict mode: exact cursor match required
    if cache_context.mode == 'strict' then
        if cache_context.cursor_offset ~= current_context.cursor_offset then
            return nil
        end
    end

    -- Fuzzy mode: allow some context reuse
    if cache_context.mode == 'fuzzy' then
        -- Allow reuse within same function/class boundary
        if cache_context.function_hash ~= current_context.function_hash then
            return nil
        end
    end

    -- Emit cache hit event
    self.events.emit(self.events.EVENT_TYPES.CACHE_HIT, {
        cache_key = cache_key,
        age = age
    }, { source = 'core' })

    return cached.data
end

-- Store result in cache with context metadata
function M:store_cache(cache_key, data, context)
    self.performance_state.cache[cache_key] = {
        data = vim.deepcopy(data),
        timestamp = vim.loop.now(),
        context = vim.deepcopy(context)
    }

    -- Limit cache size
    local cache_keys = vim.tbl_keys(self.performance_state.cache)
    local max_cache_size = self.config.get('max_cache_size') or 50
    if #cache_keys > max_cache_size then
        table.remove(cache_keys, 1)
        self.performance_state.cache[cache_keys[1]] = nil
    end
end

-- Cleanup expired cache entries
function M:cleanup_cache()
    local current_time = vim.loop.now()
    local to_remove = {}
    local cache_ttl = self.config.get('cache_ttl') or 30000

    for key, cached in pairs(self.performance_state.cache) do
        if (current_time - cached.timestamp) > cache_ttl then
            table.insert(to_remove, key)
        end
    end

    for _, key in ipairs(to_remove) do
        self.performance_state.cache[key] = nil
    end

    -- Schedule next cleanup
    vim.defer_fn(function()
        self:cleanup_cache()
    end, cache_ttl)
end

-- Request completions from server with error handling
function M:request_completions()
    if not self:is_enabled() then
        return
    end

    -- Emit before request event
    self.events.emit(self.events.EVENT_TYPES.BEFORE_REQUEST, {
        operation = 'completion_request'
    }, { source = 'core' })

    -- Use error handler for safe execution
    return self.error_handler.safe_call(function()
        return self:do_request_completions()
    end, {
        operation = 'completion_request',
        retry_function = function()
            return self:request_completions()
        end,
        fallback_function = function()
            return self:handle_completion_fallback()
        end
    })
end

-- Internal completion request implementation
function M:do_request_completions()
    -- Validate that we have a valid document
    local document = self:get_current_document()
    if not document.text or document.text == '' then
        self.log.warn("Cannot complete: empty document")
        return
    end

    local editor_options = self:get_editor_options()
    local context = self:get_completion_context()
    local cache_key = self:generate_cache_key(document, editor_options, context)

    -- Check cache first
    local cached_result = self:check_cache(cache_key, context)
    if cached_result then
        self.log.debug("Using cached completion result")
        self.completion_state.items = cached_result
        self.completion_state.index = 0
        self:render_current_completion()
        return
    end

    -- Emit cache miss event
    self.events.emit(self.events.EVENT_TYPES.CACHE_MISS, {
        cache_key = cache_key
    }, { source = 'core' })

    -- Generate new request ID and cancel any active request
    self.completion_state.request_id = self.completion_state.request_id + 1
    local current_request_id = self.completion_state.request_id

    local params = {
        metadata = self.server.request_metadata(),
        document = document,
        editor_options = editor_options,
        context = context,
        api_server_params = {
            api_timeout_ms = self.config.get('api_timeout_ms'),
            first_temperature = self.config.get('first_temperature'),
            max_completions = self.config.get('max_completions'),
            max_newlines = self.config.get('max_newlines'),
            max_tokens = self.config.get('max_tokens'),
            min_log_probability = self.config.get('min_log_probability'),
            temperature = self.config.get('temperature'),
            top_k = self.config.get('top_k'),
            top_p = self.config.get('top_p')
        }
    }

    -- Check for identical request
    if vim.deep_equal(self.completion_state.request_data, params) then
        return
    end

    self.completion_state.request_data = vim.deepcopy(params)

    -- Add request ID
    params.metadata.request_id = current_request_id
    self.completion_state.request_id = current_request_id

    -- Send request with error handling
    self.server.request('GetCompletions', params, function(response)
        self:handle_completions_response(response, 0, current_request_id)
    end)
end

-- Handle completions response with error handling
function M:handle_completions_response(response, status, request_id)
    -- Check if this request is still active
    if self.completion_state.request_id ~= request_id then
        self.log.debug("Discarding stale completion response")
        return
    end

    if not response or status ~= 0 then
        self.log.error("Invalid response from language server")
        self.error_handler.handle_error('invalid_response', response, {
            operation = 'completion_response'
        })
        return
    end

    local completion_items = response.completionItems or {}
    self.completion_state.items = completion_items
    self.completion_state.index = 0

    -- Cache the result with context metadata
    if self.completion_state.request_data then
        local document = self.completion_state.request_data.document
        local editor_options = self.completion_state.request_data.editor_options
        local context = self.completion_state.request_data.context
        local cache_key = self:generate_cache_key(document, editor_options, context)
        self:store_cache(cache_key, completion_items, context)
    end

    -- Emit completion received event
    self.events.emit(self.events.EVENT_TYPES.COMPLETION_RECEIVED, {
        items = completion_items,
        count = #completion_items
    }, { source = 'core' })

    self:render_current_completion()
end

-- Handle completion fallback
function M:handle_completion_fallback()
    self.log.info("Using completion fallback")
    -- Could implement fallback logic here
    return nil
end

-- Render current completion
function M:render_current_completion()
    local current_item = self:get_current_completion_item()
    if not current_item then
        local ui = require('neopilot.ui')
        ui.clear_completion()
        return
    end

    -- Check if we're on the correct line
    local util = require('neopilot.util')
    local start_offset = current_item.range and current_item.range.startOffset or 0
    local start_row = util.offset_to_position(start_offset)
    if start_row ~= vim.fn.line('.') then
        self.log.info("Ignoring completion, line number is not the current line.")
        local ui = require('neopilot.ui')
        ui.clear_completion()
        return
    end

    local ui = require('neopilot.ui')
    ui.render_completion(current_item)
    
    -- Emit completion shown event
    self.events.emit(self.events.EVENT_TYPES.COMPLETION_SHOWN, {
        item = current_item
    }, { source = 'core' })
end

-- Get current completion item
function M:get_current_completion_item()
    if not self.completion_state.items or
       self.completion_state.index < 0 or
       self.completion_state.index >= #self.completion_state.items then
        return nil
    end
    return self.completion_state.items[self.completion_state.index + 1] -- Lua is 1-indexed
end

-- Cycle through completions
function M:cycle_completions(direction)
    if not self:get_current_completion_item() then
        return
    end

    self.completion_state.index = self.completion_state.index + direction
    local n_items = #self.completion_state.items

    if self.completion_state.index < 0 then
        self.completion_state.index = n_items - 1
    elseif self.completion_state.index >= n_items then
        self.completion_state.index = 0
    end

    self:render_current_completion()
end

-- Accept current completion
function M:accept_completion()
    local mode = vim.fn.mode()
    if not (mode == 'i' or mode == 'R') then
        return ''
    end

    local current_item = self:get_current_completion_item()
    if not current_item then
        local fallback = self.config.get('tab_fallback')
        if fallback then
            return fallback
        end
        return vim.fn.pumvisible() == 1 and '\14' or '\t' -- <C-N> or <Tab>
    end

    -- Emit completion accepted event
    self.events.emit(self.events.EVENT_TYPES.COMPLETION_ACCEPTED, {
        item = current_item
    }, { source = 'core' })

    local range = current_item.range or {}
    local start_offset = range.startOffset or 0
    local end_offset = range.endOffset or 0

    local util = require('neopilot.util')
    local start_row, start_col = util.offset_to_position(start_offset)
    local end_row, end_col = util.offset_to_position(end_offset)

    local completion = current_item.completion or {}
    local suffix = completion.suffix or {}
    local suffix_text = suffix.text or ''

    local text = (completion.text or '') .. suffix_text
    if text == '' then
        local fallback = self.config.get('tab_fallback')
        if fallback then
            return fallback
        end
        return vim.fn.pumvisible() == 1 and '\14' or '\t'
    end

    -- Handle multi-line completions
    local lines = vim.split(text, '\n', { plain = true })
    if #lines > 1 then
        -- Multi-line completion
        self.completion_text = text
        local insert_text = vim.api.nvim_replace_termcodes('<C-R><C-O>=luaeval("require(\'neopilot.core\').get_completion_text()")<CR>', true, true, true)
        local move_to_start = self:get_move_to_position_command(start_row, start_col)
        local delete_text = move_to_start .. self:get_delete_command(start_row, start_col, end_row, end_col)
        return delete_text .. insert_text
    else
        -- Single-line completion - use optimized insertion
        return self:insert_single_line_completion(text, start_row, start_col, end_row, end_col, completion.completionId)
    end
end

-- Optimized single-line completion insertion
function M:insert_single_line_completion(text, start_row, start_col, end_row, end_col, completion_id)
    -- For single-line completions, we can use more efficient insertion
    local current_line = vim.fn.getline('.')
    local before_cursor = current_line:sub(1, vim.fn.col('.') - 1)
    local after_cursor = current_line:sub(vim.fn.col('.'))

    -- Replace the text in the current line
    local new_line = before_cursor .. text .. after_cursor
    vim.fn.setline('.', new_line)

    -- Move cursor to end of inserted text
    local new_col = #before_cursor + #text + 1
    vim.fn.cursor(vim.fn.line('.'), new_col)

    -- Send accept completion request
    self.server.request('AcceptCompletion', {
        metadata = self.server.request_metadata(),
        completion_id = completion_id
    })

    return ''
end

-- Get stored completion text
function M.get_completion_text()
    -- This is a class method, not instance method
    return M.completion_text or ''
end

-- Generate move to position command
function M:get_move_to_position_command(row, col)
    return string.format(vim.api.nvim_replace_termcodes('<C-O>:call cursor(%d,%d)<CR>', true, true, true), row, col)
end

-- Generate delete command
function M:get_delete_command(start_row, start_col, end_row, end_col)
    if start_row == end_row then
        if end_col > start_col then
            return string.format(vim.api.nvim_replace_termcodes('<C-O>d%d', true, true, true), end_col - start_col) .. 'l'
        end
        return ""
    else
        -- Delete last line, then intermediate lines
        return vim.api.nvim_replace_termcodes('<C-O>d0', true, true, true) ..
               self:get_move_to_position_command(start_row, start_col) ..
               string.rep(vim.api.nvim_replace_termcodes('<C-O>DJ', true, true, true), end_row - start_row) ..
               vim.api.nvim_replace_termcodes('<C-O>dl', true, true, true)
    end
end

-- Debounced completion request with improved performance
function M:debounced_complete()
    self:clear()
    local current_buf = vim.api.nvim_get_current_buf()
    local delay = self.config.get('idle_delay') or 75

    -- Cancel existing timer
    if self.performance_state.debounce_timer then
        vim.fn.timer_stop(self.performance_state.debounce_timer)
        self.performance_state.debounce_timer = nil
    end

    -- Set new timer
    self.performance_state.debounce_timer = vim.fn.timer_start(delay, function()
        self.performance_state.debounce_timer = nil
        -- Check if we're still in the same buffer and mode
        if vim.api.nvim_get_current_buf() == current_buf and
           string.find(vim.fn.mode(), '^[iR]') then
            -- Rate limiting
            local now = vim.loop.now()
            local min_interval = self.config.get('min_request_interval') or 50
            if now - self.performance_state.last_request_time > min_interval then
                self.performance_state.last_request_time = now
                self:request_completions()
            end
        end
    end)
end

-- Legacy compatibility functions (for backward compatibility)
M.setup = function(opts) return M:new():setup(opts) end
M.is_enabled = function() return M:new():is_enabled() end
M.clear = function() return M:new():clear() end
M.request_completions = function() return M:new():request_completions() end
M.get_current_completion_item = function() return M:new():get_current_completion_item() end
M.accept_completion = function() return M:new():accept_completion() end
M.cycle_completions = function(direction) return M:new():cycle_completions(direction) end
M.debounced_complete = function() return M:new():debounced_complete() end

return M
