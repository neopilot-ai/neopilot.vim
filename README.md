# Neopilot.vim

AI-powered code completion for Vim/Neovim, inspired by GitHub Copilot.

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

## Commands

- `:Neopilot Auth` - Authenticate with Neopilot
- `:Neopilot Chat` - Open interactive chat window
- `:Neopilot Enable` - Enable completions
- `:Neopilot Disable` - Disable completions
- `:Neopilot EnableBuffer` - Enable for current buffer only
- `:Neopilot DisableBuffer` - Disable for current buffer only

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

### Check server status:
The language server binary is downloaded to `~/.config/neopilot/bin/`

### Common issues:
- **No completions**: Ensure you're authenticated (`:Neopilot Auth`)
- **Slow completions**: Adjust `g:neopilot_idle_delay`
- **Permission errors**: Check write access to `~/.config/neopilot/`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Use conventional commits for your messages
5. Submit a pull request

## License

See LICENSE file for details.