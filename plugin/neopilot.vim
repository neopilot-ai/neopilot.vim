" Copybara import generated
if exists("g:loaded_neopilot")
  finish
endif
let g:loaded_neopilot = 1

" Use Lua command if available, fallback to Vimscript
if has('nvim') && exists('*luaeval')
  command! -nargs=? Neopilot lua require('neopilot.command').command(<q-args>)
  command! NeopilotHealth lua require('neopilot.health').check()
  command! NeopilotTest lua require('neopilot.test').run_all()
else
  command! -nargs=? -complete=customlist,neopilot#command#Complete Neopilot exe neopilot#command#Command(<q-args>)
  command! NeopilotHealth echo "Health check requires Neovim with Lua support"
  command! NeopilotTest echo "Testing requires Neovim with Lua support"
endif

if !neopilot#util#HasSupportedVersion()
    finish
endif

function! s:SetStyle() abort
  if &t_Co == 256
    hi def NeopilotSuggestion guifg=#808080 ctermfg=244
  else
    hi def NeopilotSuggestion guifg=#808080 ctermfg=8
  endif
  hi def link NeopilotAnnotation Normal
endfunction

function! s:MapTab() abort
  if has('nvim') && exists('*luaeval')
    imap <script><silent><nowait><expr> <Tab> luaeval('require("neopilot.core").accept_completion()')
  else
    imap <script><silent><nowait><expr> <Tab> neopilot#Accept()
  endif
endfunction

augroup neopilot
  autocmd!
  if has('nvim') && exists('*luaeval')
    autocmd InsertEnter,CursorMovedI,CompleteChanged * lua require('neopilot.core').debounced_complete()
    autocmd BufEnter     * if mode() =~# '^[iR]'|lua require('neopilot.core').debounced_complete()|endif
    autocmd InsertLeave  * lua require('neopilot.core').clear()
    autocmd BufLeave     * if mode() =~# '^[iR]'|lua require('neopilot.core').clear()|endif
  else
    autocmd InsertEnter,CursorMovedI,CompleteChanged * call neopilot#DebouncedComplete()
    autocmd BufEnter     * if mode() =~# '^[iR]'|call neopilot#DebouncedComplete()|endif
    autocmd InsertLeave  * call neopilot#Clear()
    autocmd BufLeave     * if mode() =~# '^[iR]'|call neopilot#Clear()|endif
  endif

  autocmd ColorScheme,VimEnter * call s:SetStyle()
  " Map tab using vim enter so it occurs after all other sourcing.
  autocmd VimEnter             * call s:MapTab()
augroup END

" Key mappings - use Lua if available
if has('nvim') && exists('*luaeval')
  imap <Plug>(neopilot-dismiss)     <Cmd>lua require('neopilot.core').clear()<CR>
  imap <Plug>(neopilot-next)        <Cmd>lua require('neopilot.core').cycle_completions(1)<CR>
  imap <Plug>(neopilot-previous)    <Cmd>lua require('neopilot.core').cycle_completions(-1)<CR>
  imap <Plug>(neopilot-complete)    <Cmd>lua require('neopilot.core').request_completions()<CR>
else
  imap <Plug>(neopilot-dismiss)     <Cmd>call neopilot#Clear()<CR>
  imap <Plug>(neopilot-next)        <Cmd>call neopilot#CycleCompletions(1)<CR>
  imap <Plug>(neopilot-previous)    <Cmd>call neopilot#CycleCompletions(-1)<CR>
  imap <Plug>(neopilot-complete)    <Cmd>call neopilot#Complete<CR>
endif

if empty(mapcheck('<C-]>', 'i'))
  imap <silent><script><nowait><expr> <C-]> neopilot#Clear() . "\<C-]>"
endif
if empty(mapcheck('<M-]>', 'i'))
  imap <M-]> <Plug>(neopilot-next)
endif
if empty(mapcheck('<M-[>', 'i'))
  imap <M-[> <Plug>(neopilot-previous)
endif
if empty(mapcheck('<M-Bslash>', 'i'))
  imap <M-Bslash> <Plug>(neopilot-complete)
endif

call s:SetStyle()

" Start server - use Lua if available
if has('nvim') && exists('*luaeval')
  lua require('neopilot.server').start()
else
  call neopilot#server#Start()
endif

let s:dir = expand('<sfile>:h:h')
if getftime(s:dir . '/doc/neopilot.txt') > getftime(s:dir . '/doc/tags')
  silent! execute 'helptags' fnameescape(s:dir . '/doc')
endif
