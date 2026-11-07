local addonName, ns = ...
local A = ns.Assert
local chunk = loadfile("src/StreonorDock/Cooldown.lua")
if chunk then chunk(addonName, ns) end
local function tracker(learned, groups, itemGroups)
    A.equal(type(ns.CooldownTracker),"table","CooldownTracker module available")
    return ns.CooldownTracker.new(learned, groups, itemGroups)
end
local function remaining(t,id,now,seconds,source)
    local actual, tag=t:remaining(id,now); A.equal(actual,seconds); A.equal(tag,source)
end
A.test("readable cooldown learns duration persists it and labels game source",function()
    local store={}
    local t=tracker(store)
    remaining(t,8,100,0,nil)
    A.equal(t:observe(8,100,30,105),true)
    remaining(t,8,105,25,"game"); remaining(t,8,130,0,nil)
    A.equal(store[8],30,"learning written to the persistence table")
    local again=tracker(store)
    A.equal(again:press(8,200,1),true); remaining(again,8,210,20,"est")
end)
A.test("persisted learning is validated in place",function()
    local store={[8]=30,[9]=1,[10]=-5,[11]="x",[0]=20,[1.5]=20,[12]=90000}
    local t=tracker(store)
    A.deep(store,{[8]=30}); A.equal(t:learnedDuration(8),30); A.equal(t:learnedDuration(9),nil)
    A.equal(type(tracker(false).learned),"table")
end)
A.test("press guards: item id, plain positive count, not already running",function()
    local t=tracker({[8]=60})
    A.equal(select(2,t:press(0,100,1)),"invalid"); A.equal(select(2,t:press(8,"x",1)),"invalid")
    for _, count in ipairs({0,-1,"3",false,0/0}) do
        local ok, why=t:press(8,100,count); A.equal(ok,false); A.equal(why,"count")
    end
    local ok=t:press(8,100,nil); A.equal(ok,false)
    remaining(t,8,100,0,nil)
    A.equal(t:press(8,100,2),true); remaining(t,8,110,50,"est")
end)
A.test("no restart while running: est, game and used timers",function()
    local t=tracker({[8]=60})
    t:press(8,100,1)
    local ok, why=t:press(8,130,1); A.equal(ok,false); A.equal(why,"running")
    remaining(t,8,130,30,"est")
    A.equal(t:press(8,160,1),true); remaining(t,8,170,50,"est")
    t:observe(9,100,40,100)
    A.equal(select(2,t:press(9,120,1)),"running"); remaining(t,9,120,20,"game")
    t:press(10,100,1)
    A.equal(select(2,t:press(10,500,1)),"running"); remaining(t,10,500,nil,"used")
end)
A.test("duration order: learned, then base cooldown, then used with elapsed",function()
    local t=tracker({[8]=60})
    t:press(8,100,1,45); remaining(t,8,100,60,"est")
    t:press(13,100,1,45); remaining(t,13,100,45,"est")
    t:press(9,100,1); local endsAt,_,source,usedAt=t:timer(9,150)
    A.equal(endsAt,nil); A.equal(source,"used"); A.equal(usedAt,100)
    t:press(11,100,1,1.0); remaining(t,11,100,nil,"used")  -- GCD-sized base is not a cooldown
    t:press(12,100,1,0/0); remaining(t,12,100,nil,"used")
    local e,d,s=t:timer(13,110); A.equal(e,145); A.equal(d,45); A.equal(s,"est")
    remaining(t,9,100+3600,0,nil)                       -- used marker expires
end)
A.test("timers are keyed by item id and survive anything page related",function()
    local t=tracker({[8]=60})
    t:press(8,100,3)
    -- Two different slots/pages showing item 8 read the same absolute timer.
    remaining(t,8,120,40,"est"); remaining(t,8,140,20,"est")
    A.deep(t:activeItems(140),{8})
    remaining(t,9,140,0,nil)
    A.deep(t:activeItems(161),{})
end)
A.test("readable game data reconciles and overrides an estimate",function()
    local t=tracker({[8]=60})
    t:press(8,100,1)
    A.equal(t:observe(8,0,0,100.5),false,"ready sample within grace is the pre-ack state")
    remaining(t,8,101,59,"est")
    A.equal(t:observe(8,101,120,102),true); remaining(t,8,110,111,"game")
    A.equal(t:learnedDuration(8),120)
    t:press(9,100,1)
    A.equal(t:observe(9,0,0,105),true,"failed use self-corrects")
    remaining(t,9,105,0,nil)
    t:press(10,100,1)                                   -- unknown length -> used
    t:observe(10,100,30,110); remaining(t,10,110,20,"game")
    t:observe(10,100,30,140); remaining(t,10,140,0,nil) -- expired readable sample clears, keeps learning
    A.equal(t:learnedDuration(10),30)
end)
A.test("GCD invalid and unavailable samples cannot poison or clear timers",function()
    local t=tracker()
    t:observe(8,100,20,100)
    A.equal(t:observe(8,110,1.5,110),false); A.equal(t:observe(8,110,1,110),false)
    for _, sample in ipairs({{8,-1,20,100},{8,100,-1,100},{8,100,math.huge,100},
        {8,100,0/0,100},{8,"100",20,100},{0,100,20,100},{8,111,20,110},
        {8,100,20,"bad"},{8,100,20,-1},{8,nil,nil,110}}) do
        A.equal(t:observe(unpack(sample)),false)
    end
    remaining(t,8,110,10,"game"); A.equal(t:learnedDuration(8),20)
    remaining(t,8,"bad",nil,nil); A.equal(t:timer(8,"bad"),nil)
end)
A.test("clear removes timer and learning for one item only",function()
    local store={}
    local t=tracker(store)
    t:observe(8,100,20,100); t:observe(9,100,50,100)
    t:clear(8); remaining(t,8,105,0,nil); remaining(t,9,105,45,"game")
    A.equal(store[8],nil); A.equal(store[9],50)
end)
local function groups()
    return {heal={name="Health potions",duration=120,shared=true,verified=false,source="test"},
        stone={name="Stones",duration=90,shared=nil},bomb={name="No length",shared=false},
        bad={duration=-3,shared="yes"}},
        {[8]="heal",[9]="heal",[10]="stone",[11]="bomb",[12]="missing",[0]="heal"}
