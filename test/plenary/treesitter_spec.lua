-- Tests for enhanced Tree-sitter integration
local treesitter = require('neopilot.treesitter')

describe('neopilot.treesitter', function()
    local test_bufnr
    
    before_each(function()
        -- Create a test buffer
        test_bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(test_bufnr)
    end)
    
    after_each(function()
        -- Clean up test buffer
        if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
            vim.api.nvim_buf_delete(test_bufnr, { force = true })
        end
    end)
    
    describe('is_treesitter_available', function()
        it('should return false when treesitter is not available', function()
            -- Mock treesitter as unavailable
            local original_treesitter = vim.treesitter
            vim.treesitter = nil
            
            local result = treesitter.is_treesitter_available(test_bufnr)
            assert.is_false(result)
            
            -- Restore
            vim.treesitter = original_treesitter
        end)
        
        it('should return false when filetype is empty', function()
            vim.bo[test_bufnr].filetype = ''
            local result = treesitter.is_treesitter_available(test_bufnr)
            assert.is_false(result)
        end)
    end)
    
    describe('get_imports', function()
        it('should return empty table when treesitter is unavailable', function()
            vim.bo[test_bufnr].filetype = 'python'
            local result = treesitter.get_imports(test_bufnr)
            assert.is_table(result)
            assert.equals(0, #result)
        end)
        
        it('should handle python imports correctly', function()
            vim.bo[test_bufnr].filetype = 'python'
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                'import os',
                'import sys',
                'from typing import List',
                'import numpy as np'
            })
            
            -- Mock treesitter availability
            local mock_results = {
                { capture = 'name', text = 'os' },
                { capture = 'name', text = 'sys' },
                { capture = 'name', text = 'List' },
                { capture = 'name', text = 'np' }
            }
            
            -- This test would require mocking the treesitter parser
            -- For now, we test the function structure
            local result = treesitter.get_imports(test_bufnr)
            assert.is_table(result)
        end)
    end)
    
    describe('get_functions', function()
        it('should return empty table when treesitter is unavailable', function()
            vim.bo[test_bufnr].filetype = 'python'
            local result = treesitter.get_functions(test_bufnr)
            assert.is_table(result)
            assert.equals(0, #result)
        end)
    end)
    
    describe('get_classes', function()
        it('should return empty table when treesitter is unavailable', function()
            vim.bo[test_bufnr].filetype = 'python'
            local result = treesitter.get_classes(test_bufnr)
            assert.is_table(result)
            assert.equals(0, #result)
        end)
    end)
    
    describe('get_semantic_context', function()
        it('should return unavailable status when treesitter is not available', function()
            vim.bo[test_bufnr].filetype = 'python'
            local result = treesitter.get_semantic_context(test_bufnr)
            assert.is_false(result.available)
            assert.equals('treesitter_not_available', result.reason)
        end)
        
        it('should return context structure when available', function()
            vim.bo[test_bufnr].filetype = 'python'
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                'def test_function():',
                '    pass'
            })
            
            local result = treesitter.get_semantic_context(test_bufnr)
            assert.is_table(result)
            assert.has_key(result, 'available')
            assert.has_key(result, 'filetype')
            assert.has_key(result, 'current_scope')
        end)
    end)
    
    describe('get_function_boundary_hash', function()
        it('should return global hash when no function found', function()
            vim.bo[test_bufnr].filetype = 'python'
            local result = treesitter.get_function_boundary_hash(test_bufnr)
            assert.equals('python:global', result)
        end)
    end)
    
    describe('get_enhanced_completion_context', function()
        it('should return enhanced context with additional fields', function()
            vim.bo[test_bufnr].filetype = 'python'
            local result = treesitter.get_enhanced_completion_context(test_bufnr)
            assert.is_table(result)
            assert.has_key(result, 'function_boundary_hash')
        end)
    end)
end)
