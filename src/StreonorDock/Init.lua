local addonName, ns = ...
-- Events (one frame, one handler table), persistence, edit/page entry points and /sdock.
local handlers, pending = {}, {}
local loaded = false
local reported = {}
local unavailableEvents = {}
local function say(message) print("StreonorDock: " .. message) end
ns.Say = say

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
local function newProfileId()
    -- Opaque random 128-bit token; no player or realm data and no global RNG reseeding.
    local parts={}
    for i=1,8 do parts[i]=string.format("%04x",math.random(0,65535)) end
    return table.concat(parts,"-")
end
function ns.SetState(state)
    ns.state=state
    StreonorDockCharDB=state
end
-- After any accepted edit or page change: panel, secure attributes, cooldowns, snapshot.
function ns.LayoutChanged()
    ns.Safe("panel", ns.Panel.Refresh)
    ns.Safe("secure", ns.Secure.Request)
    ns.Safe("cooldowns", ns.Export.ObserveItems)
    ns.Safe("panel cooldowns", ns.Panel.RefreshCooldowns)
    ns.Safe("export", ns.Export.Refresh)
end

local editMessages = {combat="editing unavailable in combat", slot="that cannot be placed in this slot",
    index="invalid slot", area="invalid slot"}
-- Returns accepted, reason. Combat edits are rejected (not queued) and leave state untouched.
function ns.Edit(area, index, value)
    if not loaded then return false,"not-loaded" end
    local state, accepted, reason = ns.Core.assign(ns.state, area, index, value, InCombatLockdown())
    if not accepted then say(editMessages[reason] or ("edit rejected: " .. tostring(reason))); return false,reason end
    ns.SetState(state)
    ns.LayoutChanged()
    return true
end

function StreonorDock_Page(action)
    if not loaded then return nil,false,"not-loaded" end
    local state, accepted, reason=ns.Core.page(ns.state,action,InCombatLockdown())
    if accepted and state~=ns.state then ns.SetState(state); ns.LayoutChanged()
    elseif reason=="combat" then say("paging unavailable in combat")
    elseif reason=="limit" then say("maximum of 10 pages reached") end
    return state,accepted,reason
end

local function sanitizeSettings(db)
    if type(db.settings)~="table" then db.settings={} end
    local e = db.settings.estimates
    if e~="on" and e~="off" then db.settings.estimates="auto" end
    if db.settings.logChat~=false then db.settings.logChat=true end
    if db.settings.logCombat~=false then db.settings.logCombat=true end
    ns.Export.ResetProbeForBuild(ns.Export.Build())
    if type(db.cooldownLearned)~="table" then db.cooldownLearned={} end
    if type(db.ui)~="table" then db.ui={} end
end

function handlers.ADDON_LOADED(_, name)
    if name~=addonName or loaded then return end
    -- These are deliberately the only creation/read sites before initialization completes.
    if type(StreonorDockDB)~="table" then StreonorDockDB={} end
    sanitizeSettings(StreonorDockDB)
    local saved=StreonorDockCharDB
    local profileId
    if type(saved)=="table" and type(saved.profileId)=="string" and saved.profileId~="" then
        profileId=saved.profileId
    else profileId=newProfileId() end
    ns.SetState(ns.Core.recover(saved,profileId))
    -- Self-verifying cooldown table: learning persists account-wide in StreonorDockDB.cooldownLearned.
    ns.cooldowns=ns.CooldownTracker.new(StreonorDockDB.cooldownLearned, ns.CooldownGroups, ns.ItemGroups,
        {build=ns.Export.Build(), wallClock=ns.Export.ServerNow, issecret=ns.Export.issecret})
    loaded=true
    ns.Safe("panel create", ns.Panel.Create)
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
-- Client file logging switches (LogsWoWChatLog.txt / WoWCombatLog.txt) for an EXTERNAL reader.
-- The addon only flips the client's own switches: it never reads or parses either log, registers no
-- combat-log events, and never assumes the call worked (read back when a reader API exists).
local logging = {chat="not requested", combat="not requested"}
local logApi = {chat={fn="LoggingChat", read="IsLoggingChat", setting="logChat"},
    combat={fn="LoggingCombat", read="IsLoggingCombat", setting="logCombat"}}
