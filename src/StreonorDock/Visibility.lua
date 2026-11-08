local addonName, ns = ...
-- Visibility conditions engine (ui-spec section 11). Picks the alpha of the ONE bar wrapper frame through
-- Bar.SetFadeAlpha; nothing here shows, hides, reparents or re-attributes a secure frame, so it is
-- combat-safe by construction (the wrapper SetAlpha itself is the one thing still to confirm in game).
-- Event driven: only the selected conditions' events are registered (plus the lifecycle events the addon
-- already handles). A light OnUpdate runs only while an alpha transition is in progress.
local V = {}
ns.Visibility = V
local Game = ns.Game
local issecret = Game.issecret
local plain = Game.plain

V.cache = {}            -- id -> true | false | nil(unknown)
V.hover = false
V.override = 0          -- tutorial override requests (visibleAlpha while > 0)
V.alpha = 1
local fader, shown, generation, inCombat = nil, nil, 0, false
local registered = {}   -- event -> true (dynamic ones we own)

local function settings() return ns.profile and ns.profile.bar.visibility end
local function boolean(v) v = plain(v); if v == true then return true elseif v == false then return false end end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    if issecret(a) then return nil, nil, true end
    return a, b
end

-- ------------------------------------------------------------------ predicates
-- eval returns true | false | nil (unknown or restricted). Never compares or coerces a secret.
local P = {}
P.mouseover = {label = "Mouseover", events = {}, eval = function() return V.hover end}
P.target = {label = "Has target", events = {"PLAYER_TARGET_CHANGED"}, eval = function()
    local exists, _, secret = call(_G.UnitExists, "target"); if secret then return nil end
    return boolean(exists) end}
P.hostileTarget = {label = "Has hostile target", events = {"PLAYER_TARGET_CHANGED", "UNIT_FACTION", "UNIT_FLAGS"}, eval = function()
    local exists, _, secret = call(_G.UnitExists, "target"); if secret then return nil end
    exists = boolean(exists); if exists == nil then return nil end
    if not exists then return false end
    local attack, _, s2 = call(_G.UnitCanAttack, "player", "target"); if s2 then return nil end
    return boolean(attack) end}
P.combat = {label = "In combat", events = {}, eval = function() return inCombat end}
P.noCombat = {label = "Out of combat", events = {}, eval = function() return not inCombat end}
P.group = {label = "In group", events = {"GROUP_ROSTER_UPDATE"}, eval = function()
    local v, _, s = call(_G.IsInGroup); if s then return nil end; return boolean(v) end}
P.raid = {label = "In raid", events = {"GROUP_ROSTER_UPDATE"}, eval = function()
    local v, _, s = call(_G.IsInRaid); if s then return nil end; return boolean(v) end}
P.instance = {label = "In instance", events = {"ZONE_CHANGED_NEW_AREA"}, eval = function()
    local v, _, s = call(_G.IsInInstance); if s then return nil end; return boolean(v) end}
P.pvp = {label = "In PvP", events = {"ZONE_CHANGED_NEW_AREA", "PLAYER_FLAGS_CHANGED", "UNIT_FACTION", "UPDATE_BATTLEFIELD_STATUS"}, eval = function()
    local inst, instType, s1 = call(_G.IsInInstance)
    if s1 then return nil end
    instType = plain(instType)
    if instType == "pvp" or instType == "arena" then return true end
    local flagged, _, s2 = call(_G.UnitIsPVP, "player"); if s2 then return nil end
    return boolean(flagged) end}
P.mounted = {label = "Mounted", events = {"PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_AURA"}, eval = function()
    local v, _, s = call(_G.IsMounted); if s then return nil end; return boolean(v) end}
P.resting = {label = "Resting", events = {"PLAYER_UPDATE_RESTING"}, eval = function()
    local v, _, s = call(_G.IsResting); if s then return nil end; return boolean(v) end}
-- No dedicated takeoff/landing event is known on Forever (EnhanceQoL just calls IsFlying on demand), so this
-- re-reads on mount/aura/control/zone events and may lag a transition. See Diagnostics.
P.flying = {label = "Flying (best effort)", events = {"PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_AURA", "PLAYER_CONTROL_GAINED",
    "PLAYER_CONTROL_LOST", "ZONE_CHANGED_NEW_AREA", "PLAYER_CAN_GLIDE_CHANGED", "PLAYER_IS_GLIDING_CHANGED"}, eval = function()
    local v, _, s = call(_G.IsFlying); if s then return nil end; return boolean(v) end}
