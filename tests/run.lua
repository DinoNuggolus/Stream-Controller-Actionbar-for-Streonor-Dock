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
load("tests/init_spec.lua")
load("tests/bar_spec.lua")
load("tests/assign_spec.lua")
load("tests/display_spec.lua")
load("tests/visibility_spec.lua")
load("tests/tutorial_spec.lua")
load("tests/macros_spec.lua")
local failures = 0
-- Every fake host created by a test must end with zero blocked protected attempts and zero
-- addon "internal error" messages, unless the test opted in (h.allowBlocked / h.allowInternal).
local function hostProblems(first)
    for i=first,#ns.hosts do
        local h = ns.hosts[i]
        if h.blocked>0 and not h.allowBlocked then
            return "blocked protected call(s) in combat: " .. table.concat(h.blockedNames, ", ")
        end
        if h.internalErrors>0 and not h.allowInternal then
            for _, m in ipairs(h.messages) do
                if string.find(m, "internal error", 1, true) then return "addon printed: " .. m end
            end
        end
    end
end
for _, test in ipairs(ns.Assert.tests) do
    local first = #ns.hosts + 1
    local ok, err = pcall(test[2])
    if ok then
        local problem = hostProblems(first)
        if problem then ok, err = false, problem end
    end
    if not ok then failures = failures + 1; print("FAIL " .. test[1] .. ": " .. tostring(err)) end
end
print(#ns.Assert.tests .. " tests, " .. ns.Assert.assertions .. " assertions, " .. failures .. " failures")
assert(failures == 0, "test suite failed")
