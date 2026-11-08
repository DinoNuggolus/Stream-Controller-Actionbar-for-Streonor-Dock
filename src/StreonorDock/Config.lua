local addonName, ns = ...
-- Settings schema (spec section 6), validation and one-shot migration. Pure Lua: AceDB is created
-- by Init.lua and handed in. Saved data is untrusted structurally; every value is range/enum checked.
local Config = {}
ns.Config = Config
local Core = ns.Core
Config.SCHEMA = 2

Config.defaults = {
    profile = {
        id = "",
        pageCount = 1,
        general = {showActionBar=true, alwaysShowButtons=false, showPadlock=true, showCog=true,
            rightClickEnabled=true, rightClickAction="menu"},
        bar = {scale=1, buttonSize=40, spacing=4, orientation="horizontal", columns=5,
            mirrorControllerLayout=true, growX="right", growY="down", backgroundOpacity=0.65,
            borderStyle="thin", showPageIndicator=true,
            style="flat", border="Blizzard Tooltip", background="Solid", font="Friz Quadrata TT",
            statusbar="Blizzard",
            visibility={enabled=true, baseAlpha=0.35, visibleAlpha=1, fadeIn=0.15, fadeOut=0.30, fadeDelay=0.50,
                match="ANY", hideWhenNone=false, conditions={mouseover=true, combat=true, target=true},
                mouseoverMargin=8, lowHealthPct=30, modifier="SHIFT"},
            headerFade=true, headerFadedAlpha=0.05, headerFadeDuration=0.15},
        buttons = {stackCounts=true, cooldownGrayscale=true, cooldownSweep=true, cooldownNumbers=true,
            tooltips=true, pressedFlash=true, rangeTint=false, unusableTint=false, showGCD=false,
            minuteThreshold=90, hourThreshold=5400, cooldownFontSize=19, keybindLabels="off",
            readyGlow=true},
        highlight = {style="pixel", color={0.96, 0.80, 0.20, 1}},
    },
    char = {
        currentPage = 1,
        barPosition = {point="CENTER", relativePoint="CENTER", x=0, y=0},
        minimap = {hide=false, minimapPos=225},
        nextKey = "", prevKey = "", homeKey = "",
    },
    global = {
        exportEnabled = true,
        tutorial = {seen=false, hidePopups=false, completed=false},
    },
}

