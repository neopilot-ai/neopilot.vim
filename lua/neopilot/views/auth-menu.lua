-- Authentication menu UI for Neopilot
-- Provides a user-friendly interface for authentication flows
local M = {}

local config = require('neopilot.config_v2')
local log = require('neopilot.log')
local util = require('neopilot.util')

-- Private state
local auth_win = nil
local auth_buf = nil
local ns_id = vim.api.nvim_create_namespace('neopilot_auth')

-- Authentication menu options
local auth_menu_options = {
    {
        name = 'Sign In',
        description = 'Authenticate with Neopilot using browser flow',
        action = 'browser_auth'
    },
    {
        name = 'Enter API Key',
        description = 'Manually enter an existing API key',
        action = 'manual_key'
    },
    {
        name = 'Check Status',
        description = 'Check current authentication status',
        action = 'check_status'
    },
    {
        name = 'Sign Out',
        description = 'Remove stored authentication credentials',
        action = 'sign_out'
    },
    {
        name = 'Help',
        description = 'Get help with authentication',
        action = 'help'
    }
}

-- Setup function
function M.setup()
    -- Create highlight groups
    vim.api.nvim_set_hl(0, 'NeopilotAuthTitle', { fg = '#61afef', bold = true })
    vim.api.nvim_set_hl(0, 'NeopilotAuthOption', { fg = '#abb2bf' })
    vim.api.nvim_set_hl(0, 'NeopilotAuthDescription', { fg = '#5c6370', italic = true })
    vim.api.nvim_set_hl(0, 'NeopilotAuthKey', { fg = '#98c379' })
    vim.api.nvim_set_hl(0, 'NeopilotAuthValue', { fg = '#e06c75' })
end

