describe('neopilot.config_v2', function()
  local config_v2 = require('neopilot.config_v2')

  before_each(function()
    -- Reset config before each test
    config_v2.reset()
  end)

  describe('default configuration', function()
    it('should load default values', function()
      assert.are.equal(true, config_v2.get('enabled'))
      assert.are.equal(75, config_v2.get('idle_delay'))
      assert.are.equal('WARN', config_v2.get('log_level'))
      assert.are.equal(0.2, config_v2.get('temperature'))
      assert.are.equal(256, config_v2.get('max_tokens'))
    end)

    it('should have correct default filetypes', function()
      local filetypes = config_v2.get('filetypes')
      assert.are.equal(false, filetypes.help)
      assert.are.equal(false, filetypes.gitcommit)
      assert.are.equal(false, filetypes.gitrebase)
    end)
  end)

  describe('configuration validation', function()
    it('should validate boolean values', function()
      assert.has_no.errors(function()
        config_v2.set('enabled', false)
      end)
      
      assert.has.error(function()
        config_v2.set('enabled', 'true')
      end)
    end)

    it('should validate number ranges', function()
      assert.has_no.errors(function()
        config_v2.set('idle_delay', 100)
      end)
      
      assert.has.error(function()
        config_v2.set('idle_delay', -1)
      end)
      
      assert.has.error(function()
        config_v2.set('idle_delay', 1001)
      end)
    end)

    it('should validate enum values', function()
      assert.has_no.errors(function()
        config_v2.set('log_level', 'DEBUG')
      end)
      
      assert.has.error(function()
        config_v2.set('log_level', 'INVALID')
      end)
    end)

    it('should validate temperature range', function()
      assert.has_no.errors(function()
        config_v2.set('temperature', 0.5)
      end)
      
      assert.has.error(function()
        config_v2.set('temperature', -0.1)
      end)
      
      assert.has.error(function()
        config_v2.set('temperature', 2.1)
      end)
    end)
  end)

  describe('configuration merging', function()
    it('should merge user configuration', function()
      local user_config = {
        enabled = false,
        idle_delay = 100,
        temperature = 0.8
      }
      
      config_v2.merge_user_config(user_config, 'test')
      
      assert.are.equal(false, config_v2.get('enabled'))
      assert.are.equal(100, config_v2.get('idle_delay'))
      assert.are.equal(0.8, config_v2.get('temperature'))
      assert.are.equal('WARN', config_v2.get('log_level')) -- Should keep default
    end)

    it('should reject invalid configuration keys', function()
      assert.has.error(function()
        config_v2.merge_user_config({ invalid_key = true })
      end)
    end)
  end)

  describe('configuration sources', function()
    it('should track configuration sources', function()
      assert.are.equal('default', config_v2.get_source('enabled'))
      
      config_v2.set('enabled', false, 'test')
      assert.are.equal('test', config_v2.get_source('enabled'))
    end)
  end)

  describe('filetype configuration', function()
    it('should handle filetype-specific settings', function()
      config_v2.set_filetype_config('python', { enabled = true })
      config_v2.set_filetype_config('javascript', { enabled = false })
      
      local python_config = config_v2.get_filetype_config('python')
      assert.are.equal(true, python_config.enabled)
      
      local js_config = config_v2.get_filetype_config('javascript')
      assert.are.equal(false, js_config.enabled)
    end)
  end)

  describe('change listeners', function()
    it('should notify change listeners', function()
      local called = false
      local old_val, new_val, key
      
      config_v2.on_change('enabled', function(k, old, new)
        called = true
        key = k
        old_val = old
        new_val = new
      end)
      
      config_v2.set('enabled', false)
      
      assert.is_true(called)
      assert.are.equal('enabled', key)
      assert.are.equal(true, old_val)
      assert.are.equal(false, new_val)
    end)
  end)

  describe('health check', function()
    it('should perform health checks', function()
      local health = config_v2.health_check()
      assert.are.equal('ok', health.status)
      
      -- Set some problematic values
      config_v2.set('idle_delay', 600)
      config_v2.set('cache_ttl', 1000)
      
      health = config_v2.health_check()
      assert.are.equal('warning', health.status)
      assert.is_true(#health.warnings > 0)
    end)
  end)

  describe('documentation', function()
    it('should provide configuration documentation', function()
      local docs = config_v2.get_documentation()
      
      assert.is_not_nil(docs.enabled)
      assert.are.equal('boolean', docs.enabled.type)
      assert.are.equal(true, docs.enabled.default)
      assert.is_not_nil(docs.enabled.description)
    end)
  end)

  describe('is_enabled', function()
    it('should check if enabled for current buffer', function()
      -- Mock vim.b.neopilot_enabled
      vim.b.neopilot_enabled = true
      
      assert.is_true(config_v2.is_enabled())
      
      vim.b.neopilot_enabled = false
      assert.is_false(config_v2.is_enabled())
    end)
  end)
end)
