local addonName, ns = ...
-- Pure item timer model (design Amendment 2: press-activated timers). No WoW calls.
-- Timers have an absolute end time and are keyed by item, or by cooldown group when the group in
-- CooldownData.lua is marked shared==true. Every key/readout slot on any page showing that item
-- (or any member of a shared group) displays the same timer; paging never resets it.
-- Duration at a press: learned (readable game observation, persisted per itemID) > group table
-- duration > base cooldown supplied by the adapter > unknown ("used": elapsed, no countdown).
-- Readable game data always overrides any estimate. All times use one injected clock.
local Tracker = {}
Tracker.__index = Tracker
ns.CooldownTracker = Tracker
Tracker.GCD = 1.5          -- readable samples at or below this are the global cooldown only
Tracker.GRACE = 1.5        -- a ready sample this soon after a press is the pre-ack state, not a failure
Tracker.USED_MAX = 3600    -- a "used" marker with unknown length expires after an hour
Tracker.MAX_DURATION = 86400
Tracker.MISMATCH_TOLERANCE = 1
Tracker.MAX_MISMATCHES = 20
local function number(v)
    return type(v)=="number" and v==v and v>=0 and v<math.huge
end
local function item(v) return number(v) and v>0 and v==math.floor(v) end
local function duration(v) return number(v) and v>Tracker.GCD and v<=Tracker.MAX_DURATION end
-- Validated private copy of the reference data (input tables are not mutated).
local function readGroups(groups, itemGroups)
    local outGroups, outItems = {}, {}
    if type(groups)~="table" then groups={} end
    if type(itemGroups)~="table" then itemGroups={} end
    for key, g in pairs(groups) do
        if type(key)=="string" and key~="" and type(g)=="table" then
            outGroups[key] = {duration=duration(g.duration) and g.duration or nil,
                shared=g.shared==true, verified=g.verified==true}
        end
    end
    for itemID, key in pairs(itemGroups) do
        if item(itemID) and outGroups[key] then outItems[itemID]=key end
    end
    return outGroups, outItems
end
-- learned: optional persistence table itemID -> seconds (owned by the adapter's SavedVariables).
-- Invalid entries are removed in place; the same table receives new learning.
function Tracker.new(learned, groups, itemGroups)
    if type(learned)~="table" then learned={} end
    local bad={}
    for k, v in pairs(learned) do if not item(k) or not duration(v) then bad[#bad+1]=k end end
    for _, k in ipairs(bad) do learned[k]=nil end
    local g, ig = readGroups(groups, itemGroups)
    return setmetatable({items={},learned=learned,groups=g,itemGroups=ig,mismatches={}},Tracker)
end
function Tracker:group(itemID)
    local key = item(itemID) and self.itemGroups[itemID]
    if key then return key, self.groups[key] end
end
-- Timer key: "group:<key>" for shared groups, else the item ID itself.
function Tracker:key(itemID)
    local key, g = self:group(itemID)
    if g and g.shared then return "group:" .. key end
    return itemID
end
function Tracker:learnedDuration(itemID)
    if item(itemID) then return self.learned[itemID] end
end
-- Duration a press would use, and where it came from ("learned" | "table" | "base"), or nil.
function Tracker:pressDuration(itemID, baseDuration)
    if not item(itemID) then return nil end
    if self.learned[itemID] then return self.learned[itemID],"learned" end
    local _, g = self:group(itemID)
    if g and g.duration then return g.duration,"table" end
    if duration(baseDuration) then return baseDuration,"base" end
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
local function noteMismatch(self, itemID, length)
    local key, g = self:group(itemID)
    if not g or not g.duration or math.abs(g.duration-length)<=Tracker.MISMATCH_TOLERANCE then return end
    for _, m in ipairs(self.mismatches) do
        if m.itemID==itemID and m.game==length then return end
    end
    if #self.mismatches>=Tracker.MAX_MISMATCHES then table.remove(self.mismatches,1) end
    self.mismatches[#self.mismatches+1]={itemID=itemID,group=key,table=g.duration,game=length}
end
-- Readable game reading (start, duration on the same clock as now). Authoritative.
function Tracker:observe(itemID, start, length, now)
    if not item(itemID) or not number(start) or not number(length) or not number(now) then return false end
    if start>now then return false end
    local key = self:key(itemID)
    local entry=self.items[key]
    if start==0 and length==0 then
        if entry and entry.source=="est" and now-entry.startedAt<Tracker.GRACE then return false end
        self.items[key]=nil
        return true
    end
    if length<=Tracker.GCD or not duration(length) then return false end
    self.learned[itemID]=length
    noteMismatch(self, itemID, length)
    if start+length<=now then self.items[key]=nil; return true end
    self.items[key]={endsAt=start+length,duration=length,source="game",itemID=itemID}
    return true
end
-- A key slot holding this item was pressed. Starts an estimate only when the bag count is a
-- plain number > 0 and no timer for this item (or its shared group) is running.
function Tracker:press(itemID, now, count, baseDuration)
    if not item(itemID) or not number(now) then return false,"invalid" end
    if not number(count) or count<=0 then return false,"count" end
    local key = self:key(itemID)
    if active(self.items[key], now) then return false,"running" end
    local length = self:pressDuration(itemID, baseDuration)
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
function Tracker:clear(itemID)
    if item(itemID) then self.items[self:key(itemID)]=nil; self.learned[itemID]=nil end
end
