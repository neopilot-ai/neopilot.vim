-- Neovim CMP source for Neopilot
local cmp_source = {}

-- Source configuration
cmp_source.source_name = 'neopilot'

-- Check if source is available
function cmp_source.is_available()
    return require('neopilot.config').is_enabled()
end

-- Get completion items
function cmp_source.complete(self, params, callback)
    local core = require('neopilot.core')

    -- Check if we have cached completions
    if core.get_current_completion_item then
        local current_item = core.get_current_completion_item()
        if current_item then
            local completion = current_item.completion or {}
            local suffix = completion.suffix or {}
            local suffix_text = suffix.text or ''

            local text = (completion.text or '') .. suffix_text
            if text ~= '' then
                local items = {
                    {
                        label = text,
                        kind = require('cmp.types').lsp.CompletionItemKind.Text,
                        documentation = {
                            kind = require('cmp.types').lsp.MarkupKind.Markdown,
                            value = string.format('**Neopilot Completion**\n\nProbability: %.3f\nTokens: %d',
                                completion.probability or 0,
                                completion.tokenCount or 0)
                        },
                        insertText = text,
                        preselect = true,
                        sortText = '000', -- High priority
                        data = {
                            neopilot_completion_id = completion.completionId,
                            neopilot_range = current_item.range
                        }
                    }
                }
                callback(items)
                return
            end
        end
    end

    -- No cached completion, trigger new request
    core.debounced_complete()

    -- Return empty for now, will be updated when completion arrives
    callback({})
end

-- Execute completion
function cmp_source.execute(self, completion_item, callback)
    local core = require('neopilot.core')

    -- Accept the completion through our core module
    if completion_item.data and completion_item.data.neopilot_completion_id then
        -- Send accept completion request
        require('neopilot.server').request('AcceptCompletion', {
            metadata = require('neopilot.server').request_metadata(),
            completion_id = completion_item.data.neopilot_completion_id
        })
    end

    callback(completion_item)
end

-- Get trigger characters
function cmp_source.get_trigger_characters()
    return { ' ', '\t', '\n', '.', '(', '[', '{', '"', "'", ':' }
end

-- Get keyword pattern
function cmp_source.get_keyword_pattern()
    -- Match any non-whitespace character
    return [[\k\+]]
end

return cmp_source