-- Show the authentication menu
function M.show_auth_menu()
    -- Close any existing auth window
    M.close_auth_window()
    
    -- Create buffer
    auth_buf = vim.api.nvim_create_buf(false, true)
    
    -- Set buffer name and options
    vim.api.nvim_buf_set_name(auth_buf, 'neopilot-auth')
    vim.api.nvim_buf_set_option(auth_buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(auth_buf, 'readonly', true)
    vim.api.nvim_buf_set_option(auth_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(auth_buf, 'bufhidden', 'wipe')
    
    -- Calculate window size
    local width = 80
    local height = #auth_menu_options + 6
    local ui = vim.api.nvim_list_uis()[1]
    local win_width = ui.width
    local win_height = ui.height
    
    -- Center the window
    local row = math.floor((win_height - height) / 2)
    local col = math.floor((win_width - width) / 2)
    
    -- Create floating window
    auth_win = vim.api.nvim_open_win(auth_buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        border = 'rounded',
        style = 'minimal',
        title = ' Neopilot Authentication ',
        title_pos = 'center'
    })
    
    -- Set window options
    vim.api.nvim_win_set_option(auth_win, 'winhl', 'Normal:Normal')
    vim.api.nvim_win_set_option(auth_win, 'cursorline', true)
    
    -- Populate buffer content
    M.populate_auth_buffer()
    
    -- Set up key mappings
    M.setup_auth_keymaps()
    
    -- Set up autocmd to close window on escape
    vim.api.nvim_create_autocmd('BufWinLeave', {
        buffer = auth_buf,
        once = true,
        callback = function()
            M.close_auth_window()
        end
    })
end

-- Populate the authentication buffer with content
function M.populate_auth_buffer()
    if not auth_buf then return end
    
    local lines = {}
    local highlights = {}
    
    -- Add title
    table.insert(lines, '')
    table.insert(highlights, {'NeopilotAuthTitle', 1, 0, 0})
    
    -- Add current status
    local api_key = config.get('api_key')
    local status_line = api_key and '✓ Authenticated' or '✗ Not authenticated'
    table.insert(lines, 'Status: ' .. status_line)
    table.insert(highlights, {api_key and 'NeopilotAuthKey' or 'NeopilotAuthValue', 2, 8, -1})
    
    table.insert(lines, '')
    table.insert(lines, 'Available actions:')
    table.insert(lines, '')
    
    -- Add menu options
    for i, option in ipairs(auth_menu_options) do
        local line_num = #lines + 1
        local key_binding = tostring(i)
        local option_text = string.format('  [%s] %s', key_binding, option.name)
        
        table.insert(lines, option_text)
        table.insert(highlights, {'NeopilotAuthOption', line_num, 0, -1})
        
        -- Add description on next line
        line_num = #lines + 1
        table.insert(lines, '      ' .. option.description)
        table.insert(highlights, {'NeopilotAuthDescription', line_num, 0, -1})
        
        if i < #auth_menu_options then
            table.insert(lines, '')
        end
    end
    
    -- Set buffer content
    vim.api.nvim_buf_set_lines(auth_buf, 0, -1, false, lines)
    
    -- Apply highlights
    for _, hl in ipairs(highlights) do
        vim.api.nvim_buf_add_highlight(auth_buf, ns_id, hl[1], hl[2] - 1, hl[3], hl[4])
    end
end

-- Set up key mappings for the auth window
function M.setup_auth_keymaps()
    if not auth_win or not auth_buf then return end
    
    local opts = { buffer = auth_buf, silent = true, nowait = true }
    
    -- Number keys for menu options
    for i, option in ipairs(auth_menu_options) do
        vim.keymap.set('n', tostring(i), function()
            M.handle_menu_action(option.action)
        end, opts)
    end
    
    -- Common navigation
    vim.keymap.set('n', '<Esc>', function()
        M.close_auth_window()
    end, opts)
    
    vim.keymap.set('n', 'q', function()
        M.close_auth_window()
    end, opts)
    
    vim.keymap.set('n', '<CR>', function()
        local cursor_line = vim.api.nvim_win_get_cursor(auth_win)[1]
        local option_index = M.get_option_from_line(cursor_line)
        if option_index and auth_menu_options[option_index] then
            M.handle_menu_action(auth_menu_options[option_index].action)
        end
    end, opts)
end

-- Get menu option index from cursor line
function M.get_option_from_line(line)
    -- Lines with options start at line 7, then every 3 lines
    if line < 7 then return nil end
    
    local relative_line = line - 7
    if relative_line % 3 ~= 0 then return nil end
    
    local option_index = math.floor(relative_line / 3) + 1
    return option_index <= #auth_menu_options and option_index or nil
end

-- Handle menu action selection
function M.handle_menu_action(action)
    if action == 'browser_auth' then
        M.browser_auth_flow()
    elseif action == 'manual_key' then
        M.manual_key_flow()
    elseif action == 'check_status' then
        M.show_auth_status()
    elseif action == 'sign_out' then
        M.sign_out()
    elseif action == 'help' then
        M.show_help()
    end
end

-- Browser authentication flow
function M.browser_auth_flow()
    M.close_auth_window()
    
    -- Import browser auth functionality from command module
    local command = require('neopilot.command')
    
    -- Check for supported version
    if not util.has_supported_version() then
        if vim.fn.has('nvim') == 1 then
            vim.notify('This version of Neovim is unsupported. Install Neovim 0.6 or greater to use Neopilot.', vim.log.levels.ERROR)
        else
            vim.notify('This version of Vim is unsupported. Install Vim 9.0 or greater to use Neopilot.', vim.log.levels.ERROR)
        end
        return
    end
    
    -- Generate UUID and create auth URL
    local uuid = vim.fn.trim(M.generate_uuid())
    local url = string.format('http://127.0.0.1/profile?response_type=token&redirect_uri=show-auth-token&state=%s&scope=openid%%20profile%%20email&redirect_parameters_type=query', uuid)
    
    -- Open browser
    local browser = M.get_browser_command()
    local opened_browser = false
    
    if browser ~= '' then
        local cmd = browser .. ' ' .. vim.fn.shellescape(url)
        local result = vim.fn.system(cmd)
        opened_browser = vim.v.shell_error == 0
    end
    
    if not opened_browser then
        vim.notify('Failed to open browser. Please manually visit: ' .. url, vim.log.levels.WARN)
    else
        vim.notify('Browser opened for authentication. Please complete the sign-in process.', vim.log.levels.INFO)
    end
    
    -- Get token from user
    local auth_token = vim.fn.input('Paste your token here: ')
    M.process_auth_token(auth_token)
end

-- Manual key entry flow
function M.manual_key_flow()
    M.close_auth_window()
    
    local api_key = vim.fn.inputsecret('Enter your API key: ')
    if api_key and api_key ~= '' then
        M.save_api_key(api_key)
    else
        vim.notify('No API key provided.', vim.log.levels.WARN)
    end
end

-- Show authentication status
function M.show_auth_status()
    local api_key = config.get('api_key')
    local status = {
        'Authentication Status',
        '===================',
        '',
        'Status: ' .. (api_key and 'Authenticated' or 'Not authenticated'),
        'API Key: ' .. (api_key and '••••••••••••' or 'Not set'),
        ''
    }
    
    if api_key then
        table.insert(status, 'You are successfully authenticated with Neopilot.')
        table.insert(status, 'AI completion features are available.')
    else
        table.insert(status, 'You are not authenticated.')
        table.insert(status, 'Run the authentication flow to enable AI features.')
    end
    
    vim.notify(table.concat(status, '\n'), vim.log.levels.INFO)
end

-- Sign out and remove credentials
function M.sign_out()
    local api_key = config.get('api_key')
    if not api_key then
        vim.notify('No authentication credentials found.', vim.log.levels.INFO)
        return
    end
    
    local choice = vim.fn.confirm('Are you sure you want to sign out? This will remove your stored API key.', '&Yes\n&No', 2)
    if choice == 1 then
        config.set('api_key', '', 'user')
        M.save_config_to_file({ apiKey = '' })
        vim.notify('Successfully signed out. API key removed.', vim.log.levels.INFO)
    end
end

-- Show help information
function M.show_help()
    local help_text = {
        'Neopilot Authentication Help',
        '=============================',
        '',
        'Authentication Methods:',
        '',
        '1. Browser Authentication (Recommended)',
        '   - Opens your browser to sign in to Neopilot',
        '   - Automatically generates an API key',
        '   - Most secure and convenient method',
        '',
        '2. Manual API Key Entry',
        '   - Enter an existing API key directly',
        '   - Useful if you already have a key',
        '   - Key will be stored securely',
        '',
        'Troubleshooting:',
        '- Ensure curl is installed and accessible',
        '- Check your internet connection',
        '- Verify the API key is valid',
        '- Run :NeopilotHealth for system checks',
        '',
        'For more help, visit: https://github.com/neopilot-ai/neopilot.vim'
    }
    
    vim.notify(table.concat(help_text, '\n'), vim.log.levels.INFO)
end

-- Process authentication token
function M.process_auth_token(auth_token)
    if not auth_token or auth_token == '' then
        vim.notify('No token provided.', vim.log.levels.WARN)
        return
    end
    
    local api_key = ''
    local tries = 0
    
    while api_key == '' and tries < 3 do
        local cmd = string.format('curl -s https://api.neopilot.com/register_user/ --header "Content-Type: application/json" --data \'%s\'',
            vim.fn.json_encode({firebase_id_token = auth_token}))
        local response = vim.fn.system(cmd)
        
        local ok, res = pcall(vim.fn.json_decode, response)
        if ok and res then
            api_key = res.api_key or ''
        end
        
        if api_key == '' then
            if tries < 2 then
                auth_token = vim.fn.input('Invalid token, please try again: ')
            end
        end
        tries = tries + 1
    end
    
    if api_key ~= '' then
        M.save_api_key(api_key)
    else
        vim.notify("Failed to authenticate after 3 attempts.", vim.log.levels.ERROR)
    end
end

-- Save API key
function M.save_api_key(api_key)
    config.set('api_key', api_key, 'user')
    M.save_config_to_file({ apiKey = api_key })
    vim.notify("Successfully authenticated!", vim.log.levels.INFO)
end

-- Save configuration to file
function M.save_config_to_file(cfg)
    local config_path = util.config_dir() .. '/config.json'
    vim.fn.mkdir(vim.fn.fnamemodify(config_path, ':h'), 'p')
    vim.fn.writefile({vim.fn.json_encode(cfg)}, config_path)
end

-- Generate UUID
function M.generate_uuid()
    if vim.fn.has('win32') == 1 then
        return vim.fn.system('powershell -Command "[guid]::NewGuid()"')
    elseif vim.fn.executable('uuidgen') == 1 then
        return vim.fn.system('uuidgen')
    end
    error("Could not generate uuid. Please make sure uuidgen is installed.")
end

-- Get browser command
function M.get_browser_command()
    if vim.fn.has('win32') == 1 and vim.fn.executable('rundll32') == 1 then
        return 'rundll32 url.dll,FileProtocolHandler'
    elseif vim.fn.isdirectory('/private') == 1 and vim.fn.executable('/usr/bin/open') == 1 then
        return '/usr/bin/open'
    elseif vim.fn.executable('xdg-open') == 1 then
        return 'xdg-open'
    end
    return ''
end

-- Close authentication window
function M.close_auth_window()
    if auth_win and vim.api.nvim_win_is_valid(auth_win) then
        vim.api.nvim_win_close(auth_win, true)
        auth_win = nil
    end
    
    if auth_buf and vim.api.nvim_buf_is_valid(auth_buf) then
        auth_buf = nil
    end
end

-- Check if authentication window is open
function M.is_auth_window_open()
    return auth_win and vim.api.nvim_win_is_valid(auth_win)
end

-- Export functions for external use
M.browser_auth_flow = M.browser_auth_flow
M.manual_key_flow = M.manual_key_flow
M.show_auth_status = M.show_auth_status
M.sign_out = M.sign_out

return M