end
A.test("shipped reference data is empty schema-only tables",function()
    local data=loadfile("src/StreonorDock/CooldownData.lua")
    local env={}; data("StreonorDock",env)
    A.deep(env.CooldownGroups,{}); A.deep(env.ItemGroups,{})
end)
A.test("group lookup validates reference data without mutating it",function()
    local g, ig=groups()
    local before=ns.copy and ns.copy(g) or nil
    local t=tracker({},g,ig)
    A.equal(t:group(8),"heal"); A.equal(t:group(12),nil); A.equal(t:group(0),nil)
    A.equal(t:key(8),"group:heal"); A.equal(t:key(10),10); A.equal(t:key(11),11); A.equal(t:key(99),99)
    A.equal(t.groups.bad.duration,nil); A.equal(t.groups.bad.shared,false)
    A.equal(t:pressDuration(10),90); A.equal(select(2,t:pressDuration(10)),"table")
    A.equal(t:pressDuration(11,30),30); A.equal(select(2,t:pressDuration(11,30)),"base")
    A.equal(t:pressDuration(11),nil)
    if before then A.deep(g,before) end
    A.equal(type(tracker({},false,"x").groups),"table")
end)
A.test("shared group: one timer for every member item; per-item otherwise",function()
    local g, ig=groups()
    local t=tracker({},g,ig)
    A.equal(t:press(8,100,1),true); remaining(t,9,110,110,"est")
    A.equal(select(2,t:press(9,110,1)),"running","another member cannot restart the group timer")
    A.deep(t:activeItems(110),{8})
    A.equal(t:press(10,100,1),true); remaining(t,10,110,80,"est")
    remaining(t,99,110,0,nil)
    A.equal(t:press(11,100,1),true); remaining(t,11,110,nil,"used")
    -- Readable data on any member reconciles the shared timer.
    t:observe(9,105,120,110); remaining(t,8,110,115,"game")
    t:observe(9,0,0,300); remaining(t,8,300,0,nil)
end)
A.test("precedence: game data over learned over table; mismatches are logged",function()
    local g, ig=groups()
    local store={}
    local t=tracker(store,g,ig)
    t:press(10,100,1); remaining(t,10,100,90,"est")      -- table value
    t:observe(10,101,60,102); remaining(t,10,102,59,"game") -- game overrides estimate
    A.equal(store[10],60)
    A.deep(t.mismatches,{{itemID=10,group="stone",table=90,game=60}})
    t:observe(10,101,60,103); A.equal(#t.mismatches,1,"duplicate mismatch not repeated")
    t:press(10,200,1); remaining(t,10,200,60,"est")      -- learned beats the table
    t:observe(8,100,120.5,101); A.equal(#t.mismatches,1,"within tolerance is not a mismatch")
    local fresh=tracker(store,g,ig); A.equal(fresh:pressDuration(10),60)
end)
