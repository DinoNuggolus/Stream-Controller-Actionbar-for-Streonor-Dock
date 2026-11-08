local addonName, ns = ...
local A=ns.Assert
local host, SECRET, copy = ns.host, ns.SECRET, ns.copy
local QMARK="Interface\\Icons\\INV_Misc_QuestionMark"
local function eventFrames(h)
    local n=0
    for _, f in ipairs(h.frames) do if next(f.events) then n=n+1 end end
    return n
end
A.test("load defers SavedVariables and owns exactly one event frame",function()
    local h=host()
    A.equal(rawget(h.env,"StreonorDockDB"),nil)
    A.equal(rawget(h.env,"StreonorDockCharDB"),nil)
    A.equal(h.created(),1,"only the event frame is created at load"); A.equal(h.eventFrame.events.ADDON_LOADED,true)
    for i=1,15 do
        local b=h.button(i)
        A.equal(b.xml,true); A.equal(b.template,"SecureActionButtonTemplate"); A.equal(rawget(b,"parent"),nil)
        A.equal(rawget(b,"clicks"),nil); A.deep(b.attrs,{})
    end
    h.event("ADDON_LOADED","OtherAddon")
    A.equal(rawget(h.env,"StreonorDockDB"),nil); A.equal(h.created(),1)
    h.event("ADDON_LOADED",addonName)
    A.equal(type(h.env.StreonorDockDB),"table")
    A.equal(#h.env.StreonorDockCharDB.pages[1].slots,15)
    A.equal(type(h.env.StreonorDockCharDB.profileId),"string")
    local profile=h.env.StreonorDockCharDB.profileId
    h.event("ADDON_LOADED",addonName); A.equal(h.env.StreonorDockCharDB.profileId,profile)
    A.equal(h.env.StreonorDockDB.export,nil)
    A.equal(eventFrames(h),1,"panel and secure frames register no events")
    h.event("UNHANDLED_EVENT")
end)
A.test("malformed saves and settings are repaired on ADDON_LOADED",function()
    local h=host({saved={pages=false,profileId="existing",revision="bad"},
        db={settings={estimates=7},probe={combatReadable="yes"},cooldownLearned={items={[8]={duration=-1},[9]={duration=30}}},ui={point="NOWHERE"}}})
    h.event("ADDON_LOADED",addonName)
    A.equal(h.env.StreonorDockCharDB.profileId,"existing"); A.equal(h.env.StreonorDockCharDB.revision,0)
    local db=h.env.StreonorDockDB
    A.equal(db.settings.estimates,"auto"); A.equal(db.probe.combatReadable,nil)
    A.deep(db.cooldownLearned.items,{[9]={duration=30}})
    local panel=h.named("StreonorDockPanel")
    A.deep(panel.points[1],{"CENTER",h.env.UIParent,"CENTER",0,0})
end)
A.test("pager in combat rejects with message and leaves state deeply unchanged",function()
    local h=host()
    h.login()
    h.env.SlashCmdList.STREONORDOCK("help")
    h.ns.Edit("slots",1,{kind="spell",id=42})
    local before=h.env.StreonorDockCharDB
    local snapshot=copy(before)
    local attrs=copy(h.button(1).attrs)
    local calls=h.protectedCalls
    h.combat=true
    for _, action in ipairs({"next","prev","home"}) do
        local changed,ok,why=h.env.StreonorDock_Page(action)
        A.equal(ok,false); A.equal(why,"combat"); A.equal(changed,before)
    end
    A.equal(h.env.StreonorDockCharDB,before); A.equal(h.ns.state,before)
    A.deep(before,snapshot,"state contents unchanged")
    A.deep(h.button(1).attrs,attrs); A.equal(h.protectedCalls,calls)
    A.equal(h.said("paging unavailable in combat"),true)
    -- Combat edits are rejected too (not queued) and do not run after combat.
    A.equal(h.ns.Edit("slots",2,{kind="item",id=8}),false)
    A.deep(h.env.StreonorDockCharDB,snapshot)
    h.combat=false; h.event("PLAYER_REGEN_ENABLED")
    A.deep(h.env.StreonorDockCharDB,snapshot,"nothing was queued")
    local newState,accepted=h.env.StreonorDock_Page("next")
    A.equal(accepted,true); A.equal(newState.currentPage,2); A.equal(h.env.StreonorDockCharDB,newState)
    A.equal(h.button(1).attrs["*type1"],nil,"page 2 slot 1 is empty: attributes cleared")
    h.env.StreonorDock_Page("home"); A.equal(h.button(1).attrs["*spell1"],42)
end)
A.test("secure setup during combat is queued once and runs after regen",function()
    local h=host()
    h.combat=true
    h.login(); h.event("PLAYER_ENTERING_WORLD"); h.event("SPELLS_CHANGED")
    A.equal(h.protectedCalls,0,"nothing protected attempted in combat"); A.equal(h.blocked,0)
    A.equal(rawget(h.button(1),"clicks"),nil); A.deep(h.button(1).attrs,{})
    A.equal(next(h.overrides),nil)
    h.event("PLAYER_REGEN_ENABLED")   -- still locked down: nothing runs
    A.equal(h.protectedCalls,0); A.equal(h.blocked,0)
    h.combat=false; h.event("PLAYER_REGEN_ENABLED")
    for i=1,15 do
        A.equal(h.button(i).template,"SecureActionButtonTemplate")
        A.equal(h.overrides[h.ns.Core.chord(i)],"CLICK StreonorDockSlot" .. i .. ":LeftButton")
    end
    A.equal(h.overrideOwner,h.named("StreonorDockBindingOwner"))
    A.equal(h.ns.Secure.status.verified,15); A.equal(h.setBindingCalls,0)
end)
A.test("attributes follow kind changes and never keep stale fields",function()
    local h=host()
    h.spells[42]={name="Moonfire",icon=136096,cached=true}
    h.login()
    local b=h.button(3)
    A.deep(b.attrs,{useOnKeyDown=true})
    h.ns.Edit("slots",3,{kind="spell",id=42})
    A.deep(b.attrs,{useOnKeyDown=true,["*type1"]="spell",["*spell1"]="Moonfire"})
    h.ns.Edit("slots",3,{kind="item",id=8})
    A.deep(b.attrs,{useOnKeyDown=true,["*type1"]="item",["*item1"]="item:8"},"stale *spell1 cleared")
    h.ns.Edit("slots",3,{kind="spell",id=42,pinned=true})
    A.deep(b.attrs,{useOnKeyDown=true,["*type1"]="spell",["*spell1"]=42},"pinned rank by ID; stale *item1 cleared")
    for _, key in ipairs({"type","spell","item"}) do A.equal(b.attrs[key],nil,"no unprefixed " .. key) end
    h.ns.Edit("slots",3,{kind="empty"})
    A.deep(b.attrs,{useOnKeyDown=true})
    -- Uncached spell name: cast by ID until SPELL_DATA_LOAD_RESULT, then by name.
    h.ns.Edit("slots",4,{kind="spell",id=77})
    A.equal(h.button(4).attrs["*spell1"],77)
    h.spells[77]={name="Rejuvenation",icon=1,cached=true}
    h.event("SPELL_DATA_LOAD_RESULT",77,true)
    A.equal(h.button(4).attrs["*spell1"],"Rejuvenation")
    -- Nothing changed: SPELLS_CHANGED and regen do not rewrite attributes or bindings.
    local writes, cleared=h.ns.Secure.status.writes, h.cleared
    h.event("SPELLS_CHANGED"); h.event("PLAYER_REGEN_ENABLED"); h.event("PLAYER_ENTERING_WORLD")
    A.equal(h.ns.Secure.status.writes,writes); A.equal(h.cleared,cleared)
    -- A lost override (e.g. another owner cleared it) is detected and re-applied.
    h.overrides["ALT-CTRL-SHIFT-5"]=nil; h.event("PLAYER_REGEN_ENABLED")
    A.equal(h.overrides["ALT-CTRL-SHIFT-5"],"CLICK StreonorDockSlot5:LeftButton")
end)
A.test("click direction matches ActionButtonUseKeyDown and follows CVAR_UPDATE",function()
    local h=host()
    h.login()
    A.deep(h.button(1).clicks,{"AnyDown"}); A.equal(h.button(1).attrs.useOnKeyDown,true)
    h.keyDown=false; h.event("CVAR_UPDATE","ActionButtonUseKeyDown","0")
    A.deep(h.button(15).clicks,{"AnyUp"}); A.equal(h.button(15).attrs.useOnKeyDown,false)
    h.keyDown=true; h.combat=true; h.event("CVAR_UPDATE","ActionButtonUseKeyDown","1")
    A.deep(h.button(15).clicks,{"AnyUp"},"not changed in combat")
    h.combat=false; h.event("PLAYER_REGEN_ENABLED")
    A.deep(h.button(15).clicks,{"AnyDown"})
end)
A.test("conflict report compares ordinary and effective mappings",function()
    local h=host()
    h.ordinary["ALT-CTRL-SHIFT-1"]="TOGGLEBAG1"
    h.login()
    A.equal(h.said("1 chord(s) also have other bindings"),true)
    h.messages={}
    h.slash("chords")
    A.equal(h.said("ordinary: TOGGLEBAG1 | effective: ours  CONFLICT"),true)
    A.equal(h.said("1 conflict(s)"),true)
    -- Effective lookup that ignores the override flag is reported, not assumed.
    h.env.GetBindingAction=function(key) return h.ordinary[key] or "" end
    h.messages={}; h.slash("chords")
    A.equal(h.said("2 ALT-CTRL-SHIFT-2 -> empty | ordinary: none | effective: none"),true)
end)
A.test("missing override API stops without any SetBinding fallback",function()
    local h=host({remove={"SetOverrideBindingClick"}})
    h.login()
    A.equal(h.ns.Secure.status.bindings,"unavailable"); A.equal(h.setBindingCalls,0)
    A.equal(h.said("override bindings are unavailable"),true)
    h.messages={}; h.slash("probe")
    A.equal(h.said("SetOverrideBindingClick: unavailable"),true); A.equal(h.said("overrides: unavailable"),true)
end)
A.test("drag and drop normalizes cursor and rejects without changing state",function()
    local h=host()
    h.items[8]={name="Potion",icon=500,count=3}
    h.login()
    local key, readout=h.editor("slots",5), h.editor("readouts",1)
    h.cursor={"spell",12,"spell",774}
    key.scripts.OnReceiveDrag(key)
    A.deep(h.ns.state.pages[1].slots[5],{kind="spell",id=774}); A.deep(h.cursor,{},"accepted drop clears cursor")
    local snapshot=copy(h.ns.state)
    h.cursor={"macro",4}
    key.scripts.OnReceiveDrag(key)
    A.deep(h.ns.state,snapshot); A.equal(h.cursor[1],"macro","rejected drop keeps cursor")
    h.cursor={"spell",12,"spell",774}
    readout.scripts.OnClick(readout,"LeftButton")
    A.deep(h.ns.state,snapshot); A.equal(h.said("readouts accept bag items only"),true)
    h.cursor={"item",8,"|Hitem:8::|h[Potion]|h"}
    h.combat=true; readout.scripts.OnReceiveDrag(readout)
    A.deep(h.ns.state,snapshot); A.equal(h.cursor[1],"item"); A.equal(h.said("editing unavailable in combat"),true)
    h.combat=false; readout.scripts.OnReceiveDrag(readout)
    A.deep(h.ns.state.pages[1].readouts[1],{kind="item",itemID=8})
    A.equal(readout.icon.texture,500); A.equal(readout.count.text,"3")
    -- Right-click with a held cursor only drops the cursor; without one it clears the slot.
    h.cursor={"item",8}
    key.scripts.OnClick(key,"RightButton")
    A.deep(h.cursor,{}); A.equal(h.ns.state.pages[1].slots[5].id,774)
    key.scripts.OnClick(key,"RightButton")
    A.deep(h.ns.state.pages[1].slots[5],{kind="empty"}); A.equal(h.button(5).attrs["*type1"],nil)
    A.equal(key.attrs["*type1"],nil,"editor widgets never carry action attributes")
end)
A.test("late metadata callback never overwrites a reassigned slot",function()
    local h=host()
    h.items[8]={name="Potion",icon=500,count=1}
    h.login()
    h.ns.Edit("slots",1,{kind="spell",id=42})          -- uncached: question mark, load requested
    local b=h.editor("slots",1)
    A.equal(h.requests[#h.requests],"spell:42")
    A.equal(b.icon.texture,"Interface\\Icons\\INV_Misc_QuestionMark")
    h.ns.Edit("slots",1,{kind="item",id=8})             -- reassigned before the callback
    A.equal(b.icon.texture,500)
    h.spells[42]={name="Moonfire",icon=136096,cached=true}
    b.icon.texture="sentinel"
    h.event("SPELL_DATA_LOAD_RESULT",42,true)
    A.equal(b.icon.texture,"sentinel","no refresh for a slot that no longer holds spell 42")
    A.equal(h.button(1).attrs["*item1"],"item:8")
    -- A matching slot does refresh, and a failed load is not re-requested in a loop.
    h.ns.Edit("slots",2,{kind="spell",id=43})
    local count=#h.requests
    h.event("SPELL_DATA_LOAD_RESULT",43,false)
    h.ns.Panel.Refresh()
    A.equal(#h.requests,count)
end)
A.test("export is sanitized, character-free and drops unavailable fields",function()
    local h=host()
    h.items[8]={name="Potion",icon=500,count=4}
    h.spells[42]={name="Moonfire",icon=136096,cached=true}
    h.login()
    h.ns.Edit("slots",1,{kind="spell",id=42}); h.ns.Edit("readouts",1,{kind="item",itemID=8})
    local e=h.env.StreonorDockDB.export
    A.equal(e.schema,1); A.equal(e.savedAt,1000100); A.deep(e.page,{index=1,count=1})
    A.deep(e.slots[1],{kind="spell",id=42,chord="ALT-CTRL-SHIFT-1",name="Moonfire",iconFileID=136096})
    A.deep(e.readouts[1],{kind="item",itemID=8,name="Potion",iconFileID=500,count=4})
    A.deep(e.player,{moneyCopper=5000,freeBagSlots=15})
    for k in pairs(e) do A.equal(k~="character" and k~="realm" and k~="name",true) end
    h.items[8].count=SECRET; h.money=SECRET; h.items[8].name=SECRET
    h.event("BAG_UPDATE_DELAYED"); h.runTimers()
    e=h.env.StreonorDockDB.export
    A.deep(e.readouts[1],{kind="item",itemID=8,iconFileID=500},"secret count/name removed, not kept stale")
    A.deep(e.player,{freeBagSlots=15})
    h.ns.Edit("readouts",1,{kind="empty"})
    h.slash("export"); A.equal(h.said("savedAt="),true)
    h.event("PLAYER_LOGOUT")
    A.deep(h.env.StreonorDockDB.export.readouts[1],{kind="empty"})
end)
A.test("logout stamps the built snapshot without reading teardown APIs",function()
    local h=host()
    h.items[8]={name="Water",icon=500,count=4}
    h.login(); h.ns.Edit("slots",1,{kind="item",id=8})
    local e=h.env.StreonorDockDB.export
    h.money=0; h.items[8].count=0
    h.env.C_Container.GetContainerNumFreeSlots=function() return 0 end
    h.env.GetMoney=function() error("logout must not read money") end
    h.env.C_Item.GetItemCount=function() error("logout must not read counts") end
    h.time=105
    h.event("PLAYER_LOGOUT")
    A.equal(h.env.StreonorDockDB.export,e)
    A.equal(e.slots[1].count,4); A.deep(e.player,{moneyCopper=5000,freeBagSlots=15})
    A.equal(e.savedAt,1000105); A.equal(e.revision,h.ns.state.revision)
end)
A.test("leaving flushes pending counts once and blocks late debounce callbacks",function()
    local h=host()
    h.items[8]={name="Water",icon=500,count=4}
    h.login(); h.ns.Edit("readouts",1,{kind="item",itemID=8})
    h.items[8].count=3; h.money=4900
    h.event("BAG_UPDATE_DELAYED"); h.event("PLAYER_MONEY")
    h.event("PLAYER_LEAVING_WORLD")
    local e=h.env.StreonorDockDB.export
    A.equal(e.readouts[1].count,3); A.equal(e.player.moneyCopper,4900)
    h.items[8].count=0; h.money=0
    h.env.C_Container.GetContainerNumFreeSlots=function() return 0 end
    h.event("PLAYER_LEAVING_WORLD"); h.event("BAG_UPDATE_DELAYED"); h.runTimers()
    A.equal(h.env.StreonorDockDB.export,e)
    h.event("PLAYER_LOGOUT"); A.equal(e.readouts[1].count,3)
end)
A.test("implausible zeros preserve identity matched counts and player then recover",function()
    local h=host()
    h.items[8]={name="Water",icon=500,count=4}
    h.items[9]={name="Apple",icon=501,count=2}
    h.login(); h.ns.Edit("slots",1,{kind="item",id=8})
    h.ns.Edit("readouts",1,{kind="item",itemID=9})
    h.money=0; h.items[8].count=0; h.items[9].count=0
    h.env.C_Container.GetContainerNumFreeSlots=function() return 0 end
    h.ns.Export.Refresh()
    local e=h.env.StreonorDockDB.export
    A.equal(e.countsStale,true); A.equal(e.slots[1].count,4); A.equal(e.readouts[1].count,2)
    A.deep(e.player,{moneyCopper=5000,freeBagSlots=15}); A.equal(e.slots[1].iconFileID,500)
    h.ns.Edit("slots",1,{kind="item",id=9})
    A.equal(h.env.StreonorDockDB.export.slots[1].count,2,"match item identity, not slot")
    h.money=10; h.ns.Export.Refresh()
    e=h.env.StreonorDockDB.export
    A.equal(e.countsStale,nil); A.equal(e.slots[1].count,0,"normal zero counts are valid")
    A.deep(e.player,{moneyCopper=10,freeBagSlots=0})
end)
A.test("teardown guard retains counts even with plausible live values",function()
    local h=host()
    h.items[8]={name="Water",icon=500,count=4}
    h.login(); h.ns.Edit("slots",1,{kind="item",id=8})
    h.event("PLAYER_LEAVING_WORLD")
    h.items[8].count=1; h.money=25
    h.ns.Export.Refresh()
    local e=h.env.StreonorDockDB.export
    A.equal(e.countsStale,true); A.equal(e.slots[1].count,4); A.equal(e.player.moneyCopper,5000)
    h.event("PLAYER_ENTERING_WORLD"); h.runTimers(); h.runTimers()
    A.equal(h.env.StreonorDockDB.export.slots[1].count,1)
    A.equal(h.env.StreonorDockDB.export.countsStale,nil)
end)
A.test("entering world waits for loaded bags then rebuilds without a bag event",function()
    local h=host()
    h.items[8]={name="Water",icon=500,count=0}
    h.login(); h.ns.Edit("slots",1,{kind="item",id=8})
    h.event("PLAYER_ENTERING_WORLD")
    h.items[8].count=5
    h.runTimers(); h.runTimers()
    A.equal(h.env.StreonorDockDB.export.slots[1].count,5)
end)
A.test("leaving flush guards zero readings and a later world refresh recovers",function()
    local h=host()
    h.items[8]={name="Water",icon=500,count=4}
    h.login(); h.ns.Edit("slots",1,{kind="item",id=8})
    h.event("PLAYER_ENTERING_WORLD")
    h.money=0; h.items[8].count=0
    h.env.C_Container.GetContainerNumFreeSlots=function() return 0 end
    h.event("PLAYER_MONEY"); h.event("PLAYER_LEAVING_WORLD")
    h.runTimers(); h.runTimers()
    local e=h.env.StreonorDockDB.export
    A.equal(e.countsStale,true); A.equal(e.slots[1].count,4); A.equal(e.player.freeBagSlots,15)
    h.event("PLAYER_ENTERING_WORLD"); h.money=20; h.items[8].count=2
    h.runTimers(); h.runTimers()
    e=h.env.StreonorDockDB.export
    A.equal(e.countsStale,nil); A.equal(e.slots[1].count,2); A.equal(e.player.moneyCopper,20)
end)
A.test("implausible first readings omit counts instead of copying another character",function()
    local h=host({db={export={profileId="other",player={moneyCopper=900,freeBagSlots=10},
        slots={{kind="item",id=8,count=99}}}}})
    h.money=0; h.env.C_Container.GetContainerNumFreeSlots=function() return 0 end
    h.items[8]={name="Water",icon=500,count=0}
    h.login(); h.ns.Edit("slots",1,{kind="item",id=8})
    local e=h.env.StreonorDockDB.export
    A.equal(e.countsStale,true); A.equal(e.player,nil); A.equal(e.slots[1].count,nil)
    A.equal(e.slots[1].iconFileID,500)
end)
A.test("export command reports memory without rebuilding or printing secrets",function()
    local h=host()
    h.items[8]={name="Water",icon=500,count=4}
    h.login(); h.ns.Edit("slots",1,{kind="item",id=8})
    local e=h.env.StreonorDockDB.export
    h.items[8].count=0; h.money=0
    h.slash("export")
    A.equal(h.env.StreonorDockDB.export,e); A.equal(e.slots[1].count,4)
    A.equal(h.said("slots[1]=4"),true); A.equal(h.said("freeBagSlots=15"),true)
    A.equal(h.said("money=present"),true); A.equal(h.said("savedAt=1000100"),true)
    e.player.moneyCopper=SECRET; e.slots[1].count=SECRET; e.savedAt=SECRET
    h.slash("export")
    A.equal(h.said("slots[1]=sealed"),true)
end)
A.test("key press starts one item timer shared across pages and slots",function()
    local h=host({db={cooldownLearned={items={[8]={duration=60}}}}})
    h.items[8]={name="Potion",icon=500,count=2}
    h.login()
    h.ns.Edit("slots",1,{kind="item",id=8}); h.ns.Edit("readouts",2,{kind="item",itemID=8})
    h.combat=true
    h.items[8].cd={SECRET,SECRET,SECRET}
    h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)
    local readout=h.editor("readouts",2)
    A.deep(readout.cooldown.cd,{100,60}); A.equal(readout.label.text,"est")
    h.time=110; h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)
    A.deep(readout.cooldown.cd,{100,60},"no restart while running")
    h.event("BAG_UPDATE_COOLDOWN")                     -- sealed reading changes nothing
    A.equal(h.ns.cooldowns:remaining(8,110),50)
    h.combat=false
    h.env.StreonorDock_Page("next")                    -- page 2 has no item 8...
    h.ns.Edit("slots",9,{kind="item",id=8})            -- ...until shown again: same timer
    A.deep(h.editor("slots",9).cooldown.cd,{100,60})
    -- Readable data reconciles and overrides the estimate.
    h.items[8].cd={101,120,true}; h.time=115; h.event("PLAYER_REGEN_ENABLED")
    local seconds, source=h.ns.cooldowns:remaining(8,115)
    A.equal(seconds,106); A.equal(source,"game"); A.equal(h.env.StreonorDockDB.cooldownLearned.items[8].duration,60,"start is not our last press: no learning")
    A.equal(h.editor("slots",9).label.text,"")
end)
A.test("press guards: count, non-item slots, and estimates setting",function()
    local h=host()
    h.items[8]={name="Potion",icon=500,count=0}
    h.items[9]={name="Stone",icon=501,count=1}
    h.login()
    h.ns.Edit("slots",1,{kind="item",id=8}); h.ns.Edit("slots",2,{kind="spell",id=42})
    h.ns.Edit("slots",3,{kind="item",id=9})
    -- Out of combat with a plain reading: the press is recorded, no estimate (Amendment 2.7).
    h.button(3).scripts.PostClick(h.button(3),"LeftButton",true)
    A.equal(h.editor("slots",3).label.text,"","starter food out of combat: no USED marker")
    A.deep(h.ns.cooldowns:activeItems(100),{})
    h.combat=true
    h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)
    A.equal(h.ns.cooldowns:running(8,100),false,"count 0: no timer")
    h.button(2).scripts.PostClick(h.button(2),"LeftButton",true)
    A.deep(h.ns.cooldowns:activeItems(100),{})
    h.button(3).scripts.PostClick(h.button(3),"LeftButton",true)
    A.equal(h.editor("slots",3).label.text,"USED 0s","unknown length in combat: USED, no countdown")
    -- A plain READY reading in combat is not evidence; after the grace window it resolves USED.
    h.items[9].cd={0,0,true}; h.time=103; h.event("BAG_UPDATE_COOLDOWN")
    A.equal(h.env.StreonorDockDB.probe.combatReadable,nil); A.equal(h.ns.Export.EstimatesEnabled(),true)
    A.equal(h.editor("slots",3).label.text,"","ready reading cleared the USED marker")
    -- A readable ACTIVE cooldown in combat turns auto estimates off.
    h.items[9].cd={103,60,true}; h.event("BAG_UPDATE_COOLDOWN")
    A.equal(h.env.StreonorDockDB.probe.combatReadable,true); A.equal(h.ns.Export.EstimatesEnabled(),false)
    h.items[8].count=5; h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)
    A.equal(h.ns.cooldowns:running(8,103),false)
    h.slash("estimates on"); A.equal(h.ns.Export.EstimatesEnabled(),true)
    h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)
    A.equal(h.ns.cooldowns:running(8,103),true)
    h.combat=false
