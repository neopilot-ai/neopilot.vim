let s:hlgroup = 'NeopilotSuggestion'
let s:annot_hlgroup = 'NeopilotAnnotation'
let s:request_nonce = 0

" Constants
let s:DEFAULT_IDLE_DELAY = 75
let s:API_TIMEOUT_MS = 5000
let s:MAX_COMPLETIONS = 10
let s:MAX_NEWLINES = 20
let s:MAX_TOKENS = 256
let s:MIN_LOG_PROBABILITY = -15.0
let s:TEMPERATURE = 0.2
let s:TOP_K = 50
let s:TOP_P = 1.0
let s:FIRST_TEMPERATURE = 0.2

if !has('nvim')
  if empty(prop_type_get(s:hlgroup))
    call prop_type_add(s:hlgroup, {'highlight': s:hlgroup})
  endif
  if empty(prop_type_get(s:annot_hlgroup))
    call prop_type_add(s:annot_hlgroup, {'highlight': s:annot_hlgroup})
  endif
endif

let s:default_neopilot_enabled = {
      \ 'help': 0,
      \ 'gitcommit': 0,
      \ 'gitrebase': 0,
      \ '.': 0}

" Check if Neopilot is enabled for the current buffer
function! neopilot#Enabled() abort
  if !get(g:, 'neopilot_enabled', v:true) || !get(b:, 'neopilot_enabled', v:true)
      return v:false
  endif

  let neopilot_filetypes = s:default_neopilot_enabled
  call extend(neopilot_filetypes, get(g:, 'neopilot_filetypes', {}))
  if !get(neopilot_filetypes, &ft, 1)
    return v:false
  endif

  return v:true
endfunction

" Get the current completion text for insertion
function! neopilot#CompletionText() abort
  try
    return remove(s:, 'completion_text')
  catch
    return ''
  endtry
endfunction

" Accept the current completion suggestion
function! neopilot#Accept() abort
  if mode() !~# '^[iR]' || !exists('b:_neopilot_completions')
    return ''
  endif
  let default = get(g:, 'neopilot_tab_fallback', pumvisible() ? "\<C-N>" : "\t")

  let current_completion = s:GetCurrentCompletionItem()
  if current_completion isnot v:null
    let range = current_completion.range
    let start_offset = get(range, 'startOffset', 0)
    let end_offset = get(range, 'endOffset', 0)
    let [start_row, start_col] = neopilot#util#OffsetToPosition(start_offset)
    let [end_row, end_col] = neopilot#util#OffsetToPosition(end_offset)
    let suffix = get(current_completion.completion, 'suffix', {})
    let suffix_text = get(suffix, 'text', '')

    let text = current_completion.completion.text . suffix_text
    if empty(text)
      return default
    endif

    let s:completion_text = text

    let insert_text = "\<C-R>\<C-O>=neopilot#CompletionText()\<CR>"
    let move_to_start = s:GetMoveToPositionCommand(start_row, start_col)

    let delete_text = move_to_start . s:GetDeleteCommand(start_row, start_col, end_row, end_col)

    call neopilot#server#Request('AcceptCompletion', {'metadata': neopilot#server#RequestMetadata(), "completion_id": current_completion.completion.completionId})
    return delete_text . insert_text
  endif

  return default
endfunction

function! s:HandleCompletionsResult(out, status) abort
  if exists('b:_neopilot_completions')
    let response_text = join(a:out, '')
    try
      let response = json_decode(response_text)
      let completionItems = get(response, 'completionItems', [])

      let b:_neopilot_completions.items = completionItems
      let b:_neopilot_completions.index = 0

      call s:RenderCurrentCompletion()
    catch
      call neopilot#log#Error("Invalid response from language server")
      call neopilot#log#Exception()
    endtry
  endif
endfunction

function! s:GetCurrentCompletionItem() abort
  if exists('b:_neopilot_completions') &&
        \ has_key(b:_neopilot_completions, 'items') && 
        \ has_key(b:_neopilot_completions, 'index') && 
        \ b:_neopilot_completions.index < len(b:_neopilot_completions.items)
    return get(b:_neopilot_completions.items, b:_neopilot_completions.index)
  endif

  return v:null
endfunction

function! s:GetDeleteCommand(start_row, start_col, end_row, end_col) abort
  if a:start_row == a:end_row
    if a:end_col > a:start_col
      return "\<C-O>d" . (a:end_col - a:start_col) . "l"
    endif
    return ""
  else
    " Delete last line, then intermediate lines.
    return "\<C-O>d0" . s:GetMoveToPositionCommand(a:start_row, a:start_col) . repeat("\<C-O>DJ", a:end_row - a:start_row) . "\<C-O>dl"
  endif
endfunction

function! s:GetMoveToPositionCommand(row, col) abort
  return "\<C-O>:call cursor(" . a:row . "," . a:col . ")\<CR>"
endfunction
  if has('nvim')
    let namespace = nvim_create_namespace('neopilot')
    for id in s:nvim_extmark_ids
      call nvim_buf_del_extmark(0, namespace, id)
    endfor
    let s:nvim_extmark_ids = []
  else
    call prop_remove({'type': s:hlgroup, 'all': v:true})
    call prop_remove({'type': s:annot_hlgroup, 'all': v:true})
  endif
endfunction

