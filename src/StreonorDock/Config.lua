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
            border="Blizzard Tooltip", background="Blizzard Dialog Background", font="Friz Quadrata TT",
            statusbar="Blizzard", visibility={}},
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
        tutorial = {version=1, completed=false, dismissed=false},
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
    {"bar","border","string"}, {"bar","background","string"}, {"bar","font","string"}, {"bar","statusbar","string"},
    {"buttons","stackCounts","bool"}, {"buttons","cooldownGrayscale","bool"}, {"buttons","cooldownSweep","bool"},
    {"buttons","cooldownNumbers","bool"}, {"buttons","tooltips","bool"}, {"buttons","pressedFlash","bool"},
    {"buttons","rangeTint","bool"}, {"buttons","unusableTint","bool"}, {"buttons","showGCD","bool"},
    {"buttons","readyGlow","bool"},
    {"buttons","minuteThreshold","int",60,180}, {"buttons","hourThreshold","int",3600,10800},
    {"buttons","cooldownFontSize","int",10,48}, {"buttons","keybindLabels","enum",{"off","slot","chord"}},
    {"highlight","style","enum",{"pixel","autocast","button","proc"}},
}
Config.SPEC = E
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
    if type(rawget(profile.bar, "visibility")) ~= "table" then profile.bar.visibility = {} end
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
    local t = rawget(g, "tutorial")
    if type(t)~="table" or type(t.completed)~="boolean" or type(t.dismissed)~="boolean" then
        g.tutorial = plainCopy(Config.defaults.global.tutorial)
    else t.version = 1 end
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
