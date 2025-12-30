-- Enhanced Tree-sitter integration for Neopilot
-- Provides comprehensive semantic context for AI completions
local M = {}

local config = require('neopilot.config')
local log = require('neopilot.log')

-- Language-specific queries for semantic analysis
local queries = {
    python = {
        imports = [[
            (import_statement 
                (dotted_name (identifier) @name)) 
            (from_statement 
                (dotted_name (identifier) @name))
            (import_statement 
                (aliased_import (identifier) @name))
        ]],
        functions = [[
            (function_definition 
                (identifier) @name
                (parameters (identifier)* @params)) @func_def
        ]],
        classes = [[
            (class_definition 
                (identifier) @name
                (argument_list (identifier)* @inheritance)) @class_def
        ]],
        variables = [[
            (assignment 
                (identifier) @name
                (_) @value) @var_def
        ]],
        current_function = [[
            (function_definition) @func
        ]],
        current_class = [[
            (class_definition) @class
        ]]
    },
    javascript = {
        imports = [[
            (import_statement 
                (import_clause (identifier) @name))
            (import_statement 
                (named_imports (import_specifier (identifier) @name)))
            (import_statement 
                (namespace_import (identifier) @name))
        ]],
        functions = [[
            (function_declaration 
                (identifier) @name
                (formal_parameters (identifier)* @params)) @func_def
            (variable_declaration 
                (variable_declarator 
                    (identifier) @name 
                    (arrow_function 
                        (formal_parameters (identifier)* @params)))) @func_def
        ]],
        classes = [[
            (class_declaration 
                (identifier) @name
                (class_heritage (identifier) @inheritance)) @class_def
        ]],
        variables = [[
            (variable_declaration 
                (variable_declarator 
                    (identifier) @name 
                    (_) @value)) @var_def
        ]],
        current_function = [[
            (function_declaration) @func
            (arrow_function) @func
        ]],
        current_class = [[
            (class_declaration) @class
        ]]
    },
    typescript = {
        imports = [[
            (import_statement 
                (import_clause (identifier) @name))
            (import_statement 
                (named_imports (import_specifier (identifier) @name)))
        ]],
        functions = [[
            (function_declaration 
                (identifier) @name
                (formal_parameters (identifier)* @params)) @func_def
        ]],
        classes = [[
            (class_declaration 
                (identifier) @name
                (class_heritage (identifier) @inheritance)) @class_def
        ]],
        interfaces = [[
            (interface_declaration 
                (identifier) @name) @interface_def
        ]],
        current_function = [[
            (function_declaration) @func
            (method_definition) @func
        ]],
        current_class = [[
            (class_declaration) @class
        ]]
    },
    lua = {
        imports = [[
            (call_expression 
                (identifier) @func_name
                (#eq? @func_name "require")
                (arguments (string (string_content) @name)))
        ]],
        functions = [[
            (function_declaration 
                (identifier) @name
                (parameters (identifier)* @params)) @func_def
            (local_function_declaration 
                (identifier) @name
                (parameters (identifier)* @params)) @func_def
            (assignment_statement 
                (variable_list (identifier) @name)
                (expression_list (function_definition (parameters (identifier)* @params)))) @func_def
        ]],
        current_function = [[
            (function_declaration) @func
            (local_function_declaration) @func
        ]]
    },
    go = {
        imports = [[
            (import_spec 
                (package_identifier) @name) @import
        ]],
        functions = [[
            (function_declaration 
                (identifier) @name
                (parameter_list (parameter_declaration (identifier) @params)*)) @func_def
        ]],
        current_function = [[
            (function_declaration) @func
        ]]
    },
    rust = {
        imports = [[
            (use_declaration 
                (use_list (identifier) @name)) @import
        ]],
        functions = [[
            (function_item 
                (identifier) @name
                (parameters (parameter (identifier) @params)*)) @func_def
        ]],
        structs = [[
            (struct_item 
                (type_identifier) @name) @struct_def
        ]],
        current_function = [[
            (function_item) @func
        ]]
    }
}

-- Default query for unsupported languages
local default_queries = {
    imports = [[
        (identifier) @name
    ]],
    functions = [[
        (identifier) @name
    ]]
}

-- Get language-specific queries or fallback to defaults
local function get_queries_for_language(lang)
    return queries[lang] or default_queries
end

-- Check if Tree-sitter is available for the current buffer
local function is_treesitter_available(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    if not vim.treesitter then
        return false
    end
    
    local lang = vim.bo[bufnr].filetype
    if not lang or lang == '' then
        return false
    end
    
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    return ok and parser ~= nil
end

-- Execute a Tree-sitter query and return results
local function execute_query(bufnr, query_str, query_type)
    if not is_treesitter_available(bufnr) then
        return {}
    end
    
    local lang = vim.bo[bufnr].filetype
    local parser = vim.treesitter.get_parser(bufnr, lang)
    if not parser then
        return {}
    end
    
    local tree = parser:parse()[1]
    if not tree then
        return {}
    end
    
    local query = vim.treesitter.query.parse(lang, query_str)
    local results = {}
    
    for id, node in query:iter_captures(tree:root(), bufnr) do
        local capture_name = query.captures[id]
        local text = vim.treesitter.get_node_text(node, bufnr)
        
        table.insert(results, {
            capture = capture_name,
            text = text,
            node = node,
            range = {
                start = { node:start() },
                ["end"] = { node:end_() }
            }
        })
    end
    
    return results
end

-- Get imports in the current buffer
function M.get_imports(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    if not is_treesitter_available(bufnr) then
        return {}
    end
    
    local lang = vim.bo[bufnr].filetype
    local lang_queries = get_queries_for_language(lang)
    
    if not lang_queries.imports then
        return {}
    end
    
    local results = execute_query(bufnr, lang_queries.imports, 'imports')
    local imports = {}
    
    for _, result in ipairs(results) do
        if result.capture == 'name' then
            table.insert(imports, {
                name = result.text,
                range = result.range
            })
        end
    end
    
    return imports
end

-- Get function definitions in the current buffer
function M.get_functions(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    if not is_treesitter_available(bufnr) then
        return {}
    end
    
    local lang = vim.bo[bufnr].filetype
    local lang_queries = get_queries_for_language(lang)
    
    if not lang_queries.functions then
        return {}
    end
    
    local results = execute_query(bufnr, lang_queries.functions, 'functions')
    local functions = {}
    
    for _, result in ipairs(results) do
        if result.capture == 'name' then
            table.insert(functions, {
                name = result.text,
                range = result.range
            })
        end
    end
    
    return functions
end

-- Get class definitions in the current buffer
function M.get_classes(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    if not is_treesitter_available(bufnr) then
        return {}
    end
    
    local lang = vim.bo[bufnr].filetype
    local lang_queries = get_queries_for_language(lang)
    
    if not lang_queries.classes then
        return {}
    end
    
    local results = execute_query(bufnr, lang_queries.classes, 'classes')
    local classes = {}
    
    for _, result in ipairs(results) do
        if result.capture == 'name' then
            table.insert(classes, {
                name = result.text,
                range = result.range
            })
        end
    end
    
    return classes
end

-- Get the current function context at cursor position
function M.get_current_function_context(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    if not is_treesitter_available(bufnr) then
        return nil
    end
    
    local lang = vim.bo[bufnr].filetype
    local lang_queries = get_queries_for_language(lang)
    
    if not lang_queries.current_function then
        return nil
    end
    
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_line = cursor[1] - 1
    local cursor_col = cursor[2]
    
    local parser = vim.treesitter.get_parser(bufnr, lang)
    if not parser then
        return nil
    end
    
    local tree = parser:parse()[1]
    if not tree then
        return nil
    end
    
    local query = vim.treesitter.query.parse(lang, lang_queries.current_function)
    
    for id, node in query:iter_captures(tree:root(), bufnr) do
        local capture_name = query.captures[id]
        if capture_name == 'func' then
            local start_line, start_col = node:start()
            local end_line, end_col = node:end_()
            
            -- Check if cursor is within this function
            if cursor_line >= start_line and cursor_line <= end_line then
                if cursor_line == start_line and cursor_col < start_col then
                    goto continue
                end
                if cursor_line == end_line and cursor_col > end_col then
                    goto continue
                end
                
                -- Extract function name
                local func_name = nil
                for child in node:iter_children() do
                    local child_type = child:type()
                    if child_type == 'identifier' or child_type == 'name' then
                        func_name = vim.treesitter.get_node_text(child, bufnr)
                        break
                    end
                end
                
                return {
                    name = func_name,
                    range = {
                        start = { start_line, start_col },
                        ["end"] = { end_line, end_col }
                    },
                    node = node
                }
            end
        end
        ::continue::
    end
    
    return nil
end

-- Get the current class context at cursor position
function M.get_current_class_context(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    if not is_treesitter_available(bufnr) then
        return nil
    end
    
    local lang = vim.bo[bufnr].filetype
    local lang_queries = get_queries_for_language(lang)
    
    if not lang_queries.current_class then
        return nil
    end
    
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_line = cursor[1] - 1
    local cursor_col = cursor[2]
    
    local parser = vim.treesitter.get_parser(bufnr, lang)
    if not parser then
        return nil
    end
    
    local tree = parser:parse()[1]
    if not tree then
        return nil
    end
    
    local query = vim.treesitter.query.parse(lang, lang_queries.current_class)
    
    for id, node in query:iter_captures(tree:root(), bufnr) do
        local capture_name = query.captures[id]
        if capture_name == 'class' then
            local start_line, start_col = node:start()
            local end_line, end_col = node:end_()
            
            -- Check if cursor is within this class
            if cursor_line >= start_line and cursor_line <= end_line then
                if cursor_line == start_line and cursor_col < start_col then
                    goto continue
                end
                if cursor_line == end_line and cursor_col > end_col then
                    goto continue
                end
                
                -- Extract class name
                local class_name = nil
                for child in node:iter_children() do
                    local child_type = child:type()
                    if child_type == 'identifier' or child_type == 'name' or child_type == 'type_identifier' then
                        class_name = vim.treesitter.get_node_text(child, bufnr)
                        break
                    end
                end
                
                return {
                    name = class_name,
                    range = {
                        start = { start_line, start_col },
                        ["end"] = { end_line, end_col }
                    },
                    node = node
                }
            end
        end
        ::continue::
    end
    
    return nil
end

-- Get comprehensive semantic context at cursor position
function M.get_semantic_context(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    if not is_treesitter_available(bufnr) then
        return {
            available = false,
            reason = 'treesitter_not_available'
        }
    end
    
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_line = cursor[1] - 1
    local cursor_col = cursor[2]
    
    local parser = vim.treesitter.get_parser(bufnr)
    if not parser then
        return {
            available = false,
            reason = 'parser_not_available'
        }
    end
    
    local tree = parser:parse()[1]
    if not tree then
        return {
            available = false,
            reason = 'parse_tree_not_available'
        }
    end
    
    local root = tree:root()
    local node = root:descendant_for_range(cursor_line, cursor_col, cursor_line, cursor_col)
    
    if not node then
        return {
            available = false,
            reason = 'no_node_at_cursor'
        }
    end
    
    -- Build semantic context
    local context = {
        available = true,
        filetype = vim.bo[bufnr].filetype,
        node_type = node:type(),
        node_text = vim.treesitter.get_node_text(node, bufnr),
        cursor_position = { cursor_line, cursor_col }
    }
    
    -- Get function context
    local func_context = M.get_current_function_context(bufnr)
    if func_context then
        context.function_context = {
            name = func_context.name,
            in_function = true,
            range = func_context.range
        }
    else
        context.function_context = {
            in_function = false
        }
    end
    
    -- Get class context
    local class_context = M.get_current_class_context(bufnr)
    if class_context then
        context.class_context = {
            name = class_context.name,
            in_class = true,
            range = class_context.range
        }
    else
        context.class_context = {
            in_class = false
        }
    end
    
    -- Get imports
    context.imports = M.get_imports(bufnr)
    
    -- Get parent hierarchy
    local parents = {}
    local current = node:parent()
    while current do
        table.insert(parents, {
            type = current:type(),
            text = vim.treesitter.get_node_text(current, bufnr),
            range = {
                start = { current:start() },
                ["end"] = { current:end_() }
            }
        })
        current = current:parent()
    end
    context.parent_hierarchy = parents
    
    -- Determine current scope
    if context.function_context.in_function then
        context.current_scope = 'function'
    elseif context.class_context.in_class then
        context.current_scope = 'class'
    else
        context.current_scope = 'global'
    end
    
    return context
end

-- Get variables in current scope
function M.get_variables_in_scope(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    if not is_treesitter_available(bufnr) then
        return {}
    end
    
    local lang = vim.bo[bufnr].filetype
    local lang_queries = get_queries_for_language(lang)
    
    if not lang_queries.variables then
        return {}
    end
    
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_line = cursor[1] - 1
    
    local func_context = M.get_current_function_context(bufnr)
    local class_context = M.get_current_class_context(bufnr)
    
    local results = execute_query(bufnr, lang_queries.variables, 'variables')
    local variables = {}
    
    for _, result in ipairs(results) do
        if result.capture == 'name' then
            local var_line = result.range.start[0]
            
            -- Check if variable is in scope
            local in_scope = false
            if func_context and var_line >= func_context.range.start[0] and var_line <= func_context.range["end"][0] then
                in_scope = true
            elseif class_context and var_line >= class_context.range.start[0] and var_line <= class_context.range["end"][0] then
                in_scope = true
            elseif var_line <= cursor_line then
                in_scope = true
            end
            
            if in_scope then
                table.insert(variables, {
                    name = result.text,
                    range = result.range
                })
            end
        end
    end
    
    return variables
end

-- Get function boundary hash for caching
function M.get_function_boundary_hash(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local func_context = M.get_current_function_context(bufnr)
    if func_context and func_context.name then
        return string.format("%s:function:%s", vim.bo[bufnr].filetype, func_context.name)
    end
    
    local class_context = M.get_current_class_context(bufnr)
    if class_context and class_context.name then
        return string.format("%s:class:%s", vim.bo[bufnr].filetype, class_context.name)
    end
    
    return string.format("%s:global", vim.bo[bufnr].filetype)
end

-- Enhanced context for AI completion
function M.get_enhanced_completion_context(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local context = M.get_semantic_context(bufnr)
    
    if not context.available then
        return context
    end
    
    -- Add additional context for AI
    context.variables_in_scope = M.get_variables_in_scope(bufnr)
    context.function_boundary_hash = M.get_function_boundary_hash(bufnr)
    
    -- Add language-specific context
    local lang = vim.bo[bufnr].filetype
    if lang == 'python' then
        context.python_context = M.get_python_context(bufnr)
    elseif lang == 'javascript' or lang == 'typescript' then
        context.javascript_context = M.get_javascript_context(bufnr)
    elseif lang == 'lua' then
        context.lua_context = M.get_lua_context(bufnr)
    end
    
    return context
end

-- Language-specific context getters
function M.get_python_context(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local context = {
        decorators = {},
        docstrings = {}
    }
    
    -- This would require additional queries for Python-specific features
    -- Implementation would be similar to other query functions
    
    return context
end

function M.get_javascript_context(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local context = {
        exports = {},
        requires = {}
    }
    
    -- This would require additional queries for JavaScript-specific features
    -- Implementation would be similar to other query functions
    
    return context
end

function M.get_lua_context(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    
    local context = {
        modules = {},
        globals = {}
    }
    
    -- This would require additional queries for Lua-specific features
    -- Implementation would be similar to other query functions
    
    return context
end

return M