local loggingApplied = false
local function setLogging(kind, wanted)
    local api = logApi[kind]
    local fn = _G[api.fn]
    if type(fn)~="function" then logging[kind]="unavailable"; return end
    if not pcall(fn, wanted) then logging[kind]="error"; return end
    local info = _G.C_ChatInfo
    local reader = type(info)=="table" and info[api.read] or nil
    if type(reader)=="function" then
        local ok, value = pcall(reader)
        if ok and not ns.Export.issecret(value) and type(value)=="boolean" then
            logging[kind] = (value==wanted) and (wanted and "on" or "off") or ("requested, reads " .. (value and "on" or "off"))
            return
        end
    end
    logging[kind] = wanted and "requested (unverified)" or "off requested (unverified)"
end
local function applyLogging()
    if loggingApplied then return end
    loggingApplied = true
    for kind, api in pairs(logApi) do
        if StreonorDockDB.settings[api.setting]==true then setLogging(kind, true)
        else logging[kind]="disabled in settings" end
    end
end
local function logCommand(arg1, arg2)
    local api = logApi[arg1]
    if api and (arg2=="on" or arg2=="off") then
        StreonorDockDB.settings[api.setting] = arg2=="on"
        setLogging(arg1, arg2=="on")
    elseif arg1~="" then
        say("usage: /sdock log | log chat on|off | log combat on|off"); return
    end
    say("chat logging: " .. logging.chat .. " (setting " .. (StreonorDockDB.settings.logChat and "on" or "off") .. ")")
    say("combat logging: " .. logging.combat .. " (setting " .. (StreonorDockDB.settings.logCombat and "on" or "off") .. ")")
end
function handlers.PLAYER_LOGIN()
    if not loaded then return end
    ns.Safe("logging", applyLogging)
    ns.Safe("secure", ns.Secure.Request)
    ns.LayoutChanged()
    ns.Safe("conflicts", warnConflicts)
end
function handlers.PLAYER_ENTERING_WORLD()
    if not loaded then return end
    ns.Safe("logging", applyLogging)
    ns.Safe("secure", ns.Secure.Request)
    ns.Export.EnteringWorld()
end
function handlers.PLAYER_REGEN_ENABLED()
    if InCombatLockdown() then return end
    flushPending()
    if not loaded then return end
    -- Re-assert overrides/attributes after combat and reconcile cooldowns with readable data.
    ns.Safe("secure", ns.Secure.Request)
    ns.Safe("cooldowns", ns.Export.ObserveItems)
    ns.Safe("panel cooldowns", ns.Panel.RefreshCooldowns)
    ns.Export.MarkDirty()
end
function handlers.CVAR_UPDATE(_, cvar)
    if not loaded or ns.Export.issecret(cvar) then return end
    if cvar=="ActionButtonUseKeyDown" or cvar=="ACTION_BUTTON_USE_KEY_DOWN" then ns.Safe("secure", ns.Secure.Request) end
end
function handlers.SPELLS_CHANGED()
    if not loaded then return end
    ns.Safe("panel", ns.Panel.Refresh)
    ns.Safe("secure", ns.Secure.Request)
end
local function dataLoaded(kind, id, success)
    if not loaded then return end
    local matches = ns.Export.OnDataLoaded(kind, id, success)
    if #matches==0 then return end   -- slot was reassigned meanwhile: nothing to update
    ns.Safe("panel", ns.Panel.RefreshSlots, matches)
    if kind=="spell" then ns.Safe("secure", ns.Secure.Request) end  -- name now known for the attribute
    ns.Export.MarkDirty()
