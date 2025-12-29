if exists("b:current_syntax")
  finish
endif

" Define syntax highlighting for Neopilot Chat
syn match neopilotChatPrompt /^You: /
syn match neopilotChatResponse /^Assistant: /
syn match neopilotChatHeader /^Neopilot Chat$/
syn match neopilotChatSeparator /^=\+$/

" Highlight groups
hi def link neopilotChatPrompt Identifier
hi def link neopilotChatResponse Type
hi def link neopilotChatHeader Title
hi def link neopilotChatSeparator Comment

let b:current_syntax = "neopilot-chat"