-- {section, key, type, a, b}: bool | enum (a = list) | int/num (a..b)
local E = {
    {"general","showActionBar","bool"}, {"general","alwaysShowButtons","bool"},
    {"general","showPadlock","bool"}, {"general","showCog","bool"}, {"general","rightClickEnabled","bool"},
    {"general","rightClickAction","enum",{"settings","assign","menu","nothing"}},
    {"bar","scale","num",0.5,2}, {"bar","buttonSize","int",24,80}, {"bar","spacing","int",0,20},
    {"bar","orientation","enum",{"horizontal","vertical"}}, {"bar","columns","int",1,15},
    {"bar","mirrorControllerLayout","bool"}, {"bar","growX","enum",{"left","right"}},
    {"bar","growY","enum",{"up","down"}}, {"bar","backgroundOpacity","num",0,1},
    {"bar","borderStyle","enum",{"none","thin","glow"}}, {"bar","showPageIndicator","bool"},
    {"bar","headerFade","bool"}, {"bar","headerFadedAlpha","num",0,1}, {"bar","headerFadeDuration","num",0,2},
    {"bar","style","enum",{"flat","slate","parchment","custom"}}, {"bar","border","string"}, {"bar","background","string"}, {"bar","font","string"}, {"bar","statusbar","string"},
    {"buttons","stackCounts","bool"}, {"buttons","cooldownGrayscale","bool"}, {"buttons","cooldownSweep","bool"},
    {"buttons","cooldownNumbers","bool"}, {"buttons","tooltips","bool"}, {"buttons","pressedFlash","bool"},
    {"buttons","rangeTint","bool"}, {"buttons","unusableTint","bool"}, {"buttons","showGCD","bool"},
    {"buttons","readyGlow","bool"},
    {"buttons","minuteThreshold","int",60,180}, {"buttons","hourThreshold","int",3600,10800},
    {"buttons","cooldownFontSize","int",10,48}, {"buttons","keybindLabels","enum",{"off","slot","chord"}},
    {"highlight","style","enum",{"pixel","autocast","button","proc"}},
}
Config.SPEC = E
-- Look presets (LibSharedMedia keys + tints). Picking a border/background yourself switches to "custom".
Config.STYLES = {
    flat = {label = "Flat (default)", background = "Solid", border = "Blizzard Tooltip",
        tint = {0.04, 0.05, 0.07}, edge = {0.55, 0.57, 0.62}, header = {1, 1, 1, 0.07}},
    slate = {label = "Slate", background = "Blizzard Dialog Background Dark", border = "Blizzard Tooltip",
        tint = {0.62, 0.68, 0.85}, edge = {0.62, 0.65, 0.75}, header = {0, 0, 0, 0.55}},
    parchment = {label = "Parchment-lite", background = "Blizzard Parchment", border = "Blizzard Tooltip",
        tint = {0.55, 0.47, 0.36}, edge = {0.85, 0.70, 0.38}, header = {0.15, 0.10, 0.04, 0.6}},
    custom = {label = "Custom", tint = {0.62, 0.68, 0.85}, edge = {0.62, 0.65, 0.75}, header = {0, 0, 0, 0.55}},
}
local function member(list, v) for _, x in ipairs(list) do if x==v then return true end end end
local function valid(spec, v)
    local kind = spec[3]
    if kind=="bool" then return type(v)=="boolean" end
    if kind=="string" then return type(v)=="string" and v~="" and #v<=128 end
    if kind=="enum" then return member(spec[4], v) end
    if kind=="num" then return Core.number(v) and v>=spec[4] and v<=spec[5] end
    if kind=="int" then return Core.integer(v) and v>=spec[4] and v<=spec[5] end
    return false
end
local function default(section, key)
    return Config.defaults.profile[section][key]
end
local function clamp(spec, v)
    if (spec[3]=="num" or spec[3]=="int") and Core.number(v) then
        v = math.max(spec[4], math.min(spec[5], v))
        if spec[3]=="int" then v = math.floor(v + 0.5) end
        return v
    end
end
-- AceDB copies defaults INTO the saved tables at load (and strips them again at logout), so every
-- key normally exists. Repair works on stored values: out-of-range numbers are clamped, anything
-- else invalid is replaced by the default.
local plainCopy
local function defaultOf(section, key)
    local d = Config.defaults.profile[section]
    if key == nil then return plainCopy(d) end
    return plainCopy(d[key])
end
-- Visibility block: finite clamped numbers, enums, boolean condition set. Unknown condition IDs are dropped
-- (counted in Config.unknownConditions for diagnostics).
Config.unknownConditions = 0
function Config.cleanVisibility(profile)
    local d = Config.defaults.profile.bar.visibility
    local bar = profile.bar
    if type(rawget(bar, "visibility")) ~= "table" then bar.visibility = plainCopy(d) end
    local v = bar.visibility
    local function num(key, min, max, int)
        local x = rawget(v, key)
        if not Core.number(x) then x = d[key] end
        x = math.max(min, math.min(max, x))
        if int then x = math.floor(x + 0.5) end
        v[key] = x
    end
    if type(rawget(v, "enabled")) ~= "boolean" then v.enabled = d.enabled end
    if type(rawget(v, "hideWhenNone")) ~= "boolean" then v.hideWhenNone = d.hideWhenNone end
    num("baseAlpha", 0, 1); num("visibleAlpha", 0, 1)
    num("fadeIn", 0, 5); num("fadeOut", 0, 5); num("fadeDelay", 0, 10)
    num("mouseoverMargin", 0, 40, true); num("lowHealthPct", 1, 100, true)
    if v.baseAlpha > v.visibleAlpha then v.baseAlpha = v.visibleAlpha end
    if v.match ~= "ANY" and v.match ~= "ALL" then v.match = d.match end
    if v.modifier ~= "SHIFT" and v.modifier ~= "CTRL" and v.modifier ~= "ALT" then v.modifier = d.modifier end
    if type(rawget(v, "conditions")) ~= "table" then v.conditions = plainCopy(d.conditions) end
    local known = Config.CONDITION_IDS or {}
    Config.unknownConditions = 0
    for k, val in pairs(v.conditions) do
        if type(val) ~= "boolean" or not known[k] then
            if not known[k] then Config.unknownConditions = Config.unknownConditions + 1 end
            v.conditions[k] = nil
        end
    end