P.casting = {label = "Casting", events = {"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP"}, eval = function()
    local cast, _, s1 = call(_G.UnitCastingInfo, "player"); if s1 then return nil end
    if plain(cast) ~= nil then return true end
    local chan, _, s2 = call(_G.UnitChannelInfo, "player"); if s2 then return nil end
    return plain(chan) ~= nil end}
P.lowHealth = {label = "Low health", events = {"UNIT_HEALTH", "UNIT_MAXHEALTH"}, eval = function()
    local hp, _, s1 = call(_G.UnitHealth, "player"); if s1 then return nil end
    local max, _, s2 = call(_G.UnitHealthMax, "player"); if s2 then return nil end
    hp, max = plain(hp), plain(max)
    if type(hp) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
    local v = settings()
    return hp / max < (v and v.lowHealthPct or 30) / 100 end}
P.modifier = {label = "Modifier key held", events = {"MODIFIER_STATE_CHANGED"}, eval = function()
    local v = settings()
    local fn = v and ({SHIFT = _G.IsShiftKeyDown, CTRL = _G.IsControlKeyDown, ALT = _G.IsAltKeyDown})[v.modifier]
    local r, _, s = call(fn); if s then return nil end; return boolean(r) end}
V.PREDICATES = P
-- Deterministic display order for the checklist and its summary.
V.ORDER = {"mouseover", "combat", "noCombat", "target", "hostileTarget", "group", "raid", "instance", "pvp", "mounted",
    "resting", "flying", "casting", "lowHealth", "modifier"}
local PLAYER_EVENT_UNITS = {UNIT_AURA = "player", UNIT_HEALTH = "player", UNIT_MAXHEALTH = "player", UNIT_FLAGS = false,
    UNIT_FACTION = false, UNIT_SPELLCAST_START = "player", UNIT_SPELLCAST_STOP = "player", UNIT_SPELLCAST_FAILED = "player",
    UNIT_SPELLCAST_INTERRUPTED = "player", UNIT_SPELLCAST_DELAYED = "player", UNIT_SPELLCAST_CHANNEL_START = "player",
    UNIT_SPELLCAST_CHANNEL_UPDATE = "player", UNIT_SPELLCAST_CHANNEL_STOP = "player"}

