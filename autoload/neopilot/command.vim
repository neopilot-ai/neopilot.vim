function! neopilot#command#BrowserCommand() abort
  if has('win32') && executable('rundll32')
    return 'rundll32 url.dll,FileProtocolHandler'
  elseif isdirectory('/private') && executable('/usr/bin/open')
    return '/usr/bin/open'
  elseif executable('xdg-open')
    return 'xdg-open'
  else
    return ''
  endif
endfunction

function! s:Uuid() abort
  if has('win32')
    return system('powershell -Command "[guid]::NewGuid()"')
  elseif executable('uuidgen')
    return system('uuidgen')
  endif

  throw "Could not generate uuid. Please make sure uuidgen is installed."
endfunction

function! s:ConfigDir() abort
  let config_dir = $XDG_CONFIG_HOME
  if empty(config_dir)
    let config_dir = $HOME . '/.config'
  endif
  return config_dir . '/neopilot'
endfunction

function! s:LoadConfig() abort
  let config_path = s:ConfigDir() . '/config.json'
  if filereadable(config_path)
    let contents = join(readfile(config_path), '')
    if !empty(contents)
      return json_decode(contents)
    endif
  endif

  return {}
endfunction

let s:api_key = get(s:LoadConfig(), 'apiKey', '')

let s:commands = {}

function! s:commands.Auth(...) abort
  if !neopilot#util#HasSupportedVersion()
    if has('nvim')
      let min_version = 'NeoVim 0.6'
    else
      let min_version = 'Vim 9.0.0185'
    endif
    echo "This version of Vim is unsupported. Install " . min_version . " or greater to use Neopilot."
    return
  endif

  let uuid = trim(s:Uuid())
  let url = 'http://127.0.0.1/profile?response_type=token&redirect_uri=show-auth-token&state=' . uuid . '&scope=openid%20profile%20email&redirect_parameters_type=query'
  let browser = neopilot#command#BrowserCommand()
  let opened_browser = v:false
  if !empty(browser)
    echo "Press ENTER to login to Neopilot in your browser."

    let c = getchar()
    while c isnot# 13 && c isnot# 10 && c isnot# 0
      let c = getchar()
    endwhile

    echo "Navigating to " . url
    try
      call system(browser . ' ' . "'" . url . "'")
      if v:shell_error is# 0
        let opened_browser = v:true
      endif
    catch
    endtry

    if !opened_browser
      echo "Failed to open browser. Please go to the link above."
    endif
  else
    echo "No available browser found. Please go to " . url
  endif

  let api_key = ''
  let auth_token = input('Paste your token here: ')
  let tries = 0

  while empty(api_key) && tries < 3
    let command = 'curl -s https://api.neopilot.com/register_user/ ' .
          \ '--header "Content-Type: application/json" ' .
          \ '--data ' . "'" . json_encode({'firebase_id_token': auth_token}) . "'"
    let response = system(command)
    let res = json_decode(response)
    let api_key = get(res, 'api_key', '')
    if empty(api_key)
      let auth_token = input('Invalid token, please try again: ')
    endif
    let tries = tries + 1
  endwhile

  if !empty(api_key)
    let s:api_key = api_key
    let config_dir = s:ConfigDir()
    let config_path = config_dir . '/config.json'
    let config = s:LoadConfig()
    let config.apiKey = api_key

    try
      if !filereadable(config_path)
        call mkdir(config_dir, "p")
      endif

      call writefile([json_encode(config)], config_path)
    catch
      call neopilot#log#Error("Could not persist api key to config.json")
    endtry
  endif
endfunction

function! s:commands.Disable(...) abort
  let g:neopilot_enabled = 0
endfunction

function! s:commands.DisableBuffer(...) abort
  let b:neopilot_enabled = 0
endfunction

function! s:commands.Enable(...) abort
  let g:neopilot_enabled = 1
endfunction

function! s:commands.EnableBuffer(...) abort
  let b:neopilot_enabled = 1
endfunction

