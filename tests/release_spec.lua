local addonName, ns = ...
local A = ns.Assert
-- Builds the real release zip into a temp folder and inspects its entries (PowerShell, Windows only).
local function run(cmd)
    local p = io.popen(cmd .. " 2>&1")
    local out = p:read("*a"); p:close()
    return out
end
A.test("release zip: StreonorDock folder with Libs and licenses, INSTALL.txt, no tests or scripts", function()
    local tmp = os.getenv("TEMP") or "."
    local out = tmp .. "\\sd-addon-release-test"
    run('cmd /c rmdir /s /q "' .. out .. '"')
    local built = run('powershell -NoProfile -ExecutionPolicy Bypass -File scripts\\build-release.ps1 -OutDir "' .. out .. '"')
    A.equal(built:find("Built ", 1, true) ~= nil, true, built)
    local version = string.match(built, "StreonorDock%-(%d+%.%d+%.%d+)%.zip")
    A.equal(version ~= nil, true)
    local toc = io.open("src/StreonorDock/StreonorDock.toc", "rb"); local text = toc:read("*a"); toc:close()
    A.equal(string.match(text, "## Version: (%S+)"), version, "zip version = TOC version")
    local list = run('powershell -NoProfile -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; '
        .. "$z=[IO.Compression.ZipFile]::OpenRead('" .. out .. "\\StreonorDock-" .. version .. ".zip'); $z.Entries|%{$_.FullName}; $z.Dispose()\"")
    local names = {}
    for line in string.gmatch(list, "[^\r\n]+") do names[line] = true end
    for _, need in ipairs({"StreonorDock/StreonorDock.toc", "StreonorDock/Core.lua", "StreonorDock/Slots.xml", "StreonorDock/Bindings.xml",
        "StreonorDock/LICENSE", "StreonorDock/Libs/Libs.xml", "StreonorDock/Libs/LIBRARIES.md", "StreonorDock/Libs/LICENSE-Ace3-BSD.txt",
        "StreonorDock/Libs/LibStub/LICENSE.txt", "StreonorDock/Libs/LibCustomGlow-1.0/LICENSE",
        "StreonorDock/Libs/AceDB-3.0/AceDB-3.0.lua", "INSTALL.txt"}) do
        A.equal(names[need], true, "missing " .. need)
    end
    for name in pairs(names) do
        A.equal(name:find("\\", 1, true), nil, "forward slashes only: " .. name)
        A.equal(name:find("^tests/") == nil and name:find("^scripts/") == nil and name:find("^docs/") == nil and name:find("%.git") == nil, true, name)
        A.equal(name:match("^StreonorDock/") ~= nil or name == "INSTALL.txt", true, "unexpected top-level entry " .. name)
    end
    -- every file the TOC loads (Lua, XML) is in the zip
    for line in string.gmatch(text, "[^%c]+") do
        if not line:match("^#") then
            local path = "StreonorDock/" .. line:gsub("\\", "/")
            A.equal(names[path], true, "TOC entry missing from zip: " .. path)
        end
    end
    run('cmd /c rmdir /s /q "' .. out .. '"')
end)
A.test("no personal identifiers or machine paths in shipped addon text files", function()
    local pattern = {"al" .. "exv", "vell" .. "ucci", "fykk" .. "zry", "privaterelay"}
    local files = {"README.md", "NOTES.md", "src/StreonorDock/StreonorDock.toc", "src/StreonorDock/Init.lua"}
    for _, file in ipairs(files) do
        local f = io.open(file, "rb"); local text = string.lower(f:read("*a")); f:close()
        for _, p in ipairs(pattern) do A.equal(text:find(p, 1, true), nil, file .. " contains " .. p) end
    end
end)