function V.Selected()
    local v, list = settings(), {}
    if not v then return list end
    for _, id in ipairs(V.ORDER) do if v.conditions[id] == true and P[id] then list[#list + 1] = id end end
    return list
end
function V.Summary()
    local sel = V.Selected()
    local names = {}
    for _, id in ipairs(sel) do names[#names + 1] = P[id].label end
    if #sel == 0 then return "No conditions: always visible" end
    return #sel .. " condition" .. (#sel == 1 and "" or "s") .. ": " .. table.concat(names, ", ")
end

-- ------------------------------------------------------------------ aggregate
-- Returns true (show at visible alpha) | false (fade to base / zero). Unknown without a conclusive
-- result keeps the bar visible; an empty selection is always visible.
function V.Aggregate()
    local v = settings()
    local sel = V.Selected()
    if #sel == 0 then return true end
    local anyTrue, anyFalse, anyUnknown = false, false, false
    for _, id in ipairs(sel) do
        local r = V.cache[id]
        if r == true then anyTrue = true elseif r == false then anyFalse = true else anyUnknown = true end
    end
    if v.match == "ALL" then
        if anyFalse then return false end
        return true             -- all true, or unknown without a false: stay visible
    end
    if anyTrue then return true end
    if anyUnknown then return true end
    return false
end
function V.Forced()
    if V.override > 0 then return true end
    return ns.Assign and ns.Assign.IsActive and ns.Assign.IsActive() or false
end

-- ------------------------------------------------------------------ fader
local function setAlpha(a)
    V.alpha = a
    if ns.Bar then ns.Bar.SetFadeAlpha(a) end
end
local function stopFade() if fader then fader:SetScript("OnUpdate", nil) end; V.fading = false end
local function startFade(to, duration)
    if duration <= 0 or math.abs(to - V.alpha) < 0.001 then stopFade(); setAlpha(to); return end
    if not fader then fader = CreateFrame("Frame", "StreonorDockFader") end
    local from, elapsed = V.alpha, 0
    V.fading = true
    fader:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= duration then stopFade(); setAlpha(to) else setAlpha(from + (to - from) * elapsed / duration) end
    end)
end
local function fadedTarget(v) return v.hideWhenNone and 0 or v.baseAlpha end

-- Re-evaluates the aggregate and drives the fader. immediate: no animation (profile switch, login).
function V.Apply(immediate)
    local v = settings()
    if not v or not ns.Bar then return end
    if not v.enabled then generation = generation + 1; stopFade(); shown = nil; setAlpha(1); return end
    local show = V.Forced() or V.Aggregate()
    if V.Forced() then immediate = true end
    if immediate then
        generation = generation + 1
        shown = show
        stopFade(); setAlpha(show and v.visibleAlpha or fadedTarget(v))
        return
    end
    if show == shown then return end     -- repeated identical result: no restart
    shown = show
    generation = generation + 1
    if show then
        startFade(v.visibleAlpha, v.fadeIn)
    else
        local mine = generation
        local function go() if mine == generation then startFade(fadedTarget(v), v.fadeOut) end end
        if v.fadeDelay > 0 and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(v.fadeDelay, go)
        else go() end
    end
end

-- ------------------------------------------------------------------ evaluation + events
function V.EvaluateAll()
    for _, id in ipairs(V.Selected()) do V.cache[id] = P[id].eval() end
end
function V.Reseed(immediate)
    if not settings() then return end
    inCombat = InCombatLockdown() and true or false
    V.cache = {}
    V.Sync()
    V.EvaluateAll()
    V.Apply(immediate == true)
end
local pendingEval = false
local function coalesce()
    if pendingEval then return end
    pendingEval = true
    local function run() pendingEval = false; V.EvaluateAll(); V.Apply(false) end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(0, run) else run() end
end
function V.OnEvent(event, unit)
    local want = PLAYER_EVENT_UNITS[event]
    if want ~= nil then
        if want == false then if unit ~= "player" and unit ~= "target" then return end
        elseif issecret(unit) or unit ~= want then return end
    end
    coalesce()
end
local function handler(event, ...) V.OnEvent(event, ...) end
function V.CombatChanged(entering)
    inCombat = entering and true or false
    V.cache.combat, V.cache.noCombat = inCombat, not inCombat
    V.Apply(false)
end
function V.SetHover(isHovered)
    if V.hover == isHovered then return end
    V.hover = isHovered
    local v = settings()
    if v and v.conditions.mouseover then V.cache.mouseover = isHovered; V.Apply(false) end
end
function V.PushOverride() V.override = V.override + 1; V.Apply(true) end
function V.PopOverride() V.override = math.max(0, V.override - 1); V.Apply(true) end
-- Assignment mode entering/leaving, called by Assign.
function V.PolicyChanged() V.Apply(V.Forced()) end

-- Registers exactly the events the selected conditions need.
function V.Sync()
    local needed = {}
    for _, id in ipairs(V.Selected()) do
        for _, event in ipairs(P[id].events) do needed[event] = true end
    end
    for event in pairs(registered) do
        if not needed[event] then ns.UnregisterEvent(event); registered[event] = nil end
    end
    for event in pairs(needed) do
        if not registered[event] then
            if ns.RegisterEvent(event, handler) then registered[event] = true else V.missing = V.missing or {}; V.missing[event] = true end
        end
    end
end
-- Called by the settings UI after any change.
function V.SettingsChanged()
    local v = settings()
    if v.baseAlpha > v.visibleAlpha then v.baseAlpha = v.visibleAlpha end
    V.Reseed(true)
    if ns.Bar and ns.Bar.UpdateHover then ns.Bar.UpdateHover() end
end
function V.RegisteredEvents()
    local list = {}
    for event in pairs(registered) do list[#list + 1] = event end
    table.sort(list)
    return list
end
