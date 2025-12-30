describe('neopilot.util', function()
  local util = require('neopilot.util')

  describe('offset_to_position and position_to_offset', function()
    it('should correctly convert back and forth', function()
      local lines = { 'hello', 'world', 'this is a test' }
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

      -- Test case 1: 'world'
      local offset1 = util.position_to_offset(2, 1)
      local row1, col1 = util.offset_to_position(offset1)
      assert.are.equal(2, row1)
      assert.are.equal(1, col1)

      -- Test case 2: 'test'
      local offset2 = util.position_to_offset(3, 11)
      local row2, col2 = util.offset_to_position(offset2)
      assert.are.equal(3, row2)
      assert.are.equal(11, col2)
    end)
  end)

  describe('has_supported_version', function()
    it('should return a boolean', function()
        assert.is_boolean(util.has_supported_version())
    end)
  end)
end)
