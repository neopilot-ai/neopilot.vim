-- Neopilot UI module for rendering completions
local M = {}

local log = require('neopilot.log')

local ns_id = vim.api.nvim_create_namespace('neopilot')
local extmark_id = nil

function M.setup()
    -- No setup needed
end

-- Render a completion item
function M.render_completion(item, opts)
    M.clear_completion()

    opts = opts or {}
    local completion_text = item.completion.text or ''
    if completion_text == '' then
        return
    end

    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local col = vim.api.nvim_win_get_cursor(0)[2]

    local display_text = { { completion_text, 'NeopilotSuggestion' } }

    extmark_id = vim.api.nvim_buf_set_extmark(0, ns_id, line, col, {
        virt_text = display_text,
        virt_text_pos = 'inline',
    })
end

-- Clear any visible completion
function M.clear_completion()
    if extmark_id then
        vim.api.nvim_buf_del_extmark(0, ns_id, extmark_id)
        extmark_id = nil
    end
end

return M
