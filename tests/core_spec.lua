local addonName, ns = ...
local A = ns.Assert
local function core() A.equal(type(ns.Core), "table", "Core module available"); return ns.Core end
local chunk = loadfile("src/StreonorDock/Core.lua")
if chunk then chunk(addonName, ns) end
local function fresh() return core().recover(nil, "opaque-1") end
local function assign(s, area, i, slot) return core().assign(s, area, i, slot, false) end
A.test("fresh defaults have fifteen keys and three independent readouts", function()
    local s = fresh()
    A.equal(s.profileId, "opaque-1"); A.equal(s.revision, 0); A.equal(s.currentPage, 1)
    A.equal(#s.pages, 1); A.equal(#s.pages[1].slots, 15); A.equal(#s.pages[1].readouts, 3)
    A.deep(s.pages[1].slots[1], {kind="empty"})
    A.equal(s.pages[1].slots[1] == s.pages[1].slots[2], false)
end)
A.test("all fixed binding strings and index bounds", function()
    local keys = {"1","2","3","4","5","6","7","8","9","0","-","=","[","]","\\"}
    for i=1,15 do A.equal(core().chord(i), "ALT-CTRL-SHIFT-" .. keys[i]) end
    for _, i in ipairs({0,16,1.5,"1",false}) do A.equal(core().chord(i), nil) end
end)
A.test("assign replace clear and caller isolation", function()
    local s, input = fresh(), {kind="spell", id=123, extra={x=1}}
    local nextState, ok = assign(s,"slots",1,input)
    A.equal(ok,true); A.deep(nextState.pages[1].slots[1],{kind="spell",id=123})
    A.deep(s.pages[1].slots[1],{kind="empty"}); A.equal(nextState.revision,1)
    input.id=999; A.equal(nextState.pages[1].slots[1].id,123)
    nextState = assign(nextState,"slots",1,{kind="item",id=456})
    A.deep(nextState.pages[1].slots[1],{kind="item",id=456})
    nextState = assign(nextState,"slots",1,{kind="empty"})
    A.deep(nextState.pages[1].slots[1],{kind="empty"})
    nextState = assign(nextState,"readouts",3,{kind="item",itemID=777})
    A.deep(nextState.pages[1].readouts[3],{kind="item",itemID=777})
end)
A.test("rejections retain exact state and validate ids kinds indices areas", function()
    local s = fresh()
    local bad = {{kind="macro",id=1},{kind="spell"},{kind="item",id=0},{kind="item",id=-1},
        {kind="spell",id=1.2},{kind="spell",id="1"},{kind="spell",id=math.huge},{kind="item",id=0/0},false}
    for _, slot in ipairs(bad) do
        local result, ok = assign(s,"slots",1,slot); A.equal(result,s); A.equal(ok,false)
    end
    for _, args in ipairs({{"readouts",1,{kind="spell",id=1}}, {"slots",0,{kind="empty"}},
        {"slots",16,{kind="empty"}}, {"readouts",4,{kind="empty"}}, {"other",1,{kind="empty"}}}) do
        local result, ok = assign(s,unpack(args)); A.equal(result,s); A.equal(ok,false)
    end
    local result, ok, why = core().assign(s,"slots",1,{kind="spell",id=1},true)
    A.equal(result,s); A.equal(ok,false); A.equal(why,"combat")
    A.deep(s,fresh())
end)
A.test("pages restore exactly create empty and stop at ten", function()
    local s = assign(fresh(),"slots",15,{kind="spell",id=42})
    s = assign(s,"readouts",1,{kind="item",itemID=7})
    local pageOne = s.pages[1]
    s = core().page(s,"next",false)
    A.equal(s.currentPage,2); A.deep(s.pages[2].slots[15],{kind="empty"})
    s = assign(s,"slots",2,{kind="item",id=8})
    local pageTwo = s.pages[2]
    s = core().page(s,"home",false); A.deep(s.pages[1],pageOne)
    s = core().page(s,"prev",false); A.equal(s.currentPage,1)
    s = core().page(s,"next",false); A.deep(s.pages[2],pageTwo)
    for i=3,10 do s = core().page(s,"next",false); A.equal(s.currentPage,i) end
    local result, ok = core().page(s,"next",false); A.equal(result,s); A.equal(ok,false)
    for _, action in ipairs({"next","prev","home"}) do
        local r, accepted, why = core().page(s,action,true)
        A.equal(r,s); A.equal(accepted,false); A.equal(why,"combat")
    end
    local r, accepted = core().page(s,"invalid",false); A.equal(r,s); A.equal(accepted,false)
end)
A.test("recovery merges malformed sparse saves without mutation", function()
    for _, bad in ipairs({false,1,"bad"}) do A.deep(core().recover(bad,"opaque-1"),fresh()) end
    local saved = {profileId="kept",revision=5,currentPage=99,pages={
        [1]={slots={[1]={kind="item",id=12},[2]={kind="spell",id=-3}},readouts="bad"},
        [3]={slots={[15]={kind="spell",id=99}}},[11]={}}}
    local s = core().recover(saved,"new")
    A.equal(s.profileId,"kept"); A.equal(s.revision,5); A.equal(#s.pages,3); A.equal(s.currentPage,3)
    A.deep(s.pages[1].slots[2],{kind="empty"}); A.equal(s.pages[3].slots[15].id,99)
    A.equal(#s.pages[2].slots,15); A.equal(#s.pages[1].readouts,3)
    s.pages[1].slots[1].id=77; A.equal(saved.pages[1].slots[1].id,12)
    local cycle = {}; cycle.pages=cycle
    A.equal(#core().recover(cycle,"x").pages,1)
    s = core().recover({profileId={},revision=-1,currentPage="bad",pages=false},"x")
    A.equal(s.profileId,"x"); A.equal(s.revision,0); A.equal(s.currentPage,1)
end)
A.test("deterministic export shape metadata and only item timers", function()
    local s = assign(fresh(),"slots",1,{kind="spell",id=42})
    s = assign(s,"slots",2,{kind="item",id=8})
    s = assign(s,"readouts",1,{kind="item",itemID=8})
    local providers = {spells={[42]={name="Spell",iconFileID=10,count=999,endsAt=99}},
        items={[8]={name="Item",iconFileID=20,count=0,endsAt=150,source="est"}}}
    local e = core().buildExport(s,100,function() return false end,providers)
    A.deep(e,{schema=1,profileId="opaque-1",revision=3,savedAt=100,page={index=1,count=1},
        slots=e.slots,readouts=e.readouts})
    A.equal(#e.slots,15); A.equal(#e.readouts,3)
    A.deep(e.slots[1],{kind="spell",id=42,chord=core().chord(1),name="Spell",iconFileID=10})
    A.deep(e.slots[2],{kind="item",id=8,chord=core().chord(2),name="Item",iconFileID=20,count=0,endsAt=150,source="est"})
    A.deep(e.readouts[1],{kind="item",itemID=8,name="Item",iconFileID=20,count=0,endsAt=150,source="est"})
    A.deep(e.slots[3],{kind="empty"}); A.deep(e.readouts[3],{kind="empty"})
    A.deep(e,core().buildExport(s,100,function() return false end,providers))
    e.slots[1].id=1; A.equal(s.pages[1].slots[1].id,42); A.equal(providers.spells[42].name,"Spell")
end)
A.test("export removes unavailable secret malformed and stale fields", function()
    local secret = setmetatable({}, {__tostring=function() error("secret touched") end})
    local function issecret(v) return v == secret end
    local s = assign(fresh(),"slots",1,{kind="item",id=8})
    local data = {items={[8]={name=secret,iconFileID=secret,count=secret,endsAt=secret,source=secret}}}
    local e = core().buildExport(s,100,issecret,data)
    A.deep(e.slots[1],{kind="item",id=8,chord=core().chord(1)})
    data.items[8]={name="cached",count=12,iconFileID=1,endsAt=150,source="game"}
    local previous = core().buildExport(s,100,issecret,data)
    data.items[8]=nil
    local current = core().buildExport(s,101,issecret,data)
    A.equal(previous.slots[1].count,12); A.equal(current.slots[1].count,nil)
    data.items[8]={count=-1,iconFileID="bad",endsAt=math.huge,source="other",name={}}
    A.deep(core().buildExport(s,102,issecret,data).slots[1],current.slots[1])
    A.equal(core().buildExport(s,secret,issecret,data).savedAt,nil)
    A.deep(core().buildExport(s,100,issecret,{items=secret}).slots[1],current.slots[1])
end)
