local addonName, ns = ...
local A=ns.Assert
local host, SECRET, copy = ns.host, ns.SECRET, ns.copy
local function eventFrames(h)
    local n=0
    for _, f in ipairs(h.frames) do if next(f.events) then n=n+1 end end
    return n
end
A.test("load defers SavedVariables and owns exactly one event frame",function()
    local h=host()
    A.equal(rawget(h.env,"StreonorDockDB"),nil)
    A.equal(rawget(h.env,"StreonorDockCharDB"),nil)
    A.equal(#h.frames,1); A.equal(h.frames[1].events.ADDON_LOADED,true)
    h.event("ADDON_LOADED","OtherAddon")
    A.equal(rawget(h.env,"StreonorDockDB"),nil); A.equal(#h.frames,1)
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
        db={settings={estimates=7},probe={combatReadable="yes"},cooldownLengths={[8]=-1,[9]=30},ui={point="NOWHERE"}}})
    h.event("ADDON_LOADED",addonName)
    A.equal(h.env.StreonorDockCharDB.profileId,"existing"); A.equal(h.env.StreonorDockCharDB.revision,0)
    local db=h.env.StreonorDockDB
    A.equal(db.settings.estimates,"auto"); A.equal(db.probe.combatReadable,nil)
    A.deep(db.cooldownLengths,{[9]=30})
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
    A.equal(h.button(1).attrs.type,nil,"page 2 slot 1 is empty: attributes cleared")
    h.env.StreonorDock_Page("home"); A.equal(h.button(1).attrs.spell,42)
end)
A.test("secure setup during combat is queued once and runs after regen",function()
    local h=host()
    h.combat=true
    h.login(); h.event("PLAYER_ENTERING_WORLD"); h.event("SPELLS_CHANGED")
    A.equal(h.button(1),nil,"no secure frame created in combat"); A.equal(h.protectedCalls,0)
    h.event("PLAYER_REGEN_ENABLED")   -- still locked down: nothing runs
    A.equal(h.button(1),nil)
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
    A.equal(b.attrs.type,"spell"); A.equal(b.attrs.spell,"Moonfire"); A.equal(b.attrs.item,nil)
    h.ns.Edit("slots",3,{kind="item",id=8})
    A.equal(b.attrs.type,"item"); A.equal(b.attrs.item,"item:8"); A.equal(b.attrs.spell,nil)
    h.ns.Edit("slots",3,{kind="spell",id=42,pinned=true})
    A.equal(b.attrs.spell,42,"pinned rank casts by ID"); A.equal(b.attrs.item,nil)
    h.ns.Edit("slots",3,{kind="empty"})
    A.deep(b.attrs,{useOnKeyDown=true})
    -- Uncached spell name: cast by ID until SPELL_DATA_LOAD_RESULT, then by name.
    h.ns.Edit("slots",4,{kind="spell",id=77})
    A.equal(h.button(4).attrs.spell,77)
    h.spells[77]={name="Rejuvenation",icon=1,cached=true}
    h.event("SPELL_DATA_LOAD_RESULT",77,true)
    A.equal(h.button(4).attrs.spell,"Rejuvenation")
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
    A.deep(h.ns.state.pages[1].slots[5],{kind="empty"}); A.equal(h.button(5).attrs.type,nil)
    A.equal(key.attrs.type,nil,"editor widgets never carry action attributes")
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
    A.equal(h.button(1).attrs.item,"item:8")
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
    h.slash("export"); A.equal(h.said("/reload or log out"),true)
    h.event("PLAYER_LOGOUT")
    A.deep(h.env.StreonorDockDB.export.readouts[1],{kind="empty"})
end)
A.test("key press starts one item timer shared across pages and slots",function()
    local h=host({db={cooldownLengths={[8]=60}}})
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
    A.equal(seconds,106); A.equal(source,"game"); A.equal(h.env.StreonorDockDB.cooldownLengths[8],120)
    A.equal(h.editor("slots",9).label.text,"")
end)
A.test("press guards: count, non-item slots, and estimates setting",function()
    local h=host()
    h.items[8]={name="Potion",icon=500,count=0}
    h.items[9]={name="Stone",icon=501,count=1}
    h.login()
    h.ns.Edit("slots",1,{kind="item",id=8}); h.ns.Edit("slots",2,{kind="spell",id=42})
    h.ns.Edit("slots",3,{kind="item",id=9})
    h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)
    A.equal(h.ns.cooldowns:running(8,100),false,"count 0: no timer")
    h.button(2).scripts.PostClick(h.button(2),"LeftButton",true)
    A.deep(h.ns.cooldowns:activeItems(100),{})
    h.button(3).scripts.PostClick(h.button(3),"LeftButton",true)
    A.equal(h.editor("slots",3).label.text,"USED 0s","unknown length: USED, no countdown")
    -- Auto mode: a readable reading during combat turns estimates off.
    h.combat=true; h.items[9].cd={0,0,true}; h.time=103; h.event("BAG_UPDATE_COOLDOWN")
    A.equal(h.env.StreonorDockDB.probe.combatReadable,true); A.equal(h.ns.Export.EstimatesEnabled(),false)
    h.items[8].count=5; h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)
    A.equal(h.ns.cooldowns:running(8,103),false)
    h.combat=false; h.slash("estimates on"); A.equal(h.ns.Export.EstimatesEnabled(),true)
    h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)
    A.equal(h.ns.cooldowns:running(8,103),true)
end)
A.test("one timer only while a countdown is active",function()
    local h=host({db={cooldownLengths={[8]=30}}})
    h.items[8]={name="Potion",icon=500,count=1}
    h.login(); h.timers={}
    h.ns.Edit("readouts",1,{kind="item",itemID=8})
    h.timers={}
    h.ns.Edit("slots",1,{kind="item",id=8}); h.timers={}
    h.button(1).scripts.PostClick(h.button(1),"LeftButton",true)
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
