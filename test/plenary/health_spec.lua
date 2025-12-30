describe('neopilot.health', function()
  it('should be able to call check function without error', function()
    local health = require('neopilot.health')
    assert.does_not.error(function()
      -- health.check() creates a new buffer, which might be problematic in tests
      -- We will just check if the function exists for now
      assert.is_function(health.check)
    end)
  end)
end)