function! s:commands.Chat(...) abort
  " Open a new buffer for chat interaction
  let chat_bufname = 'Neopilot Chat'
  
  " Check if chat buffer already exists
  let chat_bufnr = bufnr(chat_bufname)
  if chat_bufnr == -1
    " Create new buffer
    execute 'new ' . chat_bufname
    let chat_bufnr = bufnr(chat_bufname)
    
    " Set buffer options
    call setbufvar(chat_bufnr, '&buftype', 'nofile')
    call setbufvar(chat_bufnr, '&bufhidden', 'hide')
    call setbufvar(chat_bufnr, '&swapfile', 0)
    call setbufvar(chat_bufnr, '&filetype', 'neopilot-chat')
    
    " Add initial content
    call setbufline(chat_bufnr, 1, [
          \ 'Neopilot Chat',
          \ '============',
          \ '',
          \ 'Welcome to Neopilot Chat! Ask me anything about coding.',
          \ '',
          \ 'You: '
          \ ])
    
    " Set up mappings for the chat buffer
    call s:SetupChatMappings(chat_bufnr)
  else
    " Switch to existing buffer
    execute 'buffer ' . chat_bufnr
  endif
  
  " Move cursor to the end for input
  call cursor(line('$'), col('$'))
  startinsert!
endfunction

function! s:SetupChatMappings(bufnr) abort
  " Set up buffer-local mappings
  execute 'augroup NeopilotChat' . a:bufnr
  execute 'autocmd!'
  execute 'autocmd BufEnter <buffer=' . a:bufnr . '> call s:SetupChatBufferMappings()'
  execute 'autocmd BufLeave <buffer=' . a:bufnr . '> call s:CleanupChatBufferMappings()'
  execute 'augroup END'
endfunction

function! s:SetupChatBufferMappings() abort
  " Map Enter to send message in insert mode
  inoremap <buffer> <CR> <Esc>:call <SID>SendChatMessage()<CR>
  
  " Map Ctrl+C to cancel in insert mode
  inoremap <buffer> <C-C> <Esc>
  
  " Prevent accidental buffer modifications
  nnoremap <buffer> <CR> <NOP>
endfunction

function! s:CleanupChatBufferMappings() abort
  " Clean up mappings when leaving the buffer
  iunmap <buffer> <CR>
  iunmap <buffer> <C-C>
  nunmap <buffer> <CR>
endfunction
  " Get the current line
  let line = getline('.')
  
  " Check if it's a user input line (starts with "You: ")
  if line =~# '^You: '
    let message = substitute(line, '^You: ', '', '')
    
    if !empty(trim(message))
      " Replace the current line with the full message
      call setline('.', 'You: ' . message)
      
      " Add assistant response placeholder
      call append(line('$'), 'Assistant: Thinking...')
      
      " Move to the thinking line
      call cursor(line('$'), 1)
      redraw
      
      " TODO: Send actual chat request to server
      " For now, provide a simple response
      let response = s:GetChatResponse(message)
      
      " Replace the thinking line with actual response
      call setline(line('$'), 'Assistant: ' . response)
      
      " Add new input line
      call append(line('$'), '')
      call append(line('$'), 'You: ')
      
      " Move to new input line
      call cursor(line('$'), col('$'))
      startinsert!
    endif
  endif
endfunction

function! s:GetChatResponse(message) abort
  " Placeholder chat responses - in a real implementation, this would call the AI API
  let responses = [
        \ "That's an interesting question! I'm still learning how to provide detailed responses.",
        \ "I understand you're asking about: " . a:message . ". This is a placeholder response.",
        \ "Thanks for your message! Chat functionality is coming soon with full AI integration.",
        \ "I'm here to help with coding questions. What specific programming topic can I assist you with?",
        \ "Your message has been received. In the future, I'll be able to provide intelligent responses to coding questions."
        \ ]
  
  " Simple hash-based response selection for some variety
  let hash = 0
  for char in split(a:message, '\zs')
    let hash += char2nr(char)
  endfor
  
  return responses[hash % len(responses)]
endfunction

function! neopilot#command#ApiKey() abort
  return s:api_key
endfunction

function! neopilot#command#Complete(arg, lead, pos) abort
  let args = matchstr(strpart(a:lead, 0, a:pos), 'C\%[odeium][! ] *\zs.*')
  return sort(filter(keys(s:commands), { k -> strpart(k, 0, len(a:arg)) ==# a:arg }))
endfunction

function! neopilot#command#Command(arg) abort
  let cmd = matchstr(a:arg, '^\%(\\.\|\S\)\+')
  let arg = matchstr(a:arg, '\s\zs\S.*')
  
  if !has_key(s:commands, cmd)
    call neopilot#log#Error("Unknown command: " . cmd)
    return 'echoerr ' . string("Neopilot: command '" . string(cmd) . "' not found")
  endif
  
  try
    let res = s:commands[cmd](arg)
    if type(res) == v:t_string
      return res
    else
      return ''
    endif
  catch
    call neopilot#log#Exception()
    return 'echoerr ' . string("Neopilot: error executing command '" . string(cmd) . "'")
  endtry
endfunction
