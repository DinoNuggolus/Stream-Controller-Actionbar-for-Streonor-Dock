local addonName, ns = ...
-- Settings: one AceConfig-3.0 options table, shown (a) in Interface > AddOns through
-- AceConfigDialog:AddToBlizOptions and (b) as a standalone AceConfigDialog window (cog, /sdock settings,
-- minimap left-click). Media pickers use LibSharedMedia widgets (LSM30_*), profiles use AceDBOptions.
-- Custom (non-Ace) elements: none yet. The Bar > Visibility page is an intentionally empty placeholder.
local Options = {}
ns.Options = Options
local APP = "StreonorDock"
local Core = ns.Core
local order = 0
local function nextOrder() order = order + 1; return order end
local function lib(name) return _G.LibStub and LibStub(name, true) or nil end
local function lsmHash(kind)
    local m = lib("LibSharedMedia-3.0")
    return function() return m and m:HashTable(kind) or {} end
end

-- Applies a profile change: repair/validate, then redraw what depends on it.
local function changed(section, key)
    if ns.Bar then
        ns.Bar.ApplyAppearance()
        ns.Bar.Refresh()
    end
    if section == "buttons" and ns.Display then ns.Display.Refresh() end
end

local function entry(kind, section, key, name, desc, extra)
    local opt = {type = kind, name = name, desc = desc, order = nextOrder(),
        get = function() return ns.profile[section][key] end,
        set = function(_, v) ns.profile[section][key] = v; changed(section, key) end}
    for k, v in pairs(extra or {}) do opt[k] = v end
    return opt
end
local function toggle(section, key, name, desc, extra) return entry("toggle", section, key, name, desc, extra) end
local function range(section, key, name, desc, min, max, step, extra)
    local e = {min = min, max = max, step = step}
    for k, v in pairs(extra or {}) do e[k] = v end
    return entry("range", section, key, name, desc, e)
end
local function select_(section, key, name, desc, values, extra)
    local e = {values = values}
    for k, v in pairs(extra or {}) do e[k] = v end
    return entry("select", section, key, name, desc, e)
end
local function header(text) return {type = "header", name = text, order = nextOrder()} end
local function text(t) return {type = "description", name = t, order = nextOrder(), fontSize = "medium"} end
local function inCombat() return InCombatLockdown() end

