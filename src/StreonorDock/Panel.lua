local addonName, ns = ...
-- Editor panel: plain (non-secure) frames only, so showing, hiding and moving it is allowed in
-- combat and it never executes an action. The secure buttons live in Secure.lua and keep working
-- while this panel is hidden. Edits/paging are REJECTED in combat (chat message), never queued.
local Panel = {}
ns.Panel = Panel
local SLOT, GAP, PAD = 38, 6, 12
local WIDTH = PAD*2 + SLOT*3 + GAP*2 + 24
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local frame, pageText
local slots = {}      -- slots[area][index] = button
local timerHandle, timerToken = nil, 0
local POINTS = {CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,TOPLEFT=true,
    TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}

local function make(kind, name, parent, template)
    if template then
        local ok, object = pcall(CreateFrame, kind, name, parent, template)
        if ok and object then return object end
    end
    return CreateFrame(kind, name, parent)
end
local function has(object, method) return object and type(object[method])=="function" end
local function ui()
    if type(StreonorDockDB)~="table" then return {} end
    if type(StreonorDockDB.ui)~="table" then StreonorDockDB.ui={} end
    return StreonorDockDB.ui
end
local function savePosition()
    if not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    local saved = ui()
    if POINTS[point] and POINTS[relativePoint] and type(x)=="number" and type(y)=="number" then
        saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
    end
end
local function restorePosition()
    local saved = ui()
    frame:ClearAllPoints()
    if POINTS[saved.point] and POINTS[saved.relativePoint] and type(saved.x)=="number" and type(saved.y)=="number"
        and saved.x==saved.x and saved.y==saved.y then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function slotValue(area, index)
    local state = ns.state
    local page = state and state.pages[state.currentPage]
    return page and page[area][index]
end

-- Tooltip: only data from the slot's CURRENT identity.
local function onEnter(self)
    if not GameTooltip then return end
    local value = slotValue(self.area, self.index)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = false
    if value and value.kind=="spell" and has(GameTooltip, "SetSpellByID") then
        shown = pcall(GameTooltip.SetSpellByID, GameTooltip, value.id)
    elseif value and value.kind=="item" and has(GameTooltip, "SetItemByID") then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, value.id or value.itemID)
    end
    if not shown then
        local title = self.area=="readouts" and "Readout" or ("Key " .. self.index)
        if value and value.kind=="money" then title = "Money"
        elseif value and value.kind=="currency" then
            local meta = ns.Export.CurrencyMeta(value.currencyID)
            title = meta and meta.name or ("Currency " .. value.currencyID)
        end
        GameTooltip:SetText(title)
    end
    if self.area=="slots" then GameTooltip:AddLine("Chord: " .. ns.Core.chord(self.index), 0.8, 0.8, 1) end
    if value and value.kind=="item" then
        local _, source = ns.cooldowns:remaining(value.id or value.itemID, ns.Export.Now() or 0)
        if source=="est" then GameTooltip:AddLine("Cooldown: estimate (est)", 1, 0.82, 0)
        elseif source=="used" then GameTooltip:AddLine("Used; cooldown length unknown", 1, 0.82, 0) end
    end
    if self.area=="readouts" then
        GameTooltip:AddLine("Click: pick money, a currency or empty. Drop a bag item here. Right-click: clear (out of combat)", 0.6, 1, 0.6)
    else
        GameTooltip:AddLine(value and value.kind~="empty" and "Right-click: clear" or "Drop a spell or bag item here (out of combat)", 0.6, 1, 0.6)
    end
    GameTooltip:Show()
end
local function onLeave() if GameTooltip then GameTooltip:Hide() end end

