-- Neopilot Lua initialization
-- This file serves as the main entry point for Lua-based functionality

local M = {}

-- Initialize the Lua module
function M.setup(opts)
    opts = opts or {}

    -- Load core modules first
    require('neopilot.config').setup(opts)
    require('neopilot.log').setup(opts)

    -- Load other submodules
    require('neopilot.util').setup(opts)
    require('neopilot.doc').setup(opts)
    require('neopilot.core').setup(opts)
    require('neopilot.server').setup(opts)
    require('neopilot.ui').setup(opts)
    require('neopilot.command').setup(opts)
    require('neopilot.health').setup(opts)
    require('neopilot.test').setup(opts)
    require('neopilot.metrics').setup(opts)
    require('neopilot.api').setup(opts)
    require('neopilot.lsp').setup(opts)
end

-- Check if Neovim is available (for compatibility)
function M.has_nvim()
    return vim ~= nil
end

-- Get nvim-cmp source if available
function M.get_cmp_source()
    if pcall(require, 'neopilot.cmp') then
        return require('neopilot.cmp')
    end
    return nil
end

-- Run health check
function M.health_check()
    return require('neopilot.health').check()
end

-- Run tests
function M.run_tests()
    return require('neopilot.test').run_all()
end

return M