local function chordList()
    local page, lines = ns.CurrentPage(), {}
    for i = 1, 15 do
        local slot = page[i]
        local what = "empty"
        if slot.kind ~= "empty" then
            local name = slot.kind == "spell" and ns.Game.SpellMeta(slot.id) or ns.Game.ItemMeta(slot.id)
            what = slot.kind .. " " .. slot.id .. (name and (" - " .. name) or "")
        end
        lines[#lines + 1] = string.format("%2d   %-18s   %s", i, Core.chord(i), what)
    end
    return table.concat(lines, "\n")
end

local function reservedChord(key)
    if type(key) ~= "string" or key == "" then return false end
    for i = 1, 15 do if key == Core.chord(i) then return true end end
    return false
end
local function keyCapture(name, field)
    return {type = "keybinding", name = name, order = nextOrder(),
        desc = "Optional page key (out of combat). The fixed controller chords cannot be used.",
        get = function() return ns.char[field] end,
        set = function(_, v)
            if reservedChord(v) then ns.Say("that chord is reserved for the controller keys"); return end
            for _, other in ipairs({"nextKey", "prevKey", "homeKey"}) do
                if other ~= field and v ~= "" and ns.char[other] == v then ns.Say("that key is already used for another page action"); return end
            end
            ns.char[field] = v or ""
            ns.Say(name .. " saved. Page keys are applied from Key Bindings > StreonorDock; this field records your preference only.")
        end}
end

function Options.Build()
    order = 0
    local args = {}
    args.general = {type = "group", name = "General", order = nextOrder(), args = {
        bar = toggle("general", "showActionBar", "Show action bar", "Show the optional on-screen bar. Chord keys work either way."),
        always = toggle("general", "alwaysShowButtons", "Always show buttons", "Keep all 15 positions visible when locked, including empty ones."),
        padlock = toggle("general", "showPadlock", "Show padlock", "Header padlock (assignment mode)."),
        cog = toggle("general", "showCog", "Show cog", "Header cog (this window). /sdock settings always works."),
        h1 = header("Right-click"),
        rc = toggle("general", "rightClickEnabled", "Right-click on buttons opens the menu", "Off: right-clicking a button runs the action below, like the header does."),
        rca = select_("general", "rightClickAction", "Right-click action", "Header, background, and (when the option above is off) buttons.",
            {settings = "Open settings", assign = "Toggle assignment mode", menu = "Show menu", nothing = "Nothing"}),
        h2 = header("Minimap"),
        minimap = {type = "toggle", name = "Hide minimap button", order = nextOrder(),
            get = function() return ns.char.minimap.hide end,
            set = function(_, v) if ns.Minimap then ns.Minimap.SetHidden(v) end end},
        h3 = header("Assignments"),
        open = {type = "execute", name = "Open assignments", order = nextOrder(), desc = "Unlock the bar for assigning spells and items.",
            func = function() if ns.Assign then ns.Assign.Toggle() end end},
    }}
    local vis = {type = "group", name = "Visibility", order = nextOrder(), args = {
        note = text("Visibility conditions are not part of this version. This page is reserved.")}}
    args.bar = {type = "group", name = "Bar", order = nextOrder(), childGroups = "tab", args = {
        layout = {type = "group", name = "Layout", order = nextOrder(), args = {
            mirror = toggle("bar", "mirrorControllerLayout", "Mirror controller layout",
                "On: the bar copies the S15 in landscape, 5 x 3, key 1 bottom-left, numbering right then up. Off: use the settings below."),
            explain = text("Single row and single column override the controller grid: choosing either turns Mirror off. Turning Mirror on returns to the 5 x 3 grid without changing any assignment."),
            row = {type = "execute", name = "Single row", order = nextOrder(), desc = "Slots 1 to 15 left to right.",
                func = function() local b = ns.profile.bar; b.mirrorControllerLayout = false; b.columns = 15; b.orientation = "horizontal"; b.growX = "right"; changed("bar") ; Options.Notify() end},
            col = {type = "execute", name = "Single column", order = nextOrder(), desc = "Slots 1 to 15 top to bottom.",
                func = function() local b = ns.profile.bar; b.mirrorControllerLayout = false; b.columns = 1; b.orientation = "horizontal"; b.growY = "down"; changed("bar"); Options.Notify() end},
            orientation = select_("bar", "orientation", "Fill order", "Horizontal fills rows first, vertical fills columns first.",
                {horizontal = "Horizontal", vertical = "Vertical"}, {disabled = function() return ns.profile.bar.mirrorControllerLayout end}),
            columns = range("bar", "columns", "Columns", "Editing columns or rows edits the same layout.", 1, 15, 1,
                {disabled = function() return ns.profile.bar.mirrorControllerLayout end}),
            rows = {type = "range", name = "Rows", order = nextOrder(), min = 1, max = 15, step = 1,
                desc = "Derived from columns (rows = ceil(15 / columns)); editing it sets the columns.",
                disabled = function() return ns.profile.bar.mirrorControllerLayout end,
                get = function() return math.ceil(15 / ns.profile.bar.columns) end,
                set = function(_, v) ns.profile.bar.columns = math.ceil(15 / v); changed("bar") end},
            growx = select_("bar", "growX", "Grow horizontally", "", {left = "Left", right = "Right"}, {disabled = function() return ns.profile.bar.mirrorControllerLayout end}),
            growy = select_("bar", "growY", "Grow vertically", "", {up = "Up", down = "Down"}, {disabled = function() return ns.profile.bar.mirrorControllerLayout end}),
            scale = range("bar", "scale", "Scale", "", 0.5, 2, 0.05),
            size = range("bar", "buttonSize", "Button size", "", 24, 80, 1),
            spacing = range("bar", "spacing", "Spacing", "", 0, 20, 1),
            pages = toggle("bar", "showPageIndicator", "Show page indicator", "Only appears when the profile has more than one page."),
            reset = {type = "execute", name = "Reset bar position", order = nextOrder(), desc = "Centre the bar on the screen.",
                disabled = inCombat, func = function() if ns.Bar then ns.Bar.ResetPosition() end end},
        }},
        look = {type = "group", name = "Appearance", order = nextOrder(), args = {
            opacity = range("bar", "backgroundOpacity", "Background opacity", "Opacity of the bar's background fill.", 0, 1, 0.01, {isPercent = true}),
            skin = {type = "select", name = "Style", order = nextOrder(), desc = "A look preset: it sets the border, background and tint. Choosing a border or background yourself switches to Custom.",
                values = function() local v = {}; for k, s in pairs(ns.Config.STYLES) do v[k] = s.label end; return v end,
                get = function() return ns.profile.bar.style end,
                set = function(_, v)
                    local bar, preset = ns.profile.bar, ns.Config.STYLES[v]
                    bar.style = v
                    if preset and preset.background then bar.background, bar.border = preset.background, preset.border end
                    changed("bar"); Options.Notify()
                end},
            style = select_("bar", "borderStyle", "Border style", "", {none = "None", thin = "Thin", glow = "Glow (highlight colour)"}),
            border = select_("bar", "border", "Border", "Border texture (LibSharedMedia).", lsmHash("border"), {dialogControl = "LSM30_Border", set = function(_, v) ns.profile.bar.border = v; ns.profile.bar.style = "custom"; changed("bar") end}),
            background = select_("bar", "background", "Background", "Background texture (LibSharedMedia).", lsmHash("background"), {dialogControl = "LSM30_Background", set = function(_, v) ns.profile.bar.background = v; ns.profile.bar.style = "custom"; changed("bar") end}),
            font = select_("bar", "font", "Font", "Font for the page indicator (LibSharedMedia).", lsmHash("font"), {dialogControl = "LSM30_Font"}),
            statusbar = select_("bar", "statusbar", "Status bar texture", "Reserved for bar-style elements (LibSharedMedia).", lsmHash("statusbar"), {dialogControl = "LSM30_Statusbar"}),
            hfade = toggle("bar", "headerFade", "Fade header when not hovered", "The padlock/cog header fades when the mouse is away from the bar and returns on mouseover. Always fully visible while assigning. It multiplies with the bar-wide fader (the header is a child of the bar)."),
            hopacity = range("bar", "headerFadedAlpha", "Header faded opacity", "", 0, 1, 0.01, {isPercent = true, disabled = function() return not ns.profile.bar.headerFade end}),
            hdur = range("bar", "headerFadeDuration", "Header fade duration (s)", "", 0, 2, 0.05, {disabled = function() return not ns.profile.bar.headerFade end}),
            h = header("Highlight / glow"),
            style2 = select_("highlight", "style", "Glow style", "Used for the drop target, the slot being assigned and the ready flash (LibCustomGlow).", function()
                local v = {}; for k, label in pairs(ns.Glow.STYLES) do v[k] = label end; return v end),
            color = {type = "color", name = "Glow colour", order = nextOrder(), hasAlpha = true,
                get = function() local c = ns.profile.highlight.color; return c[1], c[2], c[3], c[4] end,
                set = function(_, r, g, b, a) ns.profile.highlight.color = {r, g, b, a}; changed("highlight") end},
            preview = {type = "execute", name = "Preview glow", order = nextOrder(), desc = "Flash the glow on the first bar button.",
                func = function() local b = ns.Bar and ns.Bar.buttons[1]; if b and ns.Glow then ns.Glow.Flash(b, 1.5) end end},
        }},
        visibility = vis,
    }}
    args.buttons = {type = "group", name = "Buttons", order = nextOrder(), args = {
        stack = toggle("buttons", "stackCounts", "Stack counts", "Carried stack total on item buttons (0 stays visible)."),
        tips = toggle("buttons", "tooltips", "Tooltips", ""),
        flash = toggle("buttons", "pressedFlash", "Pressed flash", ""),
        h = header("Cooldowns"),
        gray = toggle("buttons", "cooldownGrayscale", "Dim remaining time", "Dim the not-yet-ready part of the icon."),
        sweep = toggle("buttons", "cooldownSweep", "Clockwise sweep", ""),
        nums = toggle("buttons", "cooldownNumbers", "Numbers", "Seconds below the minute threshold, then 2m, then 2h."),
        gcd = toggle("buttons", "showGCD", "Show global cooldown", "Off by default; never inferred from a short duration."),
        ready = toggle("buttons", "readyGlow", "Ready glow", "Flash the glow style when a readable cooldown finishes."),
        minute = range("buttons", "minuteThreshold", "Minutes from (seconds)", "Below this many seconds show seconds; from here show minutes.", 60, 180, 1),
        hour = range("buttons", "hourThreshold", "Hours from (seconds)", "From this many seconds show hours.", 3600, 10800, 60),
        fontsize = range("buttons", "cooldownFontSize", "Number size", "", 10, 48, 1),
        h2 = header("Tint / labels"),
        range_ = toggle("buttons", "rangeTint", "Out-of-range tint", "Reserved; needs a readable range API."),
        unusable = toggle("buttons", "unusableTint", "Unusable tint", "Reserved."),
        labels = select_("buttons", "keybindLabels", "Button labels", "Slot number or the chord's key on each button.",
            {off = "Off", slot = "Slot number", chord = "Chord key"}),
    }}
    args.assignment = {type = "group", name = "Assignment", order = nextOrder(), args = {
        open = {type = "execute", name = "Open assignments", order = nextOrder(), func = function() if ns.Assign then ns.Assign.Toggle() end end},
        how = text("Unlock the bar, then drag a known spell or a carried item onto a button, or click a button for the Spells / Items menu. Edits are out of combat only."),
        h = header("Pages"),
        count = {type = "range", name = "Pages", order = nextOrder(), min = 1, max = 10, step = 1,
            desc = "Each page has the same 15 slots. Shrinking archives the removed pages.",
            get = function() return ns.profile.pageCount end,
            confirm = function(_, v)
                if v < ns.profile.pageCount then
                    return "Remove " .. (ns.profile.pageCount - v) .. " page(s)? Their assignments are archived and can be restored."
                end
            end,
            set = function(_, v)
                if InCombatLockdown() then ns.Say("changing pages is unavailable in combat"); return end
                Core.setPageCount(ns.profile, v)
                ns.char.currentPage = math.min(ns.char.currentPage, ns.profile.pageCount)
                if ns.Assign then ns.Assign.NoteChange() end
                ns.LayoutChanged()
            end},
        restore = {type = "execute", name = "Restore archived pages", order = nextOrder(),
            disabled = function() return #ns.profile.archivedPages == 0 or inCombat() end,
            func = function() Core.restoreArchive(ns.profile); if ns.Assign then ns.Assign.NoteChange() end; ns.LayoutChanged() end},
        indicator = toggle("bar", "showPageIndicator", "Show page indicator", ""),
        nextKey = keyCapture("Next page key", "nextKey"),
        prevKey = keyCapture("Previous page key", "prevKey"),
        homeKey = keyCapture("Home page key", "homeKey"),
    }}
    args.controller = {type = "group", name = "Controller", order = nextOrder(), args = {
        export = {type = "toggle", name = "Export icons for the controller", order = nextOrder(),
            desc = "Off blanks the S15 keys; the chords keep working.",
            get = function() return ns.db.global.exportEnabled end,
            set = function(_, v) ns.db.global.exportEnabled = v; ns.Export.Refresh() end},
        note = text("Actions change immediately. Controller icons update when WoW writes SavedVariables on reload or logout."),
        reload = {type = "execute", name = "Reload UI", order = nextOrder(), disabled = inCombat,
            func = function() ns.Export.Refresh(); if type(ReloadUI) == "function" then ReloadUI() end end},
        h = header("Current chords"),
        list = {type = "description", name = chordList, order = nextOrder(), fontSize = "medium"},
        fire = text("Press / release mode is a setting of the Streonor plugin, not of this addon. The addon always acts on the key-down edge: one physical press is one use attempt."),
    }}
    local aceDbOptions = lib("AceDBOptions-3.0")
    local profiles = aceDbOptions and ns.db and aceDbOptions:GetOptionsTable(ns.db)
    if profiles then
        profiles.order = nextOrder()
        profiles.args.warn = {type = "description", order = 0.5, fontSize = "medium",
            name = "Every character has its own profile by default. Copying a profile duplicates it; choosing another character's profile shares that profile's assignments."}
        args.profiles = profiles
    end
    args.diagnostics = {type = "group", name = "Diagnostics", order = nextOrder(), args = {
        probe = {type = "execute", name = "Capability probe", order = nextOrder(), func = function() SlashCmdList.STREONORDOCK("probe") end},
        chords = {type = "execute", name = "Chord report", order = nextOrder(), func = function() SlashCmdList.STREONORDOCK("chords") end},
        clicks = {type = "execute", name = "Input counters", order = nextOrder(), func = function() SlashCmdList.STREONORDOCK("clicks") end},
        export = {type = "execute", name = "Export summary", order = nextOrder(), func = function() SlashCmdList.STREONORDOCK("export") end},
        info = {type = "description", order = nextOrder(), fontSize = "medium", name = function()
            local s = ns.Secure.status
            return "Secure chord targets: " .. (s.ready and "ready" or "pending") .. "; overrides " .. s.bindings .. " (" .. s.applied .. "/15)\n"
                .. "Menu backend: " .. tostring(ns.Menu and ns.Menu.backend or "not used yet") .. "\n"
                .. "Glow library: " .. ((ns.Glow and ns.Glow.Available()) and "available" or "missing") .. "\n"
                .. "Build: " .. tostring(ns.Game.Build())
        end},
    }}
    args.about = {type = "group", name = "About", order = nextOrder(), args = {
        a = text("StreonorDock " .. ns.version .. " by DinoNuggolus (MIT).\nSlash: /sdock settings | assign | help"),
        b = text("Libraries: Ace3 (AceDB, AceConfig, AceGUI, AceDBOptions), LibSharedMedia-3.0, AceGUI-3.0-SharedMediaWidgets, LibDataBroker-1.1, LibDBIcon-1.0, LibCustomGlow-1.0, LibUIDropDownMenu."),
    }}
    return {type = "group", name = "StreonorDock", childGroups = "tree", args = args}
end

function Options.Register()
    local registry = lib("AceConfigRegistry-3.0")
    if not registry then return false end
    registry:RegisterOptionsTable(APP, Options.Build)
    local dialog = lib("AceConfigDialog-3.0")
    if dialog then
        dialog:SetDefaultSize(APP, 780, 560)
        pcall(dialog.AddToBlizOptions, dialog, APP, "StreonorDock")
    end
    Options.registered = true
    return true
end
function Options.Open()
    if not Options.registered then ns.Say("settings are unavailable (AceConfig missing)"); return false end
    local dialog = lib("AceConfigDialog-3.0")
    if not dialog then return false end
    if dialog.OpenFrames and dialog.OpenFrames[APP] then dialog:Close(APP) else dialog:Open(APP) end
    return true
end
function Options.Notify()
    local registry = lib("AceConfigRegistry-3.0")
    if registry and Options.registered then registry:NotifyChange(APP) end
end
Options.Refresh = Options.Notify
