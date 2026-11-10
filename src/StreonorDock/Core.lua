local addonName, ns = ...
-- Pure Lua 5.1: no game calls. Saved data is untrusted structurally; live secrets are filtered
-- by the Game adapter before anything reaches Core.
local Core = {}
ns.Core = Core
local keys = {"1","2","3","4","5","6","7","8","9","0","-","=","[","]","\\"}
Core.SLOTS, Core.MAX_PAGES = 15, 10
local function number(v) return type(v)=="number" and v==v and v > -math.huge and v < math.huge end
local function integer(v) return number(v) and v==math.floor(v) end
local function id(v) return integer(v) and v>0 end
Core.number, Core.integer, Core.id = number, integer, id
local function tableOrEmpty(v) if type(v)=="table" then return v end; return {} end

-- A slot is {kind="empty"} | {kind="spell",id=n,pinned=true?} | {kind="item",id=n}. Anything else -> nil.
function Core.slot(value)
    if type(value)~="table" then return nil end
    if value.kind=="empty" then return {kind="empty"} end
    if value.kind=="item" and id(value.id) then return {kind="item", id=value.id} end
    -- Macros are stored by NAME + scope (indices shift when macros are created or deleted); the index is
    -- resolved at apply time from the client's macro list.
    if value.kind=="macro" and type(value.name)=="string" and value.name~="" and #value.name<=64
        and (value.scope=="account" or value.scope=="character") then
        return {kind="macro", name=value.name, scope=value.scope}
    end
    if value.kind=="spell" and id(value.id) then
        -- pinned=true: cast this exact rank by ID; otherwise cast by name (highest known rank).
        if value.pinned==true then return {kind="spell", id=value.id, pinned=true} end
        return {kind="spell", id=value.id}
    end
end
function Core.newPage()
    local page = {}
    for i=1,15 do page[i] = {kind="empty"} end
    return page
end
-- Sanitizes one stored page into exactly 15 explicit slots (never compacts).
function Core.cleanPage(value)
    local input, page = tableOrEmpty(value), {}
    for i=1,15 do page[i] = Core.slot(input[i]) or {kind="empty"} end
    return page
end
-- Makes profile.pageCount (1..10) and profile.pages consistent. Extra stored pages beyond the count
-- are kept in the archive by the caller (Core.setPageCount), never silently dropped here.
function Core.ensurePages(profile)
    local count = profile.pageCount
    if not integer(count) then count = 1 end
    if type(profile.pages)~="table" then profile.pages = {} end
    local highest = 1
    for i=1,10 do if type(profile.pages[i])=="table" then highest = i end end
    if count < highest and not integer(profile.pageCount) then count = highest end
    count = math.max(1, math.min(10, count))
    profile.pageCount = count
    for i=1,count do profile.pages[i] = Core.cleanPage(profile.pages[i]) end
    for i=count+1, 10 do profile.pages[i] = nil end
    if type(profile.archivedPages)~="table" then profile.archivedPages = {} end
    return profile
end
function Core.sameSlot(a, b)
    if type(a)~="table" or type(b)~="table" then return false end
    if a.kind~=b.kind then return false end
    if a.kind=="empty" then return true end
    if a.kind=="macro" then return a.name==b.name and a.scope==b.scope end
    return a.id==b.id and (a.pinned==true)==(b.pinned==true)
end
function Core.chord(index)
    if integer(index) and index>=1 and index<=15 then return "ALT-CTRL-SHIFT-" .. keys[index] end
end
function Core.chordKey(index)
    local chord = Core.chord(index)
    return chord and string.match(chord,"^ALT%-CTRL%-SHIFT%-(.+)$")
end
-- Sets one slot of one page. Returns ok, changed, reason. No-ops report changed=false.
function Core.setSlot(profile, page, index, value, inCombat)
    if inCombat then return false,false,"combat" end
    if not integer(index) or index<1 or index>15 then return false,false,"index" end
    if not integer(page) or type(profile.pages)~="table" or type(profile.pages[page])~="table" then return false,false,"page" end
    local normalized = Core.slot(value)
    if not normalized then return false,false,"slot" end
    local current = profile.pages[page][index]
    if Core.sameSlot(current, normalized) then return true,false end
    profile.pages[page][index] = normalized
    return true,true
end
-- Swap/move for an internal drag: occupied destination swaps, empty destination moves.
function Core.moveSlot(profile, page, from, to, inCombat)
    if inCombat then return false,false,"combat" end
    if not integer(from) or not integer(to) or from<1 or from>15 or to<1 or to>15 then return false,false,"index" end
    if from==to then return true,false end
    local p = profile.pages and profile.pages[page]
    if type(p)~="table" then return false,false,"page" end
    p[from], p[to] = p[to], p[from]
    return true,true
end
-- Page navigation with wrap-around. Returns the new page number.
function Core.turn(current, count, action)
    if not integer(count) or count<1 then count = 1 end
    if not integer(current) or current<1 or current>count then current = 1 end
    if action=="next" then return current % count + 1 end
    if action=="prev" then return (current-2) % count + 1 end
    if action=="home" then return 1 end
    return current