function! s:RenderCurrentCompletion() abort
  call s:ClearCompletion()

  if mode() !~# '^[iR]' || (v:false && pumvisible())
    return ''
  endif
  let current_completion = s:GetCurrentCompletionItem()
  if current_completion is v:null
    return ''
  endif

  let start_offset = get(current_completion.range, 'startOffset', 0)
  let [start_row, start_col] = neopilot#util#OffsetToPosition(start_offset)
  if start_row != line('.')
    call neopilot#log#Info("Ignoring completion, line number is not the current line.")
    return ''
  endif

  let parts = get(current_completion, 'completionParts', [])

  let idx = 0
  for part in parts
    let [row, col] = neopilot#util#OffsetToPosition(part.offset)
    let text = part.text

    if part.type == 'COMPLETION_PART_TYPE_INLINE' && idx == 0
      " For first inline completion, strip any characters the user has typed
      " that match the start of the completion.
      let cursor_col = col('.')
      let typed = strpart(getline('.'), col - 1, cursor_col - 1)
      if strpart(text, 0, len(typed)) != typed
        call s:ClearCompletion()
        return ''
      endif
      let text = strpart(text, len(typed))
      let col += len(typed)
    endif

    if has('nvim')
      let data = {'id': idx + 1, 'hl_mode': 'combine', 'virt_text_win_col': virtcol('.') - 1}
      if part.type == 'COMPLETION_PART_TYPE_INLINE'
        let data.virt_text = [[text, s:hlgroup]]
      elseif part.type == 'COMPLETION_PART_TYPE_BLOCK'
        let lines = split(text, "\n", 1)
        if empty(lines[-1])
          call remove(lines, -1)
        endif
        let data.virt_lines = map(lines, { _, l -> [[l, s:hlgroup]] })
      else
        continue
      endif

      call add(s:nvim_extmark_ids, data.id)
      call nvim_buf_set_extmark(0, nvim_create_namespace('neopilot'), row - 1, col - 1, data)
    else
      if part.type == 'COMPLETION_PART_TYPE_INLINE'
        call prop_add(row, col, {'type': s:hlgroup, 'text': text})
      elseif part.type == 'COMPLETION_PART_TYPE_BLOCK'
        let text = split(part.text, "\n", 1)
        if empty(text[-1])
          call remove(text, -1)
        endif

        for line in text
          call prop_add(row, 0, {'type': s:hlgroup, 'text_align': 'below', 'text': line})
        endfor
      endif
    endif

    let idx = idx + 1
  endfor
endfunction

" Clear current completions and cancel any pending requests
function! neopilot#Clear(...) abort 
  if exists('g:_neopilot_timer')
    call timer_stop(remove(g:, '_neopilot_timer'))
  endif

  " Cancel any existing request.
  if exists('b:_neopilot_completions')
    let request_id = get(b:_neopilot_completions, 'request_id', 0)
    if request_id > 0
      try
        call neopilot#server#Request('CancelRequest', {'request_id': request_id})
      catch
        call neopilot#log#Exception()
      endtry
    endif
    call s:RenderCurrentCompletion()
    unlet! b:_neopilot_completions
  endif

  if a:0 == 0
    call s:RenderCurrentCompletion()
  endif
  return ''
endfunction

function! neopilot#CycleCompletions(n) abort
  if s:GetCurrentCompletionItem() is v:null
    return
  endif

  let b:_neopilot_completions.index += a:n
  let n_items = len(b:_neopilot_completions.items)

  if b:_neopilot_completions.index < 0
    let b:_neopilot_completions.index += n_items
  endif

  let b:_neopilot_completions.index %= n_items

  call s:RenderCurrentCompletion()
endfunction

" Request completions from the language server
function! neopilot#Complete(...) abort
  if a:0 == 2
    let bufnr = a:1
    let timer = a:2

    if timer isnot# get(g:, '_neopilot_timer', -1) 
      return
    endif

    call remove(g:, '_neopilot_timer')

    if mode() !=# 'i' || bufnr !=# bufnr('')
      return
    endif
  endif

  if exists('g:_neopilot_timer')
    call timer_stop(remove(g:, '_neopilot_timer'))
  endif

  if !neopilot#Enabled()
    return
  endif

  let data = {
        \ "metadata": neopilot#server#RequestMetadata(),
        \ "document": neopilot#doc#GetCurrentDocument(),
        \ "editor_options": neopilot#doc#GetEditorOptions(),
        \ "api_server_params": {
        \   "api_timeout_ms": s:API_TIMEOUT_MS,
        \   "first_temperature": s:FIRST_TEMPERATURE,
        \   "max_completions": s:MAX_COMPLETIONS,
        \   "max_newlines": s:MAX_NEWLINES,
        \   "max_tokens": s:MAX_TOKENS,
        \   "min_log_probability": s:MIN_LOG_PROBABILITY,
        \   "temperature": s:TEMPERATURE,
        \   "top_k": s:TOP_K,
        \   "top_p": s:TOP_P
        \ }
        \ }
    
  if exists('b:_neopilot_completions.request_data') && b:_neopilot_completions.request_data ==# data
    return
  endif

  " Add request id after we check for identical data.
  let request_data = deepcopy(data)

  let s:request_nonce += 1
  let request_id = s:request_nonce
  let data.metadata.request_id = request_id

  try
    let request_job = neopilot#server#Request('GetCompletions', data, function('s:HandleCompletionsResult', []))

    let b:_neopilot_completions = {
          \ "request_data": request_data,
          \ "request_id": request_id,
          \ "job": request_job
          \ }
  catch
    call neopilot#log#Exception()
  endtry
endfunction

function! neopilot#DebouncedComplete(...) abort
  call neopilot#Clear(v:false)
  let current_buf = bufnr('')
  let delay = get(g:, 'neopilot_idle_delay', s:DEFAULT_IDLE_DELAY)
  let g:_neopilot_timer = timer_start(delay, function('neopilot#Complete', [current_buf]))
endfunction
