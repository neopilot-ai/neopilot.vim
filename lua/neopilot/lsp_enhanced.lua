-- Enhanced LSP integration for Neopilot
-- Provides comprehensive LSP context and AI-powered code actions
local M = {}

local log = require('neopilot.log')
local events = require('neopilot.events')

-- LSP capability tracking
local lsp_capabilities = {
    document_symbol = false,
    workspace_symbol = false,
    code_action = false,
    references = false,
    definition = false,
    type_definition = false,
    implementation = false,
    rename = false,
    formatting = false,
    hover = false,
    completion = false,
    signature_help = false
}

-- Active LSP clients tracking
local active_clients = {}
local client_capabilities = {}

-- Initialize LSP integration
function M.setup()
    -- Setup autocmds to track LSP client changes
    vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(args)
            M.on_client_attach(args.data.client_id, args.buf)
        end,
        desc = 'Neopilot: Track LSP client attachment'
    })
    
    vim.api.nvim_create_autocmd('LspDetach', {
        callback = function(args)
            M.on_client_detach(args.data.client_id, args.buf)
        end,
        desc = 'Neopilot: Track LSP client detachment'
    })
    
    -- Initialize with current clients
    M.refresh_client_list()
    
    log.info("Enhanced LSP integration initialized")
end

-- Handle LSP client attachment
function M.on_client_attach(client_id, bufnr)
    local client = vim.lsp.get_client_by_id(client_id)
    if not client then
        return
    end
    
    active_clients[client_id] = client
    
    -- Update capabilities
    M.update_client_capabilities(client_id, client)
    
    log.info(string.format("LSP client attached: %s (ID: %d)", client.name, client_id))
    
    events.emit(events.EVENT_TYPES.LSP_CLIENT_ATTACHED, {
        client_id = client_id,
        client_name = client.name,
        bufnr = bufnr
    }, { source = 'lsp' })
end

-- Handle LSP client detachment
function M.on_client_detach(client_id, bufnr)
    local client = active_clients[client_id]
    if client then
        active_clients[client_id] = nil
        client_capabilities[client_id] = nil
        
        log.info(string.format("LSP client detached: %s (ID: %d)", client.name, client_id))
        
        events.emit(events.EVENT_TYPES.LSP_CLIENT_DETACHED, {
            client_id = client_id,
            client_name = client.name,
            bufnr = bufnr
        }, { source = 'lsp' })
    end
end

-- Update client capabilities
function M.update_client_capabilities(client_id, client)
    local caps = client.server_capabilities or {}
    
    client_capabilities[client_id] = {
        document_symbol = caps.documentSymbolProvider or false,
        workspace_symbol = caps.workspaceSymbolProvider or false,
        code_action = caps.codeActionProvider or false,
        references = caps.referencesProvider or false,
        definition = caps.definitionProvider or false,
        type_definition = caps.typeDefinitionProvider or false,
        implementation = caps.implementationProvider or false,
        rename = caps.renameProvider or false,
        formatting = caps.documentFormattingProvider or false,
        hover = caps.hoverProvider or false,
        completion = caps.completionProvider or false,
        signature_help = caps.signatureHelpProvider or false
    }
    
    -- Update global capabilities
    for cap, supported in pairs(client_capabilities[client_id]) do
        if supported then
            lsp_capabilities[cap] = true
        end
    end
end

-- Refresh the list of active clients
function M.refresh_client_list()
    active_clients = {}
    client_capabilities = {}
    
    local clients = vim.lsp.get_active_clients()
    for _, client in ipairs(clients) do
        active_clients[client.id] = client
        M.update_client_capabilities(client.id, client)
    end
end

