if exists('g:loaded_neopilot_log')
  finish
endif
let g:loaded_neopilot_log = 1

if !exists('s:logfile')
  let s:logfile = expand(get(g:, 'neopilot_log_file', tempname() . '-neopilot.log'))
  try
    call writefile([], s:logfile)
  catch
  endtry
endif

function! neopilot#log#Logfile() abort
  return s:logfile
endfunction

function! neopilot#log#Log(level, msg) abort
  let min_level = toupper(get(g:, 'neopilot_log_level', 'WARN'))
  " echo "logging to: " . s:logfile . "," . min_level . "," . a:level . "," a:msg
  for level in ['ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE']
    if level == toupper(a:level)
      try
        if filewritable(s:logfile)
          call writefile(split(a:msg, "\n", 1), s:logfile, 'a')
        endif
      catch
      endtry
    endif
    if level == min_level
      break
    endif
  endfor
endfunction

function! neopilot#log#Error(msg) abort
  call neopilot#log#Log('ERROR', a:msg)
endfunction

function! neopilot#log#Warn(msg) abort
  call neopilot#log#Log('WARN', a:msg)
endfunction

function! neopilot#log#Info(msg) abort
  call neopilot#log#Log('INFO', a:msg)
endfunction

function! neopilot#log#Debug(msg) abort
  call neopilot#log#Log('DEBUG', a:msg)
endfunction

function! neopilot#log#Trace(msg) abort
  call neopilot#log#Log('TRACE', a:msg)
endfunction

function! neopilot#log#Exception() abort
  if !empty(v:exception)
    call neopilot#log#Error('Exception: ' . v:exception . ' [' . v:throwpoint . ']')
  endif
endfunction
