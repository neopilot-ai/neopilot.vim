-- Neopilot core completion module
local M = {}

local config = require('neopilot.config')
local server = require('neopilot.server')
local ui = require('neopilot.ui')
local doc = require('neopilot.doc')
local util = require('neopilot.util')
local log = require('neopilot.log')
local metrics = require('neopilot.metrics')
local lsp = require('neopilot.lsp')
local virtual_text = require('neopilot.virtual_text')
local events = require('neopilot.events')

-- Completion state
local completion_state = {
    items = {},
    index = 0,
    request_id = 0,
    job = nil,
    request_data = nil
}

-- Performance optimizations
local completion_cache = {}  -- Cache for completion results
local debounce_timer = nil   -- Timer for debouncing
local last_request_time = 0  -- Track request timing
local request_queue = {}     -- Queue for pending requests

-- Cache configuration
local CACHE_TTL = 30000      -- 30 seconds cache TTL
local MIN_REQUEST_INTERVAL = 50 -- Minimum time between requests

-- Setup core module
function M.setup(opts)
    -- Initialize virtual text system
    virtual_text.setup(opts.virtual_text or {})
    
    -- Initialize completion state and cache cleanup
    vim.defer_fn(function()
        M.cleanup_cache()
    end, CACHE_TTL)
end

-- Cache key generation with semantic dimensions
local function generate_cache_key(document, editor_options, context)
    -- Create a comprehensive cache key with all relevant dimensions
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
local function check_cache(cache_key, context)
    local cached = completion_cache[cache_key]
    if not cached then
        return nil
    end

    local age = vim.loop.now() - cached.timestamp
    if age > CACHE_TTL then
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

    metrics.record_cache_hit()
    return cached.data
end

-- Store result in cache with context metadata
local function store_cache(cache_key, data, context)
    completion_cache[cache_key] = {
        data = vim.deepcopy(data),
        timestamp = vim.loop.now(),
        context = vim.deepcopy(context)
    }

    -- Limit cache size
    local cache_keys = vim.tbl_keys(completion_cache)
    if #cache_keys > 50 then
        table.remove(cache_keys, 1)
        completion_cache[cache_keys[1]] = nil
    end
end

-- Cleanup expired cache entries
function M.cleanup_cache()
    local current_time = vim.loop.now()
    local to_remove = {}

    for key, cached in pairs(completion_cache) do
        if (current_time - cached.timestamp) > CACHE_TTL then
            table.insert(to_remove, key)
        end
    end

    for _, key in ipairs(to_remove) do
        completion_cache[key] = nil
    end

    -- Schedule next cleanup
    vim.defer_fn(function()
        M.cleanup_cache()
    end, CACHE_TTL)
end

-- Check if Neopilot is enabled
function M.is_enabled()
    return config.is_enabled()
end

-- Clear current completions with request cancellation
function M.clear()
    -- Cancel any active request
    active_request_id = nil

    -- Cancel debounce timer
    if debounce_timer then
        vim.fn.timer_stop(debounce_timer)
        debounce_timer = nil
    end

    -- Clear UI and virtual text
    ui.clear_completion()
    virtual_text.clear_completion()

    -- Reset state
    completion_state.items = {}
    completion_state.index = 0
    completion_state.request_id = 0
    completion_state.request_data = nil
end

-- Get completion context with semantic awareness
function M.get_completion_context()
    local context = {
        filetype = vim.bo.filetype,
        mode = vim.fn.mode(),
        cursor_offset = doc.get_cursor_offset(),
        has_selection = vim.fn.mode() == 'v' or vim.fn.mode() == 'V',
        model_id = config.get('model_id') or 'default',
        prompt_type = 'completion'
    }

    -- Add selection information
    if context.has_selection then
        local start_pos = vim.fn.getpos("'<")
        local end_pos = vim.fn.getpos("'>")
        context.selection_start = util.position_to_offset(start_pos[2], start_pos[3])
        context.selection_end = util.position_to_offset(end_pos[2], end_pos[3])
    end

    -- Add semantic context (Treesitter-aware when available)
    context.semantic_context = M.get_semantic_context()

    -- Add function/class boundary hash for fuzzy caching
    context.function_hash = M.get_function_boundary_hash()

    -- Add LSP diagnostics to the context
    context.diagnostics = lsp.get_diagnostics()

    return context
end

