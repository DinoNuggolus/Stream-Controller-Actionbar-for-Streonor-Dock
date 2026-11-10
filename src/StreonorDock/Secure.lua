local addonName, ns = ...
-- 15 persistent SecureActionButtonTemplate buttons StreonorDockSlot1..15, declared in Slots.xml
-- (no parent, size or anchor: they exist even after a /reload in combat and keep working while the
-- bar is hidden, faded or in assignment mode). They are fired by temporary override bindings
-- (SetOverrideBindingClick) on the fixed ALT-CTRL-SHIFT chords. "*"-prefixed type/spell/item
-- attributes only: no secure snippets, no SetBinding/SaveBindings anywhere, nothing written to
-- Blizzard frames. Every attribute, click registration and binding change happens OUT OF COMBAT;
-- in combat the work is queued once and runs on PLAYER_REGEN_ENABLED.
-- The visible bar buttons (Bar.lua) are SEPARATE secure targets that share the same attribute plan
-- through Secure.WriteSlot.
local Secure = {}
ns.Secure = Secure
local buttons = {}
local owner
Secure.buttons = buttons
Secure.status = {ready=false, template=nil, bindings="not applied", applied=0, verified=nil,
    keyDown=nil, conflicts=0, lastError=nil, writes=0}
local queued = false
local appliedKeyDown = nil
local function issecret(v) return ns.Game.issecret(v) end
local function plainString(v) if not issecret(v) and type(v)=="string" then return v end end

function Secure.ButtonName(index) return "StreonorDockSlot" .. index end
function Secure.ClickAction(index) return "CLICK " .. Secure.ButtonName(index) .. ":LeftButton" end

-- ONE PRESS = ONE USE ATTEMPT. Keys act on the DOWN edge only: the buttons register AnyDown (never
-- AnyUp) and carry useOnKeyDown=true whatever the ActionButtonUseKeyDown CVar says. If the client
-- still delivers an UP click to the secure handler, PreClick makes it inert where that is possible:
-- out of combat the action type is cleared for that one click and restored in PostClick. In combat
-- attributes cannot be written, so there the guard relies on registration only (unverified on
-- Forever). Per-slot edge counters feed /sdock clicks. Counters are input-routing evidence, never
-- proof that a spell or item was used.
Secure.clicks = {}
for i=1,15 do Secure.clicks[i] = {down=0, up=0, attempts=0} end
function Secure.ResetClicks() for i=1,15 do Secure.clicks[i] = {down=0, up=0, attempts=0} end end
local function preClick(self, mouse, down)
    ns.Safe("preclick", function()
        local counter = Secure.clicks[self.streonorIndex or 0]
        if not counter then return end
        if down==false then
            counter.up = counter.up + 1
            if not InCombatLockdown() and self:GetAttribute("*type1") then
                self.streonorSuppressed = self:GetAttribute("*type1")
                self:SetAttribute("*type1", nil)
            end
        else
            counter.down = counter.down + 1
            if self:GetAttribute("*type1") then counter.attempts = counter.attempts + 1 end
        end
    end)
end
local function restoreType(self)
    local saved = self.streonorSuppressed
    if saved==nil then return end
    if InCombatLockdown() then
        ns.RunOutOfCombat(function() self:SetAttribute("*type1", saved); self.streonorSuppressed = nil end)
    else
        self:SetAttribute("*type1", saved); self.streonorSuppressed = nil
    end
end
local function postClick(self, mouse, down)
    -- Insecure PostClick on our own button, after the secure handler. Restores the type cleared
    -- for an inert up edge. It never acts on gameplay and starts no timer or estimate.
    ns.Safe("postclick", restoreType, self)
end
-- Shared by chord targets and visible bar buttons.
function Secure.Hook(button, index)
    if button.streonorHooked then return end
    button.streonorIndex = index
    button.streonorHooked = true
    button:SetScript("PreClick", preClick)
    button:SetScript("PostClick", postClick)
end
-- Always the DOWN edge for a button: AnyDown + useOnKeyDown. Caller guarantees out of combat.
function Secure.SetDown(button)
    button:SetAttribute("useOnKeyDown", true)
    button:RegisterForClicks("AnyDown")
    Secure.status.writes = Secure.status.writes + 2
end

-- Writes the attribute plan for one slot onto one secure button where it differs from what was last
-- applied; every key of the plan is set or cleared, so no stale attribute survives a kind change.
-- Caller guarantees out of combat. Returns whether anything was written.
function Secure.WriteSlot(button, slot)
    local name
    if type(slot)=="table" and slot.kind=="spell" and not slot.pinned then
        name = plainString((ns.Game.SpellMeta(slot.id)))
    end
    local macroIndex
    if type(slot)=="table" and slot.kind=="macro" then macroIndex = ns.Game.MacroIndex(slot.name, slot.scope) end
    local plan = ns.Core.secureAttributes(slot, name, macroIndex)
    local last = button.streonorApplied or {}
    local changed = false
    for _, key in ipairs(ns.Core.SECURE_KEYS) do
        if (plan[key] or nil)~=last[key] then changed = true end
    end
    if changed then
        -- Clear the type first so no mix of old and new attributes is ever actionable.
        button:SetAttribute("*type1", nil)
        for _, key in ipairs(ns.Core.SECURE_KEYS) do
            if key~="*type1" then button:SetAttribute(key, plan[key] or nil) end
        end
        if plan["*type1"] then button:SetAttribute("*type1", plan["*type1"]) end
        local record = {}
        for _, key in ipairs(ns.Core.SECURE_KEYS) do record[key] = plan[key] or nil end
        button.streonorApplied = record
        Secure.status.writes = Secure.status.writes + 4
    end
    button.streonorKind = plan["*type1"] or nil
    button.streonorID = plan["*type1"] and slot.id or nil
    return changed
