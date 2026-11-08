local addonName, ns = ...
-- Assignment mode on the bar (no separate editor window). Unlock shows all 15 buttons with the overlay
-- (+ at 100% on empty, 50% on filled); lock hides empties again (unless Always show buttons) and, only
-- when the assignments really changed during the session, offers [Reload]/[Cancel] once. No reminders,
-- no persistent pending state: the only state is the in-memory baseline compared at lock time.
-- Everything here is out-of-combat only; combat pauses (cancels drag/menu/popup), never queues casts.
local Assign = {}
ns.Assign = Assign
local Core = ns.Core
local active, temporary, paused, queuedLock = false, false, false, false
local baseline
local generation = 0          -- bumped on lock/page/profile change: stale menus and callbacks compare it
local dragSource, dragFrame
local escapeFrame
local POPUP = "STREONORDOCK_RELOAD"

function Assign.IsActive() return active end
function Assign.IsTemporary() return active and temporary end
function Assign.IsPaused() return paused end
function Assign.Generation() return generation end

-- Identity of everything the controller shows: profile, page, count, export switch, all slots.
function Assign.Snapshot()
    local p, c = ns.profile, ns.char
    if not p or not c then return "" end
    local parts = {p.id, tostring(c.currentPage), tostring(p.pageCount), tostring(ns.db.global.exportEnabled)}
    for page = 1, p.pageCount do
        for i = 1, 15 do
            local s = p.pages[page][i]
            parts[#parts + 1] = s.kind == "empty" and "-" or (s.kind .. s.id .. (s.pinned and "p" or ""))
        end
    end
    return table.concat(parts, ",")
end
function Assign.Dirty() return active and baseline ~= nil and Assign.Snapshot() ~= baseline end
-- Edits/page/profile changes call this; the comparison itself happens at lock time, so undoing back
-- to the baseline needs no bookkeeping.
function Assign.NoteChange()
    generation = generation + 1
    if ns.Options then ns.Options.Notify() end
end

-- ------------------------------------------------------------------ reload popup
local function registerPopup()
    if type(StaticPopupDialogs) ~= "table" or StaticPopupDialogs[POPUP] then return end
    StaticPopupDialogs[POPUP] = {
        text = "Spells or items changed. Reload the UI now so the controller shows the new icons?",
        button1 = "Reload", button2 = "Cancel",
        OnAccept = function()
            if InCombatLockdown() then return end   -- dismissed; never deferred
            ns.Safe("reload export", ns.Export.Refresh)
            if type(ReloadUI) == "function" then ReloadUI() end
        end,
        OnCancel = function() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end
function Assign.ShowReloadPopup()
    registerPopup()
    if type(StaticPopup_Show) == "function" and StaticPopupDialogs and StaticPopupDialogs[POPUP] then StaticPopup_Show(POPUP) end
end

-- A page or profile change made while LOCKED prompts the same way (user decision). During an assignment
-- session the comparison happens at lock instead.
function Assign.OfferReload()
    if active or InCombatLockdown() then return end
    Assign.ShowReloadPopup()
end

-- ------------------------------------------------------------------ drag helpers
local function cursorHasPayload() return type(GetCursorInfo) == "function" and GetCursorInfo() ~= nil end
local function dragIcon()
    if dragFrame then return dragFrame end
    dragFrame = CreateFrame("Frame", "StreonorDockDragIcon", UIParent)
    dragFrame:SetSize(32, 32)
    dragFrame:SetFrameStrata("TOOLTIP")
    dragFrame.tex = dragFrame:CreateTexture(nil, "OVERLAY")
    dragFrame.tex:SetAllPoints()
    dragFrame:Hide()
    return dragFrame
end
local function followCursor(self)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    if x and y and s and s > 0 then
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    end
end
function Assign.CancelDrag()
    if not dragSource then return false end
    dragSource = nil
    if dragFrame then dragFrame:SetScript("OnUpdate", nil); dragFrame:Hide() end
    if ns.Glow then ns.Glow.StopAll() end
    return true
end
function Assign.IsDragging() return dragSource ~= nil end

function Assign.OnDragStart(index)
    if not active or paused or InCombatLockdown() or cursorHasPayload() then return end
    local slot = ns.CurrentPage()[index]
    if not slot or slot.kind == "empty" then return end
    dragSource = index
    local frame = dragIcon()
    frame.tex:SetTexture(ns.Game.SlotIcon(slot) or "Interface\\Icons\\INV_Misc_QuestionMark")
    frame:SetScript("OnUpdate", followCursor)   -- only while a drag is in progress
    frame:Show()
end
-- Drop by geometry: the overlay under the mouse, else a deliberate outside drop (clears the source).
function Assign.OnDragStop(index)
    if not dragSource or dragSource ~= index then return end
    local source = dragSource
    local dest
    for i = 1, 15 do
        local b = ns.Bar.buttons[i]
        if b and b.overlay:IsShown() and b.overlay:IsMouseOver() then dest = i; break end
    end
    Assign.CancelDrag()
    if InCombatLockdown() then return end
    if dest == source then return end                  -- same slot cancels
    if dest then ns.MoveSlot(source, dest)             -- empty -> move, occupied -> swap
    else ns.Edit(source, {kind = "empty"}) end         -- deliberate outside drop clears
end

-- Cursor payload dropped on a slot (spellbook spell or bag item). Rejected payloads stay on the cursor.
function Assign.OnDrop(index)
    if not active or paused then return false end
    if InCombatLockdown() then ns.Say("editing unavailable in combat"); return false end
    if dragSource then   -- an internal drag released onto an overlay is handled by OnDragStop
        return false
    end
    if type(GetCursorInfo) ~= "function" then return false end
    local cursor = {GetCursorInfo()}
    if cursor[1] == nil then return false end
    if cursor[1] == "spell" then cursor.resolved = ns.Game.ResolveSpellbookSpell(cursor[2], cursor[3]) end
    local value, reason = Core.normalizeCursor(cursor, ns.Game.issecret)
    if not value then ns.Say("that cannot be placed here (" .. tostring(reason) .. ")"); return false end
    if value.kind == "spell" and ns.Game.IsLowRank(value.id) then value.pinned = true end
    local accepted = ns.Edit(index, value)
    if accepted and type(ClearCursor) == "function" then ClearCursor() end
    return accepted
end

-- ------------------------------------------------------------------ slot menu
function Assign.OpenMenu(index, owner)
    if InCombatLockdown() then ns.Say("editing unavailable in combat"); return false end
    local data = ns.Catalog.Collect()
    local mine = generation
    local function stale()
        if mine ~= generation or not active or InCombatLockdown() then
            ns.Say("that menu is out of date; open it again"); return true
        end
    end
    local function pick(value)
        if stale() then return end
        if not ns.Catalog.Validate(value) then ns.Say("that spell or item is no longer available"); return end
        ns.Edit(index, value)
    end
    local function clear() if not stale() then ns.Edit(index, {kind = "empty"}) end end
    local entries = ns.Catalog.BuildMenu(data, ns.CurrentPage()[index], pick, clear)
    return ns.Menu.Show(owner, entries)
end

function Assign.OnSlotClick(index, mouse, owner)
    if not active or paused or InCombatLockdown() then return end
    if mouse == "RightButton" then
        if Assign.CancelDrag() then return end
        ns.Bar.RightClick("button", owner, index)
        return
    end
    if dragSource then return end
    if cursorHasPayload() then Assign.OnDrop(index); return end
    Assign.OpenMenu(index, owner)
end
function Assign.OnEnter(index, owner)
    if not active then return end
    if (dragSource or cursorHasPayload()) and ns.Glow then ns.Glow.Start(owner) end
    local slot = ns.CurrentPage()[index]
    if GameTooltip and slot and slot.kind ~= "empty" then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        local shown = false
        if slot.kind == "spell" and GameTooltip.SetSpellByID then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, slot.id)
        elseif slot.kind == "item" and GameTooltip.SetItemByID then shown = pcall(GameTooltip.SetItemByID, GameTooltip, slot.id) end
        if not shown then GameTooltip:SetText(slot.kind .. " " .. slot.id) end
        GameTooltip:AddLine("Click: change. Drag: move or swap. Drop outside: clear.", 0.6, 1, 0.6)
        GameTooltip:Show()
    end
end
function Assign.OnLeave(index, owner)
    if ns.Glow then ns.Glow.Stop(owner) end
    if GameTooltip then GameTooltip:Hide() end
end

-- ------------------------------------------------------------------ state transitions
local function escapeHandler()
    -- Escape: cancels a drag first; otherwise it is the lock route (never in combat).
    if not escapeFrame or escapeFrame.silent then return end
    if Assign.CancelDrag() then escapeFrame:Show(); return end
    if InCombatLockdown() then escapeFrame:Show(); return end
    Assign.Lock()
end
local function ensureEscape()
    if escapeFrame then return end
    escapeFrame = CreateFrame("Frame", "StreonorDockAssignEscape", UIParent)
    escapeFrame:SetSize(1, 1)
    escapeFrame:Hide()   -- frames start shown: hide BEFORE the OnHide script exists
    escapeFrame:SetScript("OnHide", function() ns.Safe("assign escape", escapeHandler) end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "StreonorDockAssignEscape") end
end
local function setEscape(on)
    ensureEscape()
    escapeFrame.silent = true
    if on then escapeFrame:Show() else escapeFrame:Hide() end
    escapeFrame.silent = false
end

function Assign.Unlock()
    if active then return true end
    if ns.readOnly then ns.Say("saved data is from a newer version: read-only"); return false end
    if InCombatLockdown() then ns.Say("assignment mode is unavailable in combat"); return false end
    if not ns.IsLoaded() then return false end
    temporary = not ns.profile.general.showActionBar
    active, paused = true, false
    baseline = Assign.Snapshot()
    generation = generation + 1
    setEscape(true)
    if ns.Visibility then ns.Visibility.PolicyChanged() end
    ns.Bar.Refresh()
    if ns.Options then ns.Options.Notify() end
    return true
end
-- Every closing route (padlock, Escape, /sdock assign, minimap, close) comes through here.
function Assign.Lock()
    if not active then return true end
    if InCombatLockdown() then queuedLock = true; ns.Say("assignment mode will lock when combat ends"); return false end
    Assign.CancelDrag()
    if ns.Menu then ns.Menu.Close() end
    local dirty = Assign.Dirty()
    active, temporary, paused, queuedLock = false, false, false, false
    baseline = nil
    generation = generation + 1
    setEscape(false)
    if ns.Visibility then ns.Visibility.PolicyChanged() end
    ns.Bar.Refresh()
    if ns.Options then ns.Options.Notify() end
    if dirty then Assign.ShowReloadPopup() end
    return true
end
function Assign.Toggle()
    if active then return Assign.Lock() end
    return Assign.Unlock()
end

function Assign.CombatStarted()
    if not active then return end
    paused = true
    Assign.CancelDrag()
    if ns.Menu then ns.Menu.Close() end
    if type(StaticPopup_Hide) == "function" then StaticPopup_Hide(POPUP) end
    generation = generation + 1
end
function Assign.CombatEnded()
    if not active then return end
    paused = false
    if queuedLock then Assign.Lock() end
end
-- Invalidate open menus when the underlying data changes.
function Assign.SpellsChanged() generation = generation + 1 end
function Assign.BagsChanged() end
