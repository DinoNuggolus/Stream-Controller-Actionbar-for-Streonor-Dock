local addonName, ns = ...
-- The optional action bar. ONE non-secure wrapper frame owns every bar visual (header, buttons,
-- overlays, page indicator, ghost text); its alpha is the single fade hook (Bar.SetFadeAlpha) and is
-- never set anywhere else. The 15 persistent chord targets (Slots.xml / Secure.lua) are independent of
-- this frame: hiding, fading or reconfiguring the bar never touches them.
-- The visible buttons are SEPARATE secure targets (same attribute plan). Everything protected
-- (create, show/hide, anchor, scale, size, attributes) happens OUT OF COMBAT; in combat it is queued.
local Bar = {}
ns.Bar = Bar
local Layout, Core = ns.Layout, ns.Core
local wrapper, header, content, ghost, pageText
local buttons = {}
Bar.buttons = buttons
local fadeAlpha = 1
local structuralQueued = false
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local HEADER_H, PAD = Layout.HEADER_HEIGHT, 6
local MIN_W = 150

local function has(o, m) return o and type(o[m]) == "function" end
local function make(kind, name, parent, template)
    if template then
        local ok, object = pcall(CreateFrame, kind, name, parent, template)
        if ok and object then return object end
    end
    return CreateFrame(kind, name, parent)
end
local function profile() return ns.profile end
local function lsm() return _G.LibStub and LibStub("LibSharedMedia-3.0", true) or nil end
local function fetch(kind, name, fallback)
    local m = lsm()
    if m and name then
        local ok, path = pcall(m.Fetch, m, kind, name, true)
        if ok and path then return path end
    end
    return fallback
end

-- ------------------------------------------------------------------ state helpers
function Bar.WantShown()
    local p = profile()
    if not p then return false end
    local reveal = ns.Assign and ns.Assign.IsTemporary and ns.Assign.IsTemporary()
    return p.general.showActionBar or reveal or false
end
local function assigning() return ns.Assign and ns.Assign.IsActive and ns.Assign.IsActive() or false end
function Bar.IsShown() return wrapper ~= nil and wrapper:IsShown() end

-- ------------------------------------------------------------------ fade hook (single alpha owner)
-- A fader (visibility engine, tutorial override) calls this; nothing else sets wrapper alpha.
function Bar.SetFadeAlpha(alpha)
    if type(alpha) ~= "number" or alpha ~= alpha then return false end
    fadeAlpha = math.max(0, math.min(1, alpha))
    if wrapper then wrapper:SetAlpha(fadeAlpha) end
    return true
end
function Bar.GetFadeAlpha() return fadeAlpha end

-- ------------------------------------------------------------------ glyphs (original, drawn from rects)
local function rect(parent, layer, w, h, x, y, point)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetTexture(WHITE)
    t:SetSize(w, h)
    t:SetPoint(point or "CENTER", parent, point or "CENTER", x or 0, y or 0)
    return t
end
local function paint(list, r, g, b, a) for _, t in ipairs(list) do t:SetVertexColor(r, g, b, a or 1) end end

local function glyphButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.parts = {}
    b.base = {0.75, 0.75, 0.78, 0.55}
    return b
end
local function hoverable(b)
    b:SetScript("OnEnter", function(self)
        paint(self.parts, 1, 1, 1, 1)
        if self.tip and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(self.tip()); GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function(self)
        paint(self.parts, self.base[1], self.base[2], self.base[3], self.base[4])
        if GameTooltip then GameTooltip:Hide() end
    end)
