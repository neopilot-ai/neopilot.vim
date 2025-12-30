-- Tests for virtual text module
local virtual_text = require('neopilot.virtual_text')

describe('neopilot.virtual_text', function()
    local test_bufnr
    
    before_each(function()
        -- Create a test buffer
        test_bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(test_bufnr)
        
        -- Setup virtual text module
        virtual_text.setup({
            enabled = true,
            show_confidence = true,
            show_icons = true,
            animate_transitions = false, -- Disable for testing
            timeout = 1000 -- Short timeout for testing
        })
    end)
    
    after_each(function()
        -- Clean up
        virtual_text.cleanup()
        
        if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
            vim.api.nvim_buf_delete(test_bufnr, { force = true })
        end
    end)
    
    describe('setup', function()
        it('should initialize virtual text system', function()
            local state = virtual_text.get_state()
            assert.is_true(state.enabled)
            assert.has_key(state, 'config')
        end)
        
        it('should create namespace', function()
            local state = virtual_text.get_state()
            assert.is_number(state.config.highlights)
        end)
    end)
    
    describe('show_completion', function()
        it('should display completion as virtual text', function()
            local completion_item = {
                completion = {
                    text = 'test_completion',
                    confidence = 0.8
                }
            }
            
            virtual_text.show_completion(completion_item)
            
            local state = virtual_text.get_state()
            assert.equals(1, state.active_completions)
        end)
        
        it('should handle empty completion', function()
            local completion_item = {
                completion = {
                    text = '',
                    confidence = 0.5
                }
            }
            
            virtual_text.show_completion(completion_item)
            
            local state = virtual_text.get_state()
            assert.equals(0, state.active_completions)
        end)
        
        it('should handle nil completion', function()
            virtual_text.show_completion(nil)
            
            local state = virtual_text.get_state()
            assert.equals(0, state.active_completions)
        end)
        
        it('should handle multi-line completions', function()
            local completion_item = {
                completion = {
                    text = 'line1\nline2\nline3',
                    confidence = 0.9
                }
            }
            
            virtual_text.show_completion(completion_item)
            
            local state = virtual_text.get_state()
            assert.equals(1, state.active_completions)
        end)
    end)
    
    describe('clear_completion', function()
        it('should clear all completions', function()
            local completion_item = {
                completion = {
                    text = 'test_completion',
                    confidence = 0.7
                }
            }
            
            virtual_text.show_completion(completion_item)
            local state_before = virtual_text.get_state()
            assert.equals(1, state_before.active_completions)
            
            virtual_text.clear_completion()
            local state_after = virtual_text.get_state()
            assert.equals(0, state_after.active_completions)
        end)
        
        it('should clear specific completion', function()
            local completion_item = {
                completion = {
                    text = 'test_completion',
                    confidence = 0.6
                }
            }
            
            virtual_text.show_completion(completion_item)
            local state_before = virtual_text.get_state()
            assert.equals(1, state_before.active_completions)
            
            -- Note: This test assumes we can get the extmark_id, which may require
            -- exposing internal state or using a different approach
            virtual_text.clear_completion()
            local state_after = virtual_text.get_state()
            assert.equals(0, state_after.active_completions)
        end)
    end)
    
    describe('confidence handling', function()
        it('should handle high confidence', function()
            local highlight = virtual_text.get_confidence_highlight(0.9)
            assert.equals('NeopilotConfidenceHigh', highlight)
        end)
        
        it('should handle medium confidence', function()
            local highlight = virtual_text.get_confidence_highlight(0.6)
            assert.equals('NeopilotConfidenceMedium', highlight)
        end)
        
        it('should handle low confidence', function()
            local highlight = virtual_text.get_confidence_highlight(0.3)
            assert.equals('NeopilotConfidenceLow', highlight)
        end)
        
        it('should get confidence text', function()
            assert.equals('●', virtual_text.get_confidence_text(0.8))
            assert.equals('○', virtual_text.get_confidence_text(0.5))
            assert.equals('◐', virtual_text.get_confidence_text(0.2))
        end)
    end)
    
    describe('floating completion', function()
        it('should show floating completion window', function()
            local completion_item = {
                completion = {
                    text = 'floating_test',
                    confidence = 0.7
                }
            }
            
            virtual_text.show_floating_completion(completion_item)
            
            local state = virtual_text.get_state()
            assert.equals(1, state.floating_windows)
        end)
        
        it('should handle empty floating completion', function()
            local completion_item = {
                completion = {
                    text = '',
                    confidence = 0.5
                }
            }
            
            virtual_text.show_floating_completion(completion_item)
            
            local state = virtual_text.get_state()
            assert.equals(0, state.floating_windows)
        end)
    end)
    
    describe('diff preview', function()
        it('should show diff preview', function()
            local original = 'original text'
            local new_text = 'modified text'
            
            -- This test mainly checks that the function doesn't error
            virtual_text.show_diff_preview(original, new_text)
            
            -- The diff preview creates a temporary window, so we can't easily
            -- test its contents without exposing more internal state
            assert.is_true(true)
        end)
    end)
    
    describe('progress indicator', function()
        it('should show progress', function()
            virtual_text.show_progress('Processing', 50)
            
            -- Progress is shown as virtual text, difficult to test directly
            -- without exposing internal state
            assert.is_true(true)
        end)
        
        it('should handle default progress', function()
            virtual_text.show_progress('Processing')
            
            assert.is_true(true)
        end)
    end)
    
    describe('message display', function()
        it('should show error message', function()
            virtual_text.show_error('Test error')
            assert.is_true(true)
        end)
        
        it('should show warning message', function()
            virtual_text.show_warning('Test warning')
            assert.is_true(true)
        end)
        
        it('should show info message', function()
            virtual_text.show_info('Test info')
            assert.is_true(true)
        end)
    end)
    
    describe('toggle', function()
        it('should toggle enabled state', function()
            local state_before = virtual_text.get_state()
            assert.is_true(state_before.enabled)
            
            virtual_text.toggle()
            
            local state_after = virtual_text.get_state()
            assert.is_false(state_after.enabled)
            
            virtual_text.toggle()
            
            local state_final = virtual_text.get_state()
            assert.is_true(state_final.enabled)
        end)
    end)
    
    describe('cleanup', function()
        it('should clean up all resources', function()
            -- Create some completions
            local completion_item = {
                completion = {
                    text = 'test_completion',
                    confidence = 0.7
                }
            }
            
            virtual_text.show_completion(completion_item)
            virtual_text.show_floating_completion(completion_item)
            
            local state_before = virtual_text.get_state()
            assert.equals(1, state_before.active_completions)
            assert.equals(1, state_before.floating_windows)
            
            virtual_text.cleanup()
            
            local state_after = virtual_text.get_state()
            assert.equals(0, state_after.active_completions)
            assert.equals(0, state_after.floating_windows)
        end)
    end)
    
    describe('configuration', function()
        it('should respect custom configuration', function()
            virtual_text.setup({
                enabled = false,
                show_confidence = false,
                show_icons = false,
                timeout = 500
            })
            
            local state = virtual_text.get_state()
            assert.is_false(state.enabled)
            assert.is_false(state.config.show_confidence)
            assert.is_false(state.config.show_icons)
            assert.equals(500, state.config.timeout)
        end)
    end)
end)
