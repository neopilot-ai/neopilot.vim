-- Virtual text module for Neopilot
-- Provides inline completion display and visual feedback
local M = {}

local config = require('neopilot.config')
local log = require('neopilot.log')
local events = require('neopilot.events')
local util = require('neopilot.util')

-- Virtual text state
local state = {
    enabled = true,
    ns_id = nil,
    active_completions = {},
    extmarks = {},
    highlights = {},
    animations = {}
}

-- Default configuration
local default_config = {
    enabled = true,
    position = 'inline', -- 'inline' or 'float'
    show_confidence = true,
    show_icons = true,
    animate_transitions = true,
    max_width = 80,
    timeout = 5000,
    highlights = {
        completion = 'NeopilotCompletion',
        confidence_high = 'NeopilotConfidenceHigh',
        confidence_medium = 'NeopilotConfidenceMedium',
        confidence_low = 'NeopilotConfidenceLow',
        icon = 'NeopilotIcon',
        ghost_text = 'NeopilotGhostText'
    }
}

-- Initialize virtual text system
function M.setup(opts)
    opts = opts or {}
    local user_config = vim.tbl_deep_extend('force', default_config, opts)
    
    state.enabled = user_config.enabled
    state.config = user_config
    
    -- Create namespace
    state.ns_id = vim.api.nvim_create_namespace('neopilot_virtual_text')
    
    -- Setup highlights
    M.setup_highlights()
    
    -- Setup event listeners
    M.setup_events()
    
    log.info("Virtual text module initialized")
end

-- Setup default highlights
function M.setup_highlights()
    local highlights = state.config.highlights
    
    -- Completion highlight
    vim.api.nvim_set_hl(0, highlights.completion, {
        fg = '#8ec07c',
        bg = 'NONE',
        italic = true,
        default = true
    })
    
    -- Confidence highlights
    vim.api.nvim_set_hl(0, highlights.confidence_high, {
        fg = '#a6e3a1',
        bg = 'NONE',
        bold = true,
        default = true
    })
    
    vim.api.nvim_set_hl(0, highlights.confidence_medium, {
        fg = '#f9e2af',
        bg = 'NONE',
        default = true
    })
    
    vim.api.nvim_set_hl(0, highlights.confidence_low, {
        fg = '#f38ba8',
        bg = 'NONE',
        default = true
    })
    
    -- Icon highlight
    vim.api.nvim_set_hl(0, highlights.icon, {
        fg = '#89b4fa',
        bg = 'NONE',
        default = true
    })
    
    -- Ghost text highlight
    vim.api.nvim_set_hl(0, highlights.ghost_text, {
        fg = '#6c7086',
        bg = 'NONE',
        italic = true,
        default = true
    })
end

-- Setup event listeners
function M.setup_events()
    events.on(events.EVENT_TYPES.COMPLETION_SHOWN, function(data)
        if state.enabled and data.item then
            M.show_completion(data.item)
        end
    end, { source = 'virtual_text' })
    
    events.on(events.EVENT_TYPES.COMPLETION_ACCEPTED, function(data)
        M.clear_completion()
    end, { source = 'virtual_text' })
    
    events.on(events.EVENT_TYPES.COMPLETION_REJECTED, function(data)
        M.clear_completion()
    end, { source = 'virtual_text' })
    
    -- Clear virtual text on cursor move
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        callback = function()
            M.clear_completion()
        end,
        desc = 'Neopilot: Clear virtual text on cursor move'
    })
    
    -- Clear virtual text on mode change
    vim.api.nvim_create_autocmd('ModeChanged', {
        callback = function()
            if vim.fn.mode() ~= 'i' then
                M.clear_completion()
            end
        end,
        desc = 'Neopilot: Clear virtual text on mode change'
    })
end