end
Config.CONDITION_IDS = {mouseover=true, target=true, hostileTarget=true, combat=true, noCombat=true, group=true,
    raid=true, instance=true, pvp=true, mounted=true, resting=true, flying=true, casting=true, lowHealth=true, modifier=true}

function Config.cleanProfile(profile)
    for _, section in ipairs({"general","bar","buttons","highlight"}) do
        if type(rawget(profile, section)) ~= "table" then profile[section] = defaultOf(section) end
    end
    for _, spec in ipairs(E) do
        local group = profile[spec[1]]
        local v = rawget(group, spec[2])
        if v == nil then group[spec[2]] = defaultOf(spec[1], spec[2])
        elseif not valid(spec, v) then
            local fixed = clamp(spec, v)
            if fixed == nil then fixed = defaultOf(spec[1], spec[2]) end
            group[spec[2]] = fixed
        end
    end
    local buttons = profile.buttons
    if buttons.hourThreshold <= buttons.minuteThreshold then
        buttons.minuteThreshold = defaultOf("buttons", "minuteThreshold")
        buttons.hourThreshold = defaultOf("buttons", "hourThreshold")
    end
    local hl = profile.highlight
    local c = rawget(hl, "color")
    local ok = type(c) == "table"
    if ok then for i=1,4 do if not (Core.number(c[i]) and c[i] >= 0 and c[i] <= 1) then ok = false end end end
    if not ok then hl.color = defaultOf("highlight", "color") end
    Config.cleanVisibility(profile)
    Core.ensurePages(profile)
    if type(profile.id)~="string" or profile.id=="" then profile.id = Config.newId() end
end
local function validPoint(p) return type(p)=="string" and ({CENTER=1,TOP=1,BOTTOM=1,LEFT=1,RIGHT=1,TOPLEFT=1,TOPRIGHT=1,BOTTOMLEFT=1,BOTTOMRIGHT=1})[p]~=nil end
function Config.cleanChar(char, pageCount)
    local d = Config.defaults.char
    local page = rawget(char, "currentPage")
    if not Core.integer(page) then page = 1 end
    char.currentPage = math.max(1, math.min(pageCount or 1, page))
    local pos = rawget(char, "barPosition")
    if type(pos)~="table" or not validPoint(pos.point) or not validPoint(pos.relativePoint)
        or not Core.number(pos.x) or not Core.number(pos.y) then
        char.barPosition = plainCopy(d.barPosition)
    else
        pos.x = math.max(-8000, math.min(8000, pos.x)); pos.y = math.max(-8000, math.min(8000, pos.y))
    end
    local mm = rawget(char, "minimap")
    if type(mm)~="table" then char.minimap = plainCopy(d.minimap) else
        if type(mm.hide)~="boolean" then mm.hide = d.minimap.hide end
        if not (Core.number(mm.minimapPos) and mm.minimapPos>=0 and mm.minimapPos<=360) then mm.minimapPos = d.minimap.minimapPos end
    end
    for _, key in ipairs({"nextKey","prevKey","homeKey"}) do
        local v = rawget(char, key)
        if type(v)~="string" or #v>64 then char[key] = "" end
    end
