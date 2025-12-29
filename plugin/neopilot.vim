" Copybara import generated
if exists("g:loaded_neopilot")
  finish
endif
let g:loaded_neopilot = 1

command! -nargs=? -complete=customlist,neopilot#command#Complete Neopilot exe neopilot#command#Command(<q-args>)

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
  imap <script><silent><nowait><expr> <Tab> neopilot#Accept()
endfunction

augroup neopilot
  autocmd!
  autocmd InsertEnter,CursorMovedI,CompleteChanged * call neopilot#DebouncedComplete()
  autocmd BufEnter     * if mode() =~# '^[iR]'|call neopilot#DebouncedComplete()|endif
  autocmd InsertLeave  * call neopilot#Clear()
  autocmd BufLeave     * if mode() =~# '^[iR]'|call neopilot#Clear()|endif

  autocmd ColorScheme,VimEnter * call s:SetStyle()
  " Map tab using vim enter so it occurs after all other sourcing.
  autocmd VimEnter             * call s:MapTab()
augroup END

imap <Plug>(neopilot-dismiss)     <Cmd>call neopilot#Clear()<CR>
if empty(mapcheck('<C-]>', 'i'))
  imap <silent><script><nowait><expr> <C-]> neopilot#Clear() . "\<C-]>"
endif
imap <Plug>(neopilot-next)     <Cmd>call neopilot#CycleCompletions(1)<CR>
imap <Plug>(neopilot-previous) <Cmd>call neopilot#CycleCompletions(-1)<CR>
imap <Plug>(neopilot-complete)  <Cmd>call neopilot#Complete<CR>
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
call neopilot#server#Start()

let s:dir = expand('<sfile>:h:h')
if getftime(s:dir . '/doc/neopilot.txt') > getftime(s:dir . '/doc/tags')
  silent! execute 'helptags' fnameescape(s:dir . '/doc')
endif
