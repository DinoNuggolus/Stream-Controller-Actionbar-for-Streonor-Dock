local addonName, ns = ...
-- Pure Lua 5.1. Saved data is untrusted structurally; live secrets are filtered by the adapter.
local Core = {}
ns.Core = Core
local keys = {"1","2","3","4","5","6","7","8","9","0","-","=","[","]","\\"}
local function number(v) return type(v)=="number" and v==v and v > -math.huge and v < math.huge end
local function integer(v) return number(v) and v==math.floor(v) end
local function id(v) return integer(v) and v>0 end
local function tableOrEmpty(v) if type(v)=="table" then return v end; return {} end
local function slot(value, readout)
    if type(value)~="table" then return nil end
    if value.kind=="empty" then return {kind="empty"} end
    if value.kind=="item" then
        local field = readout and "itemID" or "id"
        if id(value[field]) then return {kind="item", [field]=value[field]} end
    elseif not readout and value.kind=="spell" and id(value.id) then
        -- pinned=true: cast this exact rank by ID; otherwise cast by name (highest known rank).
        if value.pinned==true then return {kind="spell",id=value.id,pinned=true} end
        return {kind="spell",id=value.id}
    end
end
local function page(value)
    value = tableOrEmpty(value)
    local result = {slots={},readouts={}}
    for _, area in ipairs({"slots","readouts"}) do
        local input = tableOrEmpty(value[area])
        for i=1,area=="slots" and 15 or 3 do
            result[area][i] = slot(input[i],area=="readouts") or {kind="empty"}
        end
    end
    return result
end
function Core.chord(index)
    if integer(index) and index>=1 and index<=15 then return "ALT-CTRL-SHIFT-" .. keys[index] end
end
function Core.recover(saved, profileId)
    saved = tableOrEmpty(saved)
    local result = {profileId=profileId,revision=0,currentPage=1,pages={}}
    if type(saved.profileId)=="string" and saved.profileId~="" then result.profileId=saved.profileId end
    if type(result.profileId)~="string" or result.profileId=="" then result.profileId="uninitialized" end
    if integer(saved.revision) and saved.revision>=0 then result.revision=saved.revision end
    local pages = tableOrEmpty(saved.pages)
    local count = 1
    for i=1,10 do if type(pages[i])=="table" then count=i end end
    for i=1,count do result.pages[i]=page(pages[i]) end
    if integer(saved.currentPage) then result.currentPage=math.max(1,math.min(count,saved.currentPage)) end
    return result
end
function Core.assign(state, area, index, value, inCombat)
    if inCombat then return state,false,"combat" end
    if area~="slots" and area~="readouts" then return state,false,"area" end
    local limit = area=="slots" and 15 or 3
    if not integer(index) or index<1 or index>limit then return state,false,"index" end
    local normalized = slot(value,area=="readouts")
    if not normalized then return state,false,"slot" end
    local result = Core.recover(state,state.profileId)
    result.pages[result.currentPage][area][index]=normalized
    result.revision=result.revision+1
    return result,true
end
function Core.page(state, action, inCombat)
    if inCombat then return state,false,"combat" end
    local target = state.currentPage
    if action=="next" then
        if target>=10 then return state,false,"limit" end
        target=target+1
    elseif action=="prev" then target=math.max(1,target-1)
    elseif action=="home" then target=1
    else return state,false,"action" end
    if target==state.currentPage then return state,true end
    local result = Core.recover(state,state.profileId)
    if not result.pages[target] then result.pages[target]=page() end
    result.currentPage=target
    result.revision=result.revision+1
    return result,true
end
local function never() return false end
-- Last resort before Core: deep copy keeping only plain strings, booleans, finite numbers and
-- tables with plain string/number keys. The predicate runs before any other use of a value.
function Core.sanitize(value, issecret, depth)
    issecret = issecret or never
    depth = depth or 0
    if issecret(value) then return nil end
    local kind = type(value)
    if kind=="string" or kind=="boolean" then return value end
    if kind=="number" then if number(value) then return value end; return nil end
    if kind~="table" or depth>=6 then return nil end
    local out = {}
    for k, v in pairs(value) do
        if not issecret(k) and (type(k)=="string" or number(k)) then
            local clean = Core.sanitize(v, issecret, depth+1)
            if clean~=nil then out[k]=clean end
        end
    end
    return out
end
-- cursor = packed GetCursorInfo() returns {kind, detail, subdetail, spellID, resolved=?}.
-- Returns {kind="spell"|"item", id} or nil, reason. Never inspects a value before issecret.
function Core.normalizeCursor(cursor, issecret)
    issecret = issecret or never
    if type(cursor)~="table" then return nil,"empty" end
    local function plain(v) if not issecret(v) then return v end end
    local kind = plain(cursor[1])
    if kind==nil then return nil,"empty" end
    if kind=="item" then
        local itemID = plain(cursor[2])
        if id(itemID) then return {kind="item",id=itemID} end
        local link = plain(cursor[3])
        if type(link)=="string" then
            local parsed = tonumber(string.match(link,"item:(%d+)") or "")
            if id(parsed) then return {kind="item",id=parsed} end
        end
        return nil,"item-id"
    elseif kind=="spell" then
        local spellID = plain(cursor[4])
        if id(spellID) then return {kind="spell",id=spellID} end
        local resolved = plain(cursor.resolved)
        if id(resolved) then return {kind="spell",id=resolved} end
        return nil,"spell-id"
    end
    return nil,"unsupported"
