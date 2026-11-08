local addonName, ns = ...
-- Live display on the BAR buttons only (never exported to hardware): stack badge and an OmniCC-style
-- cooldown (dimmed remaining region, clockwise sweep revealing the elapsed region, big centred number:
-- seconds below 90 s, "2m" from 90 s, "2h" from 90 min). Combat-safe: only plain non-secure widgets and the
-- owned Cooldown frames are touched; secure attributes are never written here. Restricted (secret)
-- cooldown data is passed OPAQUELY to the widget and formatted natively; plain data is formatted by us
-- from one shared at-most-10 Hz ticker that runs only while a countdown is visible.
local Display = {}
ns.Display = Display
local Core, Game = ns.Core, ns.Game
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ticking = {}            -- button -> true while it owns a numeric countdown
local tickGeneration, tickRunning = 0, false
local pending, pendingFlags = false, {}
local TICK = 0.1

local function has(o, m) return o and type(o[m]) == "function" end
local function settings() return ns.profile and ns.profile.buttons end
local function fontPath()
    local m = _G.LibStub and LibStub("LibSharedMedia-3.0", true)
    local name = ns.profile and ns.profile.bar.font
    if m and name then
        local ok, path = pcall(m.Fetch, m, "font", name, true)
        if ok then return path end
    end
end

-- ------------------------------------------------------------------ per-button state
local function clearCooldown(b)
    if has(b.cooldown, "Clear") then b.cooldown:Clear() end
    if b.chargeCooldown and has(b.chargeCooldown, "Clear") then b.chargeCooldown:Clear() end
    b.timer:SetText("")
    b.cdActive, b.cdStart, b.cdDuration, b.cdUnavailable, b.cdNative = nil, nil, nil, nil, nil
    ticking[b] = nil
end
local function styleCooldown(b, dim)
    local s = settings()
    local cd = b.cooldown
    if has(cd, "SetDrawSwipe") then cd:SetDrawSwipe(s.cooldownSweep or s.cooldownGrayscale) end
    if has(cd, "SetDrawEdge") then cd:SetDrawEdge(false) end
    if has(cd, "SetReverse") then cd:SetReverse(false) end
    if has(cd, "SetSwipeTexture") then
        if dim and s.cooldownGrayscale then
            -- Dimmed remaining region: the icon itself, tinted grey, swept away clockwise from 12 o'clock.
            local icon = b.iconTexture
            cd:SetSwipeTexture(icon or WHITE)
            cd:SetSwipeColor(0.42, 0.42, 0.42, 0.95)
        else
            cd:SetSwipeTexture(WHITE)
            cd:SetSwipeColor(0, 0, 0, 0.55)
        end
    end
end
local function numbers(b, native)
    -- native=true: restricted values, the widget formats the countdown itself
    local s = settings()
    local show = s.cooldownNumbers and native
    if has(b.cooldown, "SetHideCountdownNumbers") then b.cooldown:SetHideCountdownNumbers(not show) end
    if b.chargeCooldown and has(b.chargeCooldown, "SetHideCountdownNumbers") then b.chargeCooldown:SetHideCountdownNumbers(true) end
end
local function applyFont(b)
    local s = settings()
    local path = fontPath()
    if has(b.timer, "SetFont") then
        local size = s.cooldownFontSize
        if path then b.timer:SetFont(path, size, "OUTLINE") else b.timer:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
    end
end

local function setBadge(b, text)
    b.count:SetText(text or "")
end
local function setZero(b, zero)
    b.icon:SetDesaturated(zero and true or false)
    b.icon:SetAlpha(zero and 0.55 or 1)
end

-- Our own number for a plain countdown; returns false when it has run out.
local function paint(b, now)
    local s = settings()
    if not now or not b.cdStart then return false end
    local remaining = b.cdStart + b.cdDuration - now
    if b.cdObject then
        local r = Game.ObjectRemaining(b.cdObject)
        if r then remaining = r end
    end
    local text = Core.formatRemaining(remaining, s.minuteThreshold, s.hourThreshold)
    if not text then return false end
    b.timer:SetText(s.cooldownNumbers and text or "")
    return true
end

