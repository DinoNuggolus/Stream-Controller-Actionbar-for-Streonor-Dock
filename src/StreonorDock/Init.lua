local addonName, ns = ...
-- PART 1 SKELETON: event/persistence/pager infrastructure only. No protected UI exists yet.
local handlers, pending = {}, {}
local loaded = false
local function say(message) print("StreonorDock: " .. message) end
function ns.RunOutOfCombat(work)
    if InCombatLockdown() then pending[#pending+1]=work else work() end
end
function handlers.PLAYER_REGEN_ENABLED()
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
function handlers.ADDON_LOADED(_, name)
    if name~=addonName or loaded then return end
    -- These are deliberately the only creation/read sites before initialization completes.
    if type(StreonorDockDB)~="table" then StreonorDockDB={} end
    local saved=StreonorDockCharDB
    local profileId
    if type(saved)=="table" and type(saved.profileId)=="string" and saved.profileId~="" then
        profileId=saved.profileId
    else profileId=newProfileId() end
    StreonorDockCharDB=ns.Core.recover(saved,profileId)
    ns.state=StreonorDockCharDB
    ns.cooldowns=ns.CooldownTracker.new()
    loaded=true
    -- TODO(part 2): queue protected initialization, refresh sanitized export after login.
end
function StreonorDock_Page(action)
    if not loaded then return nil,false,"not-loaded" end
    local state, accepted, reason=ns.Core.page(ns.state,action,InCombatLockdown())
    if accepted then ns.state=state; StreonorDockCharDB=state
    elseif reason=="combat" then say("paging unavailable in combat")
    elseif reason=="limit" then say("maximum of 10 pages reached") end
    -- TODO(part 2): update secure actions, panel and export on an accepted page change.
    return state,accepted,reason
end
local function probe()
    -- Availability only. No binding installation, cooldown calls, secret reads or API guesses.
    local function available(label,value)
        say(label .. ": " .. (type(value)=="function" and "available" or "unavailable"))
    end
    local spells=type(C_Spell)=="table" and C_Spell or {}
    local items=type(C_Item)=="table" and C_Item or {}
    available("SetOverrideBindingClick",SetOverrideBindingClick)
    available("GetBindingAction",GetBindingAction)
    available("issecretvalue",issecretvalue)
    available("C_Spell.GetSpellInfo",spells.GetSpellInfo)
    available("C_Spell.RequestLoadSpellData",spells.RequestLoadSpellData)
    available("C_Item.GetItemInfo",items.GetItemInfo)
    available("C_Item.RequestLoadItemDataByID",items.RequestLoadItemDataByID)
    available("C_Item.GetItemCooldown",items.GetItemCooldown)
    available("GetServerTime",GetServerTime)
    available("GetTime",GetTime)
    available("GetCVarBool",GetCVarBool)
    say("Presence does not verify signatures, readable values, or override behavior; part 2 needs live tests.")
end
local function help()
    say("/sdock help | probe | chords | export. Pager keys: Game Key Bindings > StreonorDock.")
    say("Part 1: editor, secure actions and snapshot wiring are pending part 2.")
end
SLASH_STREONORDOCK1="/sdock"
SlashCmdList.STREONORDOCK=function(message)
    local command=string.lower(string.match(message or "","^%s*(%S+)") or "help")
    if command=="probe" then probe()
    elseif command=="chords" then
        for i=1,15 do say(i .. ": " .. ns.Core.chord(i)) end
        say("Conflict audit and effective overrides: TODO(part 2); no overrides installed.")
    elseif command=="export" then
        say("Snapshot wiring: TODO(part 2). Once wired, disk saves require /reload or logout.")
    else help() end
end
BINDING_HEADER_STREONORDOCK="StreonorDock"
BINDING_NAME_STREONORDOCK_NEXT="Next page (out of combat)"
BINDING_NAME_STREONORDOCK_PREV="Previous page (out of combat)"
BINDING_NAME_STREONORDOCK_HOME="Home page (out of combat)"
local frame=CreateFrame("Frame")
for event in pairs(handlers) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function(self,event,...)
    local handler=handlers[event]
    if handler then handler(self,...) end
end)
