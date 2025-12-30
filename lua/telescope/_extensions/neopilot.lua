-- Telescope extension for Neopilot
local telescope = require('telescope')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values

-- Picker for Neopilot commands
local function commands_picker(opts)
    opts = opts or {}
    local commands = {
        { name = 'Neopilot Auth', cmd = 'Neopilot Auth' },
        { name = 'Neopilot Enable', cmd = 'Neopilot Enable' },
        { name = 'Neopilot Disable', cmd = 'Neopilot Disable' },
        { name = 'Neopilot Health', cmd = 'NeopilotHealth' },
        { name = 'Neopilot Test', cmd = 'NeopilotTest' },
        { name = 'Neopilot Status', cmd = 'Neopilot status' },
    }

    pickers.new(opts, {
        prompt_title = 'Neopilot Commands',
        finder = finders.new_table({
            results = commands,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.name,
                    ordinal = entry.name,
                }
            end,
        }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
            map('i', '<CR>', function()
                local selection = require('telescope.actions.state').get_selected_entry()
                require('telescope.actions').close(prompt_bufnr)
                vim.cmd(selection.value.cmd)
            end)
            return true
        end,
    }):find()
end

-- Placeholder for completion history picker
local function completions_picker(opts)
    vim.notify('Completion history picker is not yet implemented.', vim.log.levels.INFO)
end

-- Placeholder for chat history picker
local function chat_history_picker(opts)
    vim.notify('Chat history picker is not yet implemented.', vim.log.levels.INFO)
end

return telescope.register_extension({
    setup = function(ext_config, config)
        -- No setup needed yet
    end,
    exports = {
        commands = commands_picker,
        completions = completions_picker,
        chat_history = chat_history_picker,
    },
})