local addonName, ns = ...
-- WoW data adapter. Every game read goes through here, is guarded with issecretvalue BEFORE any
-- comparison, arithmetic or storage, and is sanitized again before Core sees it. Core never
-- receives a secret. Unavailable readings are omitted, never kept from an earlier read.
-- Exported snapshot = StreonorDockDB.export (account-wide, no character names). It reaches disk
-- only at /reload, logout or exit: consumers must label it "saved snapshot" and show its age.
local Export = {}
ns.Export = Export
Export.stats = {reads=0, readable=0, sealed=0, unavailable=0, estimates=0}
local requested = {spell={}, item={}}   -- metadata load requests in flight (dedupe)
local failed = {spell={}, item={}}      -- loads that reported failure this session
local attempts = {spell={}, item={}}    -- requests per ID this session (capped: no request loops)
Export.MAX_REQUESTS = 3
local dirtyScheduled = false

function Export.issecret(value)
    if type(issecretvalue)~="function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    -- If the predicate itself fails, treat the value as secret (fail closed).
    return not ok or secret==true
end
local issecret = Export.issecret
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
Export.plain, Export.finite = plain, finite

function Export.Now() return finite((type(GetTime)=="function") and GetTime() or nil) end
function Export.ServerNow()
    local t = finite((type(GetServerTime)=="function") and GetServerTime() or nil)
    if t then return math.floor(t) end
end

local function request(kind, itemID)
    if requested[kind][itemID] or failed[kind][itemID] then return end
    if (attempts[kind][itemID] or 0)>=Export.MAX_REQUESTS then return end
    local fn = kind=="spell" and lib("C_Spell").RequestLoadSpellData or lib("C_Item").RequestLoadItemDataByID
    attempts[kind][itemID]=(attempts[kind][itemID] or 0)+1
    if call(fn, itemID) then requested[kind][itemID]=true end
end

