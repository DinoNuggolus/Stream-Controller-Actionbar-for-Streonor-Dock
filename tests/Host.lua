local addonName, ns = ...
local A = ns.Assert
-- Isolated fake WoW host for adapter tests. Unexpected globals are errors; protected operations
-- (secure attributes, click registration, override bindings) THROW when called in combat, so a
-- test fails if the addon ever attempts them during lockdown. No real game API is modelled
-- beyond what these tests assert; passing here proves lifecycle logic, not client behavior.
local SECRET = setmetatable({}, {__tostring=function() error("secret printed") end,
    __concat=function() error("secret concatenated") end, __lt=function() error("secret compared") end,
    __le=function() error("secret compared") end, __index=function() error("secret indexed") end})
ns.SECRET = SECRET
local noop = function() end
function ns.host(options)
    options = options or {}
    local h = {frames={}, messages={}, combat=false, time=100, overrides={}, ordinary={},
        cursor={}, keyDown=true, items={}, spells={}, requests={}, timers={}, money=5000,
        unknownEvents=options.unknownEvents or {}, protectedCalls=0, setBindingCalls=0, cleared=0}
    local env = {type=type,pairs=pairs,ipairs=ipairs,tostring=tostring,tonumber=tonumber,select=select,
        math=math,string=string,table=table,setmetatable=setmetatable,pcall=pcall,unpack=unpack,next=next,
        error=error,rawequal=rawequal,
        print=function(msg) h.messages[#h.messages+1]=msg end,
        SlashCmdList={}, StreonorDockCharDB=options.saved, StreonorDockDB=options.db}
    h.env = env
    local function protected(name)
        if h.combat then error("ADDON_ACTION_BLOCKED " .. name .. " in combat") end
        h.protectedCalls = h.protectedCalls + 1
    end
    local function object(kind, name, parent, template)
        local o = {kind=kind, name=name, parent=parent, template=template, scripts={}, attrs={},
            points={}, shown=true, events={}}
        o.secure = template=="SecureActionButtonTemplate"
        local methods = {}
        function methods:GetName() return self.name end
        function methods:SetScript(which, fn) self.scripts[which]=fn end
        function methods:GetScript(which) return self.scripts[which] end
        function methods:RegisterEvent(event)
            if h.unknownEvents[event] then error("Attempt to register unknown event " .. event) end
            self.events[event]=true
        end
        function methods:SetAttribute(key, value)
            if self.secure then protected("SetAttribute") end
            self.attrs[key]=value
        end
        function methods:GetAttribute(key) return self.attrs[key] end
        function methods:RegisterForClicks(...)
            if self.secure then protected("RegisterForClicks") end
            self.clicks={...}
        end
        function methods:SetPoint(...) self.points[#self.points+1]={...} end
        function methods:ClearAllPoints() self.points={} end
        function methods:GetPoint() local p=self.points[1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
        function methods:Show() if not self.shown then self.shown=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end end
        function methods:Hide() if self.shown then self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end end
        function methods:IsShown() return self.shown end
        function methods:SetText(text) self.text=text end
        function methods:GetText() return self.text end
        function methods:SetTexture(texture) self.texture=texture end
        function methods:SetCooldown(start, duration) self.cd={start, duration} end
        function methods:Clear() self.cd=nil end
        function methods:GetFrameLevel() return 1 end
        function methods:CreateTexture() return object("Texture") end
        function methods:CreateFontString() return object("FontString") end
        function methods:IsOwned(owner) return self.owner==owner end
        function methods:SetOwner(owner) self.owner=owner end
        return setmetatable(o, {__index=function(_, key) return methods[key] or noop end})
    end
    h.object = object
    env.CreateFrame = function(kind, name, parent, template)
        if template=="SecureActionButtonTemplate" then protected("CreateFrame secure") end
        local o = object(kind, name, parent, template)
        h.frames[#h.frames+1] = o
        return o
    end
    env.UIParent = object("Frame", "UIParent")
    env.GameTooltip = object("GameTooltip", "GameTooltip")
    env.InCombatLockdown = function() return h.combat end
    env.issecretvalue = function(v) return rawequal(v, SECRET) end
    env.GetTime = function() return h.time end
    env.GetServerTime = function() return 1000000 + math.floor(h.time) end
    env.GetCVarBool = function(name) if name=="ActionButtonUseKeyDown" then return h.keyDown end end
    env.GetMoney = function() return h.money end
    env.GetCursorInfo = function() return unpack(h.cursor) end
    env.ClearCursor = function() h.cursor={} end
    env.SetOverrideBindingClick = function(owner, priority, key, button, mouse)
        protected("SetOverrideBindingClick")
        h.overrides[key] = "CLICK " .. button .. ":" .. (mouse or "LeftButton")
        h.overrideOwner = owner
    end
    env.ClearOverrideBindings = function() protected("ClearOverrideBindings"); h.overrides={}; h.cleared=h.cleared+1 end
    env.GetBindingAction = function(key, checkOverride)
        if checkOverride and h.overrides[key] then return h.overrides[key] end
        return h.ordinary[key] or ""
    end
    env.SetBinding = function() h.setBindingCalls=h.setBindingCalls+1; error("SetBinding must never be used") end
    env.SaveBindings = function() h.setBindingCalls=h.setBindingCalls+1; error("SaveBindings must never be used") end
    env.C_Spell = {
        GetSpellInfo=function(id) local s=h.spells[id]; if s and s.cached then return {name=s.name, iconID=s.icon} end end,
        RequestLoadSpellData=function(id) h.requests[#h.requests+1]="spell:" .. id end,
    }
    env.C_Item = {
        GetItemIconByID=function(id) local i=h.items[id]; return i and i.icon end,
        GetItemNameByID=function(id) local i=h.items[id]; return i and i.name end,
        GetItemCount=function(id) local i=h.items[id]; return i and i.count or 0 end,
        GetItemCooldown=function(id)
            local i=h.items[id]; local cd=i and i.cd or {0,0,true}
            return cd[1], cd[2], cd[3]
        end,
        RequestLoadItemDataByID=function(id) h.requests[#h.requests+1]="item:" .. id end,
    }
    env.C_Container = {GetContainerNumFreeSlots=function(bag) return bag==0 and 7 or 2, 0 end}
    env.C_Timer = {After=function(delay, fn) h.timers[#h.timers+1]={delay=delay, fn=fn} end,
        NewTimer=function(delay, fn) local t={delay=delay, fn=fn}; function t:Cancel() self.cancelled=true end
            h.timers[#h.timers+1]=t; return t end}
    for k, v in pairs(options.env or {}) do env[k]=v end
    for _, k in ipairs(options.remove or {}) do env[k]=nil end
    env._G = env
    local allowed = {StreonorDockDB=true, StreonorDockCharDB=true, WOW_PROJECT_ID=true, GetBuildInfo=true,
        GetSpellBaseCooldown=true, NUM_BAG_SLOTS=true, C_SpellBook=true, Enum=true,
        SetOverrideBindingClick=true, ClearOverrideBindings=true, GetBindingAction=true, issecretvalue=true,
        C_Spell=true, C_Item=true, C_Container=true, C_Timer=true, GetCVarBool=true, GetServerTime=true,
        GetTime=true, GetMoney=true, GetCursorInfo=true, ClearCursor=true, GameTooltip=true}
    setmetatable(env, {__index=function(_, key)
        if not allowed[key] then error("unexpected global " .. tostring(key), 2) end
    end})
    h.ns = {}
    for _, name in ipairs({"Core","CooldownData","Cooldown","Panel","Secure","Export","Init"}) do
        local chunk, err = loadfile("src/StreonorDock/" .. name .. ".lua")
        A.equal(type(chunk), "function", err or name)
        setfenv(chunk, env); chunk(addonName, h.ns)
    end
    h.eventFrame = h.frames[1]
    function h.event(name, ...) h.eventFrame.scripts.OnEvent(h.eventFrame, name, ...) end
    function h.slash(text) env.SlashCmdList.STREONORDOCK(text) end
    function h.button(i) return h.named("StreonorDockSlot" .. i) end
    function h.named(name) for _, f in ipairs(h.frames) do if f.name==name then return f end end end
    function h.editor(area, index) for _, f in ipairs(h.frames) do if f.area==area and f.index==index then return f end end end
    function h.login() h.event("ADDON_LOADED", addonName); h.event("PLAYER_LOGIN") end
    function h.said(pattern)
        for _, m in ipairs(h.messages) do if string.find(m, pattern, 1, true) then return true end end
        return false
    end
    function h.runTimers() local list=h.timers; h.timers={}; for _, t in ipairs(list) do if not t.cancelled then t.fn() end end end
    return h
end
function ns.copy(value)
    if type(value)~="table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k]=ns.copy(v) end
    return out
end
