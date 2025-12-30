-- Virtual text configuration example
-- Add this to your Neopilot setup to customize virtual text behavior

require('neopilot').setup({
    -- ... other config options
    
    -- Virtual text configuration
    virtual_text = {
        -- Enable/disable virtual text
        enabled = true,
        
        -- Display position: 'inline' or 'float'
        position = 'inline',
        
        -- Show confidence indicators
        show_confidence = true,
        
        -- Show completion icons
        show_icons = true,
        
        -- Animate transitions (fade in/out)
        animate_transitions = true,
        
        -- Maximum width for floating windows
        max_width = 80,
        
        -- Auto-clear timeout (ms), 0 = no timeout
        timeout = 5000,
        
        -- Custom highlights
        highlights = {
            completion = 'NeopilotCompletion',
            confidence_high = 'NeopilotConfidenceHigh',
            confidence_medium = 'NeopilotConfidenceMedium',
            confidence_low = 'NeopilotConfidenceLow',
            icon = 'NeopilotIcon',
            ghost_text = 'NeopilotGhostText'
        }
    }
})

-- Custom highlight setup (optional)
vim.api.nvim_set_hl(0, 'NeopilotCompletion', {
    fg = '#8ec07c',  -- Green
    bg = 'NONE',
    italic = true,
    default = true
})

vim.api.nvim_set_hl(0, 'NeopilotConfidenceHigh', {
    fg = '#a6e3a1',  -- Bright green
    bg = 'NONE',
    bold = true,
    default = true
})

vim.api.nvim_set_hl(0, 'NeopilotConfidenceMedium', {
    fg = '#f9e2af',  -- Yellow
    bg = 'NONE',
    default = true
})

vim.api.nvim_set_hl(0, 'NeopilotConfidenceLow', {
    fg = '#f38ba8',  -- Red
    bg = 'NONE',
    default = true
})

vim.api.nvim_set_hl(0, 'NeopilotIcon', {
    fg = '#89b4fa',  -- Blue
    bg = 'NONE',
    default = true
})

vim.api.nvim_set_hl(0, 'NeopilotGhostText', {
    fg = '#6c7086',  -- Gray
    bg = 'NONE',
    italic = true,
    default = true
})

-- Example: Toggle virtual text with a command
vim.api.nvim_create_user_command('NeopilotToggleVirtualText', function()
    require('neopilot.virtual_text').toggle()
end, { desc = 'Toggle Neopilot virtual text' })

-- Example: Show diff preview
vim.api.nvim_create_user_command('NeopilotShowDiff', function()
    local original_text = vim.fn.input('Original text: ')
    local new_text = vim.fn.input('New text: ')
    require('neopilot.virtual_text').show_diff_preview(original_text, new_text)
end, { desc = 'Show Neopilot diff preview' })

-- Example: Custom event handler for virtual text
require('neopilot.events').on(require('neopilot.events').EVENT_TYPES.COMPLETION_SHOWN, function(data)
    -- Custom logic when completion is shown
    if data.item and data.item.completion then
        local text = data.item.completion.text or ''
        if #text > 50 then
            -- Show warning for long completions
            require('neopilot.virtual_text').show_warning('Long completion', vim.fn.line('.'))
        end
    end
end)