-- Normalizes the cursor, then asks Init to apply the edit. The cursor is cleared ONLY when the
-- edit was accepted, so a rejected drop leaves the player still holding what they dragged.
function Panel.Drop(button)
    if type(GetCursorInfo)~="function" then return false end
    local cursor = {GetCursorInfo()}
    if cursor[1]==nil then return false end
    if InCombatLockdown() then ns.Say("editing unavailable in combat"); return false end
    if cursor[1]=="spell" then cursor.resolved = ns.Export.ResolveSpellbookSpell(cursor[2], cursor[3]) end
    local value, reason = ns.Core.normalizeCursor(cursor, ns.Export.issecret)
    if value then value, reason = ns.Core.forArea(value, button.area) end
    if not value then
        ns.Say(reason=="items-only" and "readouts accept bag items only" or "that cannot be placed here (" .. tostring(reason) .. ")")
        return false
    end
    if value.kind=="spell" and ns.Export.IsLowRank(value.id) then value.pinned=true end
    local accepted = ns.Edit(button.area, button.index, value)
    if accepted and type(ClearCursor)=="function" then ClearCursor() end
    return accepted
end
local function onClick(self, mouse)
    ns.Safe("panel click", function()
        local holding = type(GetCursorInfo)=="function" and GetCursorInfo()~=nil
        if mouse=="RightButton" then
            -- Right-click on an editor widget never executes anything (plain button, no attributes).
            if holding then if type(ClearCursor)=="function" then ClearCursor() end
            else ns.Edit(self.area, self.index, {kind="empty"}) end
        elseif holding then
            Panel.Drop(self)
        elseif self.area=="readouts" then
            Panel.OpenPicker(self)
        end
        if has(GameTooltip, "IsOwned") and GameTooltip:IsOwned(self) then onEnter(self) end
    end)
end

-- Readout picker: a small custom list (plain frames only: nothing secure, nothing tainted).
-- It lists Empty, Money and the currencies the character has right now (read when it opens).
local picker, pickerRows, pickerTarget
local ROW_H, PICK_W, MAX_ROWS = 20, 230, 14
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local function closePicker() if picker and picker:IsShown() then picker:Hide() end; pickerTarget=nil end
Panel.ClosePicker = closePicker
local function pickerRow(i)
    local row = pickerRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, picker.child)
    row:SetSize(PICK_W - 34, ROW_H)
    row:SetPoint("TOPLEFT", picker.child, "TOPLEFT", 0, -(i-1)*ROW_H)
    if has(row, "SetHighlightTexture") then row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD") end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16); row.icon:SetPoint("LEFT", 2, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 22, 0); row.text:SetPoint("RIGHT", -2, 0)
    if has(row.text, "SetJustifyH") then row.text:SetJustifyH("LEFT") end
    row:SetScript("OnClick", function(self)
        ns.Safe("picker pick", function()
            local target = pickerTarget
            closePicker()
            if target then ns.Edit("readouts", target.index, self.choice) end
        end)
    end)
    pickerRows[i] = row
    return row
end
local function ensurePicker()
    if picker then return picker end
    pickerRows = {}
    picker = make("Frame", "StreonorDockPicker", UIParent, "BackdropTemplate")
    picker:SetSize(PICK_W, 100)
    picker:SetFrameStrata("DIALOG")
    picker:EnableMouse(true)
    if has(picker, "SetBackdrop") then
        picker:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=16,
            insets={left=4,right=4,top=4,bottom=4}})
    end
    local scroll = make("ScrollFrame", "StreonorDockPickerScroll", picker, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8); scroll:SetPoint("BOTTOMRIGHT", -26, 8)
    picker.child = CreateFrame("Frame", nil, scroll)
    picker.child:SetSize(PICK_W - 34, 10)
    if has(scroll, "SetScrollChild") then scroll:SetScrollChild(picker.child) end
    picker:Hide()
    return picker