end
function Config.cleanGlobal(g)
    if type(rawget(g, "exportEnabled")) ~= "boolean" then g.exportEnabled = true end
    local d = Config.defaults.global.tutorial
    local t = rawget(g, "tutorial")
    if type(t) ~= "table" then g.tutorial = plainCopy(d); return end
    -- 0.3 builds stored {version, completed, dismissed}: dismissed means "hide popups". No version key:
    -- the tutorial state is never reset by updates.
    if type(t.hidePopups) ~= "boolean" then t.hidePopups = (t.dismissed == true) end
    if type(t.seen) ~= "boolean" then t.seen = (t.completed == true) or (t.dismissed == true) end
    if type(t.completed) ~= "boolean" then t.completed = false end
    t.version, t.dismissed = nil, nil
end

function Config.newId()
    -- Opaque random 128-bit token; no player or realm data and no global RNG reseeding.
    local parts = {}
    for i=1,8 do parts[i] = string.format("%04x", math.random(0,65535)) end
    return table.concat(parts, "-")
end

-- Plain deep copy of data (archive entries): booleans, strings, finite numbers, tables only.
plainCopy = function(value, depth)
    depth = depth or 0
    local kind = type(value)
    if kind=="string" or kind=="boolean" then return value end
    if kind=="number" then if Core.number(value) then return value end; return nil end
    if kind~="table" or depth>=6 then return nil end
    local out = {}
    for k, v in pairs(value) do
        if type(k)=="string" or Core.number(k) then
            local c = plainCopy(v, depth+1)
            if c ~= nil then out[k] = c end
        end
    end
    return out
end
Config.plainCopy = plainCopy

-- ACCOUNT migration (idempotent): moves schema-1 account data to a sanitized rollback archive and
-- removes the obsolete keys. sv is the StreonorDockDB table. Returns "future" for unknown schemas.
function Config.migrateAccount(sv, global)
    local version = sv.schemaVersion
    if Core.integer(version) and version > Config.SCHEMA then return "future" end
    if version == Config.SCHEMA then return "current" end
    local archive = {}
    for _, key in ipairs({"settings","cooldownLearned","probe","ui"}) do
        if sv[key] ~= nil then archive[key] = plainCopy(sv[key]); sv[key] = nil end
    end
    -- The old snapshot is regenerated from assignments; never reconstruct actions from it.
    sv.export = nil
    if next(archive) ~= nil then global.archive = global.archive or {}; global.archive.account = archive end
    sv.schemaVersion = Config.SCHEMA
    return "migrated"
end

-- CHARACTER migration (idempotent, once per character): legacy StreonorDockCharDB -> profile pages.
-- Readouts, revision and settings go to a sanitized rollback archive and never become slots.
function Config.migrateCharacter(legacy, profile, char, global)
    if type(legacy) ~= "table" then return false end
    if legacy.schemaVersion == Config.SCHEMA then return false end
    if Core.integer(legacy.schemaVersion) and legacy.schemaVersion > Config.SCHEMA then return "future" end
    if type(legacy.pages) == "table" then
        local record = plainCopy(legacy)
        local count = 1
        for i=1,10 do if type(legacy.pages[i]) == "table" then count = i end end
        profile.pageCount = count
        profile.pages = {}
        for i=1,count do
            local src = type(legacy.pages[i])=="table" and legacy.pages[i].slots or nil
            profile.pages[i] = Core.cleanPage(src)
        end
        if type(legacy.profileId)=="string" and legacy.profileId~="" and #legacy.profileId<=64 then
            profile.id = legacy.profileId
        end
        if Core.integer(legacy.currentPage) then char.currentPage = math.max(1, math.min(count, legacy.currentPage)) end
        legacy.pages, legacy.profileId, legacy.currentPage, legacy.revision = nil, nil, nil, nil
        legacy.archive = record
    end
    -- Compatible saved bar position (old panel was CENTER/CENTER-anchored only when so saved).
    local ui = global.archive and global.archive.account and global.archive.account.ui
    if type(ui)=="table" and ui.point=="CENTER" and ui.relativePoint=="CENTER"
        and Core.number(ui.x) and Core.number(ui.y) then
        char.barPosition = {point="CENTER", relativePoint="CENTER", x=ui.x, y=ui.y}
    end
    legacy.schemaVersion = Config.SCHEMA
    return true
end
