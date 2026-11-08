local addonName, ns = ...
-- Six-step first-run tour with hand-built, addon-owned callouts (original arrow, text, Next, X, n/6).
-- The native HelpTip path is deliberately not used: Aurora documents taint from touching pooled HelpTip
-- fields on this client, so the owned callout is the baseline.
-- State is ACCOUNT-wide in db.global.tutorial = {seen, hidePopups, completed} and has NO version key:
-- addon updates never reset it. The tour starts automatically only once (the very first login after
-- install, tracked by `seen`) and never when hidePopups is set. X (or Escape) closes the whole tour and
-- sets hidePopups=true. Replay from Settings > General runs it again on request.
local T = {}
ns.Tutorial = T
local WHITE = "Interface\\Buttons\\WHITE8X8"
local STEPS = {
    {key = "bar", text = "Each button matches one controller key. One physical press is one use attempt: no hold repeat, no repeat on release."},
    {key = "padlock", text = "Unlock to assign spells and items. All 15 slots show while unlocked; lock when you are finished. Editing is out of combat only."},
    {key = "cog", text = "Open settings for appearance, pages and profiles. /sdock settings always works, even if you hide the cog."},
    {key = "slot", text = "Drag a known spell or a carried item onto a slot, or click it for Spells / Items / Clear slot. This tour never changes your assignments."},
    {key = "popup", text = "After changing assignments, locking offers Reload so the controller shows the new icons. Cancel closes it with no reminder. (This is only an example.)"},
    {key = "minimap", text = "Left-click the minimap button for settings, right-click for assignment mode. /sdock assign works too."},
}
T.STEPS = STEPS
T.step, T.running, T.suspended = 0, false, false
local callout, example
local overridden = false

local function state() return ns.db and ns.db.global.tutorial end
local function make(kind, name, parent, template)
    if template then
        local ok, o = pcall(CreateFrame, kind, name, parent, template)
        if ok and o then return o end
    end
    return CreateFrame(kind, name, parent)
end

-- ------------------------------------------------------------------ frames
local function build()
    if callout then return callout end
    callout = make("Frame", "StreonorDockTutorial", UIParent, "BackdropTemplate")
    callout:SetSize(270, 120)
    callout:SetFrameStrata("FULLSCREEN_DIALOG")
    callout:SetClampedToScreen(true)
    if callout.SetBackdrop then
        callout:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12, insets = {left = 3, right = 3, top = 3, bottom = 3}})
        callout:SetBackdropBorderColor(0.96, 0.8, 0.2, 1)
    end
    callout.arrow = callout:CreateTexture(nil, "OVERLAY")
    callout.arrow:SetTexture(WHITE); callout.arrow:SetSize(12, 12); callout.arrow:SetVertexColor(0.96, 0.8, 0.2, 1)
    if callout.arrow.SetRotation then callout.arrow:SetRotation(math.rad(45)) end
    callout.text = callout:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    callout.text:SetPoint("TOPLEFT", 12, -12); callout.text:SetPoint("TOPRIGHT", -26, -12)
    if callout.text.SetJustifyH then callout.text:SetJustifyH("LEFT") end
    callout.progress = callout:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    callout.progress:SetPoint("BOTTOMLEFT", 12, 10)
    callout.next = make("Button", nil, callout, "UIPanelButtonTemplate")
    callout.next:SetSize(70, 22); callout.next:SetPoint("BOTTOMRIGHT", -10, 8)
    callout.next:SetText("Next")
    callout.next:SetScript("OnClick", function() ns.Safe("tutorial next", T.Next) end)
    callout.close = make("Button", nil, callout, "UIPanelCloseButton")
    callout.close:SetPoint("TOPRIGHT", 2, 2)
    callout.close:SetScript("OnClick", function() ns.Safe("tutorial dismiss", T.Dismiss) end)
    callout:Hide()   -- hide BEFORE the OnHide script exists
    callout:SetScript("OnHide", function()
        -- Escape closes the whole tour (X semantics); programmatic hides are marked silent.
        if callout.silent or not T.running or T.suspended then return end
        ns.Safe("tutorial escape", T.Dismiss)
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "StreonorDockTutorial") end
    return callout
end
-- Inert illustration of the reload popup for step 5 (never a real confirmation, never reloads).
local function buildExample()
    if example then return example end
    example = make("Frame", "StreonorDockTutorialExample", UIParent, "BackdropTemplate")
    example:SetSize(250, 80)
    example:SetFrameStrata("FULLSCREEN_DIALOG")
    if example.SetBackdrop then
        example:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24, insets = {left = 6, right = 6, top = 6, bottom = 6}})
    end
    local t = example:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOP", 0, -14); t:SetWidth(220); t:SetText("Spells or items changed. Reload the UI now so the controller shows the new icons?")
    for i, label in ipairs({"Reload", "Cancel"}) do
        local b = make("Button", nil, example, "UIPanelButtonTemplate")
        b:SetSize(80, 20); b:SetPoint("BOTTOM", example, "BOTTOM", i == 1 and -45 or 45, 10); b:SetText(label)
        if b.Disable then b:Disable() end
    end
    example:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    example:Hide()
    return example
