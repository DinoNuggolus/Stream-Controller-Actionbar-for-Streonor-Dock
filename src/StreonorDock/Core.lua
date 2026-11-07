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
                    end
                end
            end
            result[area][i]=out
        end
    end
    return result
end