-- ------------------------------------------------------------------ ticker (shared, only while active)
local function step()
    tickRunning = false
    if not Display.AnyTicking() then return end
    if not ns.Bar.IsShown() then
        for b in pairs(ticking) do ticking[b] = nil end   -- hidden bar: stop display work
        return
    end
    local s = settings()
    local now = Game.Now()
    local done = {}
    for b in pairs(ticking) do
        if not paint(b, now) then done[#done + 1] = b end
    end
    for _, b in ipairs(done) do
        ticking[b] = nil
        local wasActive = b.cdActive
        clearCooldown(b)
        if wasActive and s.readyGlow and ns.Glow and not ns.Assign.IsActive() then ns.Glow.Flash(b, 1.5) end
    end
    Display.ScheduleTick()
end
function Display.AnyTicking() return next(ticking) ~= nil end
function Display.ScheduleTick()
    if tickRunning or not Display.AnyTicking() then return end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    tickRunning = true
    local mine = tickGeneration
    C_Timer.After(TICK, function() if mine == tickGeneration then ns.Safe("display tick", step) else tickRunning = false end end)
end
function Display.Suspend()    -- bar hidden: drop everything
    tickGeneration = tickGeneration + 1
    tickRunning = false
    for b in pairs(ticking) do ticking[b] = nil end
end

-- ------------------------------------------------------------------ update
local function startNumeric(b, start, duration, dim)
    b.cdActive, b.cdStart, b.cdDuration, b.cdObject, b.cdNative = true, start, duration, nil, false
    styleCooldown(b, dim)
    numbers(b, false)
    b.cooldown:SetCooldown(start, duration)
    ticking[b] = true
    paint(b, Game.Now())
end
local function startObject(b, object, dim)
    b.cdActive, b.cdObject = true, object
    styleCooldown(b, dim)
    local remaining = Game.ObjectRemaining(object)
    if remaining ~= nil and remaining <= 0 then clearCooldown(b); return end
    if has(b.cooldown, "SetCooldownFromDurationObject") then
        b.cooldown:SetCooldownFromDurationObject(object)
    end
    if remaining ~= nil then
        -- readable: our formatting from the shared ticker
        b.cdStart, b.cdDuration, b.cdNative = (Game.Now() or 0), remaining, false
        numbers(b, false)
        ticking[b] = true
        paint(b, Game.Now())
    else
        b.cdNative = true          -- restricted: native countdown text, native sweep
        numbers(b, true)
    end
end

local function updateSpell(b, slot, s)
    local charges = Game.SpellCharges(slot.id)
    local cd = Game.SpellCooldown(slot.id, not s.showGCD)
    if charges then
        setBadge(b, s.stackCounts and tostring(charges.current) or "")
        setZero(b, false)
        if charges.current > 0 then
            -- usable: only the recharge sweep, never dimmed
            clearCooldown(b)
            if charges.object and has(b.chargeCooldown, "SetCooldownFromDurationObject") then
                b.chargeCooldown:SetCooldownFromDurationObject(charges.object)
                b.cdActive = true
            end
            return
        end
    else
        setBadge(b, "")
        setZero(b, false)
        if b.chargeCooldown and has(b.chargeCooldown, "Clear") then b.chargeCooldown:Clear() end
    end
    if cd.start ~= nil and cd.duration ~= nil and not cd.object then
        if cd.duration > 0 and cd.start > 0 and not (cd.onGCD and not s.showGCD) then startNumeric(b, cd.start, cd.duration, true)
        else clearCooldown(b) end
    elseif cd.object then
        if cd.onGCD and not s.showGCD then clearCooldown(b) else startObject(b, cd.object, true) end
    elseif cd.secret then
        clearCooldown(b)   -- restricted and no duration object: nothing safe to show
    else
        clearCooldown(b)
    end
end
local function updateItem(b, slot, s)
    local count = Game.ItemCount(slot.id)
    if s.stackCounts then setBadge(b, count == nil and "?" or tostring(count)) else setBadge(b, "") end
    setZero(b, count == 0)
    local cd = Game.ItemCooldown(slot.id)
    if cd.unavailable then
        clearCooldown(b)
        b.cdUnavailable = count ~= nil and count > 0
        return
    end
    if cd.duration > 0 and cd.start > 0 and not (cd.duration <= 1.5 and not s.showGCD) then
        -- Item cooldowns carry no GCD flag; a bare GCD blip is the shared game GCD, never an item timer.
        startNumeric(b, cd.start, cd.duration, true)
    else
        clearCooldown(b)
    end
end

function Display.UpdateButton(b, slot)
    local s = settings()
    if not s or not b then return end
    local wasTicking = ticking[b]
    local before = b.cdActive
    b.iconTexture = b.icon:GetTexture()
    clearCooldown(b)
    b.cdActive = nil
    if b.chargeCooldown and has(b.chargeCooldown, "Clear") then b.chargeCooldown:Clear() end
    if not slot or slot.kind == "empty" then setBadge(b, ""); setZero(b, false); return end
    applyFont(b)
    if slot.kind == "spell" then updateSpell(b, slot, s)
    elseif slot.kind == "item" then updateItem(b, slot, s) end
end
function Display.Refresh()
    if not ns.Bar or not ns.Bar.IsShown() then Display.Suspend(); return end
    local page = ns.CurrentPage()
    for i = 1, 15 do
        local b = ns.Bar.buttons[i]
        if b and b:IsShown() then Display.UpdateButton(b, page[i]) end
    end
    Display.ScheduleTick()
end

-- ------------------------------------------------------------------ event coalescing
local function flush()
    pending = false
    local flags = pendingFlags
    pendingFlags = {}
    if flags.cooldowns or flags.bags then ns.Safe("display refresh", Display.Refresh) end
end
local function mark(kind)
    pendingFlags[kind] = true
    if pending then return end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        pending = true
        C_Timer.After(0.05, function() flush() end)
    else
        flush()
    end
end
function Display.BagsChanged() mark("bags") end
function Display.CooldownsChanged() mark("cooldowns") end