end

-- ------------------------------------------------------------------ targets
local function minimapButton()
    local dbicon = _G.LibStub and LibStub("LibDBIcon-1.0", true)
    if dbicon and dbicon.GetMinimapButton then
        local ok, b = pcall(dbicon.GetMinimapButton, dbicon, "StreonorDock")
        if ok and b and b.IsShown and b:IsShown() then return b end
    end
end
local function targetFor(key)
    if key == "popup" then return buildExample(), true end
    local bar = ns.Bar
    local visible = bar and bar.IsShown()
    if key == "minimap" then return minimapButton() end
    if not visible then return nil end
    if key == "bar" then return bar.wrapper end
    if key == "padlock" then local f = bar.header.padlock; return f:IsShown() and f or bar.header end
    if key == "cog" then local f = bar.header.cog; return f:IsShown() and f or bar.header end
    if key == "slot" then
        for i = 1, 15 do local b = bar.buttons[i]; if b and b:IsShown() then return b end end
        return bar.wrapper
    end
end

-- ------------------------------------------------------------------ show / hide
local function place(target)
    callout:ClearAllPoints()
    if not target then
        callout.arrow:Hide()
        callout:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
        return
    end
    local _, cy = target:GetCenter()
    local screenH = UIParent:GetHeight() or 768
    local below = not cy or cy > screenH * 0.35     -- room below: callout under the target, arrow on its top edge
    callout:ClearAllPoints()
    callout.arrow:ClearAllPoints()
    if below then
        callout:SetPoint("TOP", target, "BOTTOM", 0, -16)
        callout.arrow:SetPoint("CENTER", callout, "TOP", 0, 2)
    else
        callout:SetPoint("BOTTOM", target, "TOP", 0, 16)
        callout.arrow:SetPoint("CENTER", callout, "BOTTOM", 0, -2)
    end
    callout.arrow:Show()
end
local function render()
    if not T.running or T.suspended then return end
    build()
    local step = STEPS[T.step]
    local target = targetFor(step.key)
    if example and step.key ~= "popup" then example:Hide() end
    if step.key == "popup" then example:Show() end
    local text = step.text
    if not target and step.key ~= "popup" then text = text .. " (Not shown right now, so this callout is at the centre of the screen.)" end
    callout.text:SetText(text)
    callout.progress:SetText(T.step .. "/" .. #STEPS)
    callout.next:SetText(T.step == #STEPS and "Done" or "Next")
    callout:SetHeight(110 + math.floor(#text / 48) * 12)
    place(target)
    callout.silent = true
    callout:Show()
    callout.silent = false
end
local function hideAll()
    if callout then callout.silent = true; callout:Hide(); callout.silent = false end
    if example then example:Hide() end
end
local function release()
    if overridden and ns.Visibility then ns.Visibility.PopOverride() end
    overridden = false
end

function T.Start(manual)
    if T.running then return false end
    if not ns.IsLoaded() then return false end
    local s = state()
    if not manual and (s.seen or s.hidePopups) then return false end
    s.seen = true                     -- persisted now: the automatic tour never repeats
    T.running, T.step, T.suspended = true, 1, false
    if ns.Visibility then ns.Visibility.PushOverride(); overridden = true end
    if InCombatLockdown() then T.suspended = true; return true end   -- resumes when combat ends
    render()
    return true
end
function T.Next()
    if not T.running then return end
    if T.step >= #STEPS then return T.Finish() end
    T.step = T.step + 1
    render()
end
function T.Finish()
    local s = state()
    s.completed = true
    T.running, T.step, T.suspended = false, 0, false
    hideAll(); release()
end
-- X / Escape: closes every remaining tip and remembers it account-wide. Never reset by updates.
function T.Dismiss()
    local s = state()
    s.hidePopups = true
    s.completed = true
    T.running, T.step, T.suspended = false, 0, false
    hideAll(); release()
end
function T.Replay() return T.Start(true) end
function T.Suspend()
    if not T.running then return end
    T.suspended = true
    hideAll()
end
function T.Resume()
    if T.running and T.suspended and not InCombatLockdown() then T.suspended = false; render() end
end
-- Called from PLAYER_ENTERING_WORLD: only the first ever login starts the tour, after the bar exists.
local autoTried = false
function T.WorldEntered()
    if autoTried then return end
    autoTried = true
    if not ns.IsLoaded() then return end
    local s = state()
    if s.seen or s.hidePopups then return end
    local function go() if not T.running then T.Start(false) end end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(3, go) else go() end
end