-- name, iconFileID (each plain or nil). Missing data triggers one load request.
function Export.SpellMeta(spellID)
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
function Export.ItemMeta(itemID)
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
-- Spellbook fallback when GetCursorInfo gives no spell ID (BindPad's approach on this client):
-- C_SpellBook.GetSpellBookItemType(slot, bank) -> itemType, actionID; spells only.
function Export.ResolveSpellbookSpell(slot, bookType)
    local book, enum = lib("C_SpellBook"), lib("Enum")
    local banks, types = type(enum.SpellBookSpellBank)=="table" and enum.SpellBookSpellBank or {},
        type(enum.SpellBookItemType)=="table" and enum.SpellBookItemType or {}
    slot = positiveInteger(slot)
    if not slot or banks.Player==nil or types.Spell==nil or issecret(bookType) then return nil end
    if bookType=="pet" or (bookType~=nil and bookType==banks.Pet) then return nil end
    local ok, itemType, actionID = call(book.GetSpellBookItemType, slot, banks.Player)
    if ok and not issecret(itemType) and itemType==types.Spell then return positiveInteger(actionID) end
end
-- True when a higher rank of this spell is known (decided once, at drop time; the slot is then
-- pinned to this exact rank by ID). Unknown/unavailable -> false (cast by name = highest rank).
function Export.IsLowRank(spellID)
    local book = lib("C_SpellBook")
    if not positiveInteger(spellID) then return false end
    local ok, slot, bank = call(book.FindSpellBookSlotForSpell, spellID, true)
    if not ok or issecret(slot) or issecret(bank) or slot==nil then return false end
    local okRank, low = call(book.IsSpellBookItemLowRank, slot, bank)
    return okRank and not issecret(low) and low==true
end
function Export.MetaFailed(kind, itemID) return failed[kind] and failed[kind][itemID] or false end

-- Late SPELL_DATA_LOAD_RESULT / ITEM_DATA_LOAD_RESULT. Carries no metadata: callers re-read the
-- slot that holds this identity NOW (Core.findSlots), so a reassigned slot is never overwritten.
-- Results for IDs we did not request (other addons' loads) are ignored.
function Export.OnDataLoaded(kind, itemID, success)
    itemID = positiveInteger(itemID)
    if not itemID or not requested[kind] or not requested[kind][itemID] then return {} end
    requested[kind][itemID]=nil
    if plain(success)==false then failed[kind][itemID]=true end
    return ns.Core.findSlots(ns.state, kind, itemID)
end

function Export.ItemCount(itemID)
    if not positiveInteger(itemID) then return nil end
    local ok, count = call(lib("C_Item").GetItemCount, itemID)
    count = ok and finite(count) or nil
    if count and count>=0 and count==math.floor(count) then return count end
end

-- start, duration (GetTime clock) only when the reading is plain and enabled; otherwise nil plus
-- "sealed" | "paused" | "unavailable". Raw values never leave this function unguarded.
function Export.ReadItemCooldown(itemID)
    local fn = lib("C_Item").GetItemCooldown
    if type(fn)~="function" or not positiveInteger(itemID) then return nil,"unavailable" end
    Export.stats.reads = Export.stats.reads+1
    local ok, start, duration, enabled = pcall(fn, itemID)
    if not ok then Export.stats.unavailable=Export.stats.unavailable+1; return nil,"unavailable" end
    if issecret(start) or issecret(duration) or issecret(enabled) then
        Export.stats.sealed=Export.stats.sealed+1
        return nil,"sealed"
    end
    start, duration = finite(start), finite(duration)
    if not start or not duration then Export.stats.unavailable=Export.stats.unavailable+1; return nil,"unavailable" end
    -- enableCooldownTimer false/0 = timer paused (e.g. potion used in combat): not a usable reading.
    if enabled==false or enabled==0 then return nil,"paused" end
    Export.stats.readable=Export.stats.readable+1
    return start, duration
end

-- Item base cooldown in seconds, ONLY if the client exposes a base-cooldown API (probed, never
-- assumed): C_Item.GetItemSpell(itemID) -> spellID, then C_Spell.GetSpellBaseCooldown or the
-- GetSpellBaseCooldown global, whose first return is treated as milliseconds (unverified).
function Export.BaseCooldown(itemID)
    local getSpell = lib("C_Item").GetItemSpell
    local getBase = lib("C_Spell").GetSpellBaseCooldown
    if type(getBase)~="function" then getBase = GetSpellBaseCooldown end
    if type(getSpell)~="function" or type(getBase)~="function" or not positiveInteger(itemID) then return nil end
    local ok, _, spellID = pcall(getSpell, itemID)
    spellID = ok and positiveInteger(spellID) or nil
    if not spellID then return nil end
    local okBase, ms = pcall(getBase, spellID)
    ms = okBase and finite(ms) or nil
    if ms and ms>1500 then return ms/1000 end
end

-- Estimates (press-started timers) are a setting: "on", "off" or "auto" (default). Auto turns
-- them off only after a readable ACTIVE item cooldown (duration > 1.5 s) was seen in combat on
-- this client build and no sealed reading was seen in combat on this build.
function Export.EstimatesEnabled()
    local db = type(StreonorDockDB)=="table" and StreonorDockDB or {}
    local settings = type(db.settings)=="table" and db.settings or {}
    if settings.estimates=="on" then return true end
    if settings.estimates=="off" then return false end
    local probe = type(db.probe)=="table" and db.probe or {}
    return probe.combatReadable~=true
end
-- The combat-readability evidence belongs to one client build; a build change resets it.
function Export.ResetProbeForBuild(build)
    if type(StreonorDockDB)~="table" then return end
    local probe = type(StreonorDockDB.probe)=="table" and StreonorDockDB.probe or {}
    if probe.build~=build then probe = {build=build} end
    if type(probe.combatReadable)~="boolean" then probe.combatReadable=nil end
    StreonorDockDB.probe = probe
end
-- kind: "readable" (with its duration) or "sealed". Ready/GCD readings are not evidence: a plain
-- 0,0 says nothing about whether an ACTIVE cooldown would be sealed. Sealed evidence wins.
function Export.NoteCombatReading(kind, duration)
    if type(StreonorDockDB)~="table" or type(InCombatLockdown)~="function" or not InCombatLockdown() then return end
    if type(StreonorDockDB.probe)~="table" then StreonorDockDB.probe={} end
    local probe = StreonorDockDB.probe
    if kind=="sealed" then probe.combatReadable=false; probe.sealedSeen=true
    elseif kind=="readable" and type(duration)=="number" and duration>1.5 and not probe.sealedSeen then
        probe.combatReadable=true
    end
end
local noteCombatReading = Export.NoteCombatReading

-- PostClick of OUR secure key button holding this item (runs in combat too). Always records the
-- press time (own-use learning); starts the press timer only if estimates are enabled, the bag
-- count is plain and > 0, the item is not dormant and no timer for its key is running.
function Export.OnKeyPress(itemID)
    itemID = positiveInteger(itemID)
    local now, tracker = Export.Now(), ns.cooldowns
    if not itemID or not now or not tracker then return false end
    local estimate = Export.EstimatesEnabled()
    -- Out of combat with a plain reading the game will report the real cooldown itself
    -- (Amendment 2 item 7): record the press for learning, but start no estimate.
    if estimate and type(InCombatLockdown)=="function" and not InCombatLockdown() then
        if Export.ReadItemCooldown(itemID) then estimate=false end
    end
    local started = tracker:press(itemID, now, Export.ItemCount(itemID), Export.BaseCooldown(itemID), estimate)
    if started then Export.stats.estimates=Export.stats.estimates+1 end
    return started
end

-- Client build string for the learning store ("<version>.<build>"), or nil if unreadable.
function Export.Build()
    if type(GetBuildInfo)~="function" then return nil end
    local ok, version, build = pcall(GetBuildInfo)
    if ok and type(plain(version))=="string" and type(plain(build))=="string" then return version .. "." .. build end
end

-- Reconcile with the game: every item on the current page, every item with a live timer (any
-- page) and the HELD members of those timers' pools (sharing evidence). Readable data overrides
-- estimates; sealed/unavailable readings change nothing. Items not in the bags are never read
-- for evidence (an absent item reads as ready and would fake "not shared").
function Export.ObserveItems()
    local tracker, now = ns.cooldowns, Export.Now()
    if not tracker or not now or not ns.state then return end
    local seen = {}
    local function observe(itemID)
        if seen[itemID] then return end
        seen[itemID]=true
        local start, duration = Export.ReadItemCooldown(itemID)
        if start then
            noteCombatReading("readable", duration)
            -- The count lets the tracker ignore "ready" from an item no longer in the bags.
            tracker:observe(itemID, start, duration, now, Export.ItemCount(itemID))
        elseif duration=="sealed" then
            noteCombatReading("sealed")
        end
    end
    -- Starters of running timers first, so sharing evidence never depends on item-ID order.
    for _, itemID in ipairs(tracker:activeItems(now)) do observe(itemID) end
    for _, itemID in ipairs(ns.Core.pageItems(ns.state)) do observe(itemID) end
    -- Recomputed: a timer the readings above just started also gets its pool members read.
    for _, itemID in ipairs(tracker:activeItems(now)) do
        for _, member in ipairs(tracker:poolMembers(itemID)) do
            local count = Export.ItemCount(member)
            if count and count>0 then observe(member) end
        end
    end
end

-- Free slots in general-purpose bags (bag family 0). nil if any reading is not plain.
function Export.FreeBagSlots()
    local C_Container = lib("C_Container")
    if type(C_Container.GetContainerNumFreeSlots)~="function" then return nil end
    local last = type(NUM_BAG_SLOTS)=="number" and NUM_BAG_SLOTS or 4
    local total = 0
    for bag=0,last do
        local ok, free, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
        if not ok or issecret(free) or issecret(family) then return nil end
        free = finite(free)
        if free and (family==nil or family==0) then total = total+free end
    end
    return total
end
function Export.Money()
    local ok, money = call(GetMoney)
    money = ok and finite(money) or nil
    return money
end

-- Raw provider tables for Core.buildExport; sanitized by Export.Collect before Core sees them.
local function rawProviders()
    local spells, items = {}, {}
    local state, tracker = ns.state, ns.cooldowns
    local page = state.pages[state.currentPage]
    local now, serverNow = Export.Now(), Export.ServerNow()
    for _, area in ipairs({"slots","readouts"}) do
        for _, value in ipairs(page[area]) do
            if value.kind=="spell" and not spells[value.id] then
                local name, icon = Export.SpellMeta(value.id)
                spells[value.id] = {name=name, iconFileID=icon}
            elseif value.kind=="item" then
                local itemID = value.id or value.itemID
                if not items[itemID] then
                    local name, icon = Export.ItemMeta(itemID)
                    local entry = {name=name, iconFileID=icon, count=Export.ItemCount(itemID)}
                    if tracker and now then
                        local endsAt, _, source = tracker:timer(itemID, now)  -- source game|est|used
                        if source then entry.source=source end
                        if endsAt and serverNow then entry.endsAt=math.floor(serverNow + (endsAt-now) + 0.5) end
                    end
                    items[itemID]=entry
                end
            end
        end
    end
    return {spells=spells, items=items, player={moneyCopper=Export.Money(), freeBagSlots=Export.FreeBagSlots()}}
end
function Export.Collect()
    return ns.Core.sanitize(rawProviders(), issecret)
end

function Export.Refresh()
    dirtyScheduled = false
    if not ns.state or type(StreonorDockDB)~="table" then return false end
    StreonorDockDB.export = ns.Core.buildExport(ns.state, Export.ServerNow(), issecret, Export.Collect())
    return true
end
-- Coalesce bursts of bag/money/cooldown events into one rebuild a second later.
function Export.MarkDirty()
    if dirtyScheduled then return end
    local timer = lib("C_Timer")
    if type(timer.After)=="function" then
        dirtyScheduled = true
        local ok = pcall(timer.After, 1, function() ns.Safe("export", Export.Refresh) end)
        if ok then return end
        dirtyScheduled = false
    end
    Export.Refresh()
end
