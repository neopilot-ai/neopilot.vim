describe('neopilot.config', function()
  local config = require('neopilot.config')

  it('should have default values', function()
    assert.are.equal(75, config.get('idle_delay'))
    assert.are.equal('WARN', config.get('log_level'))
  end)

  it('should allow setting and getting values', function()
    config.set('test_value', 123)
    assert.are.equal(123, config.get('test_value'))
  end)
end)
