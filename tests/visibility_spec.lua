local addonName, ns = ...
local A = ns.Assert
local function host(options) return ns.host(options) end
local function started(patch)
    local h = host(); h.login()
    local v = h.ns.profile.bar.visibility
    for k, val in pairs(patch or {}) do v[k] = val end
    h.ns.Visibility.SettingsChanged()
    return h, v
end
local function conditions(h, list)
    local c = h.ns.profile.bar.visibility.conditions
    for k in pairs(c) do c[k] = nil end
    for _, id in ipairs(list) do c[id] = true end
    h.ns.Visibility.SettingsChanged()
end
local function alpha(h) return h.ns.Bar.wrapper.alpha end
local function flush0(h)   -- runs only the zero-delay (coalescing) timers
    local keep = {}
    local list = h.timers; h.timers = {}
    for _, t in ipairs(list) do if t.delay == 0 then t.fn() else keep[#keep + 1] = t end end
    for _, t in ipairs(keep) do h.timers[#h.timers + 1] = t end
end
-- Runs every pending C_Timer and the fader OnUpdate to completion.
local function settle(h)
    h.runTimers()
    local fader = h.named("StreonorDockFader")
    if fader and fader.scripts.OnUpdate then fader.scripts.OnUpdate(fader, 10) end
end

A.test("defaults: 35% base, 100% visible, ANY of mouseover/combat/target; faded at login with nothing true", function()
    local h = started()
    local v = h.ns.profile.bar.visibility
    A.equal(v.baseAlpha, 0.35); A.equal(v.visibleAlpha, 1); A.equal(v.fadeIn, 0.15); A.equal(v.fadeOut, 0.30); A.equal(v.fadeDelay, 0.5)
    A.equal(v.match, "ANY"); A.equal(v.hideWhenNone, false)
    A.equal(alpha(h), 0.35)
    A.equal(h.ns.Visibility.Summary(), "3 conditions: Mouseover, In combat, Has target")
end)
A.test("ANY / ALL / empty / contradictory / unknown aggregate rules", function()
    local h = started({fadeDelay = 0, fadeIn = 0, fadeOut = 0})
    conditions(h, {}); A.equal(alpha(h), 1, "empty set is always visible")
    conditions(h, {"combat", "noCombat"}); A.equal(alpha(h), 1, "ANY combat+noCombat is always true")
    local v = h.ns.profile.bar.visibility; v.match = "ALL"; h.ns.Visibility.SettingsChanged()
    A.equal(alpha(h), 0.35, "ALL combat+noCombat is impossible: faded")
    conditions(h, {"group", "raid"}); v.match = "ALL"; h.state.group = true; h.ns.Visibility.SettingsChanged()
    A.equal(alpha(h), 0.35, "one false condition fades under ALL")
    h.state.raid = true; h.ns.Visibility.SettingsChanged(); A.equal(alpha(h), 1)
    v.match = "ANY"; h.state.group, h.state.raid = false, false; h.ns.Visibility.SettingsChanged(); A.equal(alpha(h), 0.35)
    -- unknown: restricted value keeps the bar visible
    conditions(h, {"lowHealth"}); h.env.UnitHealth = function() return ns.SECRET end
    h.ns.Visibility.SettingsChanged(); A.equal(alpha(h), 1, "unreadable stays visible, never compared")
    h.env.UnitHealth = function() return 100 end
    h.ns.Visibility.SettingsChanged(); A.equal(alpha(h), 0.35)
    v.hideWhenNone = true; h.ns.Visibility.SettingsChanged(); A.equal(alpha(h), 0, "hide completely when none true")
    v.enabled = false; h.ns.Visibility.SettingsChanged(); A.equal(alpha(h), 1)
end)
A.test("every condition against its API, with threshold boundaries", function()
    local h = started({fadeDelay = 0, fadeIn = 0, fadeOut = 0})
    local function check(id, key, value, expectVisible)
        conditions(h, {id}); h.state[key] = value
        h.ns.Visibility.SettingsChanged()
        A.equal(alpha(h) == 1, expectVisible, id .. " " .. tostring(value))
    end
    check("target", "exists", true, true); check("target", "exists", false, false)
    h.state.exists = true; check("hostileTarget", "hostile", true, true); check("hostileTarget", "hostile", false, false)
    h.state.exists = false; check("hostileTarget", "hostile", true, false)
    check("group", "group", true, true); check("raid", "raid", true, true); check("raid", "raid", false, false)
    check("instance", "instance", true, true); check("instance", "instance", false, false)
    h.state.instance = false; check("pvp", "instanceType", "arena", true)
    h.state.instance = true; check("pvp", "instanceType", "pvp", true); check("pvp", "instanceType", "none", false)
    check("pvp", "pvpflag", true, true); h.state.pvpflag = false
    check("mounted", "mounted", true, true); check("resting", "resting", true, true); check("flying", "flying", true, true)
    check("casting", "casting", "Bolt", true); h.state.casting = nil; check("casting", "channel", "Drain", true); check("casting", "channel", nil, false)
    h.state.hp, h.state.hpmax = 29, 100; conditions(h, {"lowHealth"}); A.equal(alpha(h), 1, "29% is below 30%")
    h.state.hp = 30; h.ns.Visibility.SettingsChanged(); A.equal(alpha(h), 0.35, "strictly below")
    h.state.hpmax = 0; h.ns.Visibility.SettingsChanged(); A.equal(alpha(h), 1, "max 0: unknown, visible")
    h.state.shift, h.state.alt = true, false; conditions(h, {"modifier"}); A.equal(alpha(h), 1)
    h.ns.profile.bar.visibility.modifier = "ALT"; h.ns.Visibility.SettingsChanged(); A.equal(alpha(h), 0.35)
end)
A.test("events drive re-evaluation; only selected conditions' events are registered", function()
    local h = started({fadeDelay = 0, fadeIn = 0, fadeOut = 0})
    local frame = h.eventFrame
    conditions(h, {"target"})
    A.equal(frame.events.PLAYER_TARGET_CHANGED, true); A.equal(frame.events.GROUP_ROSTER_UPDATE, nil); A.equal(frame.events.UNIT_HEALTH, nil)
    A.deep(h.ns.Visibility.RegisteredEvents(), {"PLAYER_TARGET_CHANGED"})
    A.equal(alpha(h), 0.35)
    h.state.exists = true; h.event("PLAYER_TARGET_CHANGED"); settle(h); A.equal(alpha(h), 1)
    h.state.exists = false; h.event("PLAYER_TARGET_CHANGED"); settle(h); A.equal(alpha(h), 0.35)
    h.state.hp = 100
    conditions(h, {"lowHealth"})
    A.equal(frame.events.PLAYER_TARGET_CHANGED, nil, "unselected events are unregistered")
    h.state.hp = 10; h.event("UNIT_HEALTH", "target"); settle(h); A.equal(alpha(h), 0.35, "other units are filtered out")
    h.event("UNIT_HEALTH", "player"); settle(h); A.equal(alpha(h), 1)
    h.event("UNIT_HEALTH", ns.SECRET); settle(h)
    A.equal(h.internalErrors, 0)
end)
A.test("combat condition follows regen events and never touches secure state", function()
    local h = started({fadeDelay = 0, fadeIn = 0, fadeOut = 0})
    conditions(h, {"combat"}); A.equal(alpha(h), 0.35)
    h.combat = true; h.event("PLAYER_REGEN_DISABLED"); A.equal(alpha(h), 1)
    A.equal(h.blocked, 0)
    h.combat = false; h.event("PLAYER_REGEN_ENABLED"); A.equal(alpha(h), 0.35)
    local before = h.protectedCalls
    h.combat = true; h.event("PLAYER_REGEN_DISABLED"); h.state.exists = true; h.event("PLAYER_TARGET_CHANGED"); settle(h)
    A.equal(h.blocked, 0); A.equal(h.protectedCalls, before)
    for i = 1, 15 do A.equal(h.button(i).attrs["*type1"], nil) end
    h.combat = false
end)
A.test("mouseover raises alpha only when Mouseover is selected", function()
    local h = started({fadeDelay = 0, fadeIn = 0, fadeOut = 0})
    conditions(h, {"combat"})
    h.fire(h.ns.Bar.buttons[1], "OnEnter"); A.equal(h.ns.Bar.IsHovered(), true); A.equal(alpha(h), 0.35, "not selected: hover does not raise alpha")
    h.hoverAll = false; h.fire(h.ns.Bar.buttons[1], "OnLeave"); h.runTimers()
    conditions(h, {"mouseover", "combat"})
    h.fire(h.ns.Bar.buttons[1], "OnEnter"); A.equal(alpha(h), 1)
    h.fire(h.ns.Bar.buttons[1], "OnLeave"); h.runTimers(); A.equal(alpha(h), 0.35)
    h.ns.profile.bar.visibility.mouseoverMargin = 0; h.ns.Visibility.SettingsChanged()
end)
A.test("fader: delay before fade-out, smooth reverse from the current alpha, repeated events do not restart", function()
    local h = started({fadeDelay = 0.5, fadeIn = 1, fadeOut = 2})
    conditions(h, {"target"}); settle(h)
    A.equal(alpha(h), 0.35)
    h.state.exists = true; h.event("PLAYER_TARGET_CHANGED"); flush0(h)
    local fader = h.named("StreonorDockFader")
    fader.scripts.OnUpdate(fader, 0.5); A.equal(math.abs(alpha(h) - 0.675) < 1e-6, true, "halfway through the fade-in")
    local function delays() local n = 0; for _, t in ipairs(h.timers) do if t.delay == 0.5 then n = n + 1 end end; return n end
    h.state.exists = false; h.event("PLAYER_TARGET_CHANGED"); flush0(h)
    A.equal(delays(), 1)
    h.event("PLAYER_TARGET_CHANGED"); flush0(h)
    A.equal(delays(), 1, "same result again does not restart the delay")
    -- the target returns during the delay: fade-in resumes from where it is, the delayed fade-out is cancelled
    h.state.exists = true; h.event("PLAYER_TARGET_CHANGED"); flush0(h)
    h.runTimers()   -- the stale delay callback fires and must do nothing
    fader = h.named("StreonorDockFader"); fader.scripts.OnUpdate(fader, 5)
    A.equal(alpha(h), 1)
    A.equal(fader.scripts.OnUpdate, nil, "OnUpdate removed when the transition ends")
end)
A.test("zero durations apply immediately; fade-out waits for the delay then runs", function()
    local h = started({fadeDelay = 0.4, fadeIn = 0, fadeOut = 0.3})
    conditions(h, {"target"}); h.state.exists = true; h.event("PLAYER_TARGET_CHANGED"); settle(h); A.equal(alpha(h), 1)
    h.state.exists = false; h.event("PLAYER_TARGET_CHANGED"); h.runTimers()
    A.equal(alpha(h), 1, "still waiting out the delay")
    for _, t in ipairs(h.timers) do if t.delay == 0.4 then t.fn() end end
    local fader = h.named("StreonorDockFader"); fader.scripts.OnUpdate(fader, 0.15)
    A.equal(math.abs(alpha(h) - 0.675) < 1e-6, true)
    fader.scripts.OnUpdate(fader, 0.2); A.equal(alpha(h), 0.35)
end)
A.test("assignment mode forces full visibility and cancels pending fades; lock recomputes", function()
    local h = started({fadeDelay = 0.5})
    conditions(h, {"target"}); settle(h); A.equal(alpha(h), 0.35)
    h.ns.Assign.Unlock(); A.equal(alpha(h), 1)
    h.state.exists = false; h.event("PLAYER_TARGET_CHANGED"); settle(h); A.equal(alpha(h), 1)
    h.ns.Assign.Lock(); settle(h); A.equal(alpha(h), 0.35)
    h.ns.Visibility.PushOverride(); A.equal(alpha(h), 1); h.ns.Visibility.PopOverride(); A.equal(alpha(h), 0.35)
end)
A.test("profile switch reseeds against the new configuration", function()
    local h = started({fadeDelay = 0, fadeIn = 0, fadeOut = 0})
    conditions(h, {"target"}); A.equal(alpha(h), 0.35)
    h.ns.db:SetProfile("Second")
    A.equal(h.ns.profile.bar.visibility.baseAlpha, 0.35)
    A.equal(alpha(h), 0.35)
    h.state.exists = true; h.event("PLAYER_ENTERING_WORLD"); settle(h); A.equal(alpha(h), 1, "world entry reseeds")
end)
A.test("visibility values are validated and base never exceeds visible", function()
    local h = host({db = {profiles = {["Tester - TestRealm"] = {bar = {visibility = {baseAlpha = 5, visibleAlpha = 0.5, fadeIn = -3,
        match = "XOR", modifier = "WIN", conditions = {mouseover = true, bogus = true, combat = "yes"}, lowHealthPct = 500}}}},
        profileKeys = {["Tester - TestRealm"] = "Tester - TestRealm"}}})
    h.login()
    local v = h.ns.profile.bar.visibility
    A.equal(v.baseAlpha, 0.5); A.equal(v.visibleAlpha, 0.5); A.equal(v.fadeIn, 0); A.equal(v.match, "ANY"); A.equal(v.modifier, "SHIFT")
    A.equal(v.lowHealthPct, 100); A.equal(v.conditions.bogus, nil); A.equal(v.conditions.combat, nil)
    A.equal(h.ns.Config.unknownConditions >= 1, true)
    local page = h.ns.Options.Build().args.bar.args.visibility.args
    page.base.set(nil, 0.9); A.equal(v.baseAlpha, 0.5, "base clamped to visible")
    page.visible.set(nil, 0.3); A.equal(v.baseAlpha, 0.3); A.equal(v.visibleAlpha, 0.3)
    page.conditions.set(nil, "combat", true); A.equal(v.conditions.combat, true)
    A.equal(page.conditions.get(nil, "combat"), true)
    A.equal(page.summary.name():find("In combat") ~= nil, true)
    A.equal(page.none.desc:find("Invisible buttons can still receive clicks") ~= nil, true)
end)