end
local function buildPadlock(parent)
    local b = glyphButton(parent, HEADER_H - 2)
    local body = rect(b, "OVERLAY", 8, 6, 0, -2)
    local left = rect(b, "OVERLAY", 1, 4, -2.5, 3)
    local right = rect(b, "OVERLAY", 1, 4, 2.5, 3)
    local top = rect(b, "OVERLAY", 6, 1, 0, 5)
    b.parts = {body, left, right, top}
    b.shackle = {left, right, top}
    paint(b.parts, unpack(b.base))
    hoverable(b)
    b.SetLocked = function(self, locked)
        -- Unlocked: the shackle lifts one pixel row and opens on the right.
        local lift = locked and 0 or 2
        left:SetPoint("CENTER", self, "CENTER", -2.5, 3 + lift)
        right:SetPoint("CENTER", self, "CENTER", 2.5, 3 + lift)
        top:SetPoint("CENTER", self, "CENTER", 0, 5 + lift)
        if locked then right:SetHeight(4) else right:SetHeight(2) end
    end
    return b
end
local function buildCog(parent)
    local b = glyphButton(parent, HEADER_H - 2)
    local bars = {}
    for i = 0, 3 do
        local t = rect(b, "OVERLAY", 9, 2, 0, 0)
        if has(t, "SetRotation") then t:SetRotation(math.rad(45 * i)) end
        bars[#bars + 1] = t
    end
    local hub = rect(b, "OVERLAY", 4, 4, 0, 0)
    bars[#bars + 1] = hub
    b.parts = bars
    paint(b.parts, unpack(b.base))
    hoverable(b)
    return b
end

-- ------------------------------------------------------------------ dashed frame + plus (assignment)
local DASHES = 5
local function dashedFrame(parent)
    local list = {}
    local function dash(w, h, point, x, y)
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE); t:SetSize(w, h); t:SetPoint(point, parent, point, x, y)
        t:SetVertexColor(1, 1, 1, 0.7)
        list[#list + 1] = t
    end
    parent.dashes = list
    parent.layoutDashes = function(self, size)
        local seg = math.max(2, math.floor(size / (DASHES * 2 - 1)))
        for i = 1, #list do list[i]:Hide() end
        local n = 0
        for i = 0, DASHES - 1 do
            local off = i * seg * 2
            n = n + 1
            local t = list[n]
            if not t then dash(seg, 1, "TOPLEFT", off, 0); t = list[#list] end
            t:SetSize(seg, 1); t:SetPoint("TOPLEFT", self, "TOPLEFT", off, 0); t:Show()
            n = n + 1; t = list[n]
            if not t then dash(seg, 1, "BOTTOMLEFT", off, 0); t = list[#list] end
            t:SetSize(seg, 1); t:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", off, 0); t:Show()
            n = n + 1; t = list[n]
            if not t then dash(1, seg, "TOPLEFT", 0, -off); t = list[#list] end
            t:SetSize(1, seg); t:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -off); t:Show()
            n = n + 1; t = list[n]
            if not t then dash(1, seg, "TOPRIGHT", 0, -off); t = list[#list] end
            t:SetSize(1, seg); t:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -off); t:Show()
        end
    end
end

-- ------------------------------------------------------------------ right-click dispatch
local function contextEntries(slotIndex)
    local entries = {
        {text = "StreonorDock", title = true},
        {text = "Settings", func = function() if ns.Options then ns.Options.Open() end end},
        {text = assigning() and "Lock assignments" or "Unlock for assignment", func = function() if ns.Assign then ns.Assign.Toggle() end end},
        {text = "Reload UI", disabled = InCombatLockdown(), func = function() if not InCombatLockdown() and type(ReloadUI) == "function" then ReloadUI() end end},
    }
    if slotIndex and assigning() then
        entries[#entries + 1] = {divider = true}
        entries[#entries + 1] = {text = "Clear slot", disabled = InCombatLockdown(), func = function() ns.Edit(slotIndex, {kind = "empty"}) end}
    end
    return entries
end
function Bar.ContextMenu(owner, slotIndex)
    if ns.Menu then ns.Menu.Show(owner, contextEntries(slotIndex)) end
end
-- context: "button" | "header". Buttons open the menu when rightClickEnabled; otherwise (and for the
-- header and background) the configured action runs.
function Bar.RightClick(context, owner, slotIndex)
    local p = profile()
    if not p then return end
    local g = p.general
    if context == "button" and g.rightClickEnabled then return Bar.ContextMenu(owner, slotIndex) end
    local action = g.rightClickAction
    if action == "settings" then if ns.Options then ns.Options.Open() end
    elseif action == "assign" then if ns.Assign then ns.Assign.Toggle() end
    elseif action == "menu" then Bar.ContextMenu(owner, slotIndex) end
end

-- ------------------------------------------------------------------ header fade on hover
-- The header (padlock/cog bar) fades to headerFadedAlpha when the mouse is not over the panel (header,
-- bar, buttons, plus an 8 px margin) and returns to full on mouseover. It is a CHILD of the wrapper, so its
-- effective alpha is header alpha x wrapper (bar-wide fader) alpha: the two are independent and multiply.
-- Forced fully visible in assignment mode. Only a header-local OnUpdate runs, and only while animating.
local hovered, headerAlpha, headerTarget = false, 1, 1
local HOVER_MARGIN = 8
local function headerGoal()
    local p = profile()
    if not p or not p.bar.headerFade or assigning() or hovered then return 1 end
    return p.bar.headerFadedAlpha
end
local function headerStep(self, elapsed)
    local p = profile()
    local duration = p and p.bar.headerFadeDuration or 0
    if duration <= 0 then headerAlpha = headerTarget
    else
        local delta = elapsed / duration * math.abs(1 - (p.bar.headerFadedAlpha or 0.05))
        if delta <= 0 then delta = 1 end
        if headerAlpha < headerTarget then headerAlpha = math.min(headerTarget, headerAlpha + delta)
        else headerAlpha = math.max(headerTarget, headerAlpha - delta) end
    end
    self:SetAlpha(headerAlpha)
    if headerAlpha == headerTarget then self:SetScript("OnUpdate", nil) end
end
function Bar.UpdateHeaderFade()
    if not header then return end
    headerTarget = headerGoal()
    local p = profile()
    if headerAlpha == headerTarget then header:SetAlpha(headerAlpha); header:SetScript("OnUpdate", nil); return end
    if p and p.bar.headerFadeDuration <= 0 then headerAlpha = headerTarget; header:SetAlpha(headerAlpha); return end
    header:SetScript("OnUpdate", headerStep)
end
local function recheckHover()
    local over = wrapper and wrapper:IsMouseOver(HOVER_MARGIN, -HOVER_MARGIN, -HOVER_MARGIN, HOVER_MARGIN) or false
    if over ~= hovered then hovered = over; Bar.UpdateHeaderFade() end
end
local function onEnter() if not hovered then hovered = true; Bar.UpdateHeaderFade() end end
local function onLeave()
    -- Leaving one child usually means entering another: resolve after the enters have run.
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(0.05, recheckHover) else recheckHover() end
end
function Bar.WatchHover(frame)
    if not frame or frame.streonorWatched then return end
    frame.streonorWatched = true
    frame:HookScript("OnEnter", onEnter)
    frame:HookScript("OnLeave", onLeave)
end

-- ------------------------------------------------------------------ position
local function applyPosition()
    local pos = ns.char and ns.char.barPosition
    wrapper:ClearAllPoints()
    if pos then wrapper:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else wrapper:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end
local function savePosition()
    if not wrapper or not ns.char then return end
    local cx, cy = wrapper:GetCenter()
    local pcx, pcy = UIParent:GetCenter()
    local es, pes = wrapper:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (cx and cy and pcx and pcy) then return end
    local x, y = Layout.centerOffset(cx * es, cy * es, pcx * pes, pcy * pes, es)
    ns.char.barPosition = {point = "CENTER", relativePoint = "CENTER", x = x, y = y}
    wrapper:ClearAllPoints()
    wrapper:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
function Bar.ResetPosition()
    if InCombatLockdown() then ns.Say("moving the bar is unavailable in combat"); return false end
    ns.char.barPosition = {point = "CENTER", relativePoint = "CENTER", x = 0, y = 0}
    if wrapper then applyPosition() end
    return true
end

-- ------------------------------------------------------------------ appearance
function Bar.ApplyAppearance()
    local p = profile()
    if not wrapper or not p or not has(wrapper, "SetBackdrop") then return end
    local b = p.bar
    local style = b.borderStyle
    local backdrop = {bgFile = fetch("background", b.background, WHITE), tile = true, tileSize = 16,
        insets = {left = 3, right = 3, top = 3, bottom = 3}}
    if style ~= "none" then
        backdrop.edgeFile = fetch("border", b.border, "Interface\\Tooltips\\UI-Tooltip-Border")
        backdrop.edgeSize = style == "glow" and 14 or 10
    end
    wrapper:SetBackdrop(backdrop)
    wrapper:SetBackdropColor(0.04, 0.05, 0.07, b.backgroundOpacity)
    if style == "glow" then
        local c = p.highlight.color
        wrapper:SetBackdropBorderColor(c[1], c[2], c[3], 0.9)
    else
        wrapper:SetBackdropBorderColor(0.55, 0.57, 0.62, style == "none" and 0 or 0.9)
    end
    local font = fetch("font", b.font)
    if font and pageText and has(pageText, "SetFont") then pageText:SetFont(font, 10, "OUTLINE") end
end

-- ------------------------------------------------------------------ buttons
local function slotAt(i) return ns.CurrentPage()[i] end
local function iconFor(slot)
    if not slot or slot.kind == "empty" then return nil end
    return ns.Game.SlotIcon(slot) or QUESTION
end

local function buildButton(i)
    local b = make("Button", "StreonorDockBarButton" .. i, content, "SecureActionButtonTemplate")
    if not b then return nil end
    b.slotIndex = i
    b:SetSize(40, 40)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetTexture(WHITE); b.bg:SetVertexColor(0, 0, 0, 0.45)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    if has(b.icon, "SetTexCoord") then b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    b.cooldown = make("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    if has(b.cooldown, "SetDrawEdge") then b.cooldown:SetDrawEdge(false) end
    -- Recharge sweep for spells with charges (never dims an otherwise usable spell).
    b.chargeCooldown = make("Cooldown", nil, b, "CooldownFrameTemplate")
    b.chargeCooldown:SetAllPoints(b.icon)
    if has(b.chargeCooldown, "SetDrawEdge") then b.chargeCooldown:SetDrawEdge(false) end
    -- text layer above the sweep
    b.text = CreateFrame("Frame", nil, b)
    b.text:SetAllPoints()
    if has(b.text, "SetFrameLevel") then b.text:SetFrameLevel((b:GetFrameLevel() or 1) + 6) end
    b.count = b.text:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.key = b.text:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    b.key:SetPoint("TOPRIGHT", -2, -2)
    b.timer = b.text:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    b.timer:SetPoint("CENTER", 0, 0)
    b.highlight = b:CreateTexture(nil, "HIGHLIGHT"); b.highlight:SetAllPoints(); b.highlight:SetTexture(WHITE); b.highlight:SetVertexColor(1, 1, 1, 0.12)
    -- Nonsecure assignment overlay: intercepts the mouse only while assigning.
    local o = CreateFrame("Button", nil, b)
    o:SetAllPoints()
    if has(o, "SetFrameLevel") then o:SetFrameLevel((b:GetFrameLevel() or 1) + 8) end
    o:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    o:RegisterForDrag("LeftButton")
    o.slotIndex = i
    dashedFrame(o)
    o.plusH = rect(o, "OVERLAY", 14, 2, 0, 0); o.plusV = rect(o, "OVERLAY", 2, 14, 0, 0)
    o.hl = o:CreateTexture(nil, "HIGHLIGHT"); o.hl:SetAllPoints(); o.hl:SetTexture(WHITE); o.hl:SetVertexColor(1, 1, 1, 0.18)
    o:SetScript("OnClick", function(self, mouse) ns.Safe("overlay click", function()
        if ns.Assign then ns.Assign.OnSlotClick(self.slotIndex, mouse, self) end end) end)
    o:SetScript("OnReceiveDrag", function(self) ns.Safe("overlay drop", function()
        if ns.Assign then ns.Assign.OnDrop(self.slotIndex) end end) end)
    o:SetScript("OnDragStart", function(self) ns.Safe("overlay drag", function()
        if ns.Assign then ns.Assign.OnDragStart(self.slotIndex) end end) end)
    o:SetScript("OnDragStop", function(self) ns.Safe("overlay dragstop", function()
        if ns.Assign then ns.Assign.OnDragStop(self.slotIndex) end end) end)
    o:SetScript("OnEnter", function(self) ns.Safe("overlay enter", function()
        if ns.Assign then ns.Assign.OnEnter(self.slotIndex, self) end end) end)
    o:SetScript("OnLeave", function(self) ns.Safe("overlay leave", function()
        if ns.Assign then ns.Assign.OnLeave(self.slotIndex, self) end end) end)
    o:Hide()
    b.overlay = o
    -- Locked behaviour: tooltip, flash, right-click.
    b:HookScript("OnEnter", function(self) ns.Safe("tooltip", Bar.Tooltip, self) end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:HookScript("PostClick", function(self, mouse)
        if mouse == "RightButton" then ns.Safe("rightclick", Bar.RightClick, "button", self, nil) end
    end)
    Bar.WatchHover(b); Bar.WatchHover(o)
    ns.Secure.Hook(b, 0)   -- shared PostClick restore; bar clicks do not feed the chord counters
    return b
end

function Bar.Tooltip(button)
    local p = profile()
    if not GameTooltip or not p or not p.buttons.tooltips or assigning() then return end
    local slot = slotAt(button.slotIndex)
    if not slot or slot.kind == "empty" then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local shown = false
    if slot.kind == "spell" and has(GameTooltip, "SetSpellByID") then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, slot.id)
    elseif slot.kind == "item" and has(GameTooltip, "SetItemByID") then shown = pcall(GameTooltip.SetItemByID, GameTooltip, slot.id) end
    if not shown then GameTooltip:SetText((slot.kind == "spell" and "Spell " or "Item ") .. slot.id) end
    if button.cdUnavailable then GameTooltip:AddLine("Cooldown unavailable", 0.8, 0.8, 0.8) end
    if not button.streonorKind then GameTooltip:AddLine("Not usable yet: the spell is not known or the item is not available.", 1, 0.5, 0.3, true) end
    GameTooltip:Show()
end

-- Creates the secure bar buttons (out of combat only) and writes their attribute plans.
function Bar.ApplySecure()
    if InCombatLockdown() or not wrapper then return false end
    for i = 1, 15 do
        if not buttons[i] then buttons[i] = buildButton(i) end
        local b = buttons[i]
        if b then
            if not b.streonorDownSet then ns.Secure.SetDown(b); b.streonorDownSet = true end
            ns.Secure.WriteSlot(b, slotAt(i))
        end
    end
    Bar.Layout()
    return true
end

-- ------------------------------------------------------------------ layout (structural, out of combat)
local function gridConfig()
    local b = profile().bar
    return {mirror = b.mirrorControllerLayout, columns = b.columns, orientation = b.orientation, growX = b.growX, growY = b.growY}
end
function Bar.Layout()
    local p = profile()
    if not wrapper or not p then return end
    if InCombatLockdown() then
        if not structuralQueued then
            structuralQueued = true
            ns.RunOutOfCombat(function() structuralQueued = false; ns.Safe("bar layout", Bar.Layout) end)
        end
        return
    end
    if not Bar.WantShown() then
        if wrapper:IsShown() then wrapper:Hide() end
        return
    end
    local size, spacing = p.bar.buttonSize, p.bar.spacing
    local grid, gw, gh = Layout.metrics(gridConfig(), size, spacing)
    local isAssigning = assigning()
    local visible = Layout.visible(ns.CurrentPage(), isAssigning, p.general.alwaysShowButtons)
    local anyVisible = false
    for i = 1, 15 do if visible[i] then anyVisible = true end end
    local contentW, contentH = gw, gh
    local showGhost = not anyVisible
    if showGhost then contentW, contentH = math.max(gw, MIN_W - 2 * PAD), 22 end
    local width = math.max(MIN_W, contentW + 2 * PAD)
    local height = HEADER_H + contentH + 2 * PAD
    wrapper:SetScale(p.bar.scale)
    wrapper:SetSize(width, height)
    header:SetHeight(HEADER_H)
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", wrapper, "TOPLEFT", PAD + (width - 2 * PAD - contentW) / 2, -(HEADER_H + PAD))
    content:SetSize(contentW, contentH)
    for i = 1, 15 do
        local b = buttons[i]
        if b then
            b:SetSize(size, size)
            local x, y = Layout.offset(grid, i, size, spacing)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", content, "TOPLEFT", x + (showGhost and 0 or 0), y)
            if visible[i] then b:Show() else b:Hide() end
            b.overlay:SetShown(isAssigning and visible[i])
            if b.overlay.layoutDashes then b.overlay:layoutDashes(size) end
        end
    end
    ghost:SetShown(showGhost)
    if showGhost then ghost:SetText(isAssigning and "" or "Unlock to add spells") end
    applyPosition()
    Bar.ApplyAppearance()
    if not wrapper:IsShown() then wrapper:Show() end
    Bar.ApplyHeader()
    if ns.Display then ns.Display.Refresh() end   -- newly shown buttons get their count/cooldown
end

function Bar.ApplyHeader()
    local p = profile()
    if not header or not p then return end
    local g = p.general
    header.padlock:SetShown(g.showPadlock)
    header.cog:SetShown(g.showCog)
    header.padlock:SetLocked(not assigning())
    Bar.UpdateHeaderFade()
    local pages = p.pageCount
    local showPages = pages > 1 and p.bar.showPageIndicator
    pageText:SetShown(showPages); header.prev:SetShown(showPages); header.next:SetShown(showPages)
    if showPages then pageText:SetText(ns.char.currentPage .. "/" .. pages) end
end

-- ------------------------------------------------------------------ visual refresh (safe in combat)
local function refreshOverlay(b, slot)
    local filled = slot and slot.kind ~= "empty"
    local a = filled and 0.5 or 1.0
    b.overlay.plusH:SetAlpha(a); b.overlay.plusV:SetAlpha(a)
end
function Bar.RefreshVisuals()
    if not wrapper then return end
    for i = 1, 15 do
        local b = buttons[i]
        if b then
            local slot = slotAt(i)
            local icon = iconFor(slot)
            if icon then b.icon:SetTexture(icon); b.icon:Show() else b.icon:Hide() end
            refreshOverlay(b, slot)
            local p = profile()
            local mode = p.buttons.keybindLabels
            b.key:SetText(mode == "slot" and tostring(i) or (mode == "chord" and Core.chordKey(i)) or "")
        end
    end
    if ns.Display then ns.Display.Refresh() end
end
function Bar.Refresh()
    if not wrapper or not profile() then return end
    Bar.RefreshVisuals()
    if buttons[15] then Bar.Layout()          -- queues itself in combat
    elseif not InCombatLockdown() then Bar.ApplySecure() end
end

function Bar.ToggleShown()
    if InCombatLockdown() then ns.Say("showing or hiding the bar is unavailable in combat"); return end
    local g = profile().general
    g.showActionBar = not g.showActionBar
    Bar.Layout()
    if ns.Options then ns.Options.Notify() end
    ns.Say("action bar " .. (g.showActionBar and "shown" or "hidden"))
end

function Bar.CombatStarted()
    -- Dragging stops; nothing protected is touched.
    if wrapper and wrapper.isMoving then wrapper:StopMovingOrSizing(); wrapper.isMoving = false end
end
function Bar.CombatEnded()
    if wrapper then Bar.Refresh() end
end

-- ------------------------------------------------------------------ creation
function Bar.Create()
    if wrapper then return wrapper end
    wrapper = make("Frame", "StreonorDockBar", UIParent, "BackdropTemplate")
    wrapper:SetFrameStrata("MEDIUM")
    wrapper:SetMovable(true)
    wrapper:SetClampedToScreen(true)
    wrapper:EnableMouse(true)
    wrapper:SetAlpha(fadeAlpha)
    wrapper:SetSize(MIN_W, HEADER_H + 22 + 2 * PAD)
    wrapper:SetScript("OnMouseUp", function(_, mouse)
        if mouse == "RightButton" then ns.Safe("bar rightclick", Bar.RightClick, "header", wrapper, nil) end
    end)
    header = CreateFrame("Frame", nil, wrapper)
    header:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", wrapper, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    local strip = header:CreateTexture(nil, "BACKGROUND")
    strip:SetTexture(WHITE); strip:SetPoint("TOPLEFT", 3, -3); strip:SetPoint("BOTTOMRIGHT", -3, 0)
    strip:SetVertexColor(1, 1, 1, 0.06)
    header.strip = strip
    header:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        wrapper:StartMoving(); wrapper.isMoving = true
    end)
    header:SetScript("OnDragStop", function()
        if not wrapper.isMoving then return end
        wrapper:StopMovingOrSizing(); wrapper.isMoving = false
        ns.Safe("save position", savePosition)
    end)
    header:SetScript("OnMouseUp", function(_, mouse)
        if mouse == "RightButton" then ns.Safe("header rightclick", Bar.RightClick, "header", header, nil) end
    end)
    header:SetScript("OnEnter", function(self) strip:SetVertexColor(1, 1, 1, 0.14) end)
    header:SetScript("OnLeave", function(self) strip:SetVertexColor(1, 1, 1, 0.06) end)
    local cog = buildCog(header); cog:SetPoint("RIGHT", header, "RIGHT", -6, -1)
    cog.tip = function() return "Settings" end
    cog:SetScript("OnClick", function() if ns.Options then ns.Safe("open settings", ns.Options.Open) end end)
    local lock = buildPadlock(header); lock:SetPoint("RIGHT", cog, "LEFT", -4, 0)
    lock.tip = function() return assigning() and "Lock (finish assigning)" or "Unlock to assign spells and items" end
    lock:SetScript("OnClick", function() if ns.Assign then ns.Safe("toggle assign", ns.Assign.Toggle) end end)
    header.cog, header.padlock = cog, lock
    local prev = CreateFrame("Button", nil, header); prev:SetSize(12, HEADER_H); prev:SetPoint("LEFT", header, "LEFT", 6, -1)
    local next = CreateFrame("Button", nil, header); next:SetSize(12, HEADER_H)
    pageText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    next:SetPoint("LEFT", pageText, "RIGHT", 2, 0)
    for _, pair in ipairs({{prev, "<", "prev"}, {next, ">", "next"}}) do
        local fs = pair[1]:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetPoint("CENTER"); fs:SetText(pair[2])
        pair[1]:SetScript("OnClick", function() ns.Safe("page", ns.SetPage, pair[3]) end)
    end
    header.prev, header.next = prev, next
    for _, f in ipairs({wrapper, header, cog, lock, prev, next}) do Bar.WatchHover(f) end
    content = CreateFrame("Frame", nil, wrapper)
    content:SetSize(10, 10)
    ghost = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ghost:SetPoint("CENTER")
    ghost:Hide()
    applyPosition()
    wrapper:Hide()
    Bar.wrapper, Bar.header = wrapper, header
    return wrapper
end
