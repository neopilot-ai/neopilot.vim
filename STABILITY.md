# Neopilot Stability Contract

## Overview

This document outlines the stability guarantees for Neopilot v1.0-beta and beyond. It defines what APIs, behaviors, and interfaces are considered stable and what may change.

## Stability Levels

### 🔒 **Stable (Breaking Changes Require Major Version)**
- Public APIs marked as stable
- Core functionality and behavior
- Configuration options documented in README
- Command interfaces (`:Neopilot*`)
- Key mappings and user-facing behavior

### ⚠️ **Beta (May Change with Minor Versions)**
- New features in v1.0-beta
- Advanced configuration options
- Internal module APIs
- Performance characteristics
- Error messages and diagnostics

### 🔧 **Internal (May Change Anytime)**
- Undocumented functions and variables
- Internal data structures
- Implementation details
- Debug logging formats
- Test utilities

## Stable APIs

### Commands
All `:Neopilot*` commands are stable:
- `:Neopilot` - Main command interface
- `:Neopilot Auth` - Authentication
- `:Neopilot Chat` - Chat interface
- `:Neopilot Enable/Disable` - Global enable/disable
- `:Neopilot EnableBuffer/DisableBuffer` - Buffer-specific control
- `:Neopilot Health` - Health diagnostics
- `:Neopilot Test` - Test suite
- `:Neopilot Stats` - Performance statistics

### Configuration Variables
```vim
" Stable configuration (documented in README)
let g:neopilot_enabled = v:true
let g:neopilot_filetypes = {'python': v:true, 'javascript': v:true}
let g:neopilot_idle_delay = 75
let g:neopilot_log_level = 'WARN'
let g:neopilot_tab_fallback = "\<C-N>"
```

### Key Mappings
```vim
" Stable key mappings
imap <Tab> " Accept completion
imap <M-]> " Next completion
imap <M-[> " Previous completion
imap <M-\> " Force completion
imap <C-]> " Dismiss completion
```

### Completion Behavior
- Tab accepts current completion
- Automatic completion triggers on idle
- Multi-line completion support
- Cycling through multiple suggestions

## Beta Features

### Advanced Configuration
```vim
" Beta configuration (may change)
let g:neopilot_cache_ttl = 30000
let g:neopilot_min_request_interval = 50
let g:neopilot_max_cache_size = 50
let g:neopilot_context_max_tokens = 2048
let g:neopilot_context_max_lines_before = 50
let g:neopilot_context_max_lines_after = 10
let g:neopilot_context_semantic_depth = 3
```

### Observability Features
- `:NeopilotStats` output format
- Health check details
- Performance metrics

### nvim-cmp Integration
- cmp source interface
- Integration behavior

## Internal APIs

### Lua Modules
All `lua/neopilot/*.lua` modules are internal:
- Function signatures may change
- Data structures may change
- Implementation details may change

### Exceptions
The following are explicitly **not stable**:
- Direct calls to Lua module functions
- Internal data structures
- Debug logging formats
- Test utilities
- Implementation-specific behavior

## Breaking Changes

### When Breaking Changes Are Allowed
- Major version bumps (v2.0, v3.0, etc.)
- Explicit deprecation warnings in minor versions
- Security fixes (may break compatibility)

### Deprecation Policy
1. New minor version introduces deprecation warning
2. Feature remains functional but logs warnings
3. Next major version removes deprecated feature

## Compatibility Guarantees

### Neovim Versions
- Neovim 0.6+ (Lua support required for advanced features)
- Vim 9.0.0185+ (limited functionality)

### Operating Systems
- Linux, macOS, Windows (WSL)
- Server binary compatibility

### Languages
- All languages supported by the language server
- Context engine adapts to supported languages

## Migration Guide

### From v0.x to v1.0
- No breaking changes for basic usage
- Advanced features require Neovim + Lua
- Some configuration variables renamed (see README)

### Future Versions
- Monitor deprecation warnings
- Test upgrades on non-production systems
- Report issues with migration

## Support

### Stable Features
- Full support for documented stable APIs
- Bug fixes and security updates
- Backward compatibility within major versions

### Beta Features
- Best-effort support
- May change without notice
- Use at your own risk

### Internal APIs
- No support guaranteed
- May break without warning
- For development use only

## Contributing

### For Contributors
- Internal APIs may change during development
- Use stable APIs for external integrations
- Document new stable APIs clearly

### For Maintainers
- Clearly mark stability level of new features
- Update this contract when adding stable APIs
- Deprecate with warnings before breaking changes

---

## Version History

- **v1.0-beta**: Initial stability contract
- Defines stable command interface and basic configuration
- Advanced features marked as beta

---

*This stability contract is a living document and will be updated with each major release.*