end

-- Collects the XML-declared buttons (fallback: create parentless ones) and the binding owner.
-- Callers guarantee we are out of combat (applyAll checks first).
local function init()
    if Secure.status.ready then return true end
    owner = owner or CreateFrame("Frame", "StreonorDockBindingOwner")
    for i=1,15 do
        local button = buttons[i] or _G[Secure.ButtonName(i)]
        if type(button)~="table" then
            local ok, made = pcall(CreateFrame, "Button", Secure.ButtonName(i), nil, "SecureActionButtonTemplate")
            button = ok and made or nil
        end
        if not button then
            Secure.status.template = "unavailable"
            Secure.status.lastError = "SecureActionButtonTemplate button " .. i .. " missing"
            return false
        end
        Secure.Hook(button, i)
        buttons[i] = button
    end
    Secure.status.template = "available"
    Secure.status.ready = true
    return true
end

-- Always the DOWN edge. The ActionButtonUseKeyDown CVar is only read for /sdock probe: following it
-- (AnyUp when it is off) is a second edge policy we do not want.
function Secure.ApplyClickDirection()
    if appliedKeyDown~=true then
        for i=1,15 do Secure.SetDown(buttons[i]) end
        appliedKeyDown = true
    end
    Secure.status.keyDown = true
end
function Secure.ApplyAttributes()
    local page = ns.CurrentPage()
    for i=1,15 do Secure.WriteSlot(buttons[i], page[i]) end
end

-- action string or nil, ok. Second argument requests the effective (override-aware) mapping,
-- which is a modern-client signature probed here, not assumed.
local function bindingAction(chord, effective)
    if type(GetBindingAction)~="function" then return nil,false end
    local ok, action
    if effective then ok, action = pcall(GetBindingAction, chord, true)
    else ok, action = pcall(GetBindingAction, chord) end
    if not ok then return nil,false end
    action = plainString(action)
    if action=="" then action=nil end
    return action,true
end
-- Count of chords whose effective mapping is our click; nil if it cannot be checked.
function Secure.Verify()
    if type(GetBindingAction)~="function" then return nil end
    local count = 0
    for i=1,15 do
        if bindingAction(ns.Core.chord(i), true)==Secure.ClickAction(i) then count=count+1 end
    end
    return count
end
-- Temporary overrides owned by our frame, set as a block. Skipped when the last block applied
-- fully and (where checkable) every chord still maps to our click.
function Secure.ApplyBindings()
    if type(SetOverrideBindingClick)~="function" or type(ClearOverrideBindings)~="function" then
        Secure.status.bindings = "unavailable"
        return false
    end
    if Secure.status.applied==15 then
        local verified = Secure.Verify()
        if verified==nil or verified==15 then Secure.status.verified = verified; return true end
    end
    ClearOverrideBindings(owner)
    local count = 0
    for i=1,15 do
        local ok = pcall(SetOverrideBindingClick, owner, false, ns.Core.chord(i), Secure.ButtonName(i), "LeftButton")
        if ok then count = count+1 end
    end
    Secure.status.writes = Secure.status.writes + 16
    Secure.status.applied = count
    Secure.status.bindings = count==15 and "applied" or "partial"
    Secure.status.verified = Secure.Verify()
    return count==15
end
-- Per chord: ordinary binding (what our override shadows) and effective mapping.
function Secure.Conflicts()
    local rows, conflicts = {}, 0
    for i=1,15 do
        local chord = ns.Core.chord(i)
        local ordinary, okOrdinary = bindingAction(chord, false)
        local effective, okEffective = bindingAction(chord, true)
        local row = {index=i, chord=chord, ordinary=ordinary, effective=effective,
            ordinaryKnown=okOrdinary, effectiveKnown=okEffective, ours=effective==Secure.ClickAction(i)}
        row.conflict = (ordinary~=nil and ordinary~=Secure.ClickAction(i))
            or (effective~=nil and not row.ours)
        if row.conflict then conflicts=conflicts+1 end
        rows[i]=row
    end
    Secure.status.conflicts = conflicts
    return rows, conflicts
end

local function queue()
    if not queued then
        queued = true
        ns.RunOutOfCombat(function() queued = false; ns.Safe("secure", Secure.Request) end)
    end
    return false
end
-- The single entry point for secure work. The combat guard comes FIRST: nothing protected
-- (button setup, attributes, click registration, bindings) is attempted during lockdown.
local function applyAll()
    if InCombatLockdown() then return queue() end
    if not ns.profile or not init() then return false end
    Secure.ApplyClickDirection()
    Secure.ApplyAttributes()
    if ns.Bar and ns.Bar.ApplySecure then ns.Safe("bar secure", ns.Bar.ApplySecure) end
    return Secure.ApplyBindings()
end
-- Public entry: runs now out of combat, else queues once (the guard lives in applyAll only, so
-- tests delete it to prove they would catch that).
Secure.Request = applyAll
function Secure.IsQueued() return queued end
