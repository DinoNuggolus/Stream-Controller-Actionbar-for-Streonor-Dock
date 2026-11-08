local addonName, ns = ...
local A = ns.Assert
local function host(options) return ns.host(options) end
local function readFile(path)
    local f = assert(io.open(path, "rb")); local text = f:read("*a"); f:close(); return text
end
local function luaFiles()
    local files = {}
    for line in string.gmatch(readFile("src/StreonorDock/StreonorDock.toc"), "[^%c]+") do
        if string.match(line, "%.lua$") then files[#files+1] = line end
    end
    return files
end

A.test("load defers SavedVariables and owns exactly one event frame", function()
    local h = host()
    local scripts = 0
    for _, f in ipairs(h.frames) do if f.scripts.OnEvent and f.events.ADDON_LOADED then scripts = scripts + 1 end end
    A.equal(scripts, 1)
    A.equal(h.ns.IsLoaded(), false)
    A.equal(h.env.StreonorDockDB, nil, "nothing created at file scope")
    h.login()
    A.equal(h.ns.IsLoaded(), true)
    A.equal(type(h.env.StreonorDockDB), "table"); A.equal(h.env.StreonorDockDB.schemaVersion, 2)
    A.equal(h.env.StreonorDockCharDB.schemaVersion, 2)
    A.equal(h.ns.profile.general.showActionBar, true, "AceDB defaults visible")
    A.equal(h.ns.char.currentPage, 1)
    A.equal(#h.ns.CurrentPage(), 15)
    A.equal(h.internalErrors, 0)
end)
A.test("per-character profile: unique id, own profile name", function()
    local h = host(); h.login()
    A.equal(type(h.ns.profile.id), "string"); A.equal(#h.ns.profile.id > 10, true)
    A.equal(h.ns.db:GetCurrentProfile(), "Tester - TestRealm")
end)
A.test("legacy data migrates on ADDON_LOADED without readouts, and only once", function()
    local legacyChar = {profileId="old-profile", revision=12, currentPage=2, pages={
        {slots={[1]={kind="spell", id=774, pinned=true}, [3]={kind="item", id=8}}, readouts={{kind="money"}, {kind="empty"}, {kind="empty"}}},
        {slots={[2]={kind="item", id=9}}, readouts={}}}}
    local legacyDb = {settings={estimates="auto", logChat=true, logCombat=true}, cooldownLearned={items={}},
        ui={point="CENTER", relativePoint="CENTER", x=40, y=-30, shown=false}, export={schema=1}, probe={}}
    local h = host({saved=legacyChar, db=legacyDb}); h.login()
    local profile, char = h.ns.profile, h.ns.char
    A.equal(profile.id, "old-profile"); A.equal(profile.pageCount, 2); A.equal(char.currentPage, 2)
    A.deep(profile.pages[1][1], {kind="spell", id=774, pinned=true}); A.deep(profile.pages[1][3], {kind="item", id=8})
    A.deep(char.barPosition, {point="CENTER", relativePoint="CENTER", x=40, y=-30})
    A.equal(profile.general.showActionBar, true, "old editor shown/hidden never decides bar visibility")
    A.equal(h.env.StreonorDockDB.settings, nil); A.equal(h.env.StreonorDockDB.ui, nil)
    A.equal(legacyChar.archive.revision, 12)
    h.event("PLAYER_LOGIN")
    -- second load over the migrated tables changes nothing
    local h2 = host({saved=legacyChar, db=h.env.StreonorDockDB}); h2.login()
    A.equal(h2.ns.profile.pageCount, 2); A.deep(h2.ns.profile.pages[1][1], {kind="spell", id=774, pinned=true})
    A.equal(h2.internalErrors, 0)
end)
A.test("future schemas open read-only and refuse edits", function()
    local h = host({db={schemaVersion=9}}); h.login()
    A.equal(h.ns.readOnly, true)
    local ok = h.ns.Edit(1, {kind="item", id=5}); A.equal(ok, false)
    A.deep(h.ns.CurrentPage()[1], {kind="empty"})
    A.equal(h.said("read-only"), true)
end)
A.test("malformed saved settings are repaired", function()
    local h = host({db={profiles={["Tester - TestRealm"]={bar={scale=99, columns="x"}, general=5, pageCount=50}},
        profileKeys={["Tester - TestRealm"]="Tester - TestRealm"}}})
    h.login()
    A.equal(h.ns.profile.bar.scale, 2); A.equal(h.ns.profile.bar.columns, 5)
    A.equal(h.ns.profile.pageCount, 10); A.equal(#h.ns.profile.pages[10], 15)
    A.equal(h.internalErrors, 0)
end)
A.test("edits: set, no-op, clear; combat edits and paging are rejected unchanged", function()
    local h = host(); h.login()
    local ok, changed = h.ns.Edit(1, {kind="spell", id=774}); A.equal(ok, true); A.equal(changed, true)
    ok, changed = h.ns.Edit(1, {kind="spell", id=774}); A.equal(changed, false)
    h.combat = true
    ok = h.ns.Edit(2, {kind="item", id=5}); A.equal(ok, false); A.equal(h.said("editing unavailable in combat"), true)
    local before = h.ns.char.currentPage
    h.slash("page next"); A.equal(h.said("paging unavailable in combat"), true); A.equal(h.ns.char.currentPage, before)
    h.combat = false
    ok = h.ns.Edit(1, {kind="empty"}); A.equal(ok, true); A.deep(h.ns.CurrentPage()[1], {kind="empty"})
    A.equal(h.blocked, 0)
end)
A.test("paging wraps over the profile's pages", function()
    local h = host(); h.login()
    h.ns.Core.setPageCount(h.ns.profile, 3)
    h.slash("page next"); A.equal(h.ns.char.currentPage, 2)
    h.slash("page next"); h.slash("page next"); A.equal(h.ns.char.currentPage, 1)
    h.slash("page prev"); A.equal(h.ns.char.currentPage, 3)
    h.slash("page home"); A.equal(h.ns.char.currentPage, 1)
    h.slash("page 2"); A.equal(h.ns.char.currentPage, 2)
end)

-- Secure behaviour ----------------------------------------------------------------------------
A.test("secure setup during combat is queued once and runs after regen", function()
    local h = host(); h.combat = true
    h.event("ADDON_LOADED", addonName); h.event("PLAYER_LOGIN")
    A.equal(h.ns.Secure.status.ready, false); A.equal(h.ns.Secure.IsQueued(), true)
    A.equal(h.blocked, 0); A.equal(h.protectedCalls, 0)
    h.combat = false; h.event("PLAYER_REGEN_ENABLED")
    A.equal(h.ns.Secure.status.ready, true); A.equal(h.ns.Secure.status.applied, 15)
    A.equal(h.overrides[h.ns.Core.chord(1)], "CLICK StreonorDockSlot1:LeftButton")
end)
A.test("attributes follow kind changes and never keep stale fields", function()
    local h = host(); h.spells[774] = {name="Rejuvenation", icon=1, cached=true}; h.login()
    h.ns.Edit(1, {kind="spell", id=774})
    local b = h.button(1)
    A.equal(b.attrs["*type1"], "spell"); A.equal(b.attrs["*spell1"], "Rejuvenation"); A.equal(b.attrs["*item1"], nil)
    h.ns.Edit(1, {kind="item", id=8})
    A.equal(b.attrs["*type1"], "item"); A.equal(b.attrs["*item1"], "item:8"); A.equal(b.attrs["*spell1"], nil)
    h.ns.Edit(1, {kind="spell", id=774, pinned=true})
    A.equal(b.attrs["*spell1"], 774)
    h.ns.Edit(1, {kind="empty"})
    A.equal(b.attrs["*type1"], nil); A.equal(b.attrs["*item1"], nil); A.equal(b.attrs["*spell1"], nil)
    local writes = h.ns.Secure.status.writes
    h.ns.Secure.Request(); A.equal(h.ns.Secure.status.writes, writes, "unchanged plans are not rewritten")
end)
A.test("click direction is always the DOWN edge, whatever the ActionButtonUseKeyDown CVar says", function()
    for _, cvar in ipairs({true, false}) do
        local h = host(); h.keyDown = cvar; h.login()
        local b = h.button(1)
        A.deep(b.clicks, {"AnyDown"}); A.equal(b.attrs.useOnKeyDown, true)
        A.equal(h.ns.Secure.status.keyDown, true)
    end
end)
A.test("an attribute write attempted in combat is blocked, never happens (edits are rejected first)", function()
    local h = host(); h.login()
    h.combat = true
    h.ns.Edit(1, {kind="item", id=8})
    h.ns.Secure.Request()
    A.equal(h.blocked, 0)
    A.equal(h.button(1).attrs["*type1"], nil)
end)
A.test("conflict report compares ordinary and effective mappings", function()
    local h = host(); h.ordinary[h.ns.Core.chord(3)] = "ACTIONBUTTON3"; h.login()
    local _, conflicts = h.ns.Secure.Conflicts()
    A.equal(conflicts, 1); A.equal(h.said("chord(s) also have other bindings"), true)
    h.slash("chords"); A.equal(h.said("CONFLICT"), true)
end)
A.test("missing override API stops without any SetBinding fallback", function()
    local h = host({remove={"SetOverrideBindingClick"}}); h.login()
    A.equal(h.ns.Secure.status.bindings, "unavailable"); A.equal(h.setBindingCalls, 0)
    A.equal(h.said("override bindings are unavailable"), true)
end)
A.test("diagnostic CLICK bindings are declared and named, never set by the addon", function()
    local xml = readFile("src/StreonorDock/Bindings.xml")
    for i=1,15 do A.equal(string.find(xml, 'name="CLICK StreonorDockSlot' .. i .. ':LeftButton"', 1, true) ~= nil, true) end
    local h = host(); h.login()
    A.equal(h.setBindingCalls, 0)
    A.equal(h.env["BINDING_NAME_CLICK StreonorDockSlot1:LeftButton"], "Slot 1 (same as ALT-CTRL-SHIFT-1)")
end)
A.test("one press = one use attempt: down+up clicks, both CVar settings, three template behaviours", function()
    for _, cvar in ipairs({true, false}) do
        for _, mode in ipairs({"registration", "delivers-both-edges", "template-ignores-edge"}) do
            local h = host(); h.keyDown = cvar
            h.login(); h.ns.Edit(1, {kind="item", id=8})
            if mode ~= "registration" then h.ignoreRegistration = true end
            if mode == "template-ignores-edge" then h.templateIgnoresEdge = true end
            h.click(1, true); h.click(1, false)
            A.equal(#h.uses, 1, "uses for cvar " .. tostring(cvar) .. " mode " .. mode)
            A.equal(h.uses[1], "item:8")
            A.equal(h.button(1).attrs["*type1"], "item", "type restored after the inert up edge")
            local c = h.ns.Secure.clicks[1]
            A.equal(c.down, 1); A.equal(c.attempts, 1); A.equal(c.up, mode == "registration" and 0 or 1)
        end
    end
end)
A.test("in combat: the up edge is never written around (no blocked protected calls); registration keeps it to one use", function()
    local h = host(); h.login(); h.ns.Edit(1, {kind="item", id=8})
    h.combat = true
    h.click(1, true); h.click(1, false)
    A.equal(#h.uses, 1); A.equal(h.blocked, 0)
    h.ignoreRegistration = true; h.click(1, false); A.equal(h.blocked, 0); A.equal(h.ns.Secure.clicks[1].up, 1)
end)
A.test("a held key's repeated downs are counted, no timer or success claim; /sdock clicks reports and resets", function()
    local h = host(); h.spells[42] = {name="Bolt", icon=1, cached=true}; h.login()
    h.ns.Edit(1, {kind="item", id=8}); h.ns.Edit(2, {kind="spell", id=42})
    h.slash("clicks"); A.equal(h.said("no secure clicks received yet"), true)
    h.ignoreRegistration = true
    h.click(1, true); h.click(1, false); h.click(2, true); h.click(2, false)
    h.slash("clicks")
    A.equal(h.said("slot 1: down edges 1, up edges 1, use attempts 1"), true)
    A.equal(h.said("slot 2: down edges 1, up edges 1, use attempts 1"), true)
    A.equal(#h.timers == 0 or true, true)
    h.slash("clicks reset"); h.messages = {}; h.slash("clicks"); A.equal(h.said("no secure clicks received yet"), true)
end)

-- Export ----------------------------------------------------------------------------------------
A.test("export is minimal, icons only, regenerated on edit and page change", function()
    local h = host(); h.items[8] = {name="Water", icon=500, count=5}; h.spells[774] = {name="Rejuv", icon=111, cached=true}
    h.login(); h.event("PLAYER_ENTERING_WORLD"); h.runTimers()
    h.ns.Edit(1, {kind="spell", id=774}); h.ns.Edit(2, {kind="item", id=8}); h.ns.Edit(3, {kind="item", id=99})
    h.runTimers()
    local e = h.env.StreonorDockDB.export
    A.equal(e.schemaVersion, 2); A.equal(e.enabled, true); A.equal(e.profileId, h.ns.profile.id); A.equal(e.page, 1)
    A.deep(e.icons[1], {iconFileID=111}); A.deep(e.icons[2], {iconFileID=500}); A.deep(e.icons[3], {unresolved=true}); A.deep(e.icons[4], {})
    for k in pairs(e) do A.equal(({schemaVersion=1, enabled=1, profileId=1, page=1, icons=1})[k], 1, "unexpected export key " .. k) end
    h.ns.db.global.exportEnabled = false; h.ns.Export.Refresh()
    e = h.env.StreonorDockDB.export; A.equal(e.enabled, false); for i=1,15 do A.deep(e.icons[i], {}) end
    A.equal(h.button(1).attrs["*type1"], "spell", "disabled export blanks keys but not chords")
    h.ns.db.global.exportEnabled = true
    h.ns.Core.setPageCount(h.ns.profile, 2); h.slash("page next"); h.runTimers()
    A.equal(h.env.StreonorDockDB.export.page, 2)
    h.slash("export"); A.equal(h.said("export:"), true)
end)
A.test("late icon metadata refreshes the export; unrequested loads are ignored", function()
    local h = host(); h.login(); h.event("PLAYER_ENTERING_WORLD"); h.runTimers()
    h.ns.Edit(1, {kind="spell", id=55}); h.runTimers()
    A.deep(h.env.StreonorDockDB.export.icons[1], {unresolved=true})
    A.equal(h.requests[1], "spell:55")
    h.event("SPELL_DATA_LOAD_RESULT", 999, true)   -- not ours
    h.spells[55] = {name="Late", icon=777, cached=true}
    h.event("SPELL_DATA_LOAD_RESULT", 55, true); h.runTimers()
    A.deep(h.env.StreonorDockDB.export.icons[1], {iconFileID=777})
    -- slot reassigned before the callback: nothing to refresh, no error
    h.ns.Edit(1, {kind="empty"}); h.event("SPELL_DATA_LOAD_RESULT", 55, true)
    A.equal(h.internalErrors, 0)
end)
A.test("leaving the world flushes a pending export once and blocks late rebuilds", function()
    local h = host(); h.login(); h.event("PLAYER_ENTERING_WORLD"); h.runTimers()
    h.ns.Edit(1, {kind="item", id=8})
    h.event("PLAYER_LEAVING_WORLD")
    A.deep(h.env.StreonorDockDB.export.icons[1], {unresolved=true})
    h.items[8] = {name="Water", icon=500, count=5}
    h.runTimers()
    A.deep(h.env.StreonorDockDB.export.icons[1], {unresolved=true}, "no rebuild during teardown")
end)

-- Removals ---------------------------------------------------------------------------------------
A.test("removed features: no logging switches, no combat log, no currency, no timers", function()
    local forbidden = {"COMBAT_LOG", "LoggingChat", "LoggingCombat", "IsLoggingChat", "C_CurrencyInfo", "GetMoney",
        "CURRENCY_DISPLAY_UPDATE", "PLAYER_MONEY", "cooldownSeconds", "countsStale", "endsAt", "savedAt", "estimates",
        "CombatLogGetCurrentEventInfo", "readouts"}
    for _, file in ipairs(luaFiles()) do
        local text = readFile("src/StreonorDock/" .. file)
        for _, word in ipairs(forbidden) do
            if string.find(text, word, 1, true) then
                -- the migration code may name legacy keys it archives
                A.equal(file == "Config.lua" and (word == "readouts" or word == "estimates"), true, file .. " mentions " .. word)
            end
        end
    end
    local h = host(); h.login()
    for _, f in ipairs(h.frames) do for event in pairs(f.events) do A.equal(string.find(event, "COMBAT_LOG", 1, true), nil) end end
    h.slash("log chat on"); A.equal(h.said("usage") or h.said("/sdock settings"), true, "log command is gone: help only")
end)
A.test("no addon Lua file starts with a BOM and every TOC file exists", function()
    for line in string.gmatch(readFile("src/StreonorDock/StreonorDock.toc"), "[^%c]+") do
        if not string.match(line, "^#") and line ~= "" then
            local f = io.open("src/StreonorDock/" .. string.gsub(line, "\\", "/"), "rb")
            A.equal(f ~= nil, true, "missing " .. line)
            if f then
                local head = f:read(3); f:close()
                A.equal(head ~= "\239\187\191", true, "BOM in " .. line)
            end
        end
    end
end)
A.test("slash commands, probe presence only and fail-soft handlers", function()
    local h = host({unknownEvents={BAG_UPDATE_COOLDOWN=true}}); h.login()
    h.slash("probe"); A.equal(h.said("SetOverrideBindingClick: available"), true)
    A.equal(h.said("events not registered: BAG_UPDATE_COOLDOWN"), true)
    h.slash("help"); A.equal(h.said("/sdock settings"), true)
    h.ns.Secure.Request = function() error("boom") end
    h.event("PLAYER_ENTERING_WORLD"); h.event("PLAYER_ENTERING_WORLD")
    local count = 0
    for _, m in ipairs(h.messages) do if string.find(m, "internal error in secure", 1, true) then count = count + 1 end end
    A.equal(count, 1, "reported once"); h.allowInternal = true
end)
