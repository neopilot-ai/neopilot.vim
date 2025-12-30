-- Neopilot document module
local M = {}

local util = require('neopilot.util')

-- Setup document module
function M.setup(opts)
    -- Initialize any document-specific setup
end

-- Language enum mapping
local language_enum = {
    unspecified = 0,
    c = 1,
    clojure = 2,
    coffeescript = 3,
    cpp = 4,
    csharp = 5,
    css = 6,
    cudacpp = 7,
    dockerfile = 8,
    go = 9,
    groovy = 10,
    handlebars = 11,
    haskell = 12,
    hcl = 13,
    html = 14,
    ini = 15,
    java = 16,
    javascript = 17,
    json = 18,
    julia = 19,
    kotlin = 20,
    latex = 21,
    less = 22,
    lua = 23,
    makefile = 24,
    markdown = 25,
    objectivec = 26,
    objectivecpp = 27,
    perl = 28,
    php = 29,
    plaintext = 30,
    protobuf = 31,
    pbtxt = 32,
    python = 33,
    r = 34,
    ruby = 35,
    rust = 36,
    sass = 37,
    scala = 38,
    scss = 39,
    shell = 40,
    sql = 41,
    starlark = 42,
    swift = 43,
    tsx = 44,
    typescript = 45,
    visualbasic = 46,
    vue = 47,
    xml = 48,
    xsl = 49,
    yaml = 50,
    svelte = 51,
}

-- Filetype aliases
local filetype_aliases = {
    bash = "shell",
    coffee = "coffeescript",
    cs = "csharp",
    cuda = "cudacpp",
    dosini = "ini",
    make = "makefile",
    objc = "objectivec",
    objcpp = "objectivecpp",
    proto = "protobuf",
    raku = "perl",
    sh = "shell",
    text = "plaintext",
}

-- Get current document
function M.get_current_document()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    -- Add final newline if file ends with one
    if vim.bo.endofline then
        table.insert(lines, "")
    end

    local filetype = vim.bo.filetype
    if filetype == '' then
        filetype = 'text'
    end

    local language = filetype_aliases[filetype] or filetype
    local language_id = language_enum[language] or 0

    local doc = {
        text = table.concat(lines, util.line_ending_chars()),
        editor_language = vim.bo.filetype,
        language = language_id,
        cursor_offset = util.position_to_offset(vim.fn.line('.'), vim.fn.col('.')),
    }

    local line_ending = util.line_ending_chars()
    if line_ending then
        doc.line_ending = line_ending
    end

    return doc
end

-- Get editor options
function M.get_editor_options()
    return {
        tab_size = vim.bo.shiftwidth,
        insert_spaces = vim.bo.expandtab,
    }
end

return M