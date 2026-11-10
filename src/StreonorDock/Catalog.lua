local addonName, ns = ...
-- What can be assigned: known spells by spellbook tab, and carried bag items by game classification.
-- Scanning is the only part that touches the game (all values guarded, plain-only); the grouping, sorting
-- and menu model below are pure. No guessed legacy fallbacks: a missing enumeration API disables that
-- picker with an explanation. Never runs in combat.
local Catalog = {}
ns.Catalog = Catalog
local Game = ns.Game
local plain, positiveInteger, call, lib = Game.plain, Game.positiveInteger, Game.call, Game.lib

local function str(v) v = plain(v); if type(v) == "string" and v ~= "" then return v end end
local function sortKey(name) return string.lower(name or "") end

-- ------------------------------------------------------------------ spells
-- Returns lines = {{index=, name=, icon=, specID=, offSpecID=, spells={{id,name,rank,icon,pinned}}}}, nil | reason.
function Catalog.ScanSpells()
    local book, enum = lib("C_SpellBook"), lib("Enum")
    if type(book.GetNumSpellBookSkillLines) ~= "function" or type(book.GetSpellBookSkillLineInfo) ~= "function"
        or type(book.GetSpellBookItemInfo) ~= "function" or type(book.IsSpellKnown) ~= "function" then
        return nil, "The spellbook enumeration API is not available on this client."
    end
    local banks = type(enum.SpellBookSpellBank) == "table" and enum.SpellBookSpellBank or {}
    local types = type(enum.SpellBookItemType) == "table" and enum.SpellBookItemType or {}
    if banks.Player == nil then return nil, "Enum.SpellBookSpellBank.Player is not available." end
    local okN, count = call(book.GetNumSpellBookSkillLines)
    count = okN and positiveInteger(count) or 0
    local lines, seen = {}, {}
    for i = 1, count do
        local ok, info = call(book.GetSpellBookSkillLineInfo, i)
        info = ok and plain(info) or nil
        if type(info) == "table" then
            local offset = positiveInteger(info.itemIndexOffset) or (plain(info.itemIndexOffset) == 0 and 0) or nil
            local num = positiveInteger(info.numSpellBookItems)
            local line = {index = i, name = str(info.name) or ("Tab " .. i), icon = positiveInteger(info.iconID),
                specID = positiveInteger(info.specID), offSpecID = positiveInteger(info.offSpecID), spells = {}}
            if offset and num then
                for index = offset + 1, offset + num do
                    local okItem, item = call(book.GetSpellBookItemInfo, index, banks.Player)
                    item = okItem and plain(item) or nil
                    if type(item) == "table" then
                        local itemType = plain(item.itemType)
                        local spellID = positiveInteger(item.spellID) or positiveInteger(item.actionID)
                        local isSpell = types.Spell == nil or itemType == types.Spell
                        local passive = plain(item.isPassive) == true
                        local hidden = plain(item.isHidden) == true
                        if isSpell and spellID and not passive and not hidden and not seen[spellID] then
                            local okKnown, known = call(book.IsSpellKnown, spellID, banks.Player)
                            if okKnown and plain(known) == true then
                                seen[spellID] = true
                                local lowRank = false
                                if type(book.IsSpellBookItemLowRank) == "function" then
                                    local okLow, low = call(book.IsSpellBookItemLowRank, index, banks.Player)
                                    lowRank = okLow and plain(low) == true
                                end
                                line.spells[#line.spells + 1] = {id = spellID, name = str(item.name), rank = str(item.subName),
                                    icon = positiveInteger(item.iconID), pinned = lowRank}
                            end
                        end
                    end
                end
            end
            lines[#lines + 1] = line
        end
    end
    -- Fill missing names/icons from spell data (requests loads; menu rebuilds on open).
    for _, line in ipairs(lines) do
        for _, s in ipairs(line.spells) do
            if not s.name or not s.icon then
                local name, icon = Game.SpellMeta(s.id)
                s.name, s.icon = s.name or name, s.icon or icon
            end
        end
    end
    return lines
end

local function rankNumber(rank) return tonumber(rank and string.match(rank, "(%d+)") or "") or 0 end
function Catalog.SortSpells(list)
    table.sort(list, function(a, b)
        local an, bn = sortKey(a.name), sortKey(b.name)
        if an ~= bn then return an < bn end
        local ar, br = rankNumber(a.rank), rankNumber(b.rank)
        if ar ~= br then return ar > br end   -- highest rank first
        return a.id < b.id
    end)
    return list
end

-- ------------------------------------------------------------------ items
-- Returns groups = { [classID] = {label=, subs={[subID]={label=, items={{id,name,icon,count}}}}} }, pending, nil | reason
function Catalog.ScanItems()
    local container, items = lib("C_Container"), lib("C_Item")
    if type(container.GetContainerNumSlots) ~= "function" or type(container.GetContainerItemInfo) ~= "function" then
        return nil, 0, "The bag enumeration API is not available on this client."
    end
    if type(items.GetItemInfoInstant) ~= "function" then return nil, 0, "C_Item.GetItemInfoInstant is not available on this client." end
    local last = type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS or 4
    local bags = {}
    for bag = 0, last do bags[#bags + 1] = bag end
    local enumBag = lib("Enum").BagIndex
    local reagent = type(enumBag) == "table" and positiveInteger(enumBag.ReagentBag) or nil
    if reagent then
        local present = false
        for _, b in ipairs(bags) do if b == reagent then present = true end end
        if not present then bags[#bags + 1] = reagent end
    end
    local totals, order = {}, {}
    for _, bag in ipairs(bags) do
        local okS, slots = call(container.GetContainerNumSlots, bag)
        slots = okS and positiveInteger(slots) or 0
        for slot = 1, slots do
            local ok, info = call(container.GetContainerItemInfo, bag, slot)
            info = ok and plain(info) or nil
            if type(info) == "table" then
                local id, stack = positiveInteger(info.itemID), plain(info.stackCount)
                if id then
                    if not totals[id] then totals[id] = 0; order[#order + 1] = id end
                    if type(stack) == "number" and stack == stack and stack > 0 then totals[id] = totals[id] + stack end
                end
            end
        end
    end
    local groups, pending = {}, 0
    for _, id in ipairs(order) do
        local ok, _, itemType, itemSubType, _, icon, classID, subClassID = call(items.GetItemInfoInstant, id)
        classID = ok and plain(classID) or nil
        local usable = Game.ItemUsable(id)
        if usable == nil then
            pending = pending + 1   -- item data not loaded yet: decided on a later scan, never guessed
        elseif usable == false then
            -- no use effect (trade goods, junk, plain gear): not assignable
        elseif type(classID) ~= "number" or classID ~= classID then
            pending = pending + 1   -- metadata not ready: never guess a class
        else
            subClassID = plain(subClassID); if type(subClassID) ~= "number" then subClassID = 0 end
            local group = groups[classID]
            if not group then
                local label
                if type(items.GetItemClassInfo) == "function" then local okL, l = call(items.GetItemClassInfo, classID); label = okL and str(l) or nil end
                group = {label = label or str(itemType) or ("Class " .. classID), subs = {}}
                groups[classID] = group
            end
            local sub = group.subs[subClassID]
            if not sub then
                local label
                if type(items.GetItemSubClassInfo) == "function" then
                    local okL, l = call(items.GetItemSubClassInfo, classID, subClassID); label = okL and str(l) or nil
                end
                sub = {label = label or str(itemSubType) or ("Subclass " .. subClassID), items = {}}
                group.subs[subClassID] = sub
            end
            local name, ic = Game.ItemMeta(id)
            sub.items[#sub.items + 1] = {id = id, name = name or ("Item " .. id), icon = positiveInteger(icon) or ic, count = totals[id]}
        end
    end
    return groups, pending
end
local function sortedKeys(t, labelOf)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local la, lb = sortKey(labelOf(t[a])), sortKey(labelOf(t[b]))
        if la ~= lb then return la < lb end
        return a < b
    end)
    return keys
end

-- ------------------------------------------------------------------ macros
-- Returns {general = {...}, character = {...}, charName = string}; empty categories stay empty lists.
function Catalog.ScanMacros()
    return {general = Game.MacroList("account"), character = Game.MacroList("character"), charName = Game.PlayerName()}
end

-- ------------------------------------------------------------------ menu model (pure)
local NONE = {text = "None available", disabled = true}
local function same(slot, kind, id, pinned)
    return type(slot) == "table" and slot.kind == kind and slot.id == id and (slot.pinned == true) == (pinned == true)
end
-- data = {spells = lines|nil, spellError=, items = groups|nil, itemError=, pending=}
-- current = the slot's stored value; pick(value) / clear() are called on selection.
function Catalog.BuildMenu(data, current, pick, clear)
    local entries = {}
    local spellEntries = {}
    if data.spells then
        for _, line in ipairs(data.spells) do
            local list = {}
            Catalog.SortSpells(line.spells)
            for _, s in ipairs(line.spells) do
                local label = s.name or ("Spell " .. s.id)
                if s.pinned and s.rank then label = label .. " (" .. s.rank .. ")"
                elseif s.pinned then label = label .. " (lower rank)" end
                local value = {kind = "spell", id = s.id}
                if s.pinned then value.pinned = true end
                list[#list + 1] = {text = label, icon = s.icon, checked = same(current, "spell", s.id, s.pinned),
                    func = function() pick(value) end}
            end
            if #list > 0 then
                spellEntries[#spellEntries + 1] = {text = line.name, icon = line.icon, submenu = list, scroll = 420}
            end
        end
        if #spellEntries == 0 then spellEntries[1] = NONE end
    else
        spellEntries[1] = {text = data.spellError or "Unavailable", disabled = true}
    end
    entries[#entries + 1] = {text = "Spells", submenu = spellEntries}
    local itemEntries = {}
    if data.items then
        local classKeys = sortedKeys(data.items, function(g) return g.label end)
        for _, classID in ipairs(classKeys) do
            local group = data.items[classID]
            local subKeys = sortedKeys(group.subs, function(s) return s.label end)
            local subEntries = {}
            for _, subID in ipairs(subKeys) do
                local sub = group.subs[subID]
                table.sort(sub.items, function(a, b)
                    local an, bn = sortKey(a.name), sortKey(b.name)
                    if an ~= bn then return an < bn end
                    return a.id < b.id
                end)
                local list = {}
                for _, it in ipairs(sub.items) do
                    local value = {kind = "item", id = it.id}
                    list[#list + 1] = {text = it.name .. (it.count and it.count > 1 and (" x" .. it.count) or ""), icon = it.icon,
                        checked = same(current, "item", it.id), func = function() pick(value) end}
                end
                subEntries[#subEntries + 1] = {text = sub.label, submenu = list, scroll = 420}
            end
            itemEntries[#itemEntries + 1] = {text = group.label, submenu = subEntries}
        end
        if #itemEntries == 0 then itemEntries[1] = NONE end
    else
        itemEntries[1] = {text = data.itemError or "Unavailable", disabled = true}
    end
    entries[#entries + 1] = {text = "Items", submenu = itemEntries}
    local macroEntries = {}
    local function macroList(list)
        table.sort(list, function(a, b)
            local an, bn = sortKey(a.name), sortKey(b.name)
            if an ~= bn then return an < bn end
            return a.index < b.index
        end)
        local out = {}
        for _, m in ipairs(list) do
            local value = {kind = "macro", name = m.name, scope = m.scope}
            out[#out + 1] = {text = m.name, icon = m.icon, checked = type(current) == "table" and current.kind == "macro"
                and current.name == m.name and current.scope == m.scope, func = function() pick(value) end}
        end
        return out
    end
    if data.macros then
        if #data.macros.general > 0 then macroEntries[#macroEntries + 1] = {text = "General", submenu = macroList(data.macros.general), scroll = 420} end
        if #data.macros.character > 0 then macroEntries[#macroEntries + 1] = {text = data.macros.charName or "Character", submenu = macroList(data.macros.character), scroll = 420} end
    end
    if #macroEntries == 0 then macroEntries[1] = NONE end
    entries[#entries + 1] = {text = "Macros", submenu = macroEntries}
    entries[#entries + 1] = {divider = true}
    entries[#entries + 1] = {text = "Clear slot", disabled = type(current) ~= "table" or current.kind == "empty", func = clear}
    return entries
end

function Catalog.Collect()
    local data = {}
    data.spells, data.spellError = Catalog.ScanSpells()
    data.items, data.pending, data.itemError = Catalog.ScanItems()
    data.macros = Catalog.ScanMacros()
    return data
end

-- Membership revalidation when an entry is chosen (a stale menu can never assign something absent).
function Catalog.Validate(value)
    if type(value) ~= "table" then return false end
    if value.kind == "spell" then
        local lines = Catalog.ScanSpells()
        for _, line in ipairs(lines or {}) do for _, s in ipairs(line.spells) do if s.id == value.id then return true end end end
        return false
    elseif value.kind == "item" then
        local count = Game.ItemCount(value.id)
        return count ~= nil and count > 0
    elseif value.kind == "macro" then
        return Game.MacroIndex(value.name, value.scope) ~= nil
    end
    return false
end

-- ------------------------------------------------------------------ /sdock spellprobe
local function show(label, v) ns.Say(label .. ": " .. (type(v) == "function" and "available" or "unavailable")) end
function Catalog.Probe(arg)
    if InCombatLockdown() then ns.Say("probe unavailable in combat"); return end
    local book, items = lib("C_SpellBook"), lib("C_Item")
    show("C_SpellBook.GetNumSpellBookSkillLines", book.GetNumSpellBookSkillLines)
    show("C_SpellBook.GetSpellBookSkillLineInfo", book.GetSpellBookSkillLineInfo)
    show("C_SpellBook.GetSpellBookItemInfo", book.GetSpellBookItemInfo)
    show("C_SpellBook.IsSpellKnown", book.IsSpellKnown)
    show("C_SpellBook.IsSpellBookItemLowRank", book.IsSpellBookItemLowRank)
    show("C_Item.GetItemInfoInstant", items.GetItemInfoInstant)
    show("C_Item.GetItemClassInfo", items.GetItemClassInfo)
    local record = {spellLines = {}, itemClasses = {}}
    local okN, n = call(book.GetNumSpellBookSkillLines)
    ns.Say("skill lines: " .. ns.PlainText(okN and n or nil))
    if okN and positiveInteger(n) then
        for i = 1, positiveInteger(n) do
            local ok, info = call(book.GetSpellBookSkillLineInfo, i)
            info = ok and plain(info) or nil
            if type(info) == "table" then
                local row = {index = i, name = str(info.name), offset = positiveInteger(info.itemIndexOffset) or plain(info.itemIndexOffset),
                    count = positiveInteger(info.numSpellBookItems), specID = positiveInteger(info.specID),
                    offSpecID = positiveInteger(info.offSpecID), isGuild = plain(info.isGuild)}
                record.spellLines[#record.spellLines + 1] = row
                ns.Say(string.format("  line %d '%s' offset=%s items=%s specID=%s offSpecID=%s", i, tostring(row.name), tostring(row.offset),
                    tostring(row.count), tostring(row.specID), tostring(row.offSpecID)))
            end
        end
    end
    local lines = Catalog.ScanSpells()
    for _, line in ipairs(lines or {}) do ns.Say("  known in '" .. line.name .. "': " .. #line.spells) end
    local groups, pending, err = Catalog.ScanItems()
    ns.Say("bag items: " .. (groups and ("classes shown " .. (function() local c = 0; for _ in pairs(groups) do c = c + 1 end; return c end)() .. ", pending metadata " .. pending) or err))
    for classID, g in pairs(groups or {}) do record.itemClasses[#record.itemClasses + 1] = {classID = classID, label = g.label} end
    if ns.db then ns.db.global.spellProbe = record end
    ns.Say("Findings are stored in SavedVariables (StreonorDockDB.global.spellProbe) after /reload for documentation.")
end

-- /sdock macroprobe: harmless facts about the client's macro API and cursor payload.
function Catalog.MacroProbe()
    local a, c = Game.MacroCounts()
    local base, fromClient = Game.MacroBase()
    ns.Say("GetNumMacros: account " .. a .. ", character " .. c .. "; MAX_ACCOUNT_MACROS " .. ns.PlainText(_G.MAX_ACCOUNT_MACROS)
        .. (fromClient and "" or " (missing: 120 assumed)") .. ", MAX_CHARACTER_MACROS " .. ns.PlainText(_G.MAX_CHARACTER_MACROS))
    ns.Say("GetMacroInfo " .. (type(_G.GetMacroInfo) == "function" and "available" or "unavailable") .. ", GetMacroSpell "
        .. (type(_G.GetMacroSpell) == "function" and "available" or "unavailable") .. ", GetMacroItem "
        .. (type(_G.GetMacroItem) == "function" and "available" or "unavailable"))
    for _, scope in ipairs({"account", "character"}) do
        for i, m in ipairs(Game.MacroList(scope)) do
            if i <= 3 then ns.Say("  " .. scope .. " #" .. m.index .. " '" .. m.name .. "' icon " .. ns.PlainText(m.icon)) end
        end
    end
    if type(GetCursorInfo) == "function" then
        local first, second = GetCursorInfo()
        ns.Say("cursor: " .. ns.PlainText(first) .. ", " .. ns.PlainText(second) .. " (drag a macro onto the cursor first to see its payload)")
    end
end
