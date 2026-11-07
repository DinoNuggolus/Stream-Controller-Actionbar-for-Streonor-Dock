local addonName, ns = ...
-- Pure item timer model (design Amendments 2 and 3). No WoW calls; clocks, build and the secret
-- predicate are injected.
-- Timer keys: "pool:<label>" when the item's group (CooldownData.lua) has a shared pool label (all
-- groups with that label share ONE timer), "group:<key>" for a group without a label, or the item
-- ID for items not in the table. Every slot on any page showing a member displays the same
-- absolute timer; paging never resets it.
-- Duration precedence: live game data > item override > group override/verified value > shipped
-- table value (0 = no use cooldown: dormant) > base cooldown from the adapter > unknown ("used").
-- Self-verifying table: a readable cooldown that is the item's OWN use (start within OWN_WINDOW of
-- our recorded press) verifies or overrides the table; locks imposed by other items never teach.
local Tracker = {}
Tracker.__index = Tracker
ns.CooldownTracker = Tracker
Tracker.GCD = 1.5          -- readable samples at or below this are the global cooldown only
Tracker.GRACE = 1.5        -- a ready sample this soon after a press is the pre-ack state
Tracker.USED_MAX = 3600    -- a "used" marker with unknown length expires after an hour
Tracker.MAX_DURATION = 86400
Tracker.MATCH = 1          -- table match tolerance (seconds)
Tracker.OWN_WINDOW = 1     -- cooldown start vs recorded press: same use
Tracker.SHARE_WINDOW = 0.5 -- two pool members with starts this close: shared lock evidence
Tracker.MAX_LOG = 30
local function number(v)
    return type(v)=="number" and v==v and v>=0 and v<math.huge
end
local function item(v) return number(v) and v>0 and v==math.floor(v) end
local function duration(v) return number(v) and v>Tracker.GCD and v<=Tracker.MAX_DURATION end
local function never() return false end
-- Validated private copy of the shipped reference data (input tables are not mutated).
local function readGroups(groups, itemGroups)
    local outGroups, outItems = {}, {}
    if type(groups)~="table" then groups={} end
    if type(itemGroups)~="table" then itemGroups={} end
    for key, g in pairs(groups) do
        if type(key)=="string" and key~="" and type(g)=="table" then
            outGroups[key] = {duration=duration(g.duration) and g.duration or nil,
                dormant=g.duration==0, shared=(type(g.shared)=="string" and g.shared~="") and g.shared or nil,
                verified=g.verified==true, name=type(g.name)=="string" and g.name or key}
        end
    end
    for itemID, key in pairs(itemGroups) do
        if item(itemID) and outGroups[key] then outItems[itemID]=key end
    end
    return outGroups, outItems
