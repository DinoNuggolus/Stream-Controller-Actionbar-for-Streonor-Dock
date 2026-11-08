local addonName, ns = ...
-- WoW data adapter. Every game read goes through here, is guarded with issecretvalue BEFORE any
-- comparison, arithmetic or storage, and only plain values leave this module.
local Game = {}
ns.Game = Game
local requested = {spell={}, item={}}   -- metadata load requests in flight (dedupe)
local failed = {spell={}, item={}}      -- loads that reported failure this session
local attempts = {spell={}, item={}}    -- requests per ID this session (capped: no request loops)
Game.MAX_REQUESTS = 3

function Game.issecret(value)
    if type(issecretvalue)~="function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    -- If the predicate itself fails, treat the value as secret (fail closed).
    return not ok or secret==true
end
local issecret = Game.issecret
local function plain(v) if not issecret(v) then return v end end
local function finite(v)
    v = plain(v)
    if type(v)=="number" and v==v and v>-math.huge and v<math.huge then return v end
end
local function positiveInteger(v)
    v = finite(v)
    if v and v>0 and v==math.floor(v) then return v end
end
local function call(fn, ...)
    if type(fn)~="function" then return false end
    return pcall(fn, ...)
end
local function lib(name)
    local t = _G[name]
    if type(t)=="table" then return t end
    return {}
end
Game.plain, Game.finite, Game.positiveInteger, Game.call, Game.lib = plain, finite, positiveInteger, call, lib
function Game.Now() return finite((type(GetTime)=="function") and GetTime() or nil) end

local function request(kind, itemID)
    if requested[kind][itemID] or failed[kind][itemID] then return end
    if (attempts[kind][itemID] or 0)>=Game.MAX_REQUESTS then return end
    local fn = kind=="spell" and lib("C_Spell").RequestLoadSpellData or lib("C_Item").RequestLoadItemDataByID
    attempts[kind][itemID]=(attempts[kind][itemID] or 0)+1
    if call(fn, itemID) then requested[kind][itemID]=true end
end

-- name, iconFileID (each plain or nil). Missing data triggers one load request.
function Game.SpellMeta(spellID)
    if not positiveInteger(spellID) then return nil end
    local C_Spell = lib("C_Spell")
    local name, icon
    local ok, info = call(C_Spell.GetSpellInfo, spellID)
    info = ok and plain(info) or nil
    if type(info)=="table" then
        name = plain(info.name); icon = positiveInteger(info.iconID)
    end
    if not icon then
        local okTexture, texture = call(C_Spell.GetSpellTexture, spellID)
        if okTexture then icon = positiveInteger(texture) end
    end
    if type(name)~="string" or name=="" then name=nil end
    if not name or not icon then request("spell", spellID) end
    return name, icon
end
function Game.ItemMeta(itemID)
    if not positiveInteger(itemID) then return nil end
    local C_Item = lib("C_Item")
    local name, icon
    local ok, value = call(C_Item.GetItemIconByID, itemID)
    if ok then icon = positiveInteger(value) end
    ok, value = call(C_Item.GetItemNameByID, itemID)
    if ok then name = plain(value) end
    if type(name)~="string" or name=="" then
        local okInfo, infoName = call(C_Item.GetItemInfo, itemID)
        name = okInfo and plain(infoName) or nil
    end
    if type(name)~="string" or name=="" then name=nil end
    if not name or not icon then request("item", itemID) end
    return name, icon
end
-- Icon (positive integer or nil) for a stored slot.
function Game.SlotIcon(slot)
    if type(slot)~="table" then return nil end
    if slot.kind=="spell" then local _, icon = Game.SpellMeta(slot.id); return icon end
    if slot.kind=="item" then local _, icon = Game.ItemMeta(slot.id); return icon end
end
-- Spellbook fallback when GetCursorInfo gives no spell ID:
-- C_SpellBook.GetSpellBookItemType(slot, bank) -> itemType, actionID; spells only.
function Game.ResolveSpellbookSpell(slot, bookType)
    local book, enum = lib("C_SpellBook"), lib("Enum")
    local banks, types = type(enum.SpellBookSpellBank)=="table" and enum.SpellBookSpellBank or {},
        type(enum.SpellBookItemType)=="table" and enum.SpellBookItemType or {}
    slot = positiveInteger(slot)
    if not slot or banks.Player==nil or types.Spell==nil or issecret(bookType) then return nil end
    if bookType=="pet" or (bookType~=nil and bookType==banks.Pet) then return nil end
    local ok, itemType, actionID = call(book.GetSpellBookItemType, slot, banks.Player)
    if ok and not issecret(itemType) and itemType==types.Spell then return positiveInteger(actionID) end
