" Neopilot autoload - Hybrid Vimscript + Lua
" Copybara import generated

" Load legacy Vimscript functions
execute 'source ' . expand('<sfile>:h') . '/neopilot/legacy.vim'

" Try to load Lua modules if available
if has('nvim') && exists('*luaeval')
  try
    lua require('neopilot').setup()
  catch
    " Fall back to legacy if Lua fails
  endtry
endif

" Main autoload functions can be migrated to Lua gradually
" For now, all functionality is in legacy.vim