end
-- Repairs the persisted learning store IN PLACE (it is the adapter's SavedVariables table).
local function readStore(store, build)
    if type(store)~="table" then store={} end
    for _, area in ipairs({"items","groups","pools"}) do
        if type(store[area])~="table" then store[area]={} end
    end
    local bad={}
    for k, v in pairs(store.items) do
        if not item(k) or type(v)~="table" or not duration(v.duration) then bad[#bad+1]=k
        else v.verified = v.verified==true or nil end
    end
    for _, k in ipairs(bad) do store.items[k]=nil end
    bad={}
    for k, v in pairs(store.groups) do
        if type(k)~="string" or type(v)~="table" or not duration(v.duration) then bad[#bad+1]=k
        else
            v.verified = v.verified==true or nil
            local seen={}
            for _, id in ipairs(type(v.itemsSeen)=="table" and v.itemsSeen or {}) do if item(id) then seen[#seen+1]=id end end
            v.itemsSeen=seen
        end
    end
    for _, k in ipairs(bad) do store.groups[k]=nil end
    bad={}
    for k, v in pairs(store.pools) do
        if type(k)~="string" or type(v)~="table" then bad[#bad+1]=k
        else v.sharedVerified = v.sharedVerified==true or nil; v.notShared = v.notShared==true or nil end
    end
    for _, k in ipairs(bad) do store.pools[k]=nil end
    -- A different client build keeps the data but it is unverified until observed again.
    if build~=nil and store.build~=build then
        if store.build~=nil then
            for _, v in pairs(store.items) do v.verified=nil end
            for _, v in pairs(store.groups) do v.verified=nil end
            for _, v in pairs(store.pools) do v.sharedVerified=nil; v.notShared=nil end
        end
        store.build=build
    end
    return store
end
-- options: {build=<client build>, wallClock=function() -> server seconds, issecret=predicate}
function Tracker.new(store, groups, itemGroups, options)
    options = type(options)=="table" and options or {}
    local g, ig = readGroups(groups, itemGroups)
    return setmetatable({items={}, presses={}, ownStarts={}, log={},
        store=readStore(store, options.build), groups=g, itemGroups=ig,
        wallClock=type(options.wallClock)=="function" and options.wallClock or nil,
        issecret=type(options.issecret)=="function" and options.issecret or never}, Tracker)
end
function Tracker:group(itemID)
    local key = item(itemID) and self.itemGroups[itemID]
    if key then return key, self.groups[key] end
end
function Tracker:key(itemID)
    local key, g = self:group(itemID)
    if g and g.shared then return "pool:" .. g.shared end
    if g then return "group:" .. key end
    return itemID
end
-- Other table items in the same pool (or group, when unlabelled); for sharing evidence reads.
function Tracker:poolMembers(itemID)
    local list, key = {}, self:key(itemID)
    if type(key)~="string" then return list end
    for other in pairs(self.itemGroups) do
        if other~=itemID and self:key(other)==key then list[#list+1]=other end
    end
    table.sort(list)
    return list
end
-- Duration a press would use and its origin: "item" | "group" | "table" | "dormant" (0) | "base".
function Tracker:pressDuration(itemID, baseDuration)
    if not item(itemID) then return nil end
    local own = self.store.items[itemID]
    if own then return own.duration,"item" end
    local key, g = self:group(itemID)
    local learned = key and self.store.groups[key]
    if learned then return learned.duration,"group" end
    if g and g.dormant then return 0,"dormant" end
    if g and g.duration then return g.duration,"table" end
    if duration(baseDuration) then return baseDuration,"base" end
end
function Tracker:learnedDuration(itemID)
    local length, origin = self:pressDuration(itemID)
    if origin=="item" or origin=="group" then return length end
end
local function active(entry, now)
    if not entry then return false end
    if entry.used then return now-entry.usedAt<Tracker.USED_MAX end
    return entry.endsAt~=nil and entry.endsAt>now
end
function Tracker:running(itemID, now)
    if not item(itemID) or not number(now) then return false end
    return active(self.items[self:key(itemID)], now)
end
local function log(self, entry)
    if #self.log>=Tracker.MAX_LOG then table.remove(self.log,1) end
    self.log[#self.log+1]=entry
end
local function wall(self)
    local ok, t = false, nil
    if self.wallClock then ok, t = pcall(self.wallClock) end
    if ok and number(t) then return t end
end
-- Own-use learning (Amendment 3, rules 1-3).
local function learn(self, itemID, length)
    local stamp = wall(self)
    local key, g = self:group(itemID)
    if not key then
        self.store.items[itemID]={duration=length,at=stamp,verified=true}
        return
    end
    local learned = self.store.groups[key]
    local shipped = g.dormant and 0 or g.duration
    local own = self.store.items[itemID]
    if own and math.abs(own.duration-length)<=Tracker.MATCH then
        own.verified=true; own.at=stamp   -- split-out item confirms its own value
        return
    end
    if learned and learned.verified and math.abs(learned.duration-length)>Tracker.MATCH then
        self.store.items[itemID]={duration=length,at=stamp,verified=true}
        log(self,{kind="conflict",itemID=itemID,group=key,group_duration=learned.duration,game=length})
        return
    end
    local reference = (learned and learned.duration) or shipped
    if reference and math.abs(reference-length)>Tracker.MATCH then
        log(self,{kind="mismatch",itemID=itemID,group=key,table=reference,game=length})
    end
    local record = learned or {itemsSeen={}}
    record.duration = (reference and math.abs(reference-length)<=Tracker.MATCH) and reference or length
    record.verified = true
    record.at = stamp
    local seen=false
    for _, id in ipairs(record.itemsSeen) do if id==itemID then seen=true end end
    if not seen then record.itemsSeen[#record.itemsSeen+1]=itemID end
    self.store.groups[key]=record
    self.store.items[itemID]=nil   -- the group value now speaks for this item
end
-- Sharing evidence (rule 6): another member's readable state versus a recent own-use start.
local function evidence(self, itemID, start, length, now)
    local _, g = self:group(itemID)
    local label = g and g.shared
    local own = label and self.ownStarts[label]
    if not own or own.itemID==itemID or now>own.endsAt then return end
    local pool = self.store.pools[label] or {}
    self.store.pools[label]=pool
    if length>Tracker.GCD and math.abs(start-own.start)<=Tracker.SHARE_WINDOW then
        if not pool.sharedVerified then log(self,{kind="shared",pool=label,itemID=own.itemID,other=itemID}) end
        pool.sharedVerified=true; pool.notShared=nil; pool.at=wall(self)
    elseif not pool.sharedVerified and not pool.notShared then
        pool.notShared=true; pool.at=wall(self)
        log(self,{kind="not-shared",pool=label,itemID=own.itemID,other=itemID})
    end
    return true
end
-- Readable game reading (start, duration on the same clock as now). Authoritative for timers.
function Tracker:observe(itemID, start, length, now)
    local s = self.issecret
    if s(itemID) or s(start) or s(length) or s(now) then return false end
    if not item(itemID) or not number(start) or not number(length) or not number(now) then return false end
    if start>now then return false end
    local key = self:key(itemID)
    local entry = self.items[key]
    local foreign = entry and entry.itemID~=itemID and type(key)=="string" and string.sub(key,1,5)=="pool:"
    if foreign and active(entry, now) then
        -- Another pool member's reading while the starter's timer runs: sharing evidence only.
        -- The starter's own readings reconcile the timer; a member never clears or replaces it.
        evidence(self, itemID, start, length, now)
        -- A member pressed and used DURING the lock still teaches its own length (and is itself
        -- evidence the pool is not one lock).
        local pressedAt = self.presses[itemID]
        if duration(length) and pressedAt and math.abs(start-pressedAt)<=Tracker.OWN_WINDOW then
            self.presses[itemID]=nil
            learn(self, itemID, length)
        end
        return true
    end
    if start==0 and length==0 then
        if entry and entry.source=="est" and entry.itemID==itemID and now-entry.startedAt<Tracker.GRACE then return false end
        self.items[key]=nil
        return true
    end
    if length<=Tracker.GCD or not duration(length) then return false end
    local pressedAt = self.presses[itemID]
    if pressedAt and math.abs(start-pressedAt)<=Tracker.OWN_WINDOW then
        self.presses[itemID]=nil
        learn(self, itemID, length)
        local _, g = self:group(itemID)
        if g and g.shared then self.ownStarts[g.shared]={itemID=itemID,start=start,endsAt=start+length} end
    end
    if start+length<=now then
        self.items[key]=nil
        return true
    end
    self.items[key]={endsAt=start+length,duration=length,source="game",itemID=itemID,
        startedAt=start}
    return true
end
-- A key slot holding this item was pressed (our secure button's PostClick). The press time is
-- always recorded (own-use learning). An estimate starts only if `estimate` is not false, the
-- count is a plain number > 0, the key's timer is not running and the item is not dormant.
function Tracker:press(itemID, now, count, baseDuration, estimate)
    if not item(itemID) or not number(now) then return false,"invalid" end
    if not number(count) or count<=0 then return false,"count" end
    self.presses[itemID]=now
    if estimate==false then return false,"disabled" end
    local key = self:key(itemID)
    if active(self.items[key], now) then return false,"running" end
    local length, origin = self:pressDuration(itemID, baseDuration)
    if origin=="dormant" then return false,"dormant" end
    if length then
        self.items[key]={endsAt=now+length,duration=length,source="est",startedAt=now,itemID=itemID}
    else
        self.items[key]={used=true,usedAt=now,source="est",startedAt=now,itemID=itemID}
    end
    return true
end
-- Active: endsAt, duration, source. Unknown length: nil, nil, "used", usedAt. Ready: nil.
function Tracker:timer(itemID, now)
    if not item(itemID) or not number(now) then return nil end
    local entry=self.items[self:key(itemID)]
    if not active(entry, now) then return nil end
    if entry.used then return nil,nil,"used",entry.usedAt end
    return entry.endsAt,entry.duration,entry.source
end
-- Seconds and "game"/"est"; "used" state returns nil,"used"; ready returns 0,nil.
function Tracker:remaining(itemID, now)
    if not item(itemID) or not number(now) then return nil,nil end
    local entry=self.items[self:key(itemID)]
    if not active(entry, now) then return 0,nil end
    if entry.used then return nil,"used" end
    return entry.endsAt-now,entry.source
end
-- Item IDs to reconcile with game data: the item that started each live timer (any page).
function Tracker:activeItems(now)
    local list, seen={}, {}
    if not number(now) then return list end
    for _, entry in pairs(self.items) do
        if active(entry, now) and entry.itemID and not seen[entry.itemID] then
            seen[entry.itemID]=true; list[#list+1]=entry.itemID
        end
    end
    table.sort(list)
    return list
end
-- Pure report for /sdock probe and /sdock cooldowns: each group the player holds an item of
-- (countOf(itemID) > 0, or every group when countOf is nil) with table vs learned durations.
function Tracker:groupReport(countOf)
    local rows, byGroup = {}, {}
    for itemID, key in pairs(self.itemGroups) do
        local count
        if countOf then
            local ok, value = pcall(countOf, itemID)
            count = ok and number(value) and value or nil
        end
        if not countOf or (count and count>0) then
            local g, learned = self.groups[key], self.store.groups[key]
            local row = byGroup[key]
            if not row then
                row = {group=key,name=g.name,pool=g.shared,table=g.dormant and 0 or g.duration,
                    learned=learned and learned.duration,verified=learned and learned.verified or false,
                    sharing=g.shared and self.store.pools[g.shared] or nil,items={}}
                byGroup[key]=row; rows[#rows+1]=row
            end
            local own = self.store.items[itemID]
            row.items[#row.items+1]={itemID=itemID,count=count,override=own and own.duration}
        end
    end
    table.sort(rows, function(a, b) return a.group<b.group end)
    for _, row in ipairs(rows) do table.sort(row.items, function(a, b) return a.itemID<b.itemID end) end
    return rows
end
function Tracker:clear(itemID)
    if item(itemID) then self.items[self:key(itemID)]=nil; self.store.items[itemID]=nil; self.presses[itemID]=nil end
end