-- Show completion as virtual text
function M.show_completion(completion_item)
    if not state.enabled or not completion_item then
        return
    end
    
    M.clear_completion()
    
    local completion = completion_item.completion or {}
    local text = completion.text or ''
    local suffix = completion.suffix or {}
    local suffix_text = suffix.text or ''
    local full_text = text .. suffix_text
    
    if full_text == '' then
        return
    end
    
    -- Get cursor position
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1] - 1
    local col = cursor[2]
    
    -- Get current line content
    local current_line = vim.api.nvim_buf_get_lines(0, line, line + 1, false)[1] or ''
    
    -- Calculate where to place virtual text
    local insert_pos = col
    local virtual_text = full_text
    
    -- Handle multi-line completions
    local lines = vim.split(full_text, '\n', { plain = true })
    if #lines > 1 then
        virtual_text = lines[1]
        -- Show indicator for multi-line completion
        virtual_text = virtual_text .. ' …'
    end
    
    -- Create virtual text segments
    local segments = {}
    
    -- Add icon if enabled
    if state.config.show_icons then
        table.insert(segments, { '✨', state.config.highlights.icon })
        table.insert(segments, { ' ', 'Normal' })
    end
    
    -- Add completion text
    table.insert(segments, { virtual_text, state.config.highlights.ghost_text })
    
    -- Add confidence indicator if enabled
    if state.config.show_confidence and completion_item.confidence then
        local confidence = completion_item.confidence
        local confidence_highlight = M.get_confidence_highlight(confidence)
        local confidence_text = M.get_confidence_text(confidence)
        
        table.insert(segments, { ' ', 'Normal' })
        table.insert(segments, { confidence_text, confidence_highlight })
    end
    
    -- Create extmark
    local extmark_id = vim.api.nvim_buf_set_extmark(0, state.ns_id, line, insert_pos, {
        virt_text = segments,
        virt_text_pos = 'inline',
        hl_mode = 'combine',
        ephemeral = true
    })
    
    -- Store extmark info
    state.extmarks[extmark_id] = {
        id = extmark_id,
        line = line,
        col = insert_pos,
        completion = completion_item,
        timestamp = vim.loop.now()
    }
    
    -- Emit virtual text shown event
    events.emit(events.EVENT_TYPES.VIRTUAL_TEXT_SHOWN, {
        extmark_id = extmark_id,
        completion = completion_item,
        text = virtual_text
    }, { source = 'virtual_text' })
    
    -- Set timeout for auto-clear
    if state.config.timeout > 0 then
        vim.defer_fn(function()
            M.clear_completion(extmark_id)
        end, state.config.timeout)
    end
    
    -- Animate if enabled
    if state.config.animate_transitions then
        M.animate_completion(extmark_id)
    end
end

-- Clear completion virtual text
function M.clear_completion(extmark_id)
    if extmark_id then
        -- Clear specific extmark
        vim.api.nvim_buf_del_extmark(0, state.ns_id, extmark_id)
        state.extmarks[extmark_id] = nil
    else
        -- Clear all extmarks
        vim.api.nvim_buf_clear_namespace(0, state.ns_id, 0, -1)
        state.extmarks = {}
    end
    
    -- Cancel animations
    for anim_id, timer in pairs(state.animations) do
        if timer then
            timer:close()
        end
    end
    state.animations = {}
    
    -- Emit virtual text cleared event
    events.emit(events.EVENT_TYPES.VIRTUAL_TEXT_CLEARED, {
        extmark_id = extmark_id
    }, { source = 'virtual_text' })
end

-- Get confidence highlight based on score
function M.get_confidence_highlight(confidence)
    if confidence >= 0.8 then
        return state.config.highlights.confidence_high
    elseif confidence >= 0.5 then
        return state.config.highlights.confidence_medium
    else
        return state.config.highlights.confidence_low
    end
end

-- Get confidence text indicator
function M.get_confidence_text(confidence)
    if confidence >= 0.8 then
        return '●'
    elseif confidence >= 0.5 then
        return '○'
    else
        return '◐'
    end
end

