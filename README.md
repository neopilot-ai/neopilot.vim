<!-- Copybara import generated -->
# Neopilot.vim

AI-powered code completion for Vim/Neovim, inspired by GitHub Copilot.

## Status

**🚀 v1.0-beta** - Production ready with enterprise-grade reliability and intelligence.

See [STABILITY.md](STABILITY.md) for stability guarantees and API contracts.

## Installation

### Using vim-plug
```vim
Plug 'neopilot-ai/neopilot.vim'
```

### Using Vundle
```vim
Plugin 'neopilot-ai/neopilot.vim'
```

### Manual Installation
```bash
git clone https://github.com/neopilot-ai/neopilot.vim.git ~/.vim/pack/plugins/start/neopilot.vim
# or for Neovim:
git clone https://github.com/neopilot-ai/neopilot.vim.git ~/.local/share/nvim/site/pack/plugins/start/neopilot.vim
```

## Setup

1. **Authenticate**: Run `:Neopilot Auth` to login to Neopilot
2. **Start coding**: Completions will appear automatically as you type

## Features

- **AI-powered completions**: Get intelligent code suggestions
- **Multi-line support**: Completions can span multiple lines
- **Interactive chat**: Use `:Neopilot Chat` for AI assistance
- **Language support**: Works with many programming languages
- **Vim/Neovim compatible**: Supports both Vim 9+ and Neovim 0.6+
- **Performance optimized**: Intelligent caching and request deduplication
- **nvim-cmp integration**: Enhanced completion UX with nvim-cmp
- **Comprehensive diagnostics**: Built-in health checks and testing
- **Context-aware suggestions**: Smarter completions based on semantic context
- **Advanced observability**: Performance metrics and usage statistics
- **Streaming-ready architecture**: Future-ready for token streaming

## nvim-cmp Integration

For enhanced completion experience in Neovim, integrate with nvim-cmp:

```lua
require('cmp').setup({
  sources = {
    { name = 'neopilot' },
    -- other sources...
  }
})
```

This provides:
- Better completion UI
- Integration with other completion sources
- Enhanced trigger characters
- Rich completion documentation

## Intelligent Context Engine

Neopilot uses advanced context extraction to provide more accurate completions:

- **Treesitter Integration**: Semantic-aware context when available
- **Token Budgeting**: Intelligent truncation to stay within model limits
- **Scope Awareness**: Understands functions, classes, and code structure
- **Multi-language Support**: Language-specific patterns and parsing

The context engine automatically adapts based on your Neovim setup and language.

## Commands

- `:Neopilot Auth` - Authenticate with Neopilot
- `:Neopilot Chat` - Open interactive chat window
- `:Neopilot Enable` - Enable completions
- `:Neopilot Disable` - Disable completions
- `:Neopilot EnableBuffer` - Enable for current buffer only
- `:Neopilot DisableBuffer` - Disable for current buffer only
- `:Neopilot Health` - Run comprehensive health check (Neovim + Lua only)
- `:Neopilot Test` - Run test suite (Neovim + Lua only)
- `:Neopilot Stats` - Show performance and usage statistics (Neovim + Lua only)

## Key Mappings

### Default Mappings
- `<Tab>` - Accept completion
- `<M-]>` - Next completion
- `<M-[>` - Previous completion
- `<M-\>` - Force completion
- `<C-]>` - Dismiss completion

### Custom Mappings
```vim
" Custom completion acceptance
imap <C-J> <Plug>(neopilot-complete)

" Custom cycling
imap <C-N> <Plug>(neopilot-next)
imap <C-P> <Plug>(neopilot-previous)

" Custom dismissal
imap <C-C> <Plug>(neopilot-dismiss)
```

## Configuration

```vim
" Global enable/disable
let g:neopilot_enabled = v:true

" Filetype-specific settings
let g:neopilot_filetypes = {
      \ 'python': v:true,
      \ 'javascript': v:true,
      \ 'help': v:false
      \ }

" Completion delay (milliseconds)
let g:neopilot_idle_delay = 75

" Logging level
let g:neopilot_log_level = 'WARN'

" Tab fallback behavior
let g:neopilot_tab_fallback = "\<C-N>"

" Performance tuning (Neovim + Lua only)
let g:neopilot_cache_ttl = 30000  " Cache TTL in milliseconds
let g:neopilot_min_request_interval = 50  " Minimum time between requests
let g:neopilot_max_cache_size = 50  " Maximum cached completions

" Context engine configuration (Neovim + Lua only)
let g:neopilot_context_max_tokens = 2048  " Token budget for context
let g:neopilot_context_max_lines_before = 50  " Lines to look back
let g:neopilot_context_max_lines_after = 10  " Lines to look forward
let g:neopilot_context_semantic_depth = 3  " Scope depth for semantic analysis

" Server configuration
let g:neopilot_server_path = ''  " Custom server binary path
let g:neopilot_log_dir = ''  " Custom log directory
```

## Version Tagging

This repository uses automated version tagging via GitHub Actions:

### Manual Version Tagging
Go to the "Actions" tab, select "Version Tag" workflow, and click "Run workflow". Choose:
- **Version type**: patch, minor, major, or prerelease
- **Custom version**: Optional specific version number
- **Create release**: Whether to create a GitHub release

### Automatic Version Tagging
The repository automatically creates version tags based on conventional commits:
- `feat:` → minor version bump
- `fix:` → patch version bump
- `feat!:` or `fix!:` → major version bump (breaking changes)

### Conventional Commit Examples
```bash
git commit -m "feat: add chat functionality"
git commit -m "fix: resolve completion timeout issue"
git commit -m "feat!: change API breaking backward compatibility"
```

## Requirements

- **Vim**: 9.0.0185+ with text properties
- **Neovim**: 0.6.0+ with virtual text support
- **curl**: For API communication
- **git**: For version control

## Troubleshooting

### Enable logging for debugging:
```vim
let g:neopilot_log_level = 'DEBUG'
let g:neopilot_log_file = '/tmp/neopilot.log'
```

### Run diagnostics (Neovim + Lua only):
```vim
:NeopilotHealth  " Comprehensive health check
:NeopilotTest    " Run test suite
:NeopilotStats   " Show performance metrics
```

### Check server status:
The language server binary is downloaded to `~/.config/neopilot/bin/`

### Performance tuning:
- **Slow completions**: Increase `g:neopilot_idle_delay` or `g:neopilot_min_request_interval`
- **Memory usage**: Decrease `g:neopilot_max_cache_size`
- **Cache issues**: Adjust `g:neopilot_cache_ttl`
- **Context too large**: Reduce `g:neopilot_context_max_tokens` or line limits

### Common issues:
- **No completions**: Ensure you're authenticated (`:Neopilot Auth`)
- **Permission errors**: Check write access to `~/.config/neopilot/`
- **Lua errors**: Run `:NeopilotHealth` to check Lua module loading
- **Poor completion quality**: Check `:NeopilotStats` for cache hit rates

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Use conventional commits for your messages
5. Submit a pull request

## Stability & Compatibility

Neopilot follows semantic versioning with clear stability guarantees:

- **Stable APIs**: Commands, basic configuration, core functionality
- **Beta Features**: Advanced configuration, observability, integrations
- **Internal**: Implementation details, may change anytime

See [STABILITY.md](STABILITY.md) for detailed stability contracts and compatibility guarantees.

## License

See LICENSE file for details.