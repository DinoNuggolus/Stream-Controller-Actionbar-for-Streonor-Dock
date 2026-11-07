local addonName, ns = ...
-- Pure item timer model. Time inputs share one clock; adapters convert to server seconds.
local Tracker = {}
Tracker.__index = Tracker
ns.CooldownTracker = Tracker
local function number(v)
    return type(v)=="number" and v==v and v>=0 and v<math.huge
end
local function item(v) return number(v) and v>0 and v==math.floor(v) end
function Tracker.new() return setmetatable({items={}},Tracker) end
function Tracker:observe(itemID, start, duration, now)
    if not item(itemID) or not number(start) or not number(duration) or not number(now) then return false end
    if start>now then return false end
    local entry=self.items[itemID] or {}
    if start==0 and duration==0 then
        entry.endsAt=nil; entry.source=nil; entry.unknown=nil
        self.items[itemID]=entry
        return true
    end
    if duration<=1.5 or not number(start+duration) then return false end
    entry.learnedDuration=duration
    entry.endsAt=start+duration
    entry.source="game"
    entry.unknown=nil
    self.items[itemID]=entry
    return true
end
function Tracker:useDetected(itemID, now)
    if not item(itemID) or not number(now) then return false end
    local entry=self.items[itemID] or {}
    if entry.unknown or (entry.endsAt and entry.endsAt>now) then return false end
    if entry.learnedDuration and not number(now+entry.learnedDuration) then return false end
    entry.source="est"
    if entry.learnedDuration then entry.endsAt=now+entry.learnedDuration
    else entry.endsAt=nil; entry.unknown=true end
    self.items[itemID]=entry
    return true
end
function Tracker:remaining(itemID, now)
    if not item(itemID) or not number(now) then return nil,nil end
    local entry=self.items[itemID]
    if not entry then return 0,nil end
    if entry.unknown then return nil,"est" end
    if entry.endsAt and entry.endsAt>now then return entry.endsAt-now,entry.source end
    return 0,nil
end
function Tracker:clear(itemID)
    if item(itemID) then self.items[itemID]=nil end
end
function Tracker:changeItem(oldID, newID)
    -- Adapter calls only when no remaining slot references oldID. New item's timer is independent.
    if oldID~=newID then self:clear(oldID) end
end
