-- Neopilot test framework
local M = {}

local log = require('neopilot.log')

-- Test results
local test_results = {
    passed = 0,
    failed = 0,
    errors = 0,
    tests = {}
}

-- Test utilities
local function assert_equal(a, b, message)
    if a ~= b then
        error(string.format("Assertion failed: %s != %s (%s)", tostring(a), tostring(b), message or ""))
    end
end

local function assert_true(value, message)
    if not value then
        error(string.format("Assertion failed: expected true, got %s (%s)", tostring(value), message or ""))
    end
end

local function assert_false(value, message)
    if value then
        error(string.format("Assertion failed: expected false, got %s (%s)", tostring(value), message or ""))
    end
end

-- Run a single test
local function run_test(test_name, test_func)
    local success, err = pcall(test_func)
    if success then
        test_results.passed = test_results.passed + 1
        table.insert(test_results.tests, { name = test_name, status = 'passed' })
        log.info(string.format("✓ %s", test_name))
    else
        test_results.failed = test_results.failed + 1
        table.insert(test_results.tests, { name = test_name, status = 'failed', error = err })
        log.error(string.format("✗ %s: %s", test_name, err))
    end
end

-- Test configuration module
function M.test_config()
    run_test("config.get returns configured values", function()
        local config = require('neopilot.config')
        local value = config.get('idle_delay')
        assert_true(value ~= nil, "idle_delay should be configured")
        assert_true(type(value) == 'number', "idle_delay should be a number")
    end)

    run_test("config.is_enabled returns boolean", function()
        local config = require('neopilot.config')
        local enabled = config.is_enabled()
        assert_true(type(enabled) == 'boolean', "is_enabled should return boolean")
    end)
end

-- Test utility functions
function M.test_util()
    run_test("util.offset_to_position converts offsets", function()
        local util = require('neopilot.util')
        local row, col = util.offset_to_position(10)
        assert_true(type(row) == 'number', "row should be number")
        assert_true(type(col) == 'number', "col should be number")
        assert_true(row >= 1, "row should be >= 1")
        assert_true(col >= 1, "col should be >= 1")
    end)

    run_test("util.get_filetype detects filetype", function()
        local util = require('neopilot.util')
        local ft = util.get_filetype()
        assert_true(type(ft) == 'string', "filetype should be string")
        assert_true(ft ~= '', "filetype should not be empty")
    end)
end

-- Test document handling
function M.test_doc()
    run_test("doc.get_current_document returns valid document", function()
        local doc = require('neopilot.doc')
        local document = doc.get_current_document()
        assert_true(type(document) == 'table', "document should be table")
        assert_true(document.text ~= nil, "document should have text")
        assert_true(type(document.text) == 'string', "text should be string")
    end)

    run_test("doc.get_editor_options returns valid options", function()
        local doc = require('neopilot.doc')
        local options = doc.get_editor_options()
        assert_true(type(options) == 'table', "options should be table")
        assert_true(options.tab_size ~= nil, "should have tab_size")
        assert_true(options.insert_spaces ~= nil, "should have insert_spaces")
    end)
end

-- Test core completion logic
function M.test_core()
    run_test("core.is_enabled returns boolean", function()
        local core = require('neopilot.core')
        local enabled = core.is_enabled()
        assert_true(type(enabled) == 'boolean', "is_enabled should return boolean")
    end)

    run_test("core.clear resets completion state", function()
        local core = require('neopilot.core')
        core.clear()
        local current = core.get_current_completion_item()
        assert_true(current == nil, "should have no current completion after clear")
    end)
end

-- Test server communication
function M.test_server()
    run_test("server.request_metadata returns valid metadata", function()
        local server = require('neopilot.server')
        local metadata = server.request_metadata()
        assert_true(type(metadata) == 'table', "metadata should be table")
        assert_true(metadata.request_id ~= nil, "should have request_id")
    end)

    run_test("server.find_server_binary finds or returns nil", function()
        local server = require('neopilot.server')
        local binary = server.find_server_binary()
        -- Binary might not exist, but function should not error
        assert_true(binary == nil or type(binary) == 'string', "binary should be nil or string")
    end)
end

-- Test UI rendering
function M.test_ui()
    run_test("ui.clear_completion can be called", function()
        local ui = require('neopilot.ui')
        -- Should not error
        ui.clear_completion()
    end)

    run_test("ui.render_completion accepts completion item", function()
        local ui = require('neopilot.ui')
        local test_item = {
            completion = { text = "test" },
            range = { startOffset = 0, endOffset = 0 }
        }
        -- Should not error
        ui.render_completion(test_item)
    end)
end

-- Test logging
function M.test_log()
    run_test("log.info accepts messages", function()
        local log = require('neopilot.log')
        -- Should not error
        log.info("Test message")
    end)

    run_test("log.error accepts messages", function()
        local log = require('neopilot.log')
        -- Should not error
        log.error("Test error")
    end)
end

-- Run all tests
function M.run_all()
    log.info("Starting Neopilot test suite")

    test_results = {
        passed = 0,
        failed = 0,
        errors = 0,
        tests = {}
    }

    -- Run test suites
    local test_suites = {
        M.test_config,
        M.test_util,
        M.test_doc,
        M.test_core,
        M.test_server,
        M.test_ui,
        M.test_log
    }

    for _, suite in ipairs(test_suites) do
        local success, err = pcall(suite)
        if not success then
            test_results.errors = test_results.errors + 1
            log.error(string.format("Test suite failed: %s", err))
        end
    end

    -- Report results
    log.info(string.format("Test results: %d passed, %d failed, %d errors",
        test_results.passed, test_results.failed, test_results.errors))

    return test_results
end

-- Get test results
function M.get_results()
    return test_results
end

return M