-- Get enhanced LSP context for AI completion
function M.get_enhanced_context(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local context = {
        available = false,
        clients = {},
        symbols = {},
        references = {},
        diagnostics = {},
        code_actions = {},
        cursor_info = M.get_cursor_info(bufnr)
    }
    
    -- Check if we have active clients
    if vim.tbl_isempty(active_clients) then
        return context
    end
    
    context.available = true
    
    -- Get client information
    for client_id, client in pairs(active_clients) do
        table.insert(context.clients, {
            id = client_id,
            name = client.name,
            capabilities = client_capabilities[client_id] or {}
        })
    end
    
    -- Get workspace symbols if available
    if lsp_capabilities.workspace_symbol then
        context.symbols = M.get_workspace_symbols(bufnr)
    end
    
    -- Get references at cursor if available
    if lsp_capabilities.references then
        context.references = M.get_references_at_cursor(bufnr)
    end
    
    -- Get comprehensive diagnostics
    context.diagnostics = M.get_comprehensive_diagnostics(bufnr)
    
    -- Get available code actions
    if lsp_capabilities.code_action then
        context.code_actions = M.get_available_code_actions(bufnr)
    end
    
    return context
end

-- Get cursor position information
function M.get_cursor_info(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local cursor = vim.api.nvim_win_get_cursor(0)
    local position = {
        line = cursor[1] - 1,
        character = cursor[2]
    }
    
    return {
        position = position,
        text = vim.api.nvim_buf_get_lines(bufnr, position.line, position.line + 1, false)[1] or '',
        word = vim.fn.expand('<cword>'),
        filename = vim.api.nvim_buf_get_name(bufnr)
    }
end

-- Get workspace symbols
function M.get_workspace_symbols(bufnr, query)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    query = query or ''
    
    local symbols = {}
    
    for client_id, client in pairs(active_clients) do
        if client_capabilities[client_id].workspace_symbol then
            local ok, result = pcall(function()
                return vim.lsp.buf_request_sync(bufnr, 'workspace/symbol', { query = query }, 1000)
            end)
            
            if ok and result then
                for _, client_result in pairs(result) do
                    if client_result.result then
                        for _, symbol in ipairs(client_result.result) do
                            table.insert(symbols, {
                                name = symbol.name,
                                kind = symbol.kind,
                                location = symbol.location,
                                detail = symbol.detail or '',
                                client_id = client_id
                            })
                        end
                    end
                end
            end
        end
    end
    
    return symbols
end

-- Get references at cursor position
function M.get_references_at_cursor(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local references = {}
    local cursor_info = M.get_cursor_info(bufnr)
    
    for client_id, client in pairs(active_clients) do
        if client_capabilities[client_id].references then
            local ok, result = pcall(function()
                local params = vim.lsp.util.make_position_params()
                params.context = { includeDeclaration = true }
                return vim.lsp.buf_request_sync(bufnr, 'textDocument/references', params, 1000)
            end)
            
            if ok and result then
                for _, client_result in pairs(result) do
                    if client_result.result then
                        for _, ref in ipairs(client_result.result) do
                            table.insert(references, {
                                uri = ref.uri,
                                range = ref.range,
                                client_id = client_id
                            })
                        end
                    end
                end
            end
        end
    end
    
    return references
end

-- Get comprehensive diagnostics
function M.get_comprehensive_diagnostics(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local diagnostics = {}
    
    -- Get buffer diagnostics using new API (Neovim 0.6+)
    if vim.diagnostic then
        local buf_diagnostics = vim.diagnostic.get(bufnr)
        for _, diag in ipairs(buf_diagnostics) do
            table.insert(diagnostics, {
                severity = diag.severity,
                message = diag.message,
                range = diag.range,
                source = diag.source,
                code = diag.code,
                tags = diag.tags or {}
            })
        end
    else
        -- Fallback to older API
        local buf_diagnostics = vim.lsp.diagnostic.get(bufnr)
        for _, diag in ipairs(buf_diagnostics) do
            table.insert(diagnostics, {
                severity = diag.severity,
                message = diag.message,
                range = diag.range,
                source = diag.source
            })
        end
    end
    
    return diagnostics
end

-- Get available code actions at cursor
function M.get_available_code_actions(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local code_actions = {}
    local cursor_info = M.get_cursor_info(bufnr)
    
    for client_id, client in pairs(active_clients) do
        if client_capabilities[client_id].code_action then
            local ok, result = pcall(function()
                local params = vim.lsp.util.make_range_params()
                params.context = {
                    diagnostics = M.get_comprehensive_diagnostics(bufnr)
                }
                return vim.lsp.buf_request_sync(bufnr, 'textDocument/codeAction', params, 1000)
            end)
            
            if ok and result then
                for _, client_result in pairs(result) do
                    if client_result.result then
                        for _, action in ipairs(client_result.result) do
                            table.insert(code_actions, {
                                title = action.title,
                                kind = action.kind,
                                command = action.command,
                                edit = action.edit,
                                client_id = client_id
                            })
                        end
                    end
                end
            end
        end
    end
    
    return code_actions
end

-- Get document symbols
function M.get_document_symbols(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local symbols = {}
    
    for client_id, client in pairs(active_clients) do
        if client_capabilities[client_id].document_symbol then
            local ok, result = pcall(function()
                return vim.lsp.buf_request_sync(bufnr, 'textDocument/documentSymbol', {}, 1000)
            end)
            
            if ok and result then
                for _, client_result in pairs(result) do
                    if client_result.result then
                        for _, symbol in ipairs(client_result.result) do
                            table.insert(symbols, {
                                name = symbol.name,
                                kind = symbol.kind,
                                range = symbol.range or (symbol.location and symbol.location.range),
                                selection_range = symbol.selectionRange,
                                detail = symbol.detail or '',
                                children = symbol.children,
                                client_id = client_id
                            })
                        end
                    end
                end
            end
        end
    end
    
    return symbols
end

-- Get definition at cursor
function M.get_definition_at_cursor(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local definitions = {}
    
    for client_id, client in pairs(active_clients) do
        if client_capabilities[client_id].definition then
            local ok, result = pcall(function()
                return vim.lsp.buf_request_sync(bufnr, 'textDocument/definition', vim.lsp.util.make_position_params(), 1000)
            end)
            
            if ok and result then
                for _, client_result in pairs(result) do
                    if client_result.result then
                        if vim.tbl_islist(client_result.result) then
                            for _, def in ipairs(client_result.result) do
                                table.insert(definitions, {
                                    uri = def.uri,
                                    range = def.range,
                                    client_id = client_id
                                })
                            end
                        else
                            table.insert(definitions, {
                                uri = client_result.result.uri,
                                range = client_result.result.range,
                                client_id = client_id
                            })
                        end
                    end
                end
            end
        end
    end
    
    return definitions
end

-- Get type definition at cursor
function M.get_type_definition_at_cursor(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local type_definitions = {}
    
    for client_id, client in pairs(active_clients) do
        if client_capabilities[client_id].type_definition then
            local ok, result = pcall(function()
                return vim.lsp.buf_request_sync(bufnr, 'textDocument/typeDefinition', vim.lsp.util.make_position_params(), 1000)
            end)
            
            if ok and result then
                for _, client_result in pairs(result) do
                    if client_result.result then
                        if vim.tbl_islist(client_result.result) then
                            for _, type_def in ipairs(client_result.result) do
                                table.insert(type_definitions, {
                                    uri = type_def.uri,
                                    range = type_def.range,
                                    client_id = client_id
                                })
                            end
                        else
                            table.insert(type_definitions, {
                                uri = client_result.result.uri,
                                range = client_result.result.range,
                                client_id = client_id
                            })
                        end
                    end
                end
            end
        end
    end
    
    return type_definitions
end

-- Get implementation at cursor
function M.get_implementation_at_cursor(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local implementations = {}
    
    for client_id, client in pairs(active_clients) do
        if client_capabilities[client_id].implementation then
            local ok, result = pcall(function()
                return vim.lsp.buf_request_sync(bufnr, 'textDocument/implementation', vim.lsp.util.make_position_params(), 1000)
            end)
            
            if ok and result then
                for _, client_result in pairs(result) do
                    if client_result.result then
                        if vim.tbl_islist(client_result.result) then
                            for _, impl in ipairs(client_result.result) do
                                table.insert(implementations, {
                                    uri = impl.uri,
                                    range = impl.range,
                                    client_id = client_id
                                })
                            end
                        else
                            table.insert(implementations, {
                                uri = client_result.result.uri,
                                range = client_result.result.range,
                                client_id = client_id
                            })
                        end
                    end
                end
            end
        end
    end
    
    return implementations
end

-- Execute a code action with AI assistance
function M.execute_code_action(action, bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    if not action then
        log.warn("No code action provided")
        return false
    end
    
    local client = active_clients[action.client_id]
    if not client then
        log.warn("Client not found: " .. tostring(action.client_id))
        return false
    end
    
    -- Emit code action execution event
    events.emit(events.EVENT_TYPES.CODE_ACTION_EXECUTED, {
        action = action,
        bufnr = bufnr
    }, { source = 'lsp' })
    
    -- Execute the code action
    if action.edit then
        vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
        log.info("Applied workspace edit for action: " .. action.title)
        return true
    elseif action.command then
        vim.lsp.buf.execute_command(action.command)
        log.info("Executed command for action: " .. action.title)
        return true
    else
        log.warn("Unknown action type: " .. vim.inspect(action))
        return false
    end
end

-- Get hover information at cursor
function M.get_hover_at_cursor(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local hover_info = {}
    
    for client_id, client in pairs(active_clients) do
        if client_capabilities[client_id].hover then
            local ok, result = pcall(function()
                return vim.lsp.buf_request_sync(bufnr, 'textDocument/hover', vim.lsp.util.make_position_params(), 1000)
            end)
            
            if ok and result then
                for _, client_result in pairs(result) do
                    if client_result.result and client_result.result.contents then
                        table.insert(hover_info, {
                            contents = client_result.result.contents,
                            range = client_result.result.range,
                            client_id = client_id
                        })
                    end
                end
            end
        end
    end
    
    return hover_info
end

-- Get signature help at cursor
function M.get_signature_help_at_cursor(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local signature_help = {}
    
    for client_id, client in pairs(active_clients) do
        if client_capabilities[client_id].signature_help then
            local ok, result = pcall(function()
                return vim.lsp.buf_request_sync(bufnr, 'textDocument/signatureHelp', vim.lsp.util.make_position_params(), 1000)
            end)
            
            if ok and result then
                for _, client_result in pairs(result) do
                    if client_result.result then
                        table.insert(signature_help, {
                            signatures = client_result.result.signatures,
                            activeSignature = client_result.result.activeSignature,
                            activeParameter = client_result.result.activeParameter,
                            client_id = client_id
                        })
                    end
                end
            end
        end
    end
    
    return signature_help
end

-- Format current buffer or range
function M.format_buffer(bufnr, range)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local formatted = false
    
    for client_id, client in pairs(active_clients) do
        if client_capabilities[client_id].formatting then
            local ok, result = pcall(function()
                local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
                if range then
                    params.range = range
                end
                return vim.lsp.buf_request_sync(bufnr, 'textDocument/formatting', params, 2000)
            end)
            
            if ok and result then
                for _, client_result in pairs(result) do
                    if client_result.result then
                        vim.lsp.util.apply_text_edits(client_result.result, bufnr, client.offset_encoding)
                        formatted = true
                        log.info("Formatted buffer with client: " .. client.name)
                    end
                end
            end
        end
    end
    
    return formatted
end

-- Get LSP capabilities summary
function M.get_capabilities_summary()
    return {
        global = lsp_capabilities,
        clients = client_capabilities,
        active_clients = vim.tbl_count(active_clients)
    }
end

-- Check if specific capability is available
function M.has_capability(capability)
    return lsp_capabilities[capability] or false
end

-- Get clients that support a specific capability
function M.get_clients_with_capability(capability)
    local clients = {}
    
    for client_id, caps in pairs(client_capabilities) do
        if caps[capability] then
            local client = active_clients[client_id]
            if client then
                table.insert(clients, {
                    id = client_id,
                    name = client.name
                })
            end
        end
    end
    
    return clients
end

-- Legacy compatibility
function M.get_diagnostics(bufnr)
    local diagnostics = M.get_comprehensive_diagnostics(bufnr)
    
    if #diagnostics == 0 then
        return nil
    end
    
    local formatted_diagnostics = {}
    for _, d in ipairs(diagnostics) do
        table.insert(formatted_diagnostics, {
            severity = d.severity,
            message = d.message,
            line = d.range and d.range.start and d.range.start.line or 0,
        })
    end
    
    return formatted_diagnostics
end

return M
