local addonName, ns = ...
-- Events (one frame, one handler table), persistence (AceDB), edit/page entry points and /sdock.
local handlers, pending = {}, {}
local loaded = false
local reported = {}
local unavailableEvents = {}
local function say(message) print("StreonorDock: " .. message) end
ns.Say = say
ns.version = "0.3.0"

-- Fail soft: an error in one handler is reported once per label, never spammed.
function ns.Safe(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported[label] then
        reported[label] = true
        say("internal error in " .. label .. " (reported once): " .. tostring(err))
    end
    return ok, err
end
function ns.RunOutOfCombat(work)
    if InCombatLockdown() then pending[#pending+1]=work else work() end
end
local function flushPending()
    if InCombatLockdown() then return end
    local work=pending
    pending={}
    for i=1,#work do ns.RunOutOfCombat(work[i]) end
end
function ns.IsLoaded() return loaded end
function ns.CurrentPage()
    local profile, char = ns.profile, ns.char
    return profile and char and profile.pages[char.currentPage] or ns.Core.newPage()
end
function ns.Module(name) return ns[name] end

-- After any accepted edit, page change or profile switch: bar, secure attributes, export.
function ns.LayoutChanged()
    if ns.Bar then ns.Safe("bar", ns.Bar.Refresh) end
    ns.Safe("secure", ns.Secure.Request)
    ns.Export.MarkDirty()
end

local editMessages = {combat="editing unavailable in combat", slot="that cannot be placed in this slot",
    index="invalid slot", page="invalid page"}
-- Returns accepted, changed, reason. Combat edits are rejected (not queued) and leave state untouched.
function ns.Edit(index, value)
    if not loaded then return false,false,"not-loaded" end
    if ns.readOnly then say("saved data is from a newer version: read-only"); return false,false,"read-only" end
    local ok, changed, reason = ns.Core.setSlot(ns.profile, ns.char.currentPage, index, value, InCombatLockdown())
    if not ok then say(editMessages[reason] or ("edit rejected: " .. tostring(reason))); return false,false,reason end
    if changed then
        if ns.Assign then ns.Assign.NoteChange() end
        ns.LayoutChanged()
    end
    return true,changed
end
-- Internal drag (swap / move). Same rules as Edit.
function ns.MoveSlot(from, to)
    if not loaded then return false,false,"not-loaded" end
    if ns.readOnly then return false,false,"read-only" end
    local ok, changed, reason = ns.Core.moveSlot(ns.profile, ns.char.currentPage, from, to, InCombatLockdown())
    if not ok then say(editMessages[reason] or ("edit rejected: " .. tostring(reason))); return false,false,reason end
    if changed then
        if ns.Assign then ns.Assign.NoteChange() end
        ns.LayoutChanged()
    end
    return true,changed
end
-- action next|prev|home|<number>. Out of combat only; never replayed after combat.
function ns.SetPage(action)
    if not loaded then return false,"not-loaded" end
    if InCombatLockdown() then say("paging unavailable in combat"); return false,"combat" end
    local target = tonumber(action)
    local count = ns.profile.pageCount
    if not target then target = ns.Core.turn(ns.char.currentPage, count, action) end
    target = math.max(1, math.min(count, math.floor(target)))
    if target == ns.char.currentPage then return true end
    ns.char.currentPage = target
    if ns.Assign then ns.Assign.NoteChange() end
    ns.LayoutChanged()
    return true
end
function StreonorDock_Page(action) return ns.SetPage(action) end

-- (Re)binds ns.profile/char after AceDB loads, switches or resets a profile.
local function bind()
    local db = ns.db
    ns.profile, ns.char = db.profile, db.char
    ns.Config.cleanProfile(ns.profile)
    ns.Config.cleanChar(ns.char, ns.profile.pageCount)
    ns.Config.cleanGlobal(db.global)
end
function ns.ProfileChanged()
    if not loaded then return end
    bind()
    if ns.Assign then ns.Assign.NoteChange() end
    ns.LayoutChanged()
    if ns.Options then ns.Safe("options", ns.Options.Refresh) end
end

function handlers.ADDON_LOADED(_, name)
    if name~=addonName or loaded then return end
    -- These are deliberately the only creation/read sites before initialization completes.
    if type(StreonorDockDB)~="table" then StreonorDockDB={} end
    if type(StreonorDockCharDB)~="table" then StreonorDockCharDB={} end
    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if not AceDB then say("AceDB-3.0 is missing: addon disabled."); return end
    local db = AceDB:New("StreonorDockDB", ns.Config.defaults)  -- no defaultProfile: one profile per character
    ns.db, ns.sv = db, StreonorDockDB
    local accountState = ns.Config.migrateAccount(StreonorDockDB, db.global)
    if accountState=="future" then ns.readOnly = true end
    local legacy = StreonorDockCharDB
    if not ns.readOnly then
        local result = ns.Config.migrateCharacter(legacy, db.profile, db.char, db.global)
        if result=="future" then ns.readOnly = true end
    elseif legacy.schemaVersion==nil then legacy.schemaVersion = 0 end
    db.RegisterCallback(ns, "OnProfileChanged", "ProfileChanged")
    db.RegisterCallback(ns, "OnProfileCopied", "ProfileChanged")
    db.RegisterCallback(ns, "OnProfileReset", "ProfileChanged")
    loaded = true
    bind()
    if ns.readOnly then say("saved data is from a newer StreonorDock version: running read-only.") end
    ns.Safe("bar create", function() if ns.Bar then ns.Bar.Create() end end)
    ns.Safe("minimap", function() if ns.Minimap then ns.Minimap.Create() end end)
    ns.Safe("options", function() if ns.Options then ns.Options.Register() end end)
    -- Secure buttons/bindings: now if possible, else queued for PLAYER_REGEN_ENABLED.
    ns.Safe("secure", ns.Secure.Request)
end
local function warnConflicts()
    local status = ns.Secure.status
    if status.bindings=="unavailable" then
        say("override bindings are unavailable on this client: keys will not fire. See /sdock probe.")
        return
    end
    if type(GetBindingAction)~="function" or not status.ready then return end
    local _, conflicts = ns.Secure.Conflicts()
    if conflicts>0 then say(conflicts .. " chord(s) also have other bindings; ours take precedence while loaded. /sdock chords") end
end
function handlers.PLAYER_LOGIN()
    if not loaded then return end
    ns.Safe("secure", ns.Secure.Request)
    ns.LayoutChanged()
    ns.Safe("conflicts", warnConflicts)
end
function handlers.PLAYER_ENTERING_WORLD()
    if not loaded then return end
    ns.Safe("secure", ns.Secure.Request)
    ns.Export.EnteringWorld()
end
function handlers.PLAYER_REGEN_ENABLED()
    if InCombatLockdown() then return end
    flushPending()
    if not loaded then return end
    ns.Safe("secure", ns.Secure.Request)
    if ns.Bar then ns.Safe("bar combat end", ns.Bar.CombatEnded) end
    if ns.Assign then ns.Safe("assign combat end", ns.Assign.CombatEnded) end
    ns.Export.MarkDirty()
end
function handlers.PLAYER_REGEN_DISABLED()
    if not loaded then return end
    if ns.Assign then ns.Safe("assign combat", ns.Assign.CombatStarted) end
    if ns.Bar then ns.Safe("bar combat", ns.Bar.CombatStarted) end
end
function handlers.CVAR_UPDATE(_, cvar)
    if not loaded or ns.Game.issecret(cvar) then return end
    if cvar=="ActionButtonUseKeyDown" or cvar=="ACTION_BUTTON_USE_KEY_DOWN" then ns.Safe("secure", ns.Secure.Request) end
end
function handlers.SPELLS_CHANGED()
    if not loaded then return end
    if ns.Assign then ns.Safe("assign spells", ns.Assign.SpellsChanged) end
    ns.LayoutChanged()
end
local function dataLoaded(kind, id, success)
    if not loaded then return end
    if not ns.Game.OnDataLoaded(kind, id, success) then return end
    if #ns.Core.findSlots(ns.CurrentPage(), kind, id)==0 then return end  -- slot was reassigned meanwhile
    if ns.Bar then ns.Safe("bar", ns.Bar.Refresh) end
    if kind=="spell" then ns.Safe("secure", ns.Secure.Request) end  -- name now known for the attribute
    ns.Export.MarkDirty()
end
function handlers.SPELL_DATA_LOAD_RESULT(_, id, success) dataLoaded("spell", id, success) end
function handlers.ITEM_DATA_LOAD_RESULT(_, id, success) dataLoaded("item", id, success) end
function handlers.BAG_UPDATE_DELAYED()
    if not loaded then return end
    if ns.Display then ns.Safe("display bags", ns.Display.BagsChanged) end
    if ns.Assign then ns.Safe("assign bags", ns.Assign.BagsChanged) end
end
function handlers.BAG_UPDATE_COOLDOWN()
    if loaded and ns.Display then ns.Safe("display cooldowns", ns.Display.CooldownsChanged) end
end
function handlers.SPELL_UPDATE_COOLDOWN()
    if loaded and ns.Display then ns.Safe("display cooldowns", ns.Display.CooldownsChanged) end
end
function handlers.SPELL_UPDATE_CHARGES()
    if loaded and ns.Display then ns.Safe("display cooldowns", ns.Display.CooldownsChanged) end
end
function handlers.PLAYER_LEAVING_WORLD()
    if loaded then ns.Safe("export leaving", ns.Export.LeavingWorld) end
end

local function show(label, value) say(label .. ": " .. (type(value)=="function" and "available" or "unavailable")) end
local function plainText(value)
    if ns.Game.issecret(value) then return "sealed" end
    if value==nil then return "nil" end
    return tostring(value)
end
ns.PlainText = plainText
local function probe()
    -- Presence and states only. Never prints sealed values; never calls uncertain APIs blindly.
    local lib = ns.Game.lib
    local spells, items, book, container, timer = lib("C_Spell"), lib("C_Item"), lib("C_SpellBook"), lib("C_Container"), lib("C_Timer")
    show("SetOverrideBindingClick",SetOverrideBindingClick)
    show("ClearOverrideBindings",ClearOverrideBindings)
    show("GetBindingAction",GetBindingAction)
    show("issecretvalue",issecretvalue)
    show("GetCursorInfo",GetCursorInfo)
    show("C_Spell.GetSpellInfo",spells.GetSpellInfo)
    show("C_Spell.GetSpellCooldownDuration",spells.GetSpellCooldownDuration)
    show("C_Spell.GetSpellChargeDuration",spells.GetSpellChargeDuration)
    show("C_SpellBook.GetNumSpellBookSkillLines",book.GetNumSpellBookSkillLines)
    show("C_SpellBook.GetSpellBookSkillLineInfo",book.GetSpellBookSkillLineInfo)
    show("C_SpellBook.GetSpellBookItemInfo",book.GetSpellBookItemInfo)
    show("C_SpellBook.IsSpellKnown",book.IsSpellKnown)
    show("C_Item.GetItemInfoInstant",items.GetItemInfoInstant)
    show("C_Item.GetItemClassInfo",items.GetItemClassInfo)
    show("C_Item.GetItemCooldown",items.GetItemCooldown)
    show("C_Container.GetContainerNumSlots",container.GetContainerNumSlots)
    show("C_Container.GetContainerItemInfo",container.GetContainerItemInfo)
    show("C_Timer.NewTimer",timer.NewTimer)
    show("MenuUtil.CreateContextMenu",lib("MenuUtil").CreateContextMenu)
    show("Settings.RegisterCanvasLayoutCategory",lib("Settings").RegisterCanvasLayoutCategory)
    show("StaticPopup_Show",StaticPopup_Show)
    if type(GetCVarBool)=="function" then
        local ok, value = pcall(GetCVarBool, "ActionButtonUseKeyDown")
        say("ActionButtonUseKeyDown: " .. (ok and plainText(value) or "unreadable"))
    end
    say("WOW_PROJECT_ID: " .. plainText(WOW_PROJECT_ID))
    if type(GetBuildInfo)=="function" then
        local ok, version, build, _, interface = pcall(GetBuildInfo)
        if ok then say("build: " .. plainText(version) .. "." .. plainText(build) .. " interface " .. plainText(interface)) end
    end
    local s = ns.Secure.status
    say("secure buttons: " .. (s.ready and "created" or ("not created" .. (ns.Secure.IsQueued() and " (queued for after combat)" or "")))
        .. "; template " .. plainText(s.template) .. "; click on key " .. (s.keyDown==nil and "?" or (s.keyDown and "down" or "up")))
    say("overrides: " .. s.bindings .. " (" .. s.applied .. "/15); effective lookup verified "
        .. (s.verified==nil and "not checkable" or (s.verified .. "/15")))
    if #unavailableEvents>0 then say("events not registered: " .. table.concat(unavailableEvents, ", ")) end
    say("Presence does not verify behavior; follow the in-game checklist in README.md.")
end
local function describe(value)
    if not value or value.kind=="empty" then return "empty" end
    local name
    if value.kind=="spell" then name = ns.Game.SpellMeta(value.id) else name = ns.Game.ItemMeta(value.id) end
    return value.kind .. " " .. value.id .. (value.pinned and " (rank pinned)" or "") .. (name and (" " .. name) or "")
end
local function chords()
    local page = ns.CurrentPage()
    local status = ns.Secure.status
    say("page " .. ns.char.currentPage .. "; overrides " .. status.bindings .. " (" .. status.applied .. "/15)")
    if type(GetBindingAction)~="function" then
        for i=1,15 do say(i .. " " .. ns.Core.chord(i) .. " -> " .. describe(page[i])) end
        say("GetBindingAction unavailable: conflicts cannot be checked.")
        return
    end
    local rows, conflicts = ns.Secure.Conflicts()
    for i, row in ipairs(rows) do
        local effective = not row.effectiveKnown and "?" or (row.ours and "ours" or (row.effective or "none"))
        say(i .. " " .. row.chord .. " -> " .. describe(page[i]) .. " | ordinary: " .. (row.ordinary or "none")
            .. " | effective: " .. effective .. (row.conflict and "  CONFLICT" or ""))
    end
    say(conflicts .. " conflict(s). 'effective' uses GetBindingAction(key, true); if it never says 'ours' after login, that lookup is unsupported or overrides failed.")
end
local function clicksReport(arg)
    if arg=="reset" then ns.Secure.ResetClicks(); say("click counters reset"); return end
    local any = false
    for i=1,15 do
        local c = ns.Secure.clicks[i]
        if c.down>0 or c.up>0 then
            any = true
            say("slot " .. i .. ": down edges " .. c.down .. ", up edges " .. c.up .. ", use attempts " .. c.attempts)
        end
    end
    if not any then say("no secure clicks received yet: press a key once, then run /sdock clicks (expect down 1, attempts 1)") end
    say("keys act on the DOWN edge only; counters show input routing, not success; '/sdock clicks reset' clears them.")
end
local function exportReport()
    local s = ns.Export.Summary()
    if not s then say("no in-memory export yet"); return end
    say("export: enabled=" .. tostring(s.enabled) .. " page=" .. plainText(s.page) .. " icons resolved " .. s.resolved
        .. ", unresolved " .. s.unresolved .. " (icons only; written to disk on reload/logout)")
end
local function help()
    say("/sdock settings | assign | toggle | page next|prev|home|<n> | reset position | chords | probe | export | clicks | spellprobe | help")
    say("/sdock settings opens the settings window; /sdock assign locks/unlocks assignment mode (works with the bar hidden).")
    say("Pager keys: Game Menu > Key Bindings > StreonorDock.")
end
SLASH_STREONORDOCK1="/sdock"
SLASH_STREONORDOCK2="/streonordock"
SlashCmdList.STREONORDOCK=function(message)
    local command, arg, arg2 = string.match(string.lower(message or ""),"^%s*(%S*)%s*(%S*)%s*(%S*)")
    if not loaded and command~="probe" and command~="help" and command~="" then say("not loaded yet"); return end
    if command=="probe" then ns.Safe("probe", probe)
    elseif command=="settings" or command=="config" or command=="options" then
        if ns.Options then ns.Safe("settings", ns.Options.Open) else say("settings unavailable") end
    elseif command=="assign" then
        if ns.Assign then ns.Safe("assign", ns.Assign.Toggle) else say("assignment unavailable") end
    elseif command=="toggle" then
        if ns.Bar then ns.Safe("toggle", ns.Bar.ToggleShown) end
    elseif command=="reset" then
        if arg=="position" and ns.Bar then ns.Safe("reset position", ns.Bar.ResetPosition) else say("usage: /sdock reset position") end
    elseif command=="page" then
        if arg=="next" or arg=="prev" or arg=="home" or tonumber(arg) then ns.SetPage(arg) else say("usage: /sdock page next|prev|home|<n>") end
    elseif command=="chords" then ns.Safe("chords", chords)
    elseif command=="clicks" then ns.Safe("clicks", clicksReport, arg)
    elseif command=="spellprobe" then
        if ns.Catalog then ns.Safe("spellprobe", ns.Catalog.Probe, arg) end
    elseif command=="export" then ns.Safe("export summary", exportReport)
    else help() end
    return arg2
end
BINDING_HEADER_STREONORDOCK="StreonorDock"
BINDING_NAME_STREONORDOCK_NEXT="Next page (out of combat)"
BINDING_NAME_STREONORDOCK_PREV="Previous page (out of combat)"
BINDING_NAME_STREONORDOCK_HOME="Home page (out of combat)"
-- A/B diagnostic bindings (Bindings.xml): bind a spare key here to test a slot button without
-- our override path. The addon never sets or saves these itself.
BINDING_HEADER_STREONORDOCK_SLOTS="StreonorDock slots (diagnostic)"
for i=1,15 do
    _G["BINDING_NAME_CLICK StreonorDockSlot" .. i .. ":LeftButton"]="Slot " .. i .. " (same as " .. ns.Core.chord(i) .. ")"
end
local frame=CreateFrame("Frame")
for event in pairs(handlers) do
    -- An event unknown to this client would throw; record it for /sdock probe instead.
    if not pcall(frame.RegisterEvent, frame, event) then unavailableEvents[#unavailableEvents+1]=event end
end
table.sort(unavailableEvents)
frame:SetScript("OnEvent",function(self,event,...)
    local handler=handlers[event]
    if handler then ns.Safe(event, handler, self, ...) end
end)
