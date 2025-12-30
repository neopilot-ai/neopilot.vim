-- Neopilot utility module
local M = {}

local config = require('neopilot.config')

-- Setup utility module
function M.setup(opts)
    -- Initialize any utility-specific setup
end

-- Line ending characters for different file formats
local line_endings = {
    unix = '\n',
    dos = '\r\n',
    mac = '\r'
}

-- Get line ending characters for current buffer
function M.line_ending_chars()
    local ff = vim.bo.fileformat
    if line_endings[ff] then
        return line_endings[ff]
    end
    return '\n'
end

-- Calculate UTF-8 width of a string
function M.utf8_width(str)
    -- Simple implementation - count characters, handling wide characters
    local width = 0
    for _, code in utf8.codes(str) do
        if code < 0x80 then
            width = width + 1
        elseif code < 0x800 then
            width = width + 1
        elseif code < 0x10000 then
            width = width + 1
        else
            width = width + 2  -- Wide characters
        end
    end
    return width
end

-- Convert position to offset
function M.position_to_offset(row, col)
    local lines = vim.api.nvim_buf_get_lines(0, 0, row - 1, false)
    local text_pre = table.concat(lines, M.line_ending_chars())

    -- Add the current line up to the column
    local current_line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
    local col_index = vim.fn.charidx(current_line, col - 1)
    text_pre = text_pre .. current_line:sub(1, col_index)

    return M.utf8_width(text_pre)
end

-- Convert offset to position
function M.offset_to_position(offset)
    if offset < 0 then
        return 1, 1
    end

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local line_ending_len = #M.line_ending_chars()
    local char_offset = offset + 1
    local row = 1

    for i, line in ipairs(lines) do
        local line_len = M.utf8_width(line) + line_ending_len
        if line_len >= char_offset then
            -- Found the line, now find the column
            local col = 1
            local remaining = char_offset - 1
            local pos = 1

            while pos <= #line and remaining > 0 do
                local char_width = M.utf8_width(line:sub(pos, pos))
                if remaining <= char_width then
                    return i, col
                end
                remaining = remaining - char_width
                col = col + 1
                pos = vim.fn.byteidx(line, col - 1) + 1
            end

            return i, col
        end
        char_offset = char_offset - line_len
        row = row + 1
    end

    -- Past end of file
    local last_row = #lines
    local last_line = lines[last_row] or ''
    return last_row, #last_line + 1
end

-- Check if Neovim has supported version
function M.has_supported_version()
    -- Neovim 0.6+ has native LSP and treesitter support
    return vim.fn.has('nvim-0.6') == 1
end

-- Get config directory
function M.config_dir()
    local config_dir = os.getenv('XDG_CONFIG_HOME')
    if not config_dir or config_dir == '' then
        config_dir = os.getenv('HOME') .. '/.config'
    end
    return config_dir .. '/neopilot'
end

return M