end
-- Grows (empty pages, restoring archived ones only on request) or shrinks (archiving the removed
-- pages). Returns the list of removed page numbers. Confirmation is the caller's job.
function Core.setPageCount(profile, n)
    Core.ensurePages(profile)
    if not integer(n) then return {} end
    n = math.max(1, math.min(10, n))
    local removed = {}
    local old = profile.pageCount
    if n < old then
        for i=n+1, old do
            profile.archivedPages[#profile.archivedPages+1] = {page=i, slots=profile.pages[i]}
            profile.pages[i] = nil
            removed[#removed+1] = i
        end
    else
        for i=old+1, n do profile.pages[i] = Core.newPage() end
    end
    profile.pageCount = n
    return removed
end
function Core.restoreArchive(profile)
    Core.ensurePages(profile)
    local archive, restored = profile.archivedPages, 0
    table.sort(archive, function(a, b) return (a.page or 0) < (b.page or 0) end)
    for _, entry in ipairs(archive) do
        if profile.pageCount < 10 then
            profile.pageCount = profile.pageCount + 1
            profile.pages[profile.pageCount] = Core.cleanPage(entry.slots)
            restored = restored + 1
        end
    end
    profile.archivedPages = {}
    return restored
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
    elseif kind=="macro" then
        local index = plain(cursor[2])
        if id(index) then return {kind="macro",index=index} end
        return nil,"macro-index"
    elseif kind=="spell" then
        local spellID = plain(cursor[4])
        if id(spellID) then return {kind="spell",id=spellID} end
        local resolved = plain(cursor.resolved)
        if id(resolved) then return {kind="spell",id=resolved} end
        return nil,"spell-id"
    end
    return nil,"unsupported"
end
function Core.identity(value)
    if type(value)~="table" then return nil end
    if (value.kind=="spell" or value.kind=="item") and id(value.id) then return value.kind .. ":" .. value.id end
    if value.kind=="macro" and type(value.name)=="string" then return "macro:" .. tostring(value.scope) .. ":" .. value.name end
end
-- Slots on a page whose identity is kind:id (late metadata callbacks refresh only these).
function Core.findSlots(page, kind, itemID)
    local found, wanted = {}, Core.identity({kind=kind,id=itemID})
    if type(page)~="table" or not wanted then return found end
    for i=1,15 do if Core.identity(page[i])==wanted then found[#found+1]=i end end
    return found
end
-- Secure attribute plan for one key slot. Keys are "*"-prefixed with button suffix 1, so held
-- modifiers (the ALT-CTRL-SHIFT chord itself) cannot change the attribute lookup, and the binding
-- click is LeftButton. false = clear the attribute (never leave stale ones).
-- spellName must already be a plain, non-secret string or nil.
Core.SECURE_KEYS = {"*type1","*spell1","*item1","*macro1"}
function Core.secureAttributes(value, spellName, macroIndex)
    if type(value)=="table" and value.kind=="spell" and id(value.id) then
        local spell = value.id
        if not value.pinned and type(spellName)=="string" and spellName~="" then spell=spellName end
        return {["*type1"]="spell",["*spell1"]=spell,["*item1"]=false,["*macro1"]=false}
    elseif type(value)=="table" and value.kind=="item" and id(value.id) then
        return {["*type1"]="item",["*spell1"]=false,["*item1"]="item:" .. value.id,["*macro1"]=false}
    elseif type(value)=="table" and value.kind=="macro" and id(macroIndex) then
        -- A macro that cannot be resolved right now stays inert (shown as missing), never an error.
        return {["*type1"]="macro",["*spell1"]=false,["*item1"]=false,["*macro1"]=macroIndex}
    end
    return {["*type1"]=false,["*spell1"]=false,["*item1"]=false,["*macro1"]=false}
end

-- Minimal controller export (schema 2): icons only. iconFor(slot) -> positive integer | nil.
-- Empty -> {}; assigned and resolved -> {iconFileID=n}; assigned but unknown -> {unresolved=true}; an assigned
-- slot also carries name="..." (<= 40 chars) when known. Nothing else is ever exported.
function Core.buildExport(enabled, profileId, page, slots, iconFor, nameFor)
    local icons = {}
    for i=1,15 do
        local slot = type(slots)=="table" and slots[i] or nil
        local entry = {}
        if enabled and type(slot)=="table" and (slot.kind=="spell" or slot.kind=="item" or slot.kind=="macro") then
            local icon = iconFor and iconFor(slot)
            if id(icon) then entry.iconFileID = icon else entry.unresolved = true end
            -- Short display name: lets the controller draw a readable tile while it has no icon file.
            local name = nameFor and nameFor(slot)
            if type(name)=="string" then
                name = string.gsub(name, "%c", " ")
                name = string.gsub(string.gsub(string.gsub(name, "%s+", " "), "^ ", ""), " $", "")
                if name~="" then entry.name = string.sub(name, 1, 40) end
            end
        end
        icons[i] = entry
    end
    if type(profileId)~="string" or profileId=="" then profileId = "uninitialized" end
    if not integer(page) or page<1 or page>10 then page = 1 end
    return {schemaVersion=2, enabled=enabled==true, profileId=profileId, page=page, icons=icons}
end

-- OmniCC-style remaining time text. Seconds below the minute threshold, minutes from it
-- (ceil), hours from the hour threshold (ceil). r<=0 or non-finite -> nil (no text).
function Core.formatRemaining(r, minuteAt, hourAt)
    if not number(r) or r<=0 then return nil end
    minuteAt = number(minuteAt) and minuteAt or 90
    hourAt = number(hourAt) and hourAt or 5400
    if r >= hourAt then return math.ceil(r/3600) .. "h" end
    if r >= minuteAt then return math.ceil(r/60) .. "m" end
    return tostring(math.ceil(r))
end
