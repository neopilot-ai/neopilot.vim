describe('neopilot.lsp_enhanced', function()
  local lsp_enhanced = require('neopilot.lsp_enhanced')
  local events = require('neopilot.events')

  before_each(function()
    -- Mock LSP clients
    vim.lsp.get_active_clients = function()
      return {
        {
          id = 1,
          name = 'test_client',
          server_capabilities = {
            documentSymbolProvider = true,
            workspaceSymbolProvider = true,
            codeActionProvider = true,
            referencesProvider = true,
            definitionProvider = true,
            typeDefinitionProvider = true,
            implementationProvider = true,
            renameProvider = true,
            documentFormattingProvider = true,
            hoverProvider = true,
            completionProvider = true,
            signatureHelpProvider = true
          }
        }
      }
    end
    
    -- Mock vim.lsp.buf_request_sync
    vim.lsp.buf_request_sync = function(bufnr, method, params, timeout)
      if method == 'textDocument/documentSymbol' then
        return {
          [1] = {
            result = {
              {
                name = 'test_function',
                kind = 12,
                range = {
                  start = { line = 1, character = 0 },
                  ['end'] = { line = 5, character = 0 }
                }
              }
            }
          }
        }
      elseif method == 'textDocument/codeAction' then
        return {
          [1] = {
            result = {
              {
                title = 'Quick Fix',
                kind = 'quickfix'
              }
            }
          }
        }
      elseif method == 'textDocument/references' then
        return {
          [1] = {
            result = {
              {
                uri = 'file:///test.lua',
                range = {
                  start = { line = 2, character = 5 },
                  ['end'] = { line = 2, character = 10 }
                }
              }
            }
          }
        }
      end
      return {}
    end
    
    -- Mock vim.api.nvim_get_current_buf
    vim.api.nvim_get_current_buf = function()
      return 1
    end
    
    -- Mock vim.api.nvim_win_get_cursor
    vim.api.nvim_win_get_cursor = function()
      return { 3, 10 }
    end
    
    -- Mock vim.api.nvim_buf_get_lines
    vim.api.nvim_buf_get_lines = function(bufnr, start, end_, strict)
      return {'local test = "hello"'}
    end
    
    -- Mock vim.fn.expand
    vim.fn.expand = function(expr)
      if expr == '<cword>' then
        return 'test'
      end
      return ''
    end
    
    -- Mock vim.api.nvim_buf_get_name
    vim.api.nvim_buf_get_name = function(bufnr)
      return '/test/file.lua'
    end
    
    -- Mock vim.diagnostic
    vim.diagnostic = {
      get = function(bufnr)
        return {
          {
            severity = 1,
            message = 'Test error',
            range = {
              start = { line = 1, character = 0 },
              ['end'] = { line = 1, character = 5 }
            }
          }
        }
      end
    }
    
    lsp_enhanced.refresh_client_list()
  end)

  describe('client management', function()
    it('should track active LSP clients', function()
      lsp_enhanced.refresh_client_list()
      local capabilities = lsp_enhanced.get_capabilities_summary()
      
      assert.is_true(capabilities.global.document_symbol)
      assert.is_true(capabilities.global.code_action)
      assert.are.equal(1, capabilities.active_clients)
    end)

    it('should check for specific capabilities', function()
      assert.is_true(lsp_enhanced.has_capability('document_symbol'))
      assert.is_false(lsp_enhanced.has_capability('unknown_capability'))
    end)

    it('should get clients with specific capability', function()
      local clients = lsp_enhanced.get_clients_with_capability('document_symbol')
      assert.are.equal(1, #clients)
      assert.are.equal('test_client', clients[1].name)
    end)
  end)

  describe('context gathering', function()
    it('should get enhanced LSP context', function()
      local context = lsp_enhanced.get_enhanced_context()
      
      assert.is_true(context.available)
      assert.are.equal(1, #context.clients)
      assert.are.equal('test_client', context.clients[1].name)
      assert.is_not_nil(context.cursor_info)
    end)

    it('should get cursor information', function()
      local cursor_info = lsp_enhanced.get_cursor_info()
      
      assert.are.equal(2, cursor_info.position.line) -- 0-indexed
      assert.are.equal(10, cursor_info.position.character)
      assert.are.equal('test', cursor_info.word)
      assert.are.equal('/test/file.lua', cursor_info.filename)
    end)
  end)

  describe('LSP operations', function()
    it('should get document symbols', function()
      local symbols = lsp_enhanced.get_document_symbols()
      
      assert.are.equal(1, #symbols)
      assert.are.equal('test_function', symbols[1].name)
      assert.are.equal(12, symbols[1].kind)
    end)

    it('should get code actions', function()
      local actions = lsp_enhanced.get_available_code_actions()
      
      assert.are.equal(1, #actions)
      assert.are.equal('Quick Fix', actions[1].title)
      assert.are.equal('quickfix', actions[1].kind)
    end)

    it('should get references', function()
      local references = lsp_enhanced.get_references_at_cursor()
      
      assert.are.equal(1, #references)
      assert.are.equal('file:///test.lua', references[1].uri)
    end)

    it('should get comprehensive diagnostics', function()
      local diagnostics = lsp_enhanced.get_comprehensive_diagnostics()
      
      assert.are.equal(1, #diagnostics)
      assert.are.equal(1, diagnostics[1].severity)
      assert.are.equal('Test error', diagnostics[1].message)
    end)
  end)

  describe('code action execution', function()
    it('should execute code actions with workspace edits', function()
      local action = {
        title = 'Test Action',
        edit = {
          changes = {
            ['file:///test.lua'] = {
              {
                range = {
                  start = { line = 1, character = 0 },
                  ['end'] = { line = 1, character = 5 }
                },
                newText = 'new text'
              }
            }
          }
        },
        client_id = 1
      }
      
      -- Mock vim.lsp.util.apply_workspace_edit
      vim.lsp.util.apply_workspace_edit = function(edit, offset_encoding)
        assert.is_not_nil(edit)
      end
      
      local result = lsp_enhanced.execute_code_action(action)
      assert.is_true(result)
    end)

    it('should handle missing actions gracefully', function()
      local result = lsp_enhanced.execute_code_action(nil)
      assert.is_false(result)
    end)
  end)

  describe('legacy compatibility', function()
    it('should provide legacy get_diagnostics function', function()
      local diagnostics = lsp_enhanced.get_diagnostics()
      
      assert.is_not_nil(diagnostics)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(1, diagnostics[1].severity)
      assert.are.equal('Test error', diagnostics[1].message)
    end)
  end)
end)
