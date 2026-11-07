local addonName, ns = ...
local A = { tests = {}, assertions = 0 }
function A.equal(actual, expected, message)
    A.assertions = A.assertions + 1
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end
function A.deep(actual, expected, message)
    A.equal(type(actual), type(expected), message)
    if type(expected) ~= "table" then A.equal(actual, expected, message); return end
    for k, v in pairs(expected) do A.deep(actual[k], v, message) end
    for k in pairs(actual) do A.equal(expected[k] ~= nil, true, "unexpected key " .. tostring(k)) end
end
function A.test(name, fn) A.tests[#A.tests + 1] = { name, fn } end
ns.Assert = A
