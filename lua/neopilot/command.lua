-- Neopilot command module
local M = {}

local config = require('neopilot.config')
local server = require('neopilot.server')
local log = require('neopilot.log')
local util = require('neopilot.util')

-- Setup command module
function M.setup(opts)
    -- Register commands
    vim.api.nvim_create_user_command('Neopilot', function(args)
        M.command(args.args)
    end, {
        nargs = '?',
        complete = function(arg_lead, cmd_line, cursor_pos)
            return M.complete(arg_lead, cmd_line, cursor_pos)
        end
    })
end

-- Browser command detection
function M.browser_command()
    if vim.fn.has('win32') == 1 and vim.fn.executable('rundll32') == 1 then
        return 'rundll32 url.dll,FileProtocolHandler'
    elseif vim.fn.isdirectory('/private') == 1 and vim.fn.executable('/usr/bin/open') == 1 then
        return '/usr/bin/open'
    elseif vim.fn.executable('xdg-open') == 1 then
        return 'xdg-open'
    end
    return ''
end

-- Generate UUID
local function generate_uuid()
    if vim.fn.has('win32') == 1 then
        return vim.fn.system('powershell -Command "[guid]::NewGuid()"')
    elseif vim.fn.executable('uuidgen') == 1 then
        return vim.fn.system('uuidgen')
    end
    error("Could not generate uuid. Please make sure uuidgen is installed.")
end

-- Load config from file
local function load_config()
    local config_path = util.config_dir() .. '/config.json'
    if vim.fn.filereadable(config_path) == 1 then
        local contents = table.concat(vim.fn.readfile(config_path), '\n')
        if contents ~= '' then
            return vim.fn.json_decode(contents)
        end
    end
    return {}
end

-- Save config to file
local function save_config(cfg)
    local config_path = util.config_dir() .. '/config.json'
    vim.fn.mkdir(vim.fn.fnamemodify(config_path, ':h'), 'p')
    vim.fn.writefile({vim.fn.json_encode(cfg)}, config_path)
end

-- Get API key
function M.api_key()
    return config.get('api_key') or ''
end

-- Auth command
function M.auth()
    if not util.has_supported_version() then
        if vim.fn.has('nvim') == 1 then
            vim.notify('This version of Neovim is unsupported. Install Neovim 0.6 or greater to use Neopilot.', vim.log.levels.ERROR)
        else
            vim.notify('This version of Vim is unsupported. Install Vim 9.0.0185 or greater to use Neopilot.', vim.log.levels.ERROR)
        end
        return
    end

    local uuid = vim.fn.trim(generate_uuid())
    local url = string.format('http://127.0.0.1/profile?response_type=token&redirect_uri=show-auth-token&state=%s&scope=openid%%20profile%%20email&redirect_parameters_type=query', uuid)

    local browser = M.browser_command()
    local opened_browser = false

    if browser ~= '' then
        vim.notify("Press ENTER to login to Neopilot in your browser.", vim.log.levels.INFO)
        vim.fn.getchar()

        vim.notify("Navigating to " .. url, vim.log.levels.INFO)
        local result = vim.fn.system(browser .. ' "' .. url .. '"')
        if vim.v.shell_error == 0 then
            opened_browser = true
        end

        if not opened_browser then
            vim.notify("Failed to open browser. Please go to the link above.", vim.log.levels.WARN)
        end
    else
        vim.notify("No available browser found. Please go to " .. url, vim.log.levels.WARN)
    end

    local api_key = ''
    local auth_token = vim.fn.input('Paste your token here: ')
    local tries = 0

    while api_key == '' and tries < 3 do
        local cmd = string.format('curl -s https://api.neopilot.com/register_user/ --header "Content-Type: application/json" --data \'%s\'',
            vim.fn.json_encode({firebase_id_token = auth_token}))
        local response = vim.fn.system(cmd)
        local res = vim.fn.json_decode(response)
        api_key = res.api_key or ''
        if api_key == '' then
            auth_token = vim.fn.input('Invalid token, please try again: ')
        end
        tries = tries + 1
    end

    if api_key ~= '' then
        local cfg = load_config()
        cfg.apiKey = api_key
        save_config(cfg)
        config.set('api_key', api_key)
        vim.notify("Successfully authenticated!", vim.log.levels.INFO)
    else
        vim.notify("Failed to authenticate.", vim.log.levels.ERROR)
    end