end
-- Converts a normalized key value to the shape an area accepts (readouts: items only).
function Core.forArea(value, area)
    if type(value)~="table" then return nil,"slot" end
    if area=="readouts" then
        if value.kind=="item" and id(value.id) then return {kind="item",itemID=value.id} end
        if value.kind=="empty" then return {kind="empty"} end
        return nil,"items-only"
    end
    return value
end
function Core.identity(value)
    if type(value)~="table" then return nil end
    local itemID = value.id or value.itemID
    if (value.kind=="spell" or value.kind=="item") and id(itemID) then return value.kind .. ":" .. itemID end
end
local function currentPage(state)
    return type(state)=="table" and type(state.pages)=="table" and state.pages[state.currentPage] or nil
end
-- Slots on the CURRENT page whose identity is kind:id now. Late metadata callbacks refresh only these.
function Core.findSlots(state, kind, itemID)
    local found, page, wanted = {}, currentPage(state), Core.identity({kind=kind,id=itemID})
    if not page or not wanted then return found end
    for _, area in ipairs({"slots","readouts"}) do
        for i, value in ipairs(page[area] or {}) do
            if Core.identity(value)==wanted then found[#found+1]={area=area,index=i} end
        end
    end
    return found
end
-- True if any page (slots or readouts) still holds this item.
function Core.itemReferenced(state, itemID)
    if type(state)~="table" or type(state.pages)~="table" then return false end
    local wanted = Core.identity({kind="item",id=itemID})
    for _, page in ipairs(state.pages) do
        for _, area in ipairs({"slots","readouts"}) do
            for _, value in ipairs(page[area] or {}) do
                if Core.identity(value)==wanted then return true end
            end
        end
    end
    return false
end
-- Unique ascending item IDs on the current page (keys and readouts).
function Core.pageItems(state)
    local page, seen, list = currentPage(state), {}, {}
    if not page then return list end
    for _, area in ipairs({"slots","readouts"}) do
        for _, value in ipairs(page[area] or {}) do
            local itemID = value.kind=="item" and (value.id or value.itemID)
            if id(itemID) and not seen[itemID] then seen[itemID]=true; list[#list+1]=itemID end
        end
    end
    table.sort(list)
    return list
end
-- Secure attribute plan for one key slot. Keys are "*"-prefixed with button suffix 1, so held
-- modifiers (the ALT-CTRL-SHIFT chord itself) cannot change the attribute lookup, and the binding
-- click is LeftButton. false = clear the attribute (never leave stale ones).
-- spellName must already be a plain, non-secret string or nil.
Core.SECURE_KEYS = {"*type1","*spell1","*item1"}
function Core.secureAttributes(value, spellName)
    if type(value)=="table" and value.kind=="spell" and id(value.id) then
        local spell = value.id
        if not value.pinned and type(spellName)=="string" and spellName~="" then spell=spellName end
        return {["*type1"]="spell",["*spell1"]=spell,["*item1"]=false}
    elseif type(value)=="table" and value.kind=="item" and id(value.id) then
        return {["*type1"]="item",["*spell1"]=false,["*item1"]="item:" .. value.id}
    end
    return {["*type1"]=false,["*spell1"]=false,["*item1"]=false}
end
function Core.chordKey(index)
    local chord = Core.chord(index)
    return chord and string.match(chord,"^ALT%-CTRL%-SHIFT%-(.+)$")
end
function Core.buildExport(state, now, issecret, providers)
    -- Rebuild from allowlisted fields every time; never merge a previous snapshot.
    issecret = issecret or function() return false end
    local function plain(v) if not issecret(v) then return v end end
    local function record(v) v=plain(v); if type(v)=="table" then return v end; return {} end
    providers=record(providers)
    local items, spells = record(providers.items),record(providers.spells)
    local result = {schema=1,profileId=state.profileId,revision=state.revision,
        page={index=state.currentPage,count=#state.pages},slots={},readouts={}}
    local timestamp=plain(now)
    if integer(timestamp) and timestamp>=0 then result.savedAt=timestamp end
    local current=state.pages[state.currentPage]
    for _, area in ipairs({"slots","readouts"}) do
        for i, value in ipairs(current[area]) do
            local out={kind=value.kind}
            if value.kind~="empty" then
                local itemID = value.id or value.itemID
                if area=="slots" then out.id=itemID; out.chord=Core.chord(i) else out.itemID=itemID end
                local data=record((value.kind=="item" and items or spells)[itemID])
                local name, icon = plain(data.name),plain(data.iconFileID)
                if type(name)=="string" then out.name=name end
                if id(icon) then out.iconFileID=icon end
                if value.kind=="item" then
                    local count, endsAt, source=plain(data.count),plain(data.endsAt),plain(data.source)
                    if integer(count) and count>=0 then out.count=count end
                    if source=="game" or source=="est" then
                        out.source=source
                        if number(endsAt) and endsAt>=0 then out.endsAt=endsAt end
                    elseif source=="used" then
                        out.source=source  -- pressed, length unknown: no countdown claimed
                    end
                end
            end
            result[area][i]=out
        end
    end
    -- Optional ordinary player values (copper and free general bag slots); omitted when unknown.
    local player, values = record(providers.player), nil
    local money, free = plain(player.moneyCopper), plain(player.freeBagSlots)
    if integer(money) and money>=0 then values = {moneyCopper=money} end
    if integer(free) and free>=0 then values = values or {}; values.freeBagSlots=free end
    result.player = values
    return result
end