end
function Panel.OpenPicker(button)
    if InCombatLockdown() then ns.Say("editing unavailable in combat"); return false end
    ensurePicker()
    if picker:IsShown() and pickerTarget==button then closePicker(); return true end
    pickerTarget = button
    local choices = {{label="Empty", choice={kind="empty"}},
        {label="Money (gold)", choice={kind="money"}, icon=COIN}}
    for _, c in ipairs(ns.Export.ListCurrencies()) do
        choices[#choices+1] = {label=c.name .. (c.quantity and ("  (" .. c.quantity .. ")") or ""),
            choice={kind="currency", currencyID=c.id}, icon=c.iconFileID}
    end
    Panel.pickerChoices = choices
    for i, entry in ipairs(choices) do
        local row = pickerRow(i)
        row.choice = entry.choice
        row.text:SetText(entry.label)
        if entry.icon then row.icon:SetTexture(entry.icon); row.icon:Show() else row.icon:Hide() end
        row:Show()
    end
    for i=#choices+1, #pickerRows do pickerRows[i]:Hide() end
    picker.child:SetSize(PICK_W - 34, #choices*ROW_H)
    picker:SetSize(PICK_W, math.min(#choices, MAX_ROWS)*ROW_H + 18)
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    picker:Show()
    return true
end

local function createSlot(area, index, x, y)
    local b = CreateFrame("Button", nil, frame)
    b.area, b.index = area, index
    b:SetSize(SLOT, SLOT)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    if has(b, "SetHighlightTexture") then b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
    b.cooldown = make("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    if has(b.cooldown, "SetHideCountdownNumbers") then b.cooldown:SetHideCountdownNumbers(false) end
    -- Text sits on an overlay above the cooldown swipe.
    local overlay = CreateFrame("Frame", nil, b)
    overlay:SetAllPoints()
    if has(overlay, "SetFrameLevel") and has(b.cooldown, "GetFrameLevel") then
        overlay:SetFrameLevel((b.cooldown:GetFrameLevel() or 1) + 2)
    end
    b.key = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    b.key:SetPoint("TOPRIGHT", -2, -2)
    b.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("BOTTOMLEFT", 2, 2)
    if area=="slots" then b.key:SetText(ns.Core.chordKey(index)) else b.key:SetText("R" .. index) end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnReceiveDrag", function(self) ns.Safe("panel drop", Panel.Drop, self) end)
    b:SetScript("OnEnter", function(self) ns.Safe("tooltip", onEnter, self) end)
    b:SetScript("OnLeave", onLeave)
    slots[area][index] = b
end
local function pagerButton(label, x, action)
    local b = make("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(36, 20)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -30)
    b:SetText(label)
    b:SetScript("OnClick", function() ns.Safe("pager", StreonorDock_Page, action) end)
end

function Panel.Create()
    if frame then return frame end
    frame = make("Frame", "StreonorDockPanel", UIParent, "BackdropTemplate")
    local rows = 5
    local gridTop = -58
    local readTop = gridTop - rows*(SLOT+GAP) - 18
    frame:SetSize(WIDTH, -readTop + SLOT + PAD)
    if has(frame, "SetBackdrop") then
        frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=16,
            insets={left=4,right=4,top=4,bottom=4}})
    end
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); ns.Safe("panel save", savePosition) end)
    frame:SetScript("OnHide", function() ui().shown=false end)
    frame:SetScript("OnShow", function() ui().shown=true; ns.Safe("panel refresh", Panel.Refresh) end)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -10); title:SetText("StreonorDock")
    local close = make("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() frame:Hide() end)
    pagerButton("<", PAD, "prev"); pagerButton("H", PAD+40, "home"); pagerButton(">", PAD+80, "next")
    pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("TOPLEFT", PAD+122, -34)
    slots.slots, slots.readouts = {}, {}
    local left = (WIDTH - (SLOT*3 + GAP*2)) / 2
    for i=1,15 do
        local row, col = math.floor((i-1)/3), (i-1)%3   -- row-major: slot N = device key N
        createSlot("slots", i, left + col*(SLOT+GAP), gridTop - row*(SLOT+GAP))
    end
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", left, readTop + 14); label:SetText("Readouts (click: money / currency)")
    for i=1,3 do createSlot("readouts", i, left + (i-1)*(SLOT+GAP), readTop) end
    restorePosition()
    if ui().shown then frame:Show() else frame:Hide() end
    return frame
end

local function refreshSlot(b)
    local value = slotValue(b.area, b.index)
    local icon, count
    if value and value.kind=="spell" then
        local _, iconID = ns.Export.SpellMeta(value.id)
        icon = iconID or QUESTION
    elseif value and value.kind=="item" then
        local itemID = value.id or value.itemID
        local _, iconID = ns.Export.ItemMeta(itemID)
        icon = iconID or QUESTION
        count = ns.Export.ItemCount(itemID)
    end
    local countText = count and tostring(count) or ""
    if value and value.kind=="money" then
        icon = "Interface\Icons\INV_Misc_Coin_01"
        local copper = ns.Export.Money()
        countText = copper and (tostring(math.floor(copper/10000)) .. "g") or ""
    elseif value and value.kind=="currency" then
        local meta = ns.Export.CurrencyMeta(value.currencyID)
        icon = meta and meta.iconFileID or QUESTION
        countText = meta and meta.quantity and tostring(meta.quantity) or ""
    end
    if icon then b.icon:SetTexture(icon); b.icon:Show() else b.icon:Hide() end
    b.count:SetText(countText)
end
-- Re-read only the given slots (late metadata callbacks pass Core.findSlots matches).
function Panel.RefreshSlots(list)
    if not frame then return end
    for _, where in ipairs(list or {}) do
        local b = slots[where.area] and slots[where.area][where.index]
        if b then refreshSlot(b) end
    end
end

local function cancelTimer()
    timerToken = timerToken + 1
    if timerHandle and has(timerHandle, "Cancel") then timerHandle:Cancel() end
    timerHandle = nil
end
-- One C_Timer only while a timer is running, re-armed at the next expiry; none when idle.
local function schedule(seconds)
    cancelTimer()
    if not seconds or type(C_Timer)~="table" then return end
    local token = timerToken
    local function fire()
        if token~=timerToken then return end
        timerHandle = nil
        -- Re-read the game first: a pending USED/est marker may be resolved by a plain reading.
        ns.Safe("cooldown timer", function()
            ns.Export.ObserveItems(); Panel.RefreshCooldowns(); ns.Export.MarkDirty()
        end)
    end
    local delay = math.max(0.1, seconds + 0.05)
    if type(C_Timer.NewTimer)=="function" then
        local ok, handle = pcall(C_Timer.NewTimer, delay, fire)
        if ok then timerHandle = handle; return end
    end
    if type(C_Timer.After)=="function" then pcall(C_Timer.After, delay, fire) end
end
local function formatElapsed(seconds)
    seconds = math.floor(seconds)
    if seconds>=60 then return math.floor(seconds/60) .. "m" end
    return seconds .. "s"
end
-- Cooldown widget display from the tracker only (plain numbers, never raw API values).
function Panel.RefreshCooldowns()
    if not frame then return end
    local now = ns.Export.Now()
    local soonest
    for _, area in ipairs({"slots","readouts"}) do
        for index, b in ipairs(slots[area]) do
            local value = slotValue(area, index)
            local itemID = value and value.kind=="item" and (value.id or value.itemID)
            local endsAt, duration, source, usedAt
            if itemID and now then endsAt, duration, source, usedAt = ns.cooldowns:timer(itemID, now) end
            if endsAt then
                b.cooldown:SetCooldown(endsAt - duration, duration)
                b.label:SetText(source=="est" and "est" or "")
                soonest = math.min(soonest or math.huge, endsAt - now)
            else
                if has(b.cooldown, "Clear") then b.cooldown:Clear() end
                if source=="used" then
                    b.label:SetText("USED " .. formatElapsed(now - usedAt))
                    soonest = math.min(soonest or math.huge, 30)  -- refresh elapsed text and expiry
                else b.label:SetText("") end
            end
        end
    end
    schedule(soonest)
end

-- Values only (money/currency events): readouts redraw, nothing else.
function Panel.RefreshReadouts()
    if not frame or not slots.readouts then return end
    for _, b in ipairs(slots.readouts) do refreshSlot(b) end
end
function Panel.Refresh()
    if not frame then return end
    local state = ns.state
    if pageText and state then pageText:SetText("Page " .. state.currentPage .. "/" .. #state.pages) end
    for _, area in ipairs({"slots","readouts"}) do
        for _, b in ipairs(slots[area]) do refreshSlot(b) end
    end
    Panel.RefreshCooldowns()
end
function Panel.Toggle()
    Panel.Create()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
function Panel.IsShown() return frame~=nil and frame:IsShown() end