end)
A.test("one timer only while a countdown is active",function()
    local h=host({db={cooldownLearned={items={[8]={duration=30}}}}})
    h.items[8]={name="Potion",icon=500,count=1}
    h.login(); h.timers={}
    h.ns.Edit("readouts",1,{kind="item",itemID=8})
    h.timers={}
    h.ns.Edit("slots",1,{kind="item",id=8}); h.timers={}
    h.combat=true
    h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)
    h.combat=false
    local armed=0
    for _, t in ipairs(h.timers) do if t.Cancel and not t.cancelled then armed=armed+1 end end
    A.equal(armed,1)
    h.time=131; h.runTimers()
    armed=0
    for _, t in ipairs(h.timers) do if t.Cancel and not t.cancelled then armed=armed+1 end end
    A.equal(armed,0,"idle: no timer re-armed")
    A.equal(rawget(h.editor("readouts",1).cooldown,"cd"),nil)
end)
A.test("slash commands, probe presence only, unknown events and fail-soft handlers",function()
    local h=host({unknownEvents={BAG_UPDATE_COOLDOWN=true}})
    h.login()
    A.equal(h.env.SLASH_STREONORDOCK1,"/sdock")
    h.slash("help"); A.equal(h.said("/sdock toggle"),true)
    h.env.SetOverrideBindingClick=function() error("probe must not bind") end
    h.env.C_Item.GetItemCooldown=function() error("probe must not read cooldown") end
    h.env.WOW_PROJECT_ID=SECRET
    h.messages={}; h.slash("probe")
    A.equal(h.said("WOW_PROJECT_ID: sealed"),true); A.equal(h.said("events not registered: BAG_UPDATE_COOLDOWN"),true)
    A.equal(h.said("internal error"),false)
    local panel=h.named("StreonorDockPanel")
    A.equal(panel:IsShown(),false); h.slash("toggle"); A.equal(panel:IsShown(),true)
    A.equal(h.env.StreonorDockDB.ui.shown,true)
    h.combat=true; h.slash("toggle"); A.equal(panel:IsShown(),false,"plain panel may hide in combat")
    h.combat=false
    h.slash("page next"); A.equal(h.ns.state.currentPage,2)
    h.slash("page sideways"); A.equal(h.said("usage: /sdock page"),true)
    -- A throwing API is reported once, not spammed, and does not break later events.
    h.env.GetMoney=function() error("boom") end
    h.messages={}
    h.event("PLAYER_LOGOUT"); h.event("PLAYER_LOGOUT")
    local reports=0
    for _, m in ipairs(h.messages) do if string.find(m,"internal error",1,true) then reports=reports+1 end end
    A.equal(reports<=1,true)
end)
A.test("no addon Lua file starts with a BOM and every TOC file exists",function()
    local toc=io.open("src/StreonorDock/StreonorDock.toc","rb"); local text=toc:read("*a"); toc:close()
    local files=0
    for line in string.gmatch(text,"[^\r\n]+") do
        if string.match(line,"%.lua$") then
            files=files+1
            local f=io.open("src/StreonorDock/" .. line,"rb"); A.equal(f~=nil,true,line .. " exists")
            local head=f:read(25); f:close()
            A.equal(string.sub(head,1,3)~="\239\187\191",true,line .. " has no BOM")
            A.equal(head,"local addonName, ns = ...",line .. " namespace first line")
        end
    end
    A.equal(files,7)
    for _, name in ipairs({"StreonorDock.toc","Bindings.xml","Slots.xml"}) do
        local f=io.open("src/StreonorDock/" .. name,"rb"); local head=f:read(3); f:close()
        A.equal(head~="\239\187\191",true,name .. " has no BOM")
    end
end)
A.test("degrades gracefully: empty bags, no spells, no cooldown items",function()
    local h=host()
    h.env.C_Item.GetItemCount=function() return 0 end
    h.env.C_Item.GetItemIconByID=function() return nil end
    h.env.C_Spell.GetSpellInfo=function() return nil end
    h.env.C_Container.GetContainerNumFreeSlots=function() return 0, 0 end
    h.login(); h.event("PLAYER_ENTERING_WORLD",true,false)
    for _, e in ipairs({"BAG_UPDATE_COOLDOWN","BAG_UPDATE_DELAYED","PLAYER_MONEY","SPELLS_CHANGED",
        "PLAYER_REGEN_ENABLED","ITEM_DATA_LOAD_RESULT","SPELL_DATA_LOAD_RESULT"}) do h.event(e) end
    for i=1,15 do h.button(i).scripts.PostClick(h.button(i),"LeftButton",true) end
    for _, cmd in ipairs({"probe","chords","cooldowns","export","toggle","toggle","page home","page prev",
        "estimates","help",""}) do h.slash(cmd) end
    local key=h.editor("slots",1)
    key.scripts.OnClick(key,"LeftButton"); key.scripts.OnClick(key,"RightButton"); key.scripts.OnEnter(key)
    key.scripts.OnReceiveDrag(key)
    h.runTimers(); h.event("PLAYER_LOGOUT")
    A.equal(h.said("internal error"),false)
    A.equal(h.said("nothing learned yet"),true)
    A.equal(h.said("cooldown table: 0 group(s)"),true)
    local e=h.env.StreonorDockDB.export
    for i=1,15 do A.deep(e.slots[i],{kind="empty"}) end
    A.deep(e.player,{moneyCopper=5000,freeBagSlots=0})
    A.deep(h.ns.cooldowns:activeItems(h.time),{})
end)
A.test("probe lists held table groups and cooldowns prints learned own-use data",function()
    local h=host()
    h.items[118]={name="Minor Healing Potion",icon=1,count=2}
    h.items[2455]={name="Minor Mana Potion",icon=2,count=1}
    h.login()
    h.slash("probe")
    A.equal(h.said("health_potion [pool potion]: table 120s, observed -; items 118x2"),true)
    A.equal(h.said("mana_potion [pool potion]: table 120s, observed -; items 2455x1"),true)
    h.ns.Edit("slots",1,{kind="item",id=118})
    h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)       -- press at t=100
    h.items[118].cd={100.2,120,true}; h.items[2455].cd={100.2,120,true}
    h.time=100.5; h.event("BAG_UPDATE_COOLDOWN")
    h.messages={}; h.slash("cooldowns")
    A.equal(h.said("group health_potion = 120s verified; items seen 118"),true)
    A.equal(h.said("pool potion: shared lock seen"),true)
    h.messages={}; h.slash("probe")
    A.equal(h.said("health_potion [pool potion]: table 120s, observed 120s (verified this build); pool sharing seen"),true)
    A.equal(h.editor("slots",1).label.text,"")
