-- Enhanced nvim-cmp source for Neopilot with modern framework support
local cmp = require('cmp')
local source = {}

-- Source configuration
source.new = function()
  return setmetatable({}, { __index = source })
end

-- Source metadata
function source:get_keyword_pattern()
  return [[\k\+]]
end

function source:get_trigger_characters()
  return { ' ', '\t', '\n', '.', '(', '[', '{', '"', "'", ':', ',', ';', '=', '+', '-', '*', '/' }
end

function source:is_available()
  local config = require('neopilot.config_v2')
  return config.is_enabled()
end

function source:get_debug_name()
  return 'neopilot'
end

function source:complete(params, callback)
  local core = require('neopilot.core')
  local config = require('neopilot.config_v2')
  local lsp_enhanced = require('neopilot.lsp_enhanced')
  local events = require('neopilot.events')

  -- Emit completion request event
  events.emit(events.EVENT_TYPES.COMPLETION_REQUESTED, {
    params = params,
    source = 'cmp'
  }, { source = 'cmp_source' })

  -- Get enhanced context with LSP integration if enabled
  local context = {}
  if config.get('lsp_context') and lsp_enhanced then
    context = lsp_enhanced.get_enhanced_context()
  end

  -- Check if we have cached completions
  local current_item = core.get_current_completion_item()
  if current_item then
    local completion = current_item.completion or {}
    local suffix = completion.suffix or {}
    local suffix_text = suffix.text or ''

    local text = (completion.text or '') .. suffix_text
    if text ~= '' then
      local items = source.create_completion_items(current_item, context)
      
      -- Emit completion received event
      events.emit(events.EVENT_TYPES.COMPLETION_RECEIVED, {
        items = items,
        context = context,
        source = 'cmp'
      }, { source = 'cmp_source' })
      
      callback({
        items = items,
        isIncomplete = false
      })
      return
    end
  end

  -- No cached completion, trigger new request with enhanced context
  if config.get('enable_debounce') then
    core.debounced_complete()
  else
    core.request_completions()
  end

  -- Return empty for now, will be updated when completion arrives
  callback({ items = {}, isIncomplete = true })
end

-- Create completion items with enhanced metadata
function source.create_completion_items(completion_item, lsp_context)
  local completion = completion_item.completion or {}
  local suffix = completion.suffix or {}
  local suffix_text = suffix.text or ''
  local text = (completion.text or '') .. suffix_text

  local items = {}

  -- Primary completion item
  local primary_item = {
    label = text,
    kind = cmp.lsp.CompletionItemKind.Text,
    documentation = {
      kind = cmp.lsp.MarkupKind.Markdown,
      value = source.create_documentation(completion, lsp_context)
    },
    insertText = text,
    insertTextFormat = cmp.lsp.InsertTextFormat.PlainText,
    preselect = true,
    sortText = '000', -- High priority
    data = {
      neopilot_completion_id = completion.completionId,
      neopilot_range = completion_item.range,
      neopilot_probability = completion.probability,
      neopilot_token_count = completion.tokenCount
    }
  }

  -- Add LSP context information if available
  if lsp_context and lsp_context.available then
    primary_item.detail = source.create_detail_text(completion, lsp_context)
  end

  table.insert(items, primary_item)

  -- Add alternative completions if available
  if completion.alternatives then
    for i, alt in ipairs(completion.alternatives) do
      local alt_item = {
        label = alt.text or '',
        kind = cmp.lsp.CompletionItemKind.Text,
        documentation = {
          kind = cmp.lsp.MarkupKind.Markdown,
          value = source.create_documentation(alt, lsp_context)
        },
        insertText = alt.text or '',
        insertTextFormat = cmp.lsp.InsertTextFormat.PlainText,
        sortText = string.format('%03d', i + 1),
        data = {
          neopilot_completion_id = alt.completionId,
          neopilot_alternative_index = i
        }
      }
      table.insert(items, alt_item)
    end
  end

  return items
end

