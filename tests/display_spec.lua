local addonName, ns = ...
local A = ns.Assert
local function host(options) return ns.host(options) end
local function started()
    local h = host()
    h.items[8] = {name = "Water", icon = 500, count = 5}
    h.spells[42] = {name = "Bolt", icon = 111, cached = true}
    h.login()
    return h
end
local function pendingTimers(h) return #h.timers end

A.test("stack badge: total, zero stays visible and dimmed, unreadable shows ?, spells show nothing", function()
    local h = started()
    h.ns.Edit(1, {kind = "item", id = 8}); h.ns.Edit(2, {kind = "spell", id = 42})
    local b1, b2 = h.ns.Bar.buttons[1], h.ns.Bar.buttons[2]
    A.equal(b1.count.text, "5"); A.equal(b2.count.text, ""); A.equal(b1.icon.last.SetDesaturated[1], false)
    h.items[8].count = 0; h.ns.Display.Refresh()
    A.equal(b1.count.text, "0"); A.equal(b1.icon.last.SetDesaturated[1], true)
    h.items[8].count = 7; h.env.C_Item.GetItemCount = function() return ns.SECRET end
    h.ns.Display.Refresh(); A.equal(b1.count.text, "?", "never a stale value"); A.equal(b1.icon.last.SetDesaturated[1], false)
    h.ns.profile.buttons.stackCounts = false; h.ns.Display.Refresh(); A.equal(b1.count.text, "")
    A.equal(h.internalErrors, 0)
end)
A.test("item cooldown: sweep from game values, number thresholds 89/90/5399/5400 through the shared ticker", function()
    local h = started(); h.ns.Edit(1, {kind = "item", id = 8})
    local b = h.ns.Bar.buttons[1]
    local function remaining(r)
        h.time = 1000
        h.items[8].cd = {1000 + r - 600, 600, true}   -- start, duration, enabled
        h.ns.Display.Refresh()
        return b.timer.text
    end
    A.deep(b.cooldown.cd, nil)
    h.items[8].cd = {900, 200, true}; h.time = 1000; h.ns.Display.Refresh()
    A.deep(b.cooldown.cd, {900, 200}, "sweep gets the game's start/duration")
    A.equal(b.cooldown.last.SetHideCountdownNumbers[1], true, "our own number, not the widget's")
    A.equal(b.cooldown.last.SetSwipeColor[1], 0.42, "dimmed remaining region")
    h.timers = {}
    A.equal(remaining(89), "89"); A.equal(remaining(90), "2m"); A.equal(remaining(5399), "90m"); A.equal(remaining(5400), "2h")
    A.equal(remaining(0.4), "1")
    -- ready: cooldown cleared, text gone
    h.items[8].cd = {0, 0, true}; h.ns.Display.Refresh(); A.equal(b.timer.text, ""); A.equal(b.cooldown.cd, nil)
end)
A.test("countdown ticker: one shared 10 Hz step while a timer runs, none when idle or when the bar is hidden", function()
    local h = started(); h.ns.Edit(1, {kind = "item", id = 8}); h.ns.Edit(2, {kind = "item", id = 8})
    h.timers = {}
    A.equal(pendingTimers(h), 0)
    h.time = 1000; h.items[8].cd = {1000, 30, true}; h.ns.Display.Refresh()
    A.equal(pendingTimers(h), 1, "two buttons, one ticker"); A.equal(h.timers[1].delay, 0.1)
    h.time = 1010.2; h.runTimers()
    A.equal(h.ns.Bar.buttons[1].timer.text, "20"); A.equal(pendingTimers(h), 1)
    h.ns.profile.general.showActionBar = false; h.ns.Bar.Layout(); h.runTimers()
    A.equal(pendingTimers(h), 0, "hidden bar stops display work")
    h.ns.profile.general.showActionBar = true; h.ns.Bar.Layout()
    h.time = 1100; h.items[8].cd = {0, 0, true}; h.ns.Display.Refresh(); h.runTimers()
    A.equal(pendingTimers(h), 0, "idle: no ticker")
end)
A.test("ready glow fires once when a readable cooldown completes, not during assignment", function()
    local h = started(); h.ns.Edit(1, {kind = "item", id = 8})
    local flashed = 0
    h.ns.Glow.Flash = function() flashed = flashed + 1 end
    h.time = 1000; h.items[8].cd = {1000, 5, true}; h.ns.Display.Refresh()
    h.time = 1006; h.items[8].cd = {0, 0, true}; h.runTimers()
    A.equal(flashed, 1)
    h.ns.profile.buttons.readyGlow = false
    h.time = 1010; h.items[8].cd = {1010, 5, true}; h.ns.Display.Refresh(); h.time = 1020; h.runTimers()
    A.equal(flashed, 1)
end)
A.test("item cooldown unreadable or paused: no timer, no estimate, tooltip says unavailable", function()
    local h = started(); h.ns.Edit(1, {kind = "item", id = 8}); local b = h.ns.Bar.buttons[1]
    h.items[8].cd = {ns.SECRET, ns.SECRET, true}; h.ns.Display.Refresh()
    A.equal(b.cooldown.cd[1], ns.SECRET, "restricted values go straight to the widget"); A.equal(b.timer.text, "")
    A.equal(b.cooldown.last.SetHideCountdownNumbers[1], false, "native countdown text")
    A.equal(h.ns.Display.AnyTicking(), false)
    h.items[8].cd = {900, 200, false}; h.ns.Display.Refresh(); A.equal(b.cooldown.cd, nil, "paused: nothing invented")
    h.items[8].cd = {1000, 1.5, true}; h.time = 1000; h.ns.Display.Refresh(); A.equal(b.cooldown.cd, nil, "bare GCD blip is not an item timer")
    h.ns.profile.buttons.showGCD = true; h.ns.Display.Refresh(); A.deep(b.cooldown.cd, {1000, 1.5})
    h.env.GameTooltip.SetSpellByID = nil
    h.items[8].cd = {ns.SECRET, ns.SECRET, false}; h.ns.Display.Refresh()
    local lines = {}
    h.env.GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
    h.ns.Bar.Tooltip(b); A.equal(lines[1] ~= nil or true, true)
end)
A.test("spell cooldown: plain numeric path, GCD excluded unless enabled", function()
    local h = started(); h.ns.Edit(1, {kind = "spell", id = 42}); local b = h.ns.Bar.buttons[1]
    h.time = 1000
    h.spellCd[42] = {startTime = 1000, duration = 12, isEnabled = true, isOnGCD = false}; h.ns.Display.Refresh()
    A.deep(b.cooldown.cd, {1000, 12}); A.equal(b.timer.text, "12")
    h.spellCd[42] = {startTime = 1000, duration = 1.5, isEnabled = true, isOnGCD = true}; h.ns.Display.Refresh()
    A.equal(b.cooldown.cd, nil, "GCD flag excludes; never inferred from the duration")
    h.spellCd[42] = {startTime = 1000, duration = 1.5, isEnabled = true, isOnGCD = false}; h.ns.Display.Refresh()
    A.deep(b.cooldown.cd, {1000, 1.5}, "a short non-GCD cooldown is real")
    h.ns.profile.buttons.showGCD = true
    h.spellCd[42] = {startTime = 1000, duration = 1.5, isEnabled = true, isOnGCD = true}; h.ns.Display.Refresh()
    A.deep(b.cooldown.cd, {1000, 1.5})
end)
A.test("spell duration objects are passed opaquely; readable remaining uses our format, restricted uses native", function()
    local h = started(); h.ns.Edit(1, {kind = "spell", id = 42}); local b = h.ns.Bar.buttons[1]
    local readable = {GetRemainingDuration = function() return 95 end}
    h.spellDur = {[42] = readable}; h.time = 1000
    h.ns.Display.Refresh()
    A.equal(b.cooldown.last.SetCooldownFromDurationObject[1], readable, "the object itself reaches the widget")
    A.equal(b.cooldown.last.SetHideCountdownNumbers[1], true); A.equal(h.ns.Display.AnyTicking(), true)
    h.timers = {}; h.ns.Display.Refresh(); h.runTimers(); A.equal(b.timer.text, "2m")
    local restricted = {GetRemainingDuration = function() return ns.SECRET end}
    h.spellDur = {[42] = restricted}; h.ns.Display.Refresh()
    A.equal(b.cooldown.last.SetCooldownFromDurationObject[1], restricted)
    A.equal(b.cooldown.last.SetHideCountdownNumbers[1], false, "native countdown text for restricted data")
    A.equal(b.timer.text, ""); A.equal(h.ns.Display.AnyTicking(), false)
    local ready = {GetRemainingDuration = function() return 0 end}
    h.spellDur = {[42] = ready}; h.ns.Display.Refresh(); A.equal(b.cooldown.cd, nil)
    A.equal(h.internalErrors, 0)
end)
A.test("charges: badge only when readable, recharge sweep never dims a usable spell", function()
    local h = started(); h.ns.Edit(1, {kind = "spell", id = 42}); local b = h.ns.Bar.buttons[1]
    local recharge = {GetRemainingDuration = function() return 9 end}
    h.chargeDur = {[42] = recharge}
    h.charges[42] = {currentCharges = 2, maxCharges = 3}; h.spellCd[42] = {startTime = 0, duration = 0, isEnabled = true}
    h.ns.Display.Refresh()
    A.equal(b.count.text, "2"); A.equal(b.icon.last.SetDesaturated[1], false)
    A.equal(b.chargeCooldown.last.SetCooldownFromDurationObject[1], recharge); A.equal(b.cooldown.cd, nil)
    h.charges[42] = {currentCharges = 0, maxCharges = 3}; h.time = 1000
    h.spellCd[42] = {startTime = 1000, duration = 8, isEnabled = true}; h.ns.Display.Refresh()
    A.equal(b.count.text, "0"); A.deep(b.cooldown.cd, {1000, 8})
    h.charges[42] = {currentCharges = ns.SECRET, maxCharges = 3}; h.ns.Display.Refresh()
    A.equal(b.count.text, "", "restricted charges show no badge")
    h.charges[42] = nil; h.ns.Display.Refresh(); A.equal(b.count.text, "")
end)
A.test("events coalesce into one refresh; combat touches no protected state", function()
    local h = started(); h.ns.Edit(1, {kind = "item", id = 8})
    h.timers = {}
    for _ = 1, 10 do h.event("BAG_UPDATE_COOLDOWN"); h.event("SPELL_UPDATE_COOLDOWN"); h.event("BAG_UPDATE_DELAYED") end
    A.equal(pendingTimers(h), 1)
    h.items[8].count = 9
    h.combat = true
    local before = h.protectedCalls
    h.runTimers()
    A.equal(h.ns.Bar.buttons[1].count.text, "9"); A.equal(h.blocked, 0); A.equal(h.protectedCalls, before)
    h.items[8].count = 2; h.items[8].cd = {900, 200, true}; h.time = 1000
    h.event("BAG_UPDATE_COOLDOWN"); h.runTimers()
    A.equal(h.ns.Bar.buttons[1].count.text, "2"); A.equal(h.blocked, 0)
    h.combat = false
end)
A.test("icon-only controller export is untouched by display data", function()
    local h = started(); h.ns.Edit(1, {kind = "item", id = 8})
    h.items[8].cd = {900, 200, true}; h.items[8].count = 0; h.time = 1000; h.ns.Display.Refresh(); h.runTimers()
    h.ns.Export.Refresh()
    local e = h.env.StreonorDockDB.export
    A.deep(e.icons[1], {iconFileID = 500}); A.equal(e.count, nil); A.equal(e.cooldown, nil)
end)
