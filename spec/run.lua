-- Zero-dependency LuaJIT runner for the busted-style specs (no install needed).
-- Defines minimal busted globals (describe/it/assert), loads the spec, reports.
-- Run from the plugin root:  luajit spec/run.lua
package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0

function describe(name, fn)
    print("- " .. name)
    fn()
end

function it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  [pass] " .. name)
    else
        failed = failed + 1
        print("  [FAIL] " .. name .. "\n        " .. tostring(err))
    end
end

local function eq(expected, actual)
    if expected ~= actual then
        error("expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

assert = setmetatable({
    are = { equal = eq, same = eq },
    is_true = function(v) if v ~= true then error("expected true, got " .. tostring(v), 2) end end,
    is_false = function(v) if v ~= false then error("expected false, got " .. tostring(v), 2) end end,
    is_nil = function(v) if v ~= nil then error("expected nil, got " .. tostring(v), 2) end end,
}, { __call = function(_, v, m) if not v then error(m or "assertion failed", 2) end end })

dofile("spec/unit/model_spec.lua")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