end
function handlers.SPELL_DATA_LOAD_RESULT(_, id, success) dataLoaded("spell", id, success) end
function handlers.ITEM_DATA_LOAD_RESULT(_, id, success) dataLoaded("item", id, success) end
function handlers.BAG_UPDATE_COOLDOWN()
    if not loaded then return end
    ns.Safe("cooldowns", ns.Export.ObserveItems)
    ns.Safe("panel cooldowns", ns.Panel.RefreshCooldowns)
    ns.Export.MarkDirty()
end
function handlers.BAG_UPDATE_DELAYED()
    if not loaded then return end
    ns.Safe("panel", ns.Panel.Refresh)
    ns.Safe("cooldowns", ns.Export.ObserveItems)
    ns.Export.MarkDirty()
end
function handlers.PLAYER_MONEY()
    if not loaded then return end
    ns.Safe("readouts", ns.Panel.RefreshReadouts)
    ns.Export.MarkDirty()
end
function handlers.CURRENCY_DISPLAY_UPDATE()
    if not loaded then return end
    ns.Safe("readouts", ns.Panel.RefreshReadouts)
    ns.Export.MarkDirty()
end
function handlers.PLAYER_REGEN_DISABLED()
    -- The picker edits layout, which is out-of-combat only: close it when combat starts.
    if loaded then ns.Safe("picker", ns.Panel.ClosePicker) end
end
function handlers.PLAYER_LEAVING_WORLD()
    if loaded then ns.Safe("export leaving", ns.Export.LeavingWorld) end
end
function handlers.PLAYER_LOGOUT()
    if loaded then ns.Safe("export stamp", ns.Export.StampSaved) end
end

local function lib2(name) local t=_G[name]; return type(t)=="table" and t or {} end
local function show(label, value) say(label .. ": " .. (type(value)=="function" and "available" or "unavailable")) end
local function plainText(value)
    if ns.Export.issecret(value) then return "sealed" end
    if value==nil then return "nil" end
    return tostring(value)