end)
A.test("combat readability latch: ready readings are no evidence, sealed wins, per build",function()
    local h=host({db={probe={build="old.1",combatReadable=true}},env={GetBuildInfo=function() return "1.60.1","70790","x",16001 end}})
    h.items[8]={name="Potion",icon=500,count=1}
    h.login()
    A.equal(h.env.StreonorDockDB.probe.build,"1.60.1.70790"); A.equal(h.env.StreonorDockDB.probe.combatReadable,nil,"build change resets")
    A.equal(h.ns.Export.EstimatesEnabled(),true)
    h.ns.Edit("readouts",1,{kind="item",itemID=8})
    h.combat=true
    h.items[8].cd={0,0,true}; h.event("BAG_UPDATE_COOLDOWN")          -- plain ready reading
    h.items[8].cd={100,1.5,true}; h.event("BAG_UPDATE_COOLDOWN")      -- plain GCD reading
    A.equal(h.env.StreonorDockDB.probe.combatReadable,nil); A.equal(h.ns.Export.EstimatesEnabled(),true)
    h.items[8].cd={SECRET,SECRET,SECRET}; h.event("BAG_UPDATE_COOLDOWN")  -- sealed active cooldown
    A.equal(h.ns.Export.stats.sealed,1,"classified sealed, not unavailable")
    A.equal(h.env.StreonorDockDB.probe.combatReadable,false); A.equal(h.ns.Export.EstimatesEnabled(),true)
    h.items[8].cd={100,60,true}; h.event("BAG_UPDATE_COOLDOWN")       -- later readable active
    A.equal(h.env.StreonorDockDB.probe.combatReadable,false,"sealed evidence wins on this build")
    h.combat=false
    -- Same build next session keeps the evidence.
    local db=h.env.StreonorDockDB
    local h2=host({db=db,env={GetBuildInfo=function() return "1.60.1","70790","x",16001 end}})
    h2.login(); A.equal(h2.env.StreonorDockDB.probe.combatReadable,false)
end)
A.test("sealed vs unavailable classification of item cooldown readings",function()
    local h=host()
    h.login()
    A.equal(select(2,h.ns.Export.ReadItemCooldown(0)),"unavailable")
    h.items[8]={count=1,cd={SECRET,5,true}}
    A.equal(select(2,h.ns.Export.ReadItemCooldown(8)),"sealed")
    h.items[8].cd={100,SECRET,true}; A.equal(select(2,h.ns.Export.ReadItemCooldown(8)),"sealed")
    h.items[8].cd={100,30,SECRET}; A.equal(select(2,h.ns.Export.ReadItemCooldown(8)),"sealed")
    h.items[8].cd={nil,nil,nil}; A.equal(select(2,h.ns.Export.ReadItemCooldown(8)),"unavailable")
    h.items[8].cd={100,30,false}; A.equal(select(2,h.ns.Export.ReadItemCooldown(8)),"paused")
    h.items[8].cd={100,30,true}; local s,d=h.ns.Export.ReadItemCooldown(8); A.equal(s,100); A.equal(d,30)
    A.deep({h.ns.Export.stats.sealed,h.ns.Export.stats.unavailable,h.ns.Export.stats.readable},{3,1,1})
end)
A.test("metadata results: unrequested IDs ignored, retries capped",function()
    local h=host()
    h.login()
    h.ns.Edit("slots",1,{kind="spell",id=42})
    local refreshed=0
    local original=h.ns.Panel.RefreshSlots
    h.ns.Panel.RefreshSlots=function(list) refreshed=refreshed+#list; return original(list) end
    h.event("SPELL_DATA_LOAD_RESULT",777,true)                          -- someone else's load
    A.equal(refreshed,0)
    for _=1,10 do h.event("SPELL_DATA_LOAD_RESULT",42,true); h.ns.Panel.Refresh() end
    local n=0
    for _, r in ipairs(h.requests) do if r=="spell:42" then n=n+1 end end
    A.equal(n,h.ns.Export.MAX_REQUESTS,"request -> result -> request loop is capped")
end)
A.test("diagnostic CLICK bindings are declared and named, never set by the addon",function()
    local f=io.open("src/StreonorDock/Bindings.xml","rb"); local xml=f:read("*a"); f:close()
    local n=0
    for i in string.gmatch(xml,'<Binding name="CLICK StreonorDockSlot(%d+):LeftButton"') do n=n+1; A.equal(tonumber(i),n) end
    A.equal(n,15); A.equal(string.find(xml,'header="STREONORDOCK_SLOTS"',1,true)~=nil,true)
    A.equal(string.find(xml,'header="STREONORDOCK"',1,true)~=nil,true)
    local h=host(); h.login()
    A.equal(h.env.BINDING_HEADER_STREONORDOCK_SLOTS~=nil,true)
    A.equal(h.env["BINDING_NAME_CLICK StreonorDockSlot11:LeftButton"],"Slot 11 (same as ALT-CTRL-SHIFT--)")
    A.equal(h.setBindingCalls,0)
    for _, file in ipairs({"Core","Cooldown","CooldownData","Panel","Secure","Export","Init"}) do
        local src=io.open("src/StreonorDock/" .. file .. ".lua","rb"); local text=src:read("*a"); src:close()
        local code=string.gsub(text,"%-%-[^\n]*","")
        A.equal(string.find(code,"SetBinding%s*%(")==nil and string.find(code,"SaveBindings%s*%(")==nil,true,file)
    end
end)
A.test("fresh login with nothing cached: icons, counts and export fill in without /reload",function()
    local h=host({saved=nil})
    -- First session builds a layout, second session restores it with all item/spell data uncached.
    h.items[8]={name="Water",icon=500,count=4}
    h.spells[42]={name="Moonfire",icon=136096,cached=true}
    h.login(); h.ns.Edit("slots",1,{kind="spell",id=42}); h.ns.Edit("slots",2,{kind="item",id=8})
    local saved=ns.copy(h.env.StreonorDockCharDB)
    local h2=host({saved=saved,db={}})
    h2.event("ADDON_LOADED",addonName)
    h2.event("PLAYER_LOGIN"); h2.event("PLAYER_ENTERING_WORLD")
    local s1,s2=h2.editor("slots",1),h2.editor("slots",2)
    A.equal(s1.icon.texture,QMARK)
    A.equal(s2.icon.texture,QMARK)
    A.equal(s2.count.text,"0")   -- bags not loaded yet
    -- Data arrives later.
    h2.items[8]={name="Water",icon=500,count=4}
    h2.spells[42]={name="Moonfire",icon=136096,cached=true}
    h2.event("SPELL_DATA_LOAD_RESULT",42,true); h2.event("ITEM_DATA_LOAD_RESULT",8,true)
    A.equal(s1.icon.texture,136096); A.equal(s2.icon.texture,500); A.equal(s2.count.text,"4")
    for _=1,4 do h2.runTimers() end
    local e=h2.env.StreonorDockDB.export
    A.equal(e.slots[1].iconFileID,136096); A.equal(e.slots[2].iconFileID,500); A.equal(e.slots[2].count,4)
end)
A.test("missed data-load event: delayed login retry still fills icons and counts",function()
    local h=host()
    h.items[8]={name="Water",icon=500,count=4}
    h.login(); h.ns.Edit("slots",2,{kind="item",id=8})
    local saved=ns.copy(h.env.StreonorDockCharDB)
    local h2=host({saved=saved,db={}})
    h2.event("ADDON_LOADED",addonName); h2.event("PLAYER_LOGIN"); h2.event("PLAYER_ENTERING_WORLD")
    local b=h2.editor("slots",2)
    A.equal(b.icon.texture,QMARK)
    h2.items[8]={name="Water",icon=500,count=4}   -- data arrives, but no ITEM_DATA_LOAD_RESULT is delivered
    for _=1,4 do h2.runTimers() end
    A.equal(b.icon.texture,500); A.equal(b.count.text,"4")
    A.equal(h2.env.StreonorDockDB.export.slots[2].iconFileID,500)
end)
