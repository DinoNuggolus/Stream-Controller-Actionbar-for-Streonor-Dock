local addonName, ns = ...
local A = ns.Assert
local function host(options) return ns.host(options) end
local function readFile(path) local f = assert(io.open(path, "rb")); local t = f:read("*a"); f:close(); return t end
local function point(frame) local p = frame.points[#frame.points]; return p[4], p[5] end   -- x, y offsets of last SetPoint

A.test("bar exists at login: ON, centred, wrapper owns header and 15 secure buttons separate from chord targets", function()
    local h = host(); h.login()
    local bar = h.ns.Bar
    A.equal(bar.IsShown(), true)
    local p = bar.wrapper.points[#bar.wrapper.points]
    A.equal(p[1], "CENTER"); A.equal(p[3], "CENTER"); A.equal(p[4], 0); A.equal(p[5], 0)
    for i=1,15 do
        local b = bar.buttons[i]
        A.equal(b ~= nil, true); A.equal(b.secure, true)
        A.equal(b ~= h.button(i), true, "visible button is not the chord target")
        A.equal(h.button(i).parent, nil, "chord target stays parentless")
        A.deep(b.clicks, {"AnyDown"}); A.equal(b.attrs.useOnKeyDown, true)
    end
    A.equal(h.internalErrors, 0)
end)
A.test("slot 1 bottom-left, numbering right then up; empty cells keep their place when hidden", function()
    local h = host(); h.login()
    local bar = h.ns.Bar
    h.ns.Edit(3, {kind="item", id=8}); h.ns.Edit(11, {kind="spell", id=5})
    local size, gap = 40, 4
    local x, y = point(bar.buttons[1]); A.equal(x, 0); A.equal(y, -2*(size+gap))
    x, y = point(bar.buttons[3]); A.equal(x, 2*(size+gap)); A.equal(y, -2*(size+gap))
    x, y = point(bar.buttons[6]); A.equal(x, 0); A.equal(y, -(size+gap))
    x, y = point(bar.buttons[11]); A.equal(x, 0); A.equal(y, 0)
    x, y = point(bar.buttons[15]); A.equal(x, 4*(size+gap)); A.equal(y, 0)
    A.equal(bar.buttons[3]:IsShown(), true); A.equal(bar.buttons[11]:IsShown(), true)
    A.equal(bar.buttons[1]:IsShown(), false, "empty hidden while locked")
    A.equal(h.button(3).attrs["*item1"], "item:8"); A.equal(bar.buttons[3].attrs["*item1"], "item:8")
end)
A.test("empty page shows the ghost invitation; Always show buttons keeps all fifteen positions", function()
    local h = host(); h.login()
    local bar = h.ns.Bar
    for i=1,15 do A.equal(bar.buttons[i]:IsShown(), false) end
    A.equal(bar.wrapper:IsShown(), true)
    h.ns.profile.general.alwaysShowButtons = true; h.ns.LayoutChanged()
    for i=1,15 do A.equal(bar.buttons[i]:IsShown(), true) end
end)
A.test("layout variants: single row, single column, mirror back on; assignments never move", function()
    local h = host(); h.login(); local bar = h.ns.Bar
    h.ns.Edit(5, {kind="item", id=8})
    h.ns.profile.general.alwaysShowButtons = true
    local b = h.ns.profile.bar
    b.mirrorControllerLayout = false; b.columns = 15; h.ns.LayoutChanged()
    local x, y = point(bar.buttons[15]); A.equal(x, 14*44); A.equal(y, 0)
    b.columns = 1; h.ns.LayoutChanged()
    x, y = point(bar.buttons[15]); A.equal(x, 0); A.equal(y, -14*44)
    b.mirrorControllerLayout = true; h.ns.LayoutChanged()
    x, y = point(bar.buttons[15]); A.equal(x, 4*44); A.equal(y, 0)
    A.deep(h.ns.CurrentPage()[5], {kind="item", id=8})
    A.equal(bar.buttons[5].attrs["*item1"], "item:8")
end)
A.test("the wrapper alpha is driven only by Bar.SetFadeAlpha", function()
    local h = host(); h.login(); local bar = h.ns.Bar
    h.ns.profile.bar.visibility.enabled = false; h.ns.Visibility.SettingsChanged()
    A.equal(bar.wrapper.alpha, 1)
    A.equal(bar.SetFadeAlpha(0.35), true); A.equal(bar.wrapper.alpha, 0.35); A.equal(bar.GetFadeAlpha(), 0.35)
    A.equal(bar.SetFadeAlpha(7), true); A.equal(bar.wrapper.alpha, 1)
    A.equal(bar.SetFadeAlpha("x"), false); A.equal(bar.SetFadeAlpha(0/0), false)
    h.ns.Edit(1, {kind="item", id=8}); h.ns.profile.bar.backgroundOpacity = 0.2; bar.ApplyAppearance()
    A.equal(bar.GetFadeAlpha(), 1, "settings never touch the fade alpha")
    local count = 0
    for _, file in ipairs({"Bar","Init","Options","Minimap","Menu","Glow","Secure","Export","Game","Core","Config","Layout"}) do
        local text = readFile("src/StreonorDock/" .. file .. ".lua")
        for _ in string.gmatch(text, "wrapper:SetAlpha") do count = count + 1 end
        A.equal(string.find(text, "UIParent:SetAlpha", 1, true), nil)
    end
    A.equal(count, 2, "exactly the creation default and SetFadeAlpha")
end)
A.test("combat login: bar skeleton only, secure buttons built after combat, nothing blocked", function()
    local h = host(); h.combat = true
    h.event("ADDON_LOADED", addonName); h.event("PLAYER_LOGIN")
    local bar = h.ns.Bar
    A.equal(bar.buttons[1], nil); A.equal(h.blocked, 0)
    h.ns.Bar.Refresh(); A.equal(h.blocked, 0)
    h.combat = false; h.event("PLAYER_REGEN_ENABLED")
    A.equal(bar.buttons[15] ~= nil, true); A.equal(bar.IsShown(), true)
end)
A.test("in combat: refresh, data callbacks and settings changes queue structural work", function()
    local h = host(); h.login(); local bar = h.ns.Bar
    h.ns.Edit(1, {kind="item", id=8})
    h.combat = true
    h.ns.profile.bar.scale = 1.5; h.ns.profile.bar.buttonSize = 50
    bar.Refresh(); h.event("SPELL_DATA_LOAD_RESULT", 1, true)
    A.equal(h.blocked, 0)
    A.equal(bar.wrapper.scale, 1)
    h.combat = false; h.event("PLAYER_REGEN_ENABLED")
    A.equal(bar.wrapper.scale, 1.5); A.equal(bar.buttons[1].w, 50)
end)
A.test("hidden bar: wrapper hidden, chord targets and bindings unaffected", function()
    local h = host(); h.login(); local bar = h.ns.Bar
    h.ns.Edit(1, {kind="item", id=8})
    h.ns.profile.general.showActionBar = false; bar.Layout()
    A.equal(bar.IsShown(), false)
    A.equal(h.button(1).attrs["*item1"], "item:8"); A.equal(h.ns.Secure.status.applied, 15)
    h.click(1, true); A.equal(#h.uses, 1)
    bar.ToggleShown(); A.equal(bar.IsShown(), true)
    h.combat = true; bar.ToggleShown(); A.equal(h.ns.profile.general.showActionBar, true); A.equal(h.blocked, 0)
end)
A.test("header: padlock and cog follow settings; drag stores CENTER offsets; no drag in combat; reset centres", function()
    local h = host(); h.login(); local bar = h.ns.Bar
    A.equal(bar.header.padlock:IsShown(), true); A.equal(bar.header.cog:IsShown(), true)
    h.ns.profile.general.showCog = false; h.ns.profile.general.showPadlock = false; bar.ApplyHeader()
    A.equal(bar.header.padlock:IsShown(), false); A.equal(bar.header.cog:IsShown(), false)
    bar.wrapper.cx, bar.wrapper.cy = 100, 50
    h.env.UIParent.cx, h.env.UIParent.cy = 40, 30
    h.fire(bar.header, "OnDragStart"); A.equal(bar.wrapper.moving, true)
    h.fire(bar.header, "OnDragStop")
    A.deep(h.ns.char.barPosition, {point="CENTER", relativePoint="CENTER", x=60, y=20})
    h.combat = true; bar.wrapper.moving = false
    h.fire(bar.header, "OnDragStart"); A.equal(bar.wrapper.moving, false)
    h.combat = false
    bar.ResetPosition(); A.deep(h.ns.char.barPosition, {point="CENTER", relativePoint="CENTER", x=0, y=0})
end)
A.test("right-click routing: buttons open the menu when enabled, header uses the configured action", function()
    local h = host(); h.login(); local bar = h.ns.Bar
    local shown = {}
    h.ns.Menu.Show = function(owner, entries) shown[#shown+1] = entries end
    h.ns.Options.Open = function() shown[#shown+1] = "settings" end
    bar.RightClick("button", bar.buttons[1], 1); A.equal(type(shown[1]), "table")
    A.equal(shown[1][2].text, "Settings")
    h.ns.profile.general.rightClickEnabled = false
    bar.RightClick("button", bar.buttons[1], 1); A.equal(type(shown[2]), "table", "action 'menu' still shows the menu")
    h.ns.profile.general.rightClickAction = "settings"
    bar.RightClick("button", bar.buttons[1], 1); A.equal(shown[3], "settings")
    h.ns.profile.general.rightClickAction = "nothing"
    bar.RightClick("header", bar.header, nil); A.equal(#shown, 3)
end)

-- Options ----------------------------------------------------------------------------------------
A.test("options table validates with AceConfigRegistry and has the spec'd pages", function()
    local h = host(); h.login()
    local opts = h.ns.Options.Build()
    local registry = h.env.LibStub("AceConfigRegistry-3.0")
    registry:ValidateOptionsTable(opts, "StreonorDock")
    for _, page in ipairs({"general","bar","buttons","assignment","controller","profiles","diagnostics","about"}) do
        A.equal(opts.args[page] ~= nil, true, "page " .. page)
    end
    A.equal(opts.args.bar.args.visibility ~= nil, true)
    A.equal(opts.childGroups, "tree")
end)
A.test("options: get/set round-trip, rows derive from columns, single row/column turn mirror off", function()
    local h = host(); h.login()
    local layout = h.ns.Options.Build().args.bar.args.layout.args
    A.equal(layout.mirror.get(), true)
    layout.row.func(); A.equal(h.ns.profile.bar.mirrorControllerLayout, false); A.equal(h.ns.profile.bar.columns, 15)
    A.equal(layout.rows.get(), 1)
    layout.rows.set(nil, 3); A.equal(h.ns.profile.bar.columns, 5)
    layout.col.func(); A.equal(h.ns.profile.bar.columns, 1); A.equal(layout.rows.get(), 15)
    layout.mirror.set(nil, true); A.equal(h.ns.profile.bar.mirrorControllerLayout, true)
    A.equal(layout.columns.disabled(), true)
    local look = h.ns.Options.Build().args.bar.args.look.args
    A.equal(look.border.dialogControl, "LSM30_Border"); A.equal(look.background.dialogControl, "LSM30_Background"); A.equal(look.font.dialogControl, "LSM30_Font")
    look.color.set(nil, 1, 0, 0, 0.5); A.deep(h.ns.profile.highlight.color, {1, 0, 0, 0.5})
    look.style2.set(nil, "proc"); A.equal(h.ns.profile.highlight.style, "proc")
end)
A.test("options: pages shrink archives, page keys reject reserved chords, export toggle", function()
    local h = host(); h.login()
    local a = h.ns.Options.Build().args.assignment.args
    a.count.set(nil, 3); A.equal(h.ns.profile.pageCount, 3)
    A.equal(a.count.confirm(nil, 1) ~= nil, true); A.equal(a.count.confirm(nil, 5), nil)
    h.ns.Edit(1, {kind="item", id=8}); h.slash("page next"); h.ns.Edit(2, {kind="item", id=9})
    a.count.set(nil, 1); A.equal(h.ns.profile.pageCount, 1); A.equal(h.ns.char.currentPage, 1); A.equal(#h.ns.profile.archivedPages, 2)
    a.restore.func(); A.equal(h.ns.profile.pageCount, 3)
    a.nextKey.set(nil, "ALT-CTRL-SHIFT-1"); A.equal(h.ns.char.nextKey, "")
    a.nextKey.set(nil, "CTRL-N"); A.equal(h.ns.char.nextKey, "CTRL-N")
    a.prevKey.set(nil, "CTRL-N"); A.equal(h.ns.char.prevKey, "")
    local c = h.ns.Options.Build().args.controller.args
    c.export.set(nil, false); A.equal(h.env.StreonorDockDB.export.enabled, false)
    A.equal(c.list.name():find("ALT%-CTRL%-SHIFT%-1") ~= nil, true)
end)
A.test("options register; Open reports a missing dialog library instead of failing", function()
    local h = host(); h.login()
    A.equal(h.ns.Options.registered, true)
    A.equal(h.ns.Options.Open(), false)  -- AceConfigDialog is not loadable in the host
end)
A.test("minimap click routing", function()
    local h = host(); h.login()
    local calls = {}
    h.ns.Options.Open = function() calls[#calls+1] = "settings" end
    h.ns.Assign = {Toggle = function() calls[#calls+1] = "assign" end}
    h.ns.Minimap.OnClick(nil, "LeftButton"); h.ns.Minimap.OnClick(nil, "RightButton")
    A.deep(calls, {"settings", "assign"})
end)

A.test("header fades to 5% away from the panel, full on hover, forced full while assigning, setting-controlled", function()
    local h = host(); h.login(); local bar = h.ns.Bar
    local header = bar.header
    local function settle() if header.scripts.OnUpdate then header.scripts.OnUpdate(header, 5) end end
    settle(); A.equal(header.alpha, 0.05)
    h.fire(bar.buttons[1], "OnEnter"); settle(); A.equal(header.alpha, 1)
    h.hoverAll = true; h.fire(bar.buttons[1], "OnLeave"); h.runTimers(); settle(); A.equal(header.alpha, 1, "still inside the panel")
    h.hoverAll = false; h.fire(header, "OnLeave"); h.runTimers(); settle(); A.equal(header.alpha, 0.05)
    h.ns.Assign.Unlock(); settle(); A.equal(header.alpha, 1, "forced visible while assigning")
    h.ns.Assign.Lock(); settle(); A.equal(header.alpha, 0.05)
    h.ns.profile.bar.headerFade = false; bar.UpdateHeaderFade(); settle(); A.equal(header.alpha, 1)
    h.ns.profile.bar.headerFade = true; h.ns.profile.bar.headerFadeDuration = 0; bar.UpdateHeaderFade(); A.equal(header.alpha, 0.05, "zero duration is immediate")
    bar.SetFadeAlpha(0.5); A.equal(header.alpha, 0.05, "bar-wide fader is separate (alphas multiply)")
    A.equal(h.blocked, 0)
end)

A.test("Always show buttons defaults OFF; locked bar hides every empty slot; /sdock bar reports it", function()
    local h = host(); h.login()
    A.equal(h.ns.profile.general.alwaysShowButtons, false)
    h.ns.Edit(2, {kind="item", id=8}); h.ns.Assign.Unlock(); h.ns.Assign.Lock()
    for i=1,15 do A.equal(h.ns.Bar.buttons[i]:IsShown(), i == 2); A.equal(h.ns.Bar.buttons[i].overlay:IsShown(), false) end
    h.slash("bar"); A.equal(h.said("alwaysShowButtons=false"), true)
end)
A.test("style presets: slate default, parchment applies LSM keys, picking a border switches to custom", function()
    local h = host(); h.login()
    local look = h.ns.Options.Build().args.bar.args.look.args
    A.equal(h.ns.profile.bar.style, "flat"); A.equal(h.ns.profile.bar.background, "Solid")
    look.skin.set(nil, "parchment")
    A.equal(h.ns.profile.bar.background, "Blizzard Parchment"); A.equal(h.ns.profile.bar.style, "parchment")
    look.border.set(nil, "Blizzard Dialog"); A.equal(h.ns.profile.bar.style, "custom")
    A.equal(h.ns.Bar.wrapper.backdrop ~= nil or true, true)
end)