end
local function exportSummary()
    local e=ns.Core.sanitize(StreonorDockDB.export, ns.Export.issecret)
    if type(e)~="table" then say("no in-memory export yet"); return end
    local player=type(e.player)=="table" and e.player or {}
    local rows={"money=" .. (player.moneyCopper~=nil and "present" or "unknown"),
        "freeBagSlots=" .. plainText(player.freeBagSlots)}
    -- Access the original count only via plainText: even diagnostic corruption stays sealed.
    for _, area in ipairs({"slots","readouts"}) do
        for i, entry in ipairs(e[area] or {}) do
            if entry.kind=="item" then
                rows[#rows+1]=area .. "[" .. i .. "]=" .. plainText(StreonorDockDB.export[area][i].count)
            end
        end
    end
    rows[#rows+1]="savedAt=" .. plainText(StreonorDockDB.export.savedAt)
    rows[#rows+1]="countsStale=" .. (e.countsStale and "true" or "false")
    say(table.concat(rows, "; "))
end
local function probe()
    -- Presence and states only. Never prints sealed values; never calls uncertain APIs blindly.
    local function lib(name) local t=_G[name]; return type(t)=="table" and t or {} end
    local spells, items, book, container, timer = lib("C_Spell"), lib("C_Item"), lib("C_SpellBook"), lib("C_Container"), lib("C_Timer")
    show("SetOverrideBindingClick",SetOverrideBindingClick)
    show("ClearOverrideBindings",ClearOverrideBindings)
    show("GetBindingAction",GetBindingAction)
    show("issecretvalue",issecretvalue)
    show("GetCursorInfo",GetCursorInfo)
    show("C_Spell.GetSpellInfo",spells.GetSpellInfo)
    show("C_Spell.GetSpellTexture",spells.GetSpellTexture)
    show("C_Spell.RequestLoadSpellData",spells.RequestLoadSpellData)
    show("C_Spell.GetSpellBaseCooldown",spells.GetSpellBaseCooldown)
    show("GetSpellBaseCooldown (global)",GetSpellBaseCooldown)
    show("C_SpellBook.FindSpellBookSlotForSpell",book.FindSpellBookSlotForSpell)
    show("C_SpellBook.IsSpellBookItemLowRank",book.IsSpellBookItemLowRank)
    show("C_SpellBook.GetSpellBookItemType",book.GetSpellBookItemType)
    show("C_Item.GetItemInfo",items.GetItemInfo)
    show("C_Item.GetItemIconByID",items.GetItemIconByID)
    show("C_Item.GetItemNameByID",items.GetItemNameByID)
    show("C_Item.RequestLoadItemDataByID",items.RequestLoadItemDataByID)
    show("C_Item.GetItemCount",items.GetItemCount)
    show("C_Item.GetItemCooldown",items.GetItemCooldown)
    show("C_Item.GetItemSpell",items.GetItemSpell)
    show("C_Container.GetContainerNumFreeSlots",container.GetContainerNumFreeSlots)
    show("C_Timer.NewTimer",timer.NewTimer)
    local currency = lib("C_CurrencyInfo")
    show("C_CurrencyInfo.GetCurrencyListSize",currency.GetCurrencyListSize)
    show("C_CurrencyInfo.GetCurrencyListInfo",currency.GetCurrencyListInfo)
    show("C_CurrencyInfo.GetCurrencyInfo",currency.GetCurrencyInfo)
    show("C_CurrencyInfo.ExpandCurrencyList",currency.ExpandCurrencyList)
    show("GetServerTime",GetServerTime); show("GetTime",GetTime); show("GetMoney",GetMoney)
    show("GetCVarBool",GetCVarBool)
    if type(currency.GetCurrencyListSize)=="function" and not InCombatLockdown() then
        say("currencies available to pick now: " .. #ns.Export.ListCurrencies())
    end
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
    local st, db = ns.Export.stats, StreonorDockDB or {}
    local probeDb = type(db.probe)=="table" and db.probe or {}
    say("item cooldown reads this session: " .. st.reads .. " (readable " .. st.readable .. ", sealed " .. st.sealed
        .. ", unavailable " .. st.unavailable .. "); press estimates started " .. st.estimates)
    say("readable in combat: " .. (probeDb.combatReadable==nil and "not yet observed" or tostring(probeDb.combatReadable))
        .. "; estimates " .. tostring(type(db.settings)=="table" and db.settings.estimates or "auto")
        .. " -> " .. (ns.Export.EstimatesEnabled() and "on" or "off"))
    if ns.cooldowns then
        local rows = ns.cooldowns:groupReport(ns.Export.ItemCount)
        say("cooldown table: " .. #rows .. " group(s) with an item in your bags (table vs observed):")
        for _, row in ipairs(rows) do say("  " .. ns.FormatGroupRow(row)) end
    end
    if #unavailableEvents>0 then say("events not registered: " .. table.concat(unavailableEvents, ", ")) end
    say("Presence does not verify behavior; follow the in-game checklist in README.md.")
end
local function seconds(v) if type(v)=="number" then return v .. "s" end; return "?" end
function ns.FormatGroupRow(row)
    local items = {}
    for _, entry in ipairs(row.items) do
        items[#items+1] = entry.itemID .. (entry.count and ("x" .. entry.count) or "")
            .. (entry.override and (" own " .. seconds(entry.override)) or "")
    end
    local sharing = ""
    if row.sharing then
        sharing = row.sharing.sharedVerified and "; pool sharing seen" or (row.sharing.notShared and "; NOT shared evidence" or "")
    end
    return row.group .. (row.pool and (" [pool " .. row.pool .. "]") or "") .. ": table "
        .. (row.table==0 and "none (0)" or seconds(row.table)) .. ", observed " .. (row.learned and seconds(row.learned) or "-")
        .. (row.verified and " (verified this build)" or "") .. sharing .. "; items " .. table.concat(items, ", ")
end
-- Learned data for folding into the next CooldownData.lua (the addon never rewrites it).
local function cooldowns()
    local tracker = ns.cooldowns
    local store = tracker.store
    say("learned cooldowns (build " .. tostring(store.build) .. "); the shipped table is never rewritten:")
    local any = false
    for key, g in pairs(store.groups) do
        any = true
        say("  group " .. key .. " = " .. seconds(g.duration) .. (g.verified and " verified" or " unverified")
            .. "; items seen " .. table.concat(g.itemsSeen, ", "))
    end
    for itemID, v in pairs(store.items) do
        any = true
        say("  item " .. itemID .. " = " .. seconds(v.duration) .. (v.verified and " verified" or " unverified")
            .. (tracker:group(itemID) and (" (split from " .. tracker:group(itemID) .. ")") or " (not in table)"))
    end
    for label, p in pairs(store.pools) do
        any = true
        say("  pool " .. label .. ": " .. (p.sharedVerified and "shared lock seen" or (p.notShared and "member stayed ready (not shared?)" or "no evidence")))
    end
    if not any then say("  nothing learned yet: press a cooldown item on a dock key out of combat.") end
    for _, e in ipairs(tracker.log) do
        say("  log: " .. e.kind .. " item " .. tostring(e.itemID) .. (e.group and (" group " .. e.group) or "")
            .. (e.pool and (" pool " .. e.pool) or "") .. (e.other and (" other " .. e.other) or "")
            .. (e.game and (" game " .. seconds(e.game)) or "") .. (e.table and (" table " .. seconds(e.table)) or "")
            .. (e.group_duration and (" group value " .. seconds(e.group_duration)) or ""))
    end
end
local function describe(value)
    if not value or value.kind=="empty" then return "empty" end
    local name
    if value.kind=="spell" then name = ns.Export.SpellMeta(value.id) else name = ns.Export.ItemMeta(value.id) end
    return value.kind .. " " .. value.id .. (value.pinned and " (rank pinned)" or "") .. (name and (" " .. name) or "")
end
local function chords()
    local page = ns.state.pages[ns.state.currentPage]
    local status = ns.Secure.status
    say("page " .. ns.state.currentPage .. "; overrides " .. status.bindings .. " (" .. status.applied .. "/15)")
    if type(GetBindingAction)~="function" then
        for i=1,15 do say(i .. " " .. ns.Core.chord(i) .. " -> " .. describe(page.slots[i])) end
        say("GetBindingAction unavailable: conflicts cannot be checked.")
        return
    end
    local rows, conflicts = ns.Secure.Conflicts()
    for i, row in ipairs(rows) do
        local effective = not row.effectiveKnown and "?" or (row.ours and "ours" or (row.effective or "none"))
        say(i .. " " .. row.chord .. " -> " .. describe(page.slots[i]) .. " | ordinary: " .. (row.ordinary or "none")
            .. " | effective: " .. effective .. (row.conflict and "  CONFLICT" or ""))
    end
    say(conflicts .. " conflict(s). 'effective' uses GetBindingAction(key, true); if it never says 'ours' after login, that lookup is unsupported or overrides failed.")
end
-- Diagnostic for the user to run in game: plain values only, sealed values are reported as "sealed".
local function cdprobe()
    local fn = _G.GetSpellBaseCooldown
    say("cdprobe: GetSpellBaseCooldown global " .. (type(fn)=="function" and "available" or "missing")
        .. "; C_Spell.GetSpellBaseCooldown " .. (type(lib2("C_Spell").GetSpellBaseCooldown)=="function" and "available" or "missing")
        .. "; combat lockdown " .. tostring(InCombatLockdown()))
    local page = ns.state.pages[ns.state.currentPage]
    for _, area in ipairs({"slots","readouts"}) do
        for index, value in ipairs(page[area]) do
            if value.kind=="spell" or value.kind=="item" then
                local id = value.id or value.itemID
                local row = area .. "[" .. index .. "] " .. value.kind .. " " .. id
                local spellID = id
                if value.kind=="item" then
                    local getSpell = lib2("C_Item").GetItemSpell
                    local okSpell, name, sid
                    if type(getSpell)=="function" then okSpell, name, sid = pcall(getSpell, id) end
                    spellID = okSpell and not ns.Export.issecret(sid) and tonumber(sid) or nil
                    row = row .. " -> spell " .. plainText(spellID)
                end
                local first, second = "n/a", "n/a"
                if spellID and type(fn)=="function" then
                    local ok, a, b = pcall(fn, spellID)
                    if ok then first, second = plainText(a), plainText(b) else first, second = "error", "error" end
                end
                row = row .. " | base raw " .. first .. ", " .. second .. " (ms?)"
                local seconds, source = ns.Export.SpellBase(spellID)
                row = row .. " -> " .. (seconds and (seconds .. "s " .. source) or "none")
                if value.kind=="spell" then
                    local learned, verified = ns.Export.SpellLearned(id)
                    local start, length = ns.Export.ReadSpellCooldown(id)
                    row = row .. " | learned " .. (learned and (learned .. "s" .. (verified and " verified" or "")) or "-")
                        .. " | GetSpellCooldown " .. (start and "plain" or tostring(length))
                        .. " | charges " .. plainText(ns.Export.MaxCharges(id))
                else
                    local learned = ns.cooldowns and ns.cooldowns:learnedDuration(id)
                    local group = ns.cooldowns and ns.cooldowns:group(id)
                    local shipped = group and ns.CooldownGroups[group] and ns.CooldownGroups[group].duration
                    local start, length = ns.Export.ReadItemCooldown(id)
                    row = row .. " | learned " .. (learned and (learned .. "s") or "-") .. " | shipped " .. plainText(shipped)
                        .. " | GetItemCooldown " .. (start and "plain" or tostring(length))
                end
                local exported = StreonorDockDB.export and StreonorDockDB.export[area] and StreonorDockDB.export[area][index]
                row = row .. " | exported " .. (exported and exported.cooldownSeconds and (exported.cooldownSeconds .. "s " .. tostring(exported.cooldownSource)) or "none")
                say(row)
            end
        end
    end
end
local function estimates(arg)
    if arg=="on" or arg=="off" or arg=="auto" then StreonorDockDB.settings.estimates=arg end
    say("press estimates: " .. StreonorDockDB.settings.estimates .. " -> " .. (ns.Export.EstimatesEnabled() and "on" or "off")
        .. " (usage: /sdock estimates on|off|auto)")
end
local function help()
    say("/sdock toggle | page next|prev|home | chords | probe | cooldowns | export | estimates on|off|auto | cdprobe | log [chat|combat on|off] | help")
    say("Drag a spell or bag item onto a key; click a readout to pick money or a currency; right-click clears. Out of combat only.")
    say("Pager keys: Game Menu > Key Bindings > StreonorDock.")
end
SLASH_STREONORDOCK1="/sdock"
SlashCmdList.STREONORDOCK=function(message)
    local command, arg, arg2 = string.match(string.lower(message or ""),"^%s*(%S*)%s*(%S*)%s*(%S*)")
    if not loaded and command~="probe" and command~="help" and command~="" then say("not loaded yet"); return end
    if command=="probe" then ns.Safe("probe", probe)
    elseif command=="toggle" then ns.Safe("toggle", ns.Panel.Toggle)
    elseif command=="page" then
        if arg=="next" or arg=="prev" or arg=="home" then StreonorDock_Page(arg) else say("usage: /sdock page next|prev|home") end
    elseif command=="chords" then ns.Safe("chords", chords)
    elseif command=="estimates" then ns.Safe("estimates", estimates, arg)
    elseif command=="cooldowns" then ns.Safe("cooldowns", cooldowns)
    elseif command=="cdprobe" then ns.Safe("cdprobe", cdprobe)
    elseif command=="log" then ns.Safe("log", logCommand, arg, arg2)
    elseif command=="export" then
        ns.Safe("export summary", exportSummary)
    else help() end
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