-- Create documentation with enhanced information
function source.create_documentation(completion, lsp_context)
  local lines = { '**Neopilot AI Completion**' }
  table.insert(lines, '')

  -- Basic completion info
  if completion.probability then
    table.insert(lines, string.format('**Probability:** %.3f', completion.probability))
  end
  if completion.tokenCount then
    table.insert(lines, string.format('**Tokens:** %d', completion.tokenCount))
  end
  if completion.model then
    table.insert(lines, string.format('**Model:** %s', completion.model))
  end

  -- Add LSP context if available
  if lsp_context and lsp_context.available then
    table.insert(lines, '')
    table.insert(lines, '**Context:**')
    
    if #lsp_context.clients > 0 then
      local client_names = {}
      for _, client in ipairs(lsp_context.clients) do
        table.insert(client_names, client.name)
      end
      table.insert(lines, string.format('LSP Clients: %s', table.concat(client_names, ', ')))
    end

    if lsp_context.cursor_info and lsp_context.cursor_info.word then
      table.insert(lines, string.format('Current Word: `%s`', lsp_context.cursor_info.word))
    end

    if #lsp_context.diagnostics > 0 then
      table.insert(lines, string.format('Diagnostics: %d issues', #lsp_context.diagnostics))
    end
  end

  return table.concat(lines, '\n')
end

-- Create detail text for completion item
function source.create_detail_text(completion, lsp_context)
  local details = {}

  if completion.probability then
    table.insert(details, string.format('%.1f%%', completion.probability * 100))
  end

  if lsp_context and lsp_context.available and #lsp_context.clients > 0 then
    table.insert(details, 'LSP')
  end

  return table.concat(details, ' • ')
end

function source:execute(completion_item, callback)
  local core = require('neopilot.core')
  local events = require('neopilot.events')

  -- Accept the completion through our core module
  if completion_item.data and completion_item.data.neopilot_completion_id then
    -- Send accept completion request
    require('neopilot.server').request('AcceptCompletion', {
      metadata = require('neopilot.server').request_metadata(),
      completion_id = completion_item.data.neopilot_completion_id
    })

    -- Emit completion accepted event
    events.emit(events.EVENT_TYPES.COMPLETION_ACCEPTED, {
      completion_id = completion_item.data.neopilot_completion_id,
      text = completion_item.insertText,
      source = 'cmp'
    }, { source = 'cmp_source' })
  end

  callback(completion_item)
end

-- Handle completion confirmation
function source:confirm(completion_item, callback)
  self:execute(completion_item, callback)
end

-- Handle completion menu close
function source:close(callback)
  local events = require('neopilot.events')
  
  events.emit(events.EVENT_TYPES.COMPLETION_REJECTED, {
    source = 'cmp'
  }, { source = 'cmp_source' })
  
  callback()
end

-- Setup function for nvim-cmp integration
function source.setup()
  local cmp = require('cmp')
  
  cmp.register_source('neopilot', source)
  
  -- Configure source priority
  cmp.setup.cmdline('/', {
    sources = cmp.config.sources({
      { name = 'neopilot' }
    })
  })
  
  cmp.setup.cmdline('?', {
    sources = cmp.config.sources({
      { name = 'neopilot' }
    })
  })
  
  cmp.setup.filetype({ 'markdown', 'text', 'gitcommit' }, {
    sources = cmp.config.sources({
      { name = 'neopilot', priority = 1000 },
      { name = 'buffer' },
      { name = 'path' }
    })
  })
end

-- Blink.cmp support
local blink_source = {}

blink_source.new = function()
  local self = setmetatable({}, { __index = blink_source })
  self.completions = {}
  return self
end

function blink_source:get_trigger_characters()
  return { ' ', '\t', '\n', '.', '(', '[', '{', '"', "'", ':', ',', ';', '=', '+', '-', '*', '/' }
end

function blink_source:is_enabled()
  local config = require('neopilot.config_v2')
  return config.is_enabled()
end

function blink_source:execute_completions(params, callback)
  local core = require('neopilot.core')
  local config = require('neopilot.config_v2')
  local lsp_enhanced = require('neopilot.lsp_enhanced')

  -- Get enhanced context
  local context = {}
  if config.get('lsp_context') and lsp_enhanced then
    context = lsp_enhanced.get_enhanced_context()
  end

  -- Check for cached completions
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
          kind = 1, -- Text kind
          documentation = source.create_documentation(completion, context),
          insertText = text,
          score = 1000, -- High priority
          data = {
            neopilot_completion_id = completion.completionId,
            neopilot_range = current_item.range
          }
        }
      }
      
      callback({
        is_incomplete = false,
        items = items
      })
      return
    end
  end

  -- Trigger new completion request
  if config.get('enable_debounce') then
    core.debounced_complete()
  else
    core.request_completions()
  end

  -- Return empty for now
  callback({ is_incomplete = true, items = {} })
end

function blink_source:execute(completion_item, callback)
  if completion_item.data and completion_item.data.neopilot_completion_id then
    require('neopilot.server').request('AcceptCompletion', {
      metadata = require('neopilot.server').request_metadata(),
      completion_id = completion_item.data.neopilot_completion_id
    })
  end
  callback(completion_item)
end

-- Register with blink.cmp if available
local function register_blink()
  local ok, blink = pcall(require, 'blink.cmp')
  if not ok then
    return false
  end
  
  blink.add_source('neopilot', blink_source)
  return true
end

-- Auto-register with available completion frameworks
local function auto_register()
  -- Try nvim-cmp first
  local ok, cmp = pcall(require, 'cmp')
  if ok then
    source.setup()
    return 'nvim-cmp'
  end
  
  -- Try blink.cmp
  if register_blink() then
    return 'blink.cmp'
  end
  
  return nil
end

-- Export both sources and registration function
return {
  nvim_cmp = source,
  blink_cmp = blink_source,
  register = auto_register,
  setup_nvim_cmp = source.setup,
  register_blink = register_blink
}