-- Animate completion appearance
function M.animate_completion(extmark_id)
    local extmark_info = state.extmarks[extmark_id]
    if not extmark_info then
        return
    end
    
    local alpha = 0
    local steps = 10
    local delay = 50
    
    local function update_alpha(step)
        alpha = step / steps
        
        -- Update highlight with transparency
        local highlight_name = string.format('NeopilotAnimated_%d', extmark_id)
        vim.api.nvim_set_hl(0, highlight_name, {
            fg = '#6c7086',
            bg = 'NONE',
            italic = true,
            alpha = math.floor(alpha * 255)
        })
        
        -- Update extmark highlight
        vim.api.nvim_buf_set_extmark(0, state.ns_id, extmark_info.line, extmark_info.col, {
            virt_text = { { extmark_info.completion.completion.text, highlight_name } },
            virt_text_pos = 'inline',
            hl_mode = 'combine',
            ephemeral = true,
            id = extmark_id
        })
        
        if step < steps then
            local timer = vim.loop.new_timer()
            timer:start(delay, 0, function()
                update_alpha(step + 1)
                timer:close()
            end)
            state.animations[extmark_id] = timer
        end
    end
    
    update_alpha(0)
end

-- Show floating completion window
function M.show_floating_completion(completion_item)
    if not completion_item or not completion_item.completion then
        return
    end
    
    local completion = completion_item.completion
    local text = completion.text or ''
    
    if text == '' then
        return
    end
    
    -- Get cursor position
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1] - 1
    local col = cursor[2]
    
    -- Create floating window
    local buf = vim.api.nvim_create_buf(false, true)
    
    -- Set buffer content
    local lines = vim.split(text, '\n', { plain = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    -- Configure buffer
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(buf, 'readonly', true)
    vim.api.nvim_buf_set_option(buf, 'filetype', vim.bo.filetype)
    
    -- Calculate window dimensions
    local width = 0
    for _, line_text in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(line_text))
    end
    width = math.min(width, state.config.max_width)
    
    local height = #lines
    
    -- Calculate window position
    local win_config = {
        relative = 'cursor',
        width = width,
        height = height,
        row = 1,
        col = 0,
        style = 'minimal',
        border = 'rounded',
        title = ' AI Completion ',
        title_pos = 'center'
    }
    
    -- Create window
    local win = vim.api.nvim_open_win(buf, false, win_config)
    
    -- Set window highlights
    vim.api.nvim_win_set_option(win, 'winhighlight', 'Normal:Normal,FloatBorder:FloatBorder')
    
    -- Store window info
    state.active_completions[win] = {
        buf = buf,
        win = win,
        completion = completion_item,
        timestamp = vim.loop.now()
    }
    
    -- Emit floating window opened event
    events.emit(events.EVENT_TYPES.FLOATING_WINDOW_OPENED, {
        win = win,
        buf = buf,
        completion = completion_item
    }, { source = 'virtual_text' })
    
    -- Auto-close after timeout
    if state.config.timeout > 0 then
        vim.defer_fn(function()
            M.close_floating_completion(win)
        end, state.config.timeout)
    end
    
    -- Close on various events
    local group = vim.api.nvim_create_augroup('NeopilotFloat', { clear = true })
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'ModeChanged' }, {
        group = group,
        callback = function()
            M.close_floating_completion(win)
        end,
        once = true
    })
end

-- Close floating completion window
function M.close_floating_completion(win)
    local completion_info = state.active_completions[win]
    if completion_info then
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(completion_info.buf) then
            vim.api.nvim_buf_delete(completion_info.buf, { force = true })
        end
        state.active_completions[win] = nil
        
        -- Emit floating window closed event
        events.emit(events.EVENT_TYPES.FLOATING_WINDOW_CLOSED, {
            win = win,
            buf = completion_info.buf
        }, { source = 'virtual_text' })
    end
end

