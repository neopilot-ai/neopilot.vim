-- Neopilot server management module
local M = {}

local Job = require('plenary.job')
local config = require('neopilot.config')
local util = require('neopilot.util')
local log = require('neopilot.log')

function M.setup()
    -- No setup needed for server module at this time
end

local server_job = nil
local server_port = nil
local language_server_version = '1.1.14' -- From server.vim

-- Get the path to the server binary
local function get_binary_path()
    local os = vim.loop.os_uname().sysname
    local arch = vim.loop.os_uname().machine
    local is_arm = arch:match('arm') or arch:match('aarch64')

    local bin_suffix
    if os == 'Linux' and is_arm then
        bin_suffix = 'linux_arm'
    elseif os == 'Linux' then
        bin_suffix = 'linux_x64'
    elseif os == 'Darwin' and is_arm then
        bin_suffix = 'macos_arm'
    elseif os == 'Darwin' then
        bin_suffix = 'macos_x64'
    else
        -- Defaulting to x64 for windows, can be improved
        bin_suffix = 'windows_x64.exe'
    end

    local bin_dir = util.config_dir() .. '/bin'
    return bin_dir .. '/language_server_' .. bin_suffix
end

-- Download the server binary
local function download_binary(path)
    local bin_suffix = path:match('language_server_(.+)')
    local url = 'https://github.com/neopilot-ai/neopilot/releases/download/language-server-v' .. language_server_version .. '/language_server_' .. bin_suffix .. '.gz'

    log.info('Downloading language server from ' .. url)
    vim.notify('Neopilot: Downloading server binary...')

    Job:new({
        command = 'curl',
        args = { '-Lo', path .. '.gz', url },
        on_exit = function(j, return_val)
            if return_val ~= 0 then
                log.error('Failed to download server binary.')
                vim.notify('Neopilot: Failed to download server binary.', vim.log.levels.ERROR)
                return
            end

            log.info('Extracting server binary...')
            Job:new({
                command = 'gzip',
                args = { '-d', path .. '.gz' },
                on_exit = function(gzip_job, gzip_return_val)
                    if gzip_return_val ~= 0 then
                        log.error('Failed to extract server binary.')
                        vim.notify('Neopilot: Failed to extract server binary.', vim.log.levels.ERROR)
                        return
                    end

                    log.info('Setting executable permissions...')
                    vim.fn.system('chmod +x ' .. path)
                    vim.notify('Neopilot: Server binary downloaded successfully. Please restart Neovim.')
                end,
            }):start()
        end,
    }):start()
end

-- Start the server
function M.start()
    if M.is_running() then
        log.info('Server already running.')
        return
    end

    local bin_path = get_binary_path()

    if vim.fn.filereadable(bin_path) == 0 then
        download_binary(bin_path)
        log.warn('Server binary not found. Attempting to download. Please restart Neovim after download is complete.')
        return
    end

    if vim.fn.executable(bin_path) == 0 then
        log.error('Server binary is not executable: ' .. bin_path)
        return
    end

    local manager_dir = vim.fn.tempname() .. '/neopilot/manager'
    vim.fn.mkdir(manager_dir, 'p')

    local args = {
        '--api_server_host', 'server.neopilot.com',
        '--api_server_port', '443',
        '--manager_dir', manager_dir,
    }

    log.info('Starting server: ' .. bin_path)
    server_job = Job:new({
        command = bin_path,
        args = args,
        on_stdout = function(_, data)
            if data and data:match('Listening on port') then
                server_port = tonumber(data:match('%d+'))
                log.info('Server started on port: ' .. server_port)
                vim.notify('Neopilot: Server started.')
            end
        end,
        on_stderr = function(_, data)
            if data then
                log.warn('[SERVER] ' .. data)
            end
        end,
        on_exit = function()
            log.info('Server process exited.')
            server_job = nil
            server_port = nil
        end,
    })
    server_job:start()

    -- A timeout to check if the server started successfully
    vim.loop.setTimeout(5000, function()
        if not M.is_running() then
            log.error('Server failed to start in 5 seconds.')
            vim.notify('Neopilot: Server failed to start.', vim.log.levels.ERROR)
        end
    end)
end

-- Stop the server
function M.stop()
    if server_job then
        server_job:shutdown()
        server_job = nil
        server_port = nil
        log.info('Server stopped.')
    end
end

-- Check if the server is running
function M.is_running()
    return server_job ~= nil and server_port ~= nil
end

-- Send a request to the server
function M.request(method, params, on_complete)
    if not M.is_running() then
        log.error('Cannot make request: server is not running.')
        return
    end

    local body = {
        jsonrpc = '2.0',
        method = method,
        params = params,
        id = vim.fn.jobpid() .. '-' .. vim.loop.now(), -- Unique request id
    }

    Job:new({
        command = 'curl',
        args = {
            '-X', 'POST',
            '-H', 'Content-Type: application/json',
            '--data', vim.fn.json_encode(body),
            'http://localhost:' .. server_port .. '/neo.language_server_pb.LanguageServerService/' .. method,
        },
        on_stdout = function(_, data)
            if data then
                local ok, response = pcall(vim.fn.json_decode, data)
                if ok and on_complete then
                    on_complete(response.result)
                else
                    log.error('Failed to decode server response: ' .. data)
                end
            end
        end,
        on_stderr = function(_, data)
            if data then
                log.error('[CURL] '.. data)
            end
        end,
    }):start()
end

-- request metadata
function M.request_metadata()
    local ide_version = vim.version()
    return {
        api_key = config.get('api_key'),
        ide_name = config.get('ide_name'),
        ide_version = table.concat({ ide_version.major, ide_version.minor, ide_version.patch }, '.'),
        extension_version = language_server_version,
    }
end

-- Request code actions from the server
function M.request_code_actions(document, range, context, on_complete)
    local params = {
        metadata = M.request_metadata(),
        document = document,
        range = range,
        context = context,
    }
    M.request('RequestCodeActions', params, on_complete)
end

-- Request refactor actions from the server
function M.request_refactor_actions(document, range, context, on_complete)
    local params = {
        metadata = M.request_metadata(),
        document = document,
        range = range,
        context = context,
    }
    M.request('RequestRefactorActions', params, on_complete)
end

return M
