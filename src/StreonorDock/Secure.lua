local addonName, ns = ...
-- 15 persistent SecureActionButtonTemplate buttons StreonorDockSlot1..15, declared in Slots.xml
-- (no parent, size or anchor: they exist even after a /reload in combat and keep working while
-- the editor is hidden). They are fired by temporary override bindings (SetOverrideBindingClick)
-- on the fixed ALT-CTRL-SHIFT chords. "*"-prefixed type/spell/item attributes only: no secure
-- snippets, no SetBinding/SaveBindings anywhere, nothing written to Blizzard frames. Every
-- attribute, click registration and binding change happens OUT OF COMBAT; in combat the work is
-- queued once and runs on PLAYER_REGEN_ENABLED. Unchanged settings are not rewritten.
local Secure = {}
ns.Secure = Secure
local buttons = {}
local owner
Secure.buttons = buttons
Secure.status = {ready=false, template=nil, bindings="not applied", applied=0, verified=nil,
    keyDown=nil, conflicts=0, lastError=nil, writes=0}
local queued = false
local applied = {}          -- applied[i][attributeKey] = value last written (diff source)
local appliedKeyDown = nil
local function issecret(v) return ns.Export.issecret(v) end
local function plainString(v) if not issecret(v) and type(v)=="string" then return v end end

function Secure.ButtonName(index) return "StreonorDockSlot" .. index end
function Secure.ClickAction(index) return "CLICK " .. Secure.ButtonName(index) .. ":LeftButton" end

local function postClick(self)
    -- Insecure PostClick on our own button, after the secure handler, in combat too. It means
    -- "the key was pressed", NOT that the item was used (the use can fail); the timers treat it
    -- as a press and reconcile with readable game data. Never acts on gameplay.
    ns.Safe("press", function()
        if self.streonorKind=="item" and self.streonorID then
            if ns.Export.OnKeyPress(self.streonorID) then
                if ns.Panel.RefreshCooldowns then ns.Panel.RefreshCooldowns() end
                ns.Export.MarkDirty()
            end
        end
    end)
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
        if not buttons[i] then button:SetScript("PostClick", postClick) end
        buttons[i] = button
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
    if appliedKeyDown~=keyDown then
        for i=1,15 do
            buttons[i]:SetAttribute("useOnKeyDown", keyDown)
            buttons[i]:RegisterForClicks(keyDown and "AnyDown" or "AnyUp")
        end
        appliedKeyDown = keyDown
        Secure.status.writes = Secure.status.writes + 30
    end
    Secure.status.keyDown = keyDown
end

local function spellName(spellID)
    local name = ns.Export.SpellMeta(spellID)
    return plainString(name)
end
-- Writes the current page's attributes where they differ from what was last applied; every
-- key of the plan is set or cleared, so no stale attribute survives a kind change.
function Secure.ApplyAttributes()
    local page = ns.state.pages[ns.state.currentPage]
    for i=1,15 do
        local slot, button = page.slots[i], buttons[i]
        local name = slot.kind=="spell" and not slot.pinned and spellName(slot.id) or nil
        local plan = ns.Core.secureAttributes(slot, name)
        local last = applied[i] or {}
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
            applied[i] = record
            Secure.status.writes = Secure.status.writes + 4
        end
        button.streonorKind = plan["*type1"] or nil
        button.streonorID = plan["*type1"] and slot.id or nil
    end
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
    if not ns.state or not init() then return false end
    Secure.ApplyClickDirection()
    Secure.ApplyAttributes()
    return Secure.ApplyBindings()
end
-- Public entry: runs now out of combat, else queues once (the guard lives in applyAll only, so
-- there is exactly one place that decides; tests delete it to prove they would catch that).
Secure.Request = applyAll
function Secure.IsQueued() return queued end
