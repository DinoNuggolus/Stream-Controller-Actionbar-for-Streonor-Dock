local addonName, ns = ...
local A=ns.Assert
-- Isolated fake host: unexpected API use is an error. No actual game APIs are called.
local function host(saved)
    local sandbox, frames, messages = {}, {}, {}
    local combat=false
    local env={type=type,pairs=pairs,ipairs=ipairs,tostring=tostring,tonumber=tonumber,
        math=math,string=string,table=table,setmetatable=setmetatable,print=function(msg) messages[#messages+1]=msg end,
        SlashCmdList={},StreonorDockCharDB=saved,
        InCombatLockdown=function() return combat end}
    env.CreateFrame=function(kind)
        A.equal(kind,"Frame")
        local f={events={}}
        function f:RegisterEvent(name) self.events[name]=true end
        function f:SetScript(name,fn) A.equal(name,"OnEvent"); self.dispatch=fn end
        frames[#frames+1]=f; return f
    end
    setmetatable(env,{__index=function(_,key) error("unexpected global " .. key) end})
    -- Capability probes deliberately inspect missing globals; allow nil for known candidates.
    env._G=env
    local allowed={SetOverrideBindingClick=true,GetBindingAction=true,C_Spell=true,C_Item=true,
        issecretvalue=true,GetServerTime=true,GetTime=true,GetCVarBool=true,
        StreonorDockDB=true,StreonorDockCharDB=true}
    setmetatable(env,{__index=function(_,key) if not allowed[key] then error("unexpected global " .. key) end end})
    for _, name in ipairs({"Core","Cooldown","Panel","Secure","Export","Init"}) do
        local chunk, err=loadfile("src/StreonorDock/" .. name .. ".lua")
        A.equal(type(chunk),"function",err or (name .. " skeleton available"))
        setfenv(chunk,env); chunk(addonName,sandbox)
    end
    return {ns=sandbox,env=env,frames=frames,messages=messages,
        combat=function(v) combat=v end,
        event=function(name,...) local f=frames[1]; f.dispatch(f,name,...) end}
end
A.test("skeleton load defers SavedVariables and owns exactly one event frame",function()
    local h=host()
    A.equal(rawget(h.env,"StreonorDockDB"),nil)
    A.equal(rawget(h.env,"StreonorDockCharDB"),nil)
    A.equal(#h.frames,1); A.equal(h.frames[1].events.ADDON_LOADED,true)
    h.event("ADDON_LOADED","OtherAddon")
    A.equal(rawget(h.env,"StreonorDockDB"),nil)
    h.event("ADDON_LOADED",addonName)
    A.equal(type(h.env.StreonorDockDB),"table")
    A.equal(type(h.env.StreonorDockCharDB),"table")
    A.equal(#h.env.StreonorDockCharDB.pages[1].slots,15)
    A.equal(type(h.env.StreonorDockCharDB.profileId),"string")
    local profile=h.env.StreonorDockCharDB.profileId
    h.event("ADDON_LOADED",addonName); A.equal(h.env.StreonorDockCharDB.profileId,profile)
    A.equal(h.env.StreonorDockDB.export,nil)
    h.event("UNHANDLED_EVENT")
end)
A.test("skeleton repairs malformed saves on ADDON_LOADED",function()
    local h=host({pages=false,profileId="existing",revision="bad"})
    h.env.StreonorDockDB=false
    h.event("ADDON_LOADED",addonName)
    A.equal(h.env.StreonorDockCharDB.profileId,"existing")
    A.equal(h.env.StreonorDockCharDB.revision,0)
    A.equal(type(h.env.StreonorDockDB),"table")
end)
A.test("pager rejects combat while presentation maintenance waits for regen",function()
    local h=host()
    h.combat(true); h.event("ADDON_LOADED",addonName)
    local old=h.env.StreonorDockCharDB
    local changed,ok=h.env.StreonorDock_Page("next")
    A.equal(changed,old); A.equal(ok,false); A.equal(#old.pages,1)
    local calls=0
    h.ns.RunOutOfCombat(function() calls=calls+1 end)
    h.ns.RunOutOfCombat(function() calls=calls+10 end)
    A.equal(calls,0)
    h.event("PLAYER_REGEN_ENABLED"); A.equal(calls,0)
    h.combat(false); h.event("PLAYER_REGEN_ENABLED"); A.equal(calls,11)
    h.event("PLAYER_REGEN_ENABLED"); A.equal(calls,11)
    h.ns.RunOutOfCombat(function() calls=calls+1 end); A.equal(calls,12)
    local newState,accepted=h.env.StreonorDock_Page("next")
    A.equal(accepted,true); A.equal(newState.currentPage,2)
    A.equal(h.env.StreonorDockCharDB,newState)
end)
A.test("slash help and capability probe report missing functions without calling them",function()
    local h=host(); h.event("ADDON_LOADED",addonName)
    A.equal(h.env.SLASH_STREONORDOCK1,"/sdock")
    h.env.SlashCmdList.STREONORDOCK("help")
    A.equal(#h.messages>0,true)
    h.env.SlashCmdList.STREONORDOCK("probe")
    A.equal(#h.messages>1,true)
    h.env.SetOverrideBindingClick=function() error("probe must not bind") end
    h.env.C_Item={GetItemCooldown=function() error("probe must not read cooldown") end}
    h.env.SlashCmdList.STREONORDOCK("probe")
    h.env.SlashCmdList.STREONORDOCK("")
    h.env.SlashCmdList.STREONORDOCK("export")
    A.equal(h.env.StreonorDockDB.export,nil)
end)
