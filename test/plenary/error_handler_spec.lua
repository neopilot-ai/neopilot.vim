describe('neopilot.error_handler', function()
  local error_handler = require('neopilot.error_handler')
  local events = require('neopilot.events')

  before_each(function()
    -- Reset error handler stats
    error_handler.clear_error_stats()
    
    -- Mock log.error
    local log = require('neopilot.log')
    log.error = function(msg) end
  end)

  describe('error handling', function()
    it('should handle and categorize errors', function()
      local recovered = error_handler.handle_error('Connection timeout', { retry_count = 1 })
      
      local stats = error_handler.get_error_stats()
      assert.are.equal(1, stats.total)
      assert.are.equal(1, stats.by_category.network)
    end)

    it('should categorize network errors correctly', function()
      local category = error_handler.categorize_error('Connection failed', {})
      assert.are.equal('network', category)
      
      category = error_handler.categorize_error('Request timeout', {})
      assert.are.equal('network', category)
    end)

    it('should categorize server errors correctly', function()
      local category = error_handler.categorize_error('Server not responding', { server_error = true })
      assert.are.equal('server', category)
      
      category = error_handler.categorize_error('Server error occurred', {})
      assert.are.equal('server', category)
    end)

    it('should categorize config errors correctly', function()
      local category = error_handler.categorize_error('Invalid configuration', { config_key = 'test' })
      assert.are.equal('config', category)
      
      category = error_handler.categorize_error('Configuration validation failed', {})
      assert.are.equal('config', category)
    end)

    it('should categorize LSP errors correctly', function()
      local category = error_handler.categorize_error('LSP client error', { lsp_client = true })
      assert.are.equal('lsp', category)
    end)

    it('should categorize UI errors correctly', function()
      local category = error_handler.categorize_error('UI rendering failed', { ui_component = true })
      assert.are.equal('ui', category)
    end)

    it('should categorize completion errors correctly', function()
      local category = error_handler.categorize_error('Completion request failed', { completion_request = true })
      assert.are.equal('completion', category)
    end)

    it('should default to unknown category', function()
      local category = error_handler.categorize_error('Some unknown error', {})
      assert.are.equal('unknown', category)
    end)
  end)

  describe('recovery strategies', function()
    it('should register recovery strategies', function()
      local strategy_called = false
      local test_strategy = function(error_msg, context)
        strategy_called = true
        return true
      end
      
      error_handler.register_recovery_strategy('test', test_strategy)
      local recovered = error_handler.attempt_recovery('test', 'test error', {})
      
      assert.is_true(strategy_called)
      assert.is_true(recovered)
    end)

    it('should attempt network error recovery', function()
      local retry_emitted = false
      
      -- Mock events.emit
      local original_emit = events.emit
      events.emit = function(event_name, data)
        if event_name == 'neopilot:retry_request' then
          retry_emitted = true
        end
      end
      
      local recovered = error_handler.recover_network_error('Connection timeout', { retry_count = 1 })
      
      assert.is_true(recovered)
      assert.is_true(retry_emitted)
      
      -- Restore
      events.emit = original_emit
    end)

    it('should not retry after max attempts', function()
      local recovered = error_handler.recover_network_error('Connection timeout', { retry_count = 3 })
      assert.is_false(recovered)
    end)

    it('should attempt server error recovery', function()
      local restart_emitted = false
      
      -- Mock events.emit
      local original_emit = events.emit
      events.emit = function(event_name, data)
        if event_name == 'neopilot:restart_server' then
          restart_emitted = true
        end
      end
      
      local recovered = error_handler.recover_server_error('server not running', {})
      
      assert.is_true(recovered)
      assert.is_true(restart_emitted)
      
      -- Restore
      events.emit = original_emit
    end)

    it('should attempt config error recovery', function()
      local config_reset = false
      
      -- Mock config_v2.reset
      local original_reset = require('neopilot.config_v2').reset
      require('neopilot.config_v2').reset = function()
        config_reset = true
      end
      
      local recovered = error_handler.recover_config_error('Invalid config', { config_key = 'test' })
      
      assert.is_true(recovered)
      assert.is_true(config_reset)
      
      -- Restore
      require('neopilot.config_v2').reset = original_reset
    end)
  end)

  describe('error statistics', function()
    it('should track error statistics correctly', function()
      error_handler.handle_error('Network error', {}, 'network')
      error_handler.handle_error('Server error', {}, 'server')
      error_handler.handle_error('Network error', {}, 'network')
      
      local stats = error_handler.get_error_stats()
      assert.are.equal(3, stats.total)
      assert.are.equal(2, stats.by_category.network)
      assert.are.equal(1, stats.by_category.server)
      assert.are.equal(3, #stats.recent)
    end)

    it('should limit recent errors', function()
      -- Add many errors
      for i = 1, 105 do
        error_handler.handle_error('Error ' .. i, {}, 'unknown')
      end
      
      local stats = error_handler.get_error_stats()
      assert.are.equal(105, stats.total)
      assert.are.equal(100, #stats.recent) -- Should be limited to max_recent
    end)

    it('should clear error statistics', function()
      error_handler.handle_error('Test error', {}, 'unknown')
      assert.are.equal(1, error_handler.get_error_stats().total)
      
      error_handler.clear_error_stats()
      assert.are.equal(0, error_handler.get_error_stats().total)
    end)
  end)

  describe('error storm detection', function()
    it('should detect error storm', function()
      -- Mock vim.loop.now to return consistent time
      local original_now = vim.loop.now
      local current_time = 1000
      vim.loop.now = function()
        return current_time
      end
      
      -- Add many errors within short time window
      for i = 1, 15 do
        error_handler.handle_error('Error ' .. i, {}, 'unknown')
        current_time = current_time + 1000 -- 1 second between errors
      end
      
      assert.is_true(error_handler.is_error_storm())
      
      -- Restore
      vim.loop.now = original_now
    end)

    it('should not detect error storm with few errors', function()
      -- Mock vim.loop.now
      local original_now = vim.loop.now
      local current_time = 1000
      vim.loop.now = function()
        return current_time
      end
      
      -- Add few errors
      for i = 1, 5 do
        error_handler.handle_error('Error ' .. i, {}, 'unknown')
        current_time = current_time + 1000
      end
      
      assert.is_false(error_handler.is_error_storm())
      
      -- Restore
      vim.loop.now = original_now
    end)
  end)

  describe('graceful degradation', function()
    it('should enable graceful degradation', function()
      local config_set = false
      local config_values = {}
      
      -- Mock config_v2.set
      local original_set = require('neopilot.config_v2').set
      require('neopilot.config_v2').set = function(key, value, source)
        config_set = true
        config_values[key] = value
      end
      
      error_handler.enable_graceful_degradation()
      
      assert.is_true(config_set)
      assert.is_false(config_values.enable_caching)
      assert.is_false(config_values.lsp_context)
      
      -- Restore
      require('neopilot.config_v2').set = original_set
    end)
  end)

  describe('event emission', function()
    it('should emit error events', function()
      local error_event_emitted = false
      local recovered_event_emitted = false
      
      -- Mock events.emit
      local original_emit = events.emit
      events.emit = function(event_name, data, opts)
        if event_name == events.EVENT_TYPES.ERROR_OCCURRED then
          error_event_emitted = true
        elseif event_name == events.EVENT_TYPES.ERROR_RECOVERED then
          recovered_event_emitted = true
        end
      end
      
      error_handler.handle_error('Test error', {}, 'unknown')
      
      assert.is_true(error_event_emitted)
      
      -- Restore
      events.emit = original_emit
    end)
  end)
end)
