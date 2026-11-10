local addonName, ns = ...
local A = ns.Assert
local function host(options) return ns.host(options) end
local function started()
    local h = host()
    h.macros.account = {{name = "Heal All", icon = 100, body = "/cast Rejuvenation"}, {name = "Drink", icon = 101}}
    h.macros.char = {{name = "Bear Form", icon = 102}, {name = "Aaa First", icon = 103}}
    h.login()
    return h
end
local function capture(h)
    local cap = {}
    h.ns.Menu.Show = function(owner, entries) cap.entries = entries end
    return cap
end

A.test("macro slot validation: name + scope only, identity and equality by name", function()
    local Core = ns.Core
    A.deep(Core.slot({kind = "macro", name = "Heal", scope = "account", index = 5}), {kind = "macro", name = "Heal", scope = "account"})
    A.equal(Core.slot({kind = "macro", name = "", scope = "account"}), nil); A.equal(Core.slot({kind = "macro", name = "x", scope = "other"}), nil)
    A.equal(Core.slot({kind = "macro", name = 5, scope = "account"}), nil)
    A.equal(Core.sameSlot({kind = "macro", name = "A", scope = "account"}, {kind = "macro", name = "A", scope = "character"}), false)
    A.equal(Core.sameSlot({kind = "macro", name = "A", scope = "account"}, {kind = "macro", name = "A", scope = "account"}), true)
    A.deep(Core.secureAttributes({kind = "macro", name = "A", scope = "account"}, nil, 3), {["*type1"] = "macro", ["*spell1"] = false, ["*item1"] = false, ["*macro1"] = 3})
    A.deep(Core.secureAttributes({kind = "macro", name = "A", scope = "account"}, nil, nil), {["*type1"] = false, ["*spell1"] = false, ["*item1"] = false, ["*macro1"] = false})
end)
A.test("indices come from the client constants: account 1.., character from MAX_ACCOUNT_MACROS + 1", function()
    local h = started(); local G = h.ns.Game
    A.equal(G.MacroIndex("Drink", "account"), 2); A.equal(G.MacroIndex("Bear Form", "character"), 121); A.equal(G.MacroIndex("Aaa First", "character"), 122)
    A.equal(G.MacroIndex("Drink", "character"), nil)
    local name, scope = G.MacroByIndex(121); A.equal(name, "Bear Form"); A.equal(scope, "character")
    name, scope = G.MacroByIndex(1); A.equal(scope, "account")
    h.env.MAX_ACCOUNT_MACROS = 100; h.macros.char = {{name = "Bear Form", icon = 102}}
    A.equal(G.MacroIndex("Bear Form", "character"), 101, "uses the client's own constant")
end)
A.test("drag a macro from the macro window onto a button: stored by name, cursor cleared", function()
    local h = started(); h.ns.Assign.Unlock()
    h.cursor = {"macro", 121}
    A.equal(h.ns.Assign.OnDrop(4), true); A.deep(h.ns.CurrentPage()[4], {kind = "macro", name = "Bear Form", scope = "character"}); A.deep(h.cursor, {})
    h.cursor = {"macro", 99}
    A.equal(h.ns.Assign.OnDrop(5), false); A.equal(h.cursor[1], "macro", "unreadable macro stays on the cursor")
    A.deep(h.ns.CurrentPage()[5], {kind = "empty"})
end)
A.test("secure button: type macro with the resolved index; one press = one use; unresolved is inert", function()
    local h = started()
    h.ns.Edit(1, {kind = "macro", name = "Drink", scope = "account"})
    local chord, bar = h.button(1), h.ns.Bar.buttons[1]
    A.equal(chord.attrs["*type1"], "macro"); A.equal(chord.attrs["*macro1"], 2); A.equal(bar.attrs["*macro1"], 2)
    A.equal(chord.attrs["*spell1"], nil); A.equal(chord.attrs["*item1"], nil)
    h.click(1, true); h.click(1, false)
    A.equal(h.ns.Secure.clicks[1].down, 1); A.equal(h.ns.Secure.clicks[1].attempts, 1); A.deep(chord.clicks, {"AnyDown"})
    -- the macro is deleted: inert, flagged missing, no error
    h.macros.account = {{name = "Heal All", icon = 100}}
    h.event("UPDATE_MACROS")
    A.equal(chord.attrs["*type1"], nil); A.equal(chord.attrs["*macro1"], nil); A.equal(bar.attrs["*type1"], nil)
    A.equal(bar.macroMissing, true); A.equal(bar.icon.last.SetDesaturated[1], true)
    A.equal(h.internalErrors, 0)
end)
A.test("indices shift when macros are created or deleted: UPDATE_MACROS re-resolves by name", function()
    local h = started()
    h.ns.Edit(2, {kind = "macro", name = "Drink", scope = "account"})
    A.equal(h.button(2).attrs["*macro1"], 2)
    table.remove(h.macros.account, 1); h.event("UPDATE_MACROS")
    A.equal(h.button(2).attrs["*macro1"], 1); A.equal(h.ns.Bar.buttons[2].attrs["*macro1"], 1)
    table.insert(h.macros.account, 1, {name = "New", icon = 5}); table.insert(h.macros.account, 1, {name = "New2", icon = 6})
    h.event("UPDATE_MACROS"); A.equal(h.button(2).attrs["*macro1"], 3)
    -- in combat: queued, nothing blocked, applied afterwards
    table.remove(h.macros.account, 1)
    h.combat = true; h.event("UPDATE_MACROS"); A.equal(h.blocked, 0); A.equal(h.button(2).attrs["*macro1"], 3)
    h.combat = false; h.event("PLAYER_REGEN_ENABLED"); A.equal(h.button(2).attrs["*macro1"], 2)
end)
A.test("dropdown: Macros next to Spells/Items with General and the character name; empty categories hidden", function()
    local h = started(); h.ns.Assign.Unlock(); local cap = capture(h)
    h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    local e = cap.entries
    A.equal(e[1].text, "Spells"); A.equal(e[2].text, "Items"); A.equal(e[3].text, "Macros")
    local m = e[3].submenu
    A.equal(#m, 2); A.equal(m[1].text, "General"); A.equal(m[2].text, "Tester")
    A.equal(m[1].submenu[1].text, "Drink"); A.equal(m[1].submenu[2].text, "Heal All"); A.equal(m[1].submenu[1].icon, 101)
    A.equal(m[2].submenu[1].text, "Aaa First", "sorted by name"); A.equal(m[2].submenu[2].text, "Bear Form")
    m[2].submenu[2].func(); A.deep(h.ns.CurrentPage()[1], {kind = "macro", name = "Bear Form", scope = "character"})
    cap.entries = nil; h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    A.equal(cap.entries[3].submenu[2].submenu[2].checked, true, "current macro is checked")
    h.macros.account = {}; cap.entries = nil; h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    A.equal(#cap.entries[3].submenu, 1); A.equal(cap.entries[3].submenu[1].text, "Tester")
    h.macros.char = {}; cap.entries = nil; h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    A.equal(cap.entries[3].submenu[1].text, "None available"); A.equal(cap.entries[3].submenu[1].disabled, true)
end)
A.test("a stale macro choice is revalidated when selected", function()
    local h = started(); h.ns.Assign.Unlock(); local cap = capture(h)
    h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    local pick = cap.entries[3].submenu[1].submenu[1]
    h.macros.account = {}
    pick.func(); A.deep(h.ns.CurrentPage()[1], {kind = "empty"}); A.equal(h.said("no longer available"), true)
end)
A.test("icon on the bar and in the controller export; missing macro exports unresolved", function()
    local h = started(); h.event("PLAYER_ENTERING_WORLD"); h.runTimers()
    h.ns.Edit(1, {kind = "macro", name = "Drink", scope = "account"})
    A.equal(h.ns.Bar.buttons[1].icon.texture, 101)
    h.ns.Export.Refresh(); A.deep(h.env.StreonorDockDB.export.icons[1], {iconFileID = 101})
    h.macros.account = {}; h.ns.Export.Refresh(); A.deep(h.env.StreonorDockDB.export.icons[1], {unresolved = true})
    h.macros.account = {{name = "Drink", icon = "Interface\\Icons\\INV_Drink_01"}}; h.ns.Export.Refresh()
    A.deep(h.env.StreonorDockDB.export.icons[1], {unresolved = true}, "only numeric file IDs reach the controller")
end)
A.test("macro buttons show the cooldown of the macro's spell or item; none otherwise", function()
    local h = started(); h.ns.Edit(1, {kind = "macro", name = "Drink", scope = "account"})
    local b = h.ns.Bar.buttons[1]
    h.time = 1000; h.spells[42] = {name = "Bolt", icon = 111, cached = true}
    h.macroSpell[2] = 42; h.spellCd[42] = {startTime = 1000, duration = 12, isEnabled = true}
    h.ns.Display.Refresh(); A.deep(b.cooldown.cd, {1000, 12}); A.equal(b.count.text, "")
    h.macroSpell[2] = nil; h.macroItem[2] = "item:8"; h.items[8] = {name = "Water", icon = 500, count = 4, cd = {1000, 30, true}}
    h.ns.Display.Refresh(); A.deep(b.cooldown.cd, {1000, 30}); A.equal(b.count.text, "4")
    h.macroItem[2] = nil; h.ns.Display.Refresh(); A.equal(b.cooldown.cd, nil)
end)
A.test("tooltip for a macro and chords/describe never error; macroprobe prints facts", function()
    local h = started(); h.ns.Edit(1, {kind = "macro", name = "Drink", scope = "account"}); h.ns.Edit(2, {kind = "macro", name = "Gone", scope = "character"})
    local lines = {}
    h.env.GameTooltip.SetText = function(_, t) lines[#lines + 1] = t end
    h.env.GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
    h.ns.Bar.Tooltip(h.ns.Bar.buttons[1]); A.equal(lines[1], "Drink")
    h.ns.Display.Refresh()
    h.ns.Bar.Tooltip(h.ns.Bar.buttons[2]); A.equal(lines[#lines]:find("Missing") ~= nil, true)
    h.slash("chords"); A.equal(h.said("MISSING"), true)
    h.slash("macroprobe"); A.equal(h.said("GetNumMacros: account 2, character 2"), true)
    A.equal(h.internalErrors, 0)
end)
A.test("macro assignment counts as a change for the reload popup", function()
    local h = started(); h.ns.Assign.Unlock(); h.ns.Edit(1, {kind = "macro", name = "Drink", scope = "account"}); h.ns.Assign.Lock()
    A.equal(#h.popups, 1)
end)