end

-- Server command
function M.server(args)
    if not args or args == '' then
        if server.is_running() then
            vim.notify("Server is running", vim.log.levels.INFO)
        else
            vim.notify("Server is not running", vim.log.levels.INFO)
        end
        return
    end

    if args == 'start' then
        if server.start() then
            vim.notify("Server started successfully", vim.log.levels.INFO)
        else
            vim.notify("Failed to start server", vim.log.levels.ERROR)
        end
    elseif args == 'stop' then
        server.stop()
        vim.notify("Server stopped", vim.log.levels.INFO)
    elseif args == 'restart' then
        server.stop()
        vim.wait(1000) -- Wait 1 second
        if server.start() then
            vim.notify("Server restarted successfully", vim.log.levels.INFO)
        else
            vim.notify("Failed to restart server", vim.log.levels.ERROR)
        end
    else
        vim.notify("Unknown server command: " .. args, vim.log.levels.ERROR)
    end
end

-- Status command
function M.status()
    local status_lines = {
        "Neopilot Status:",
        "================",
        "Enabled: " .. (config.is_enabled() and "Yes" or "No"),
        "Server Running: " .. (server.is_running() and "Yes" or "No"),
        "API Key: " .. (M.api_key() ~= '' and "Set" or "Not set"),
        "Log Level: " .. (config.get('log_level') or 'WARN'),
        "Idle Delay: " .. (config.get('idle_delay') or 75) .. "ms",
    }

    for _, line in ipairs(status_lines) do
        vim.notify(line, vim.log.levels.INFO)
    end
end

-- Main command handler
function M.command(args)
    if not args or args == '' then
        M.status()
        return
    end

    local cmd = vim.split(args, ' ', {plain = true})[1]
    local rest = args:sub(#cmd + 2) or ''
    local core = require('neopilot.core')

    if cmd == 'auth' then
        M.auth()
    elseif cmd == 'server' then
        M.server(rest)
    elseif cmd == 'status' then
        M.status()
    elseif cmd == 'log' then
        local logfile = log.logfile()
        vim.notify("Log file: " .. logfile, vim.log.levels.INFO)
        vim.cmd('edit ' .. logfile)
    elseif cmd == 'code_action' then
        core.get_code_actions()
    elseif cmd == 'refactor' then
        core.get_refactor_actions()
    else
        vim.notify("Unknown command: " .. cmd, vim.log.levels.ERROR)
        vim.notify("Available commands: auth, server, status, log, code_action, refactor", vim.log.levels.INFO)
    end
end

-- Command completion
function M.complete(arg_lead, cmd_line, cursor_pos)
    local commands = {'auth', 'server', 'status', 'log', 'code_action', 'refactor'}
    local server_commands = {'start', 'stop', 'restart'}

    local args = vim.split(cmd_line, ' ', {plain = true})
    if #args <= 2 then
        -- Complete main commands
        local matches = {}
        for _, cmd in ipairs(commands) do
            if cmd:find('^' .. arg_lead) then
                table.insert(matches, cmd)
            end
        end
        return matches
    elseif args[2] == 'server' and #args <= 3 then
        -- Complete server subcommands
        local matches = {}
        for _, cmd in ipairs(server_commands) do
            if cmd:find('^' .. arg_lead) then
                table.insert(matches, cmd)
            end
        end
        return matches
    end

    return {}
end

return M