end
-- True when a higher rank of this spell is known (decided once, at assignment time; the slot is
-- then pinned to this exact rank by ID). Unknown/unavailable -> false (cast by name = top rank).
function Game.IsLowRank(spellID)
    local book = lib("C_SpellBook")
    if not positiveInteger(spellID) then return false end
    local ok, slot, bank = call(book.FindSpellBookSlotForSpell, spellID, true)
    if not ok or issecret(slot) or issecret(bank) or slot==nil then return false end
    local okRank, low = call(book.IsSpellBookItemLowRank, slot, bank)
    return okRank and not issecret(low) and low==true
end
function Game.MetaFailed(kind, itemID) return failed[kind] and failed[kind][itemID] or false end
-- Late SPELL_DATA_LOAD_RESULT / ITEM_DATA_LOAD_RESULT. Results for IDs we did not request are ignored.
-- Returns true when the result belongs to us.
function Game.OnDataLoaded(kind, itemID, success)
    itemID = positiveInteger(itemID)
    if not itemID or not requested[kind] or not requested[kind][itemID] then return false end
    requested[kind][itemID]=nil
    if plain(success)==false then failed[kind][itemID]=true end
    return true
end
function Game.ForgetRequests()
    for _, kind in ipairs({"spell","item"}) do requested[kind], failed[kind], attempts[kind] = {}, {}, {} end
end
-- Carried count of an item across bags; nil when unreadable. Zero is a real count.
function Game.ItemCount(itemID)
    if not positiveInteger(itemID) then return nil end
    local ok, count = call(lib("C_Item").GetItemCount, itemID)
    count = ok and finite(count) or nil
    if count and count>=0 and count==math.floor(count) then return count end
end
function Game.Build()
    if type(GetBuildInfo)~="function" then return nil end
    local ok, version, build = pcall(GetBuildInfo)
    if ok and type(plain(version))=="string" and type(plain(build))=="string" then return version .. "." .. build end
end

-- ------------------------------------------------------------------ cooldown / charge readers (bar display)
-- Spell cooldown. Returns {object=opaque|nil, start=, duration=, onGCD=bool, secret=bool}. The duration
-- object is NEVER inspected here (it may be restricted); numeric fields are present only when plain.
function Game.SpellCooldown(spellID, ignoreGCD)
    local out = {}
    spellID = positiveInteger(spellID)
    if not spellID then return out end
    local C_Spell = lib("C_Spell")
    if type(C_Spell.GetSpellCooldownDuration) == "function" then
        local ok, object = pcall(C_Spell.GetSpellCooldownDuration, spellID, ignoreGCD ~= false)
        if ok and object ~= nil then out.object = object end
    end
    local ok, info = call(C_Spell.GetSpellCooldown, spellID)
    if ok then
        if issecret(info) then out.secret = true
        elseif type(info) == "table" then
            if issecret(info.startTime) or issecret(info.duration) then out.secret = true
            else
                out.start, out.duration = finite(info.startTime), finite(info.duration)
                out.onGCD = plain(info.isOnGCD) == true
            end
        end
    end
    return out
end
-- Charges: {current=, max=} (plain, max>1 only) | nil, secret=bool. Recharge duration object when offered.
function Game.SpellCharges(spellID)
    spellID = positiveInteger(spellID)
    if not spellID then return nil end
    local C_Spell = lib("C_Spell")
    local ok, info = call(C_Spell.GetSpellCharges, spellID)
    if not ok then return nil end
    if issecret(info) then return nil, true end
    if type(info) ~= "table" then return nil end
    if issecret(info.currentCharges) or issecret(info.maxCharges) then return nil, true end
    local current, max = finite(info.currentCharges), positiveInteger(info.maxCharges)
    if not current or not max or max < 2 then return nil end
    local object
    if type(C_Spell.GetSpellChargeDuration) == "function" then
        local okObj, obj = pcall(C_Spell.GetSpellChargeDuration, spellID)
        if okObj then object = obj end
    end
    return {current = current, max = max, object = object}
end
-- Item cooldown: numeric only when plain and enabled. Returns {start=,duration=} | {unavailable=true}.
function Game.ItemCooldown(itemID)
    itemID = positiveInteger(itemID)
    local fn = lib("C_Item").GetItemCooldown
    if not itemID or type(fn) ~= "function" then return {unavailable = true} end
    local ok, start, duration, enabled = pcall(fn, itemID)
    if not ok then return {unavailable = true} end
    -- Restricted values are handed to the Cooldown widget untouched (no arithmetic, no comparison).
    if issecret(start) or issecret(duration) then return {secret = true, rawStart = start, rawDuration = duration} end
    if issecret(enabled) then return {unavailable = true} end
    start, duration = finite(start), finite(duration)
    if not start or not duration then return {unavailable = true} end
    if enabled == false or enabled == 0 then return {unavailable = true} end
    return {start = start, duration = duration}
end
-- Remaining seconds of an opaque duration object when (and only when) the number is plain.
function Game.ObjectRemaining(object)
    if object == nil then return nil end
    local fn = type(object) == "table" and object.GetRemainingDuration or nil
    if type(fn) ~= "function" then return nil end
    local ok, remaining = pcall(fn, object)
    if not ok then return nil end
    return finite(remaining)
end