-- Show inline diff preview
function M.show_diff_preview(original_text, new_text)
    local diff_lines = {}
    
    -- Simple diff implementation (could be enhanced with proper diff algorithm)
    local original_lines = vim.split(original_text, '\n', { plain = true })
    local new_lines = vim.split(new_text, '\n', { plain = true })
    
    -- Create diff display
    local max_lines = math.max(#original_lines, #new_lines)
    for i = 1, max_lines do
        local orig_line = original_lines[i] or ''
        local new_line = new_lines[i] or ''
        
        if orig_line ~= new_line then
            table.insert(diff_lines, string.format('-%s', orig_line))
            table.insert(diff_lines, string.format('+%s', new_line))
        else
            table.insert(diff_lines, string.format(' %s', orig_line))
        end
    end
    
    -- Show in floating window
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(buf, 'readonly', true)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'diff')
    
    local win_config = {
        relative = 'cursor',
        width = math.min(80, vim.fn.winwidth(0) - 10),
        height = math.min(20, #diff_lines),
        row = 1,
        col = 0,
        style = 'minimal',
        border = 'rounded',
        title = ' Changes Preview '
    }
    
    local win = vim.api.nvim_open_win(buf, false, win_config)
    vim.api.nvim_win_set_option(win, 'winhighlight', 'Normal:Normal,FloatBorder:FloatBorder')
    
    -- Auto-close
    vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end, 5000)
    
    -- Emit diff preview shown event
    events.emit(events.EVENT_TYPES.DIFF_PREVIEW_SHOWN, {
        original_text = original_text,
        new_text = new_text,
        diff_lines = diff_lines,
        win = win,
        buf = buf
    }, { source = 'virtual_text' })
end

-- Show progress indicator
function M.show_progress(message, progress)
    progress = progress or 0
    
    local progress_bar = string.rep('█', math.floor(progress / 10))
    progress_bar = progress_bar .. string.rep('░', 10 - math.floor(progress / 10))
    
    local text = string.format('%s [%s]', message, progress_bar)
    
    -- Show as virtual text at cursor
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1] - 1
    local col = cursor[2]
    
    vim.api.nvim_buf_set_extmark(0, state.ns_id, line, col, {
        virt_text = { { text, state.config.highlights.completion } },
        virt_text_pos = 'right_align',
        ephemeral = true
    })
    
    -- Emit progress shown event
    events.emit(events.EVENT_TYPES.PROGRESS_SHOWN, {
        message = message,
        progress = progress,
        text = text
    }, { source = 'virtual_text' })
end

-- Show error message as virtual text
function M.show_error(message, line_num)
    line_num = line_num or vim.api.nvim_win_get_cursor(0)[1] - 1
    
    vim.api.nvim_buf_set_extmark(0, state.ns_id, line_num, 0, {
        virt_text = { { '❌ ' .. message, 'DiagnosticError' } },
        virt_text_pos = 'right_align',
        ephemeral = true
    })
end

-- Show warning message as virtual text
function M.show_warning(message, line_num)
    line_num = line_num or vim.api.nvim_win_get_cursor(0)[1] - 1
    
    vim.api.nvim_buf_set_extmark(0, state.ns_id, line_num, 0, {
        virt_text = { { '⚠️ ' .. message, 'DiagnosticWarn' } },
        virt_text_pos = 'right_align',
        ephemeral = true
    })
end

-- Show info message as virtual text
function M.show_info(message, line_num)
    line_num = line_num or vim.api.nvim_win_get_cursor(0)[1] - 1
    
    vim.api.nvim_buf_set_extmark(0, state.ns_id, line_num, 0, {
        virt_text = { { 'ℹ️ ' .. message, 'DiagnosticInfo' } },
        virt_text_pos = 'right_align',
        ephemeral = true
    })
end

-- Toggle virtual text on/off
function M.toggle()
    state.enabled = not state.enabled
    if not state.enabled then
        M.clear_completion()
    end
    log.info(string.format("Virtual text %s", state.enabled and "enabled" or "disabled"))
end

-- Get current state
function M.get_state()
    return {
        enabled = state.enabled,
        active_completions = vim.tbl_count(state.extmarks),
        floating_windows = vim.tbl_count(state.active_completions),
        config = state.config
    }
end

-- Cleanup function
function M.cleanup()
    M.clear_completion()
    
    -- Close all floating windows
    for win, _ in pairs(state.active_completions) do
        M.close_floating_completion(win)
    end
    
    -- Clear namespace
    vim.api.nvim_buf_clear_namespace(0, state.ns_id, 0, -1)
    
    log.info("Virtual text module cleaned up")
end

return M
