local addonName, ns = ...
-- 15 persistent SecureActionButtonTemplate buttons (StreonorDockSlot1..15), independent of the
-- editor panel, fired by temporary override bindings (SetOverrideBindingClick) on the fixed
-- ALT-CTRL-SHIFT chords. Plain type/spell/item attributes only: no secure snippets, no
-- SetBinding/SaveBindings fallback, nothing written to Blizzard frames. Every attribute, click
-- registration and binding change happens OUT OF COMBAT; in combat the work is queued once and
-- runs on PLAYER_REGEN_ENABLED.
local Secure = {}
ns.Secure = Secure
local buttons = {}
local owner
Secure.buttons = buttons
Secure.status = {ready=false, template=nil, bindings="not applied", applied=0, verified=nil,
    keyDown=nil, conflicts=0, lastError=nil}
local queued = false
local function issecret(v) return ns.Export.issecret(v) end
local function plainString(v) if not issecret(v) and type(v)=="string" then return v end end

function Secure.ButtonName(index) return "StreonorDockSlot" .. index end
function Secure.ClickAction(index) return "CLICK " .. Secure.ButtonName(index) .. ":LeftButton" end

local function postClick(self)
    -- Insecure PostClick on our own button: runs after the secure action, in combat too.
    -- Records an item press for the press-activated timer; never acts on gameplay.
    ns.Safe("press", function()
        if self.streonorKind=="item" and self.streonorID then
            if ns.Export.OnKeyPress(self.streonorID) then
                if ns.Panel.RefreshCooldowns then ns.Panel.RefreshCooldowns() end
                ns.Export.MarkDirty()
            end
        end
    end)
end

-- Creates the binding owner and the 15 buttons. Out of combat only; returns ready.
function Secure.Init()
    if Secure.status.ready then return true end
    if InCombatLockdown() then return false end
    owner = owner or CreateFrame("Frame", "StreonorDockBindingOwner", UIParent)
    for i=1,15 do
        if not buttons[i] then
            local ok, button = pcall(CreateFrame, "Button", Secure.ButtonName(i), UIParent, "SecureActionButtonTemplate")
            if not ok or not button then
                Secure.status.template = "unavailable"
                Secure.status.lastError = "SecureActionButtonTemplate could not be created"
                return false
            end
            -- Like BindPad's hidden binding buttons: no size or anchor, never drawn, still clickable by binding.
            button:SetScript("PostClick", postClick)
            buttons[i] = button
        end
    end
    Secure.status.template = "available"
    Secure.status.ready = true
    return true
end

-- Click direction must match ActionButtonUseKeyDown or the modern template ignores the click.
function Secure.ApplyClickDirection()
    local keyDown = true  -- modern default when the CVar cannot be read (unverified on Forever)
    if type(GetCVarBool)=="function" then
        local ok, value = pcall(GetCVarBool, "ActionButtonUseKeyDown")
        if ok and not issecret(value) and value~=nil then keyDown = value and true or false end
    end
    for i=1,15 do
        buttons[i]:SetAttribute("useOnKeyDown", keyDown)
        buttons[i]:RegisterForClicks(keyDown and "AnyDown" or "AnyUp")
    end
    Secure.status.keyDown = keyDown
end

local function spellName(spellID)
    local name = ns.Export.SpellMeta(spellID)
    return plainString(name)
end
-- Writes the current page's attributes; clears type/spell/item that the new kind does not use.
function Secure.ApplyAttributes()
    local page = ns.state.pages[ns.state.currentPage]
    for i=1,15 do
        local slot, button = page.slots[i], buttons[i]
        local name = slot.kind=="spell" and not slot.pinned and spellName(slot.id) or nil
        local plan = ns.Core.secureAttributes(slot, name)
        -- Clear first so no combination of old and new attributes is ever visible together.
        button:SetAttribute("type", nil)
        for _, key in ipairs({"spell","item"}) do
            if plan[key] then button:SetAttribute(key, plan[key]) else button:SetAttribute(key, nil) end
        end
        if plan.type then button:SetAttribute("type", plan.type) end
        button.streonorKind = plan.type or nil
        button.streonorID = plan.type and slot.id or nil
    end
end

-- Temporary overrides owned by our frame. Cleared and re-set as a block (idempotent).
function Secure.ApplyBindings()
    if type(SetOverrideBindingClick)~="function" or type(ClearOverrideBindings)~="function" then
        Secure.status.bindings = "unavailable"
        return false
    end
    ClearOverrideBindings(owner)
    local applied = 0
    for i=1,15 do
        local ok = pcall(SetOverrideBindingClick, owner, false, ns.Core.chord(i), Secure.ButtonName(i), "LeftButton")
        if ok then applied = applied+1 end
    end
    Secure.status.applied = applied
    Secure.status.bindings = applied==15 and "applied" or "partial"
    Secure.status.verified = Secure.Verify()
    return applied==15
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

local function applyAll()
    queued = false
    if not ns.state or not Secure.Init() then return false end
    Secure.ApplyClickDirection()
    Secure.ApplyAttributes()
    return Secure.ApplyBindings()
end
-- Public entry: run now if out of combat, else queue exactly once for PLAYER_REGEN_ENABLED.
function Secure.Request()
    if InCombatLockdown() then
        if not queued then
            queued = true
            ns.RunOutOfCombat(function() ns.Safe("secure", applyAll) end)
        end
        return false
    end
    return applyAll()
end
function Secure.IsQueued() return queued end
