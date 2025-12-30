-- Neopilot LSP integration module
local M = {}

function M.setup()
    -- No setup needed
end

-- Get all diagnostics for the current buffer
function M.get_diagnostics(bufnr)
    bufnr = bufnr or 0
    local diagnostics = vim.lsp.diagnostic.get(bufnr)
    if not diagnostics or #diagnostics == 0 then
        return nil
    end

    local formatted_diagnostics = {}
    for _, d in ipairs(diagnostics) do
        table.insert(formatted_diagnostics, {
            severity = d.severity,
            message = d.message,
            line = d.range.start.line,
        })
    end

    return formatted_diagnostics
end

return M