-- Get imports using Treesitter
local function get_imports(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local imports = {}
    if not vim.treesitter then
        return imports
    end

    local lang = vim.bo.filetype
    if not pcall(vim.treesitter.get_parser, lang) then
        return imports
    end

    local parser = vim.treesitter.get_parser(lang, bufnr)
    if not parser then
        return imports
    end

    local tree = parser:parse()[1]
    if not tree then
        return imports
    end

    -- Example queries for common languages (these would ideally be in a separate config)
    local queries = {
        python = [[(import_statement (dotted_name (identifier) @name)) (from_statement (dotted_name (identifier) @name))]],
        javascript = [[(import_statement (import_clause (identifier) @name)) (import_statement (named_imports (import_specifier (identifier) @name)))]],
        lua = [[(call_expression (identifier) @name (#eq? @name "require"))]],
        -- Add more languages as needed
    }

    local query_str = queries[lang]
    if not query_str then
        return imports
    end

    local query = vim.treesitter.query.parse(lang, query_str)
    for id, node in query:iter_captures(tree:root(), bufnr) do
        local name = query.captures[id]
        table.insert(imports, vim.treesitter.get_node_text(node, bufnr))
    end

    return imports
end

-- Get semantic context using Treesitter when available
function M.get_semantic_context()
    local semantic = {
        in_function = false,
        in_class = false,
        function_name = nil,
        class_name = nil,
        imports = {},
        current_scope = 'global'
    }

    -- Try Treesitter first
    if vim.treesitter then
        local ok, parser = pcall(vim.treesitter.get_parser)
        if ok and parser then
            local tree = parser:parse()[1]
            if tree then
                local cursor = vim.api.nvim_win_get_cursor(0)
                local node = tree:root():descendant_for_range(cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2])

                -- Walk up to find function/class context
                while node do
                    local node_type = node:type()
                    if node_type:match('function') or node_type:match('method') then
                        semantic.in_function = true
                        -- Try to extract function name
                        for child in node:iter_children() do
                            if child:type() == 'identifier' or child:type() == 'name' then
                                semantic.function_name = vim.treesitter.get_node_text(child, 0)
                                break
                            end
                        end
                        semantic.current_scope = 'function'
                        break
                    elseif node_type:match('class') or node_type:match('struct') then
                        semantic.in_class = true
                        -- Try to extract class name
                        for child in node:iter_children() do
                            if child:type() == 'identifier' or child:type() == 'name' then
                                semantic.class_name = vim.treesitter.get_node_text(child, 0)
                                break
                            end
                        end
                        semantic.current_scope = 'class'
                        break
                    end
                    node = node:parent()
                end
            end
        end
    end

    -- Fallback to regex-based detection for Vim users
    if not semantic.in_function and not semantic.in_class then
        semantic = M.get_semantic_context_fallback()
    end

    -- Add import statements
    semantic.imports = get_imports(vim.api.nvim_get_current_buf())

    return semantic
end

-- Fallback semantic context using regex
function M.get_semantic_context_fallback()
    local semantic = {
        in_function = false,
        in_class = false,
        function_name = nil,
        class_name = nil,
        current_scope = 'global'
    }

    local current_line = vim.fn.line('.')
    local lines = vim.api.nvim_buf_get_lines(0, 0, current_line, false)

    -- Simple regex patterns for common languages
    local patterns = {
        python = {
            func = '^%s*def%s+([%w_]+)',
            class = '^%s*class%s+([%w_]+)'
        },
        javascript = {
            func = '^%s*function%s+([%w_]+)|^%s*const%s+([%w_]+)%s*=.*=>',
            class = '^%s*class%s+([%w_]+)'
        },
        lua = {
            func = '^%s*function%s+([%w_.:]+)',
            class = nil -- Lua doesn't have classes
        }
    }

    local ft_patterns = patterns[vim.bo.filetype] or patterns.python

    -- Scan backwards for function/class definitions
    for i = #lines, 1, -1 do
        local line = lines[i]

        if ft_patterns.func then
            local func_name = line:match(ft_patterns.func)
            if func_name then
                semantic.in_function = true
                semantic.function_name = func_name
                semantic.current_scope = 'function'
                break
            end
        end

        if ft_patterns.class then
            local class_name = line:match(ft_patterns.class)
            if class_name then
                semantic.in_class = true
                semantic.class_name = class_name
                semantic.current_scope = 'class'
                break
            end
        end
    end

    return semantic
end

-- Get function boundary hash for fuzzy caching
function M.get_function_boundary_hash()
    local semantic = M.get_semantic_context()
    if semantic.in_function and semantic.function_name then
        return string.format("%s:%s:%s", vim.bo.filetype, semantic.current_scope, semantic.function_name)
    elseif semantic.in_class and semantic.class_name then
        return string.format("%s:%s:%s", vim.bo.filetype, semantic.current_scope, semantic.class_name)
    else
        return string.format("%s:global", vim.bo.filetype)
    end
end

-- Request cancellation support
local active_request_id = nil
local request_counter = 0

-- Handle completions response with cancellation check
local function handle_completions_response(response, status, request_id, start_time)
    -- Check if this request is still active
    if active_request_id ~= request_id then
        log.debug("Discarding stale completion response")
        metrics.record_request_cancelled()
        return
    end

    -- Record response time
    if start_time then
        local response_time = vim.loop.now() - start_time
        metrics.record_response_time(response_time)
    end

    if not response or status ~= 0 then
        log.error("Invalid response from language server")
        metrics.record_error("invalid_response")
        virtual_text.show_error('Failed to get completion')
        return
    end

    local completion_items = response.completionItems or {}
    completion_state.items = completion_items
    completion_state.index = 0

    -- Cache the result with context metadata
    if completion_state.request_data then
        local document = completion_state.request_data.document
        local editor_options = completion_state.request_data.editor_options
        local context = completion_state.request_data.context
        local cache_key = generate_cache_key(document, editor_options, context)
        store_cache(cache_key, completion_items, context)
    end

    -- Clear progress and show completion
    virtual_text.clear_completion()
    M.render_current_completion()
end

-- Request completions from server with cancellation
function M.request_completions()
    if not M.is_enabled() then
        return
    end

    -- Validate that we have a valid document
    local document = doc.get_current_document()
    if not document.text or document.text == '' then
        log.warn("Cannot complete: empty document")
        return
    end

    local editor_options = doc.get_editor_options()
    local context = M.get_completion_context()
    local cache_key = generate_cache_key(document, editor_options, context)

    -- Check cache first
    local cached_result = check_cache(cache_key, context)
    if cached_result then
        log.debug("Using cached completion result")
        completion_state.items = cached_result
        completion_state.index = 0
        M.render_current_completion()
        return
    end

    metrics.record_cache_miss()

    -- Show progress indicator
    virtual_text.show_progress('Requesting completion', 25)

    -- Generate new request ID and cancel any active request
    request_counter = request_counter + 1
    local current_request_id = request_counter
    active_request_id = current_request_id

    metrics.record_request_start()
    
    -- Update progress
    virtual_text.show_progress('Requesting completion', 50)

    local params = {
        metadata = server.request_metadata(),
        document = document,
        editor_options = editor_options,
        context = context,
        api_server_params = {
            api_timeout_ms = config.get('api_timeout_ms'),
            first_temperature = config.get('first_temperature'),
            max_completions = config.get('max_completions'),
            max_newlines = config.get('max_newlines'),
            max_tokens = config.get('max_tokens'),
            min_log_probability = config.get('min_log_probability'),
            temperature = config.get('temperature'),
            top_k = config.get('top_k'),
            top_p = config.get('top_p')
        }
    }

    -- Check for identical request
    if vim.deep_equal(completion_state.request_data, params) then
        return
    end

    completion_state.request_data = vim.deepcopy(params)

    -- Add request ID
    params.metadata.request_id = current_request_id
    completion_state.request_id = current_request_id

    -- Send request with cancellation callback
    server.request('GetCompletions', params, function(response)
        -- This assumes the server's JSON-RPC response has a 'result' field
        -- and the 'status' is implicitly 0 (success) if the callback is called.
        handle_completions_response(response, 0, current_request_id, request_start_time)
    end)
end

-- Render current completion
function M.render_current_completion()
    local current_item = M.get_current_completion_item()
    if not current_item then
        ui.clear_completion()
        virtual_text.clear_completion()
        return
    end

    -- Check if we're on the correct line
    local start_offset = current_item.range and current_item.range.startOffset or 0
    local start_row = util.offset_to_position(start_offset)
    if start_row ~= vim.fn.line('.') then
        log.info("Ignoring completion, line number is not the current line.")
        ui.clear_completion()
        virtual_text.clear_completion()
        return
    end

    -- Use virtual text for inline display
    virtual_text.show_completion(current_item)
    
    -- Also use traditional UI for compatibility
    ui.render_completion(current_item)
    
    -- Emit completion shown event
    events.emit(events.EVENT_TYPES.COMPLETION_SHOWN, {
        item = current_item
    }, { source = 'core' })
    
    vim.cmd('doautocmd User NeopilotCompletionShown')
end

-- Get current completion item
function M.get_current_completion_item()
    if not completion_state.items or
       completion_state.index < 0 or
       completion_state.index >= #completion_state.items then
        return nil
    end
    return completion_state.items[completion_state.index + 1] -- Lua is 1-indexed
end

-- Cycle through completions
function M.cycle_completions(direction)
    if not M.get_current_completion_item() then
        return
    end

    completion_state.index = completion_state.index + direction
    local n_items = #completion_state.items

    if completion_state.index < 0 then
        completion_state.index = n_items - 1
    elseif completion_state.index >= n_items then
        completion_state.index = 0
    end

    M.render_current_completion()
    metrics.record_completion_cycle()

-- Accept current completion
function M.accept_completion()
    local mode = vim.fn.mode()
    if not (mode == 'i' or mode == 'R') then
        return ''
    end

    local current_item = M.get_current_completion_item()
    if not current_item then
        local fallback = config.get('tab_fallback')
        if fallback then
            return fallback
        end
        return vim.fn.pumvisible() == 1 and '\14' or '\t' -- <C-N> or <Tab>
    end

    vim.cmd('doautocmd User NeopilotCompletionAccepted')

    local range = current_item.range or {}
    local start_offset = range.startOffset or 0
    local end_offset = range.endOffset or 0

    local start_row, start_col = util.offset_to_position(start_offset)
    local end_row, end_col = util.offset_to_position(end_offset)

    local completion = current_item.completion or {}
    local suffix = completion.suffix or {}
    local suffix_text = suffix.text or ''

    local text = (completion.text or '') .. suffix_text
    if text == '' then
        local fallback = config.get('tab_fallback')
        if fallback then
            return fallback
        end
        return vim.fn.pumvisible() == 1 and '\14' or '\t'
    end

    -- Handle multi-line completions
    local lines = vim.split(text, '\n', { plain = true })
    if #lines > 1 then
        -- Multi-line completion
        M.completion_text = text
        local insert_text = vim.api.nvim_replace_termcodes('<C-R><C-O>=luaeval("require(\'neopilot.core\').get_completion_text()")<CR>', true, true, true)
        local move_to_start = M.get_move_to_position_command(start_row, start_col)
        local delete_text = move_to_start .. M.get_delete_command(start_row, start_col, end_row, end_col)
        return delete_text .. insert_text
    else
        -- Single-line completion - use optimized insertion
        return M.insert_single_line_completion(text, start_row, start_col, end_row, end_col, completion.completionId)
    end
end

-- Optimized single-line completion insertion
function M.insert_single_line_completion(text, start_row, start_col, end_row, end_col, completion_id)
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
    server.request('AcceptCompletion', {
        metadata = server.request_metadata(),
        completion_id = completion_id
    })

    metrics.record_completion_accept()

    return ''
end

-- Get stored completion text
function M.get_completion_text()
    return M.completion_text or ''
end

-- Generate move to position command
function M.get_move_to_position_command(row, col)
    return string.format(vim.api.nvim_replace_termcodes('<C-O>:call cursor(%d,%d)<CR>', true, true, true), row, col)
end

-- Generate delete command
function M.get_delete_command(start_row, start_col, end_row, end_col)
    if start_row == end_row then
        if end_col > start_col then
            return string.format(vim.api.nvim_replace_termcodes('<C-O>d%d', true, true, true), end_col - start_col) .. 'l'
        end
        return ""
    else
        -- Delete last line, then intermediate lines
        return vim.api.nvim_replace_termcodes('<C-O>d0', true, true, true) ..
               M.get_move_to_position_command(start_row, start_col) ..
               string.rep(vim.api.nvim_replace_termcodes('<C-O>DJ', true, true, true), end_row - start_row) ..
               vim.api.nvim_replace_termcodes('<C-O>dl', true, true, true)
    end
end

-- Debounced completion request with improved performance
function M.debounced_complete()
    M.clear()
    local current_buf = vim.api.nvim_get_current_buf()
    local delay = config.get('idle_delay')

    -- Cancel existing timer
    if debounce_timer then
        vim.fn.timer_stop(debounce_timer)
        debounce_timer = nil
    end

    -- Set new timer
    debounce_timer = vim.fn.timer_start(delay, function()
        debounce_timer = nil
        -- Check if we're still in the same buffer and mode
        if vim.api.nvim_get_current_buf() == current_buf and
           string.find(vim.fn.mode(), '^[iR]') then
            -- Rate limiting
            local now = vim.loop.now()
            if now - last_request_time > MIN_REQUEST_INTERVAL then
                last_request_time = now
                M.request_completions()
            end
        end
    end)
end

-- Streaming completion support (future-ready)
local streaming_state = {
    active = false,
    chunks = {},
    current_text = "",
    on_chunk_callback = nil,
    on_complete_callback = nil
}

-- Apply a workspace edit to the current buffer
local function apply_workspace_edit(edit)
    if not edit or not edit.changes then
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    for uri, changes in pairs(edit.changes) do
        -- Assuming changes apply to the current buffer for now
        -- In a real LSP client, you'd match uri to bufnr
        if uri:match(vim.fn.bufname(bufnr)) then
            for _, change in ipairs(changes) do
                local start_line = change.range.start.line
                local start_col = change.range.start.character
                local end_line = change.range.end.line
                local end_col = change.range.end.character
                local new_text = change.newText

                -- Apply changes using nvim_buf_set_text
                vim.api.nvim_buf_set_text(bufnr, start_line, start_col, end_line, end_col, vim.split(new_text, '\n', true))
            end
        end
    end
end

-- Get code actions from the server
function M.get_code_actions()
    if not server.is_running() then
        log.warn("Cannot request code actions: server is not running.")
        return
    end

    local document = doc.get_current_document()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local line = cursor_pos[1] - 1
    local char = cursor_pos[2]

    local range = {
        start = { line = line, character = char },
        ['end'] = { line = line, character = char },
    }

    local context = {
        diagnostics = lsp.get_diagnostics(),
    }

    server.request_code_actions(document, range, context, function(response)
        if not response or #response == 0 then
            log.info("No code actions available from Neopilot.")
            vim.notify("Neopilot: No code actions available.", vim.log.levels.INFO)
            return
        end

        local action_titles = {}
        for _, action in ipairs(response) do
            table.insert(action_titles, action.title)
        end

        -- Display code actions to the user
        vim.ui.select(action_titles, {
            prompt = "Neopilot Code Actions:",
            kind = 'code_action',
        }, function(selected_title)
            if not selected_title then
                log.info("No code action selected.")
                return
            end

            for _, action in ipairs(response) do
                if action.title == selected_title then
                    -- Apply the selected code action
                    if action.edit then
                        apply_workspace_edit(action.edit)
                        log.info("Code action applied: " .. action.title)
                    elseif action.command then
                        log.warn("Code action command execution not yet implemented: " .. action.command.command)
                        vim.notify("Neopilot: Code action command execution not yet implemented.", vim.log.levels.WARN)
                    end
                    break
                end
            end
        end)
    end)
end

-- Stop streaming
function M.stop_streaming()
    streaming_state.active = false
    streaming_state.chunks = {}
    streaming_state.current_text = ""
    streaming_state.on_chunk_callback = nil
    streaming_state.on_complete_callback = nil
end

-- Get refactor actions from the server
function M.get_refactor_actions()
    if not server.is_running() then
        log.warn("Cannot request refactor actions: server is not running.")
        return
    end

    local document = doc.get_current_document()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local line = cursor_pos[1] - 1
    local char = cursor_pos[2]

    local range = {
        start = { line = line, character = char },
        ['end'] = { line = line, character = char },
    }

    local context = {
        diagnostics = lsp.get_diagnostics(), -- Include diagnostics as context for refactoring
    }

    server.request_refactor_actions(document, range, context, function(response)
        if not response or #response == 0 then
            log.info("No refactor actions available from Neopilot.")
            vim.notify("Neopilot: No refactor actions available.", vim.log.levels.INFO)
            return
        end

        local action_titles = {}
        for _, action in ipairs(response) do
            table.insert(action_titles, action.title)
        end

        -- Display refactor actions to the user
        vim.ui.select(action_titles, {
            prompt = "Neopilot Refactor Actions:",
            kind = 'refactor',
        }, function(selected_title)
            if not selected_title then
                log.info("No refactor action selected.")
                return
            end

            for _, action in ipairs(response) do
                if action.title == selected_title then
                    -- Apply the selected refactor action
                    if action.edit then
                        apply_workspace_edit(action.edit)
                        log.info("Refactor action applied: " .. action.title)
                    elseif action.command then
                        log.warn("Refactor action command execution not yet implemented: " .. action.command.command)
                        vim.notify("Neopilot: Refactor action command execution not yet implemented.", vim.log.levels.WARN)
                    end
                    break
                end
            end
        end)
    end)
end

return M