local addonName, ns = ...
ns = {}
-- Test host only: loadfile is absent in WoW; production modules never use it.
local function load(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk("StreonorDock", ns)
end
ns.load = load
load("tests/Assert.lua")
load("tests/Host.lua")
load("tests/core_spec.lua")
load("tests/cooldown_spec.lua")
load("tests/init_spec.lua")
local failures = 0
for _, test in ipairs(ns.Assert.tests) do
    local ok, err = pcall(test[2])
    if not ok then failures = failures + 1; print("FAIL " .. test[1] .. ": " .. tostring(err)) end
end
print(#ns.Assert.tests .. " tests, " .. ns.Assert.assertions .. " assertions, " .. failures .. " failures")
assert(failures == 0, "test suite failed")
