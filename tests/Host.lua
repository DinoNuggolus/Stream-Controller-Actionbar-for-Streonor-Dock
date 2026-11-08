local addonName, ns = ...
local A = ns.Assert
-- Isolated fake WoW host for adapter tests. Unexpected globals are errors. Protected operations
-- attempted in combat (secure frame attributes/clicks/scripts/show/hide/points, secure frame
-- creation, override bindings) are BLOCKED like the client does: ignored and COUNTED in
-- h.blocked. They do not throw, so the addon's own pcall/ns.Safe cannot hide them. run.lua fails
-- any test whose hosts recorded a blocked attempt or printed an addon "internal error" (unless the
-- test explicitly allows it). No real game API is modelled beyond what the tests assert;
-- passing proves lifecycle logic only, not client behavior.
ns.hosts = {}
local SECRET = setmetatable({}, {__tostring=function() error("secret printed") end,
    __concat=function() error("secret concatenated") end, __lt=function() error("secret compared") end,
    __le=function() error("secret compared") end, __index=function() error("secret indexed") end})
ns.SECRET = SECRET
local noop = function() end
function ns.host(options)
    options = options or {}
    local h = {frames={}, messages={}, combat=false, time=100, overrides={}, ordinary={},
        cursor={}, keyDown=true, items={}, spells={}, spellCd={}, charges={}, requests={}, timers={}, 
        unknownEvents=options.unknownEvents or {}, protectedCalls=0, setBindingCalls=0, cleared=0,
        blocked=0, blockedNames={}, internalErrors=0}
    ns.hosts[#ns.hosts+1] = h
    local env = {type=type,pairs=pairs,ipairs=ipairs,tostring=tostring,tonumber=tonumber,select=select,
        math=math,string=string,table=table,setmetatable=setmetatable,pcall=pcall,unpack=unpack,next=next,
        error=error,rawequal=rawequal,assert=assert,
        print=function(msg)
            h.messages[#h.messages+1]=msg
            if string.find(tostring(msg), "internal error", 1, true) then h.internalErrors=h.internalErrors+1 end
        end,
        SlashCmdList={}, StreonorDockCharDB=options.saved, StreonorDockDB=options.db}
    h.env = env
    -- true = allowed. In combat the attempt is blocked: counted and ignored, never thrown.
    local function protected(name)
        if h.combat then
            h.blocked = h.blocked + 1
            h.blockedNames[#h.blockedNames+1] = name
            return false
        end
        h.protectedCalls = h.protectedCalls + 1
        return true
    end
    local function object(kind, name, parent, template)
        local o = {kind=kind, name=name, parent=parent, template=template, scripts={}, attrs={},
            points={}, shown=true, events={}}
        o.secure = template=="SecureActionButtonTemplate"
        if o.secure then local p = parent; while type(p)=="table" do p.hasSecureChild = true; p = p.parent end end
        local methods = {}
        function methods:GetName() return self.name end
        function methods:SetScript(which, fn)
            if (self.secure or self.hasSecureChild) and not protected("SetScript") then return end
            self.scripts[which]=fn
        end
        function methods:GetScript(which) return self.scripts[which] end
        function methods:UnregisterEvent(event) self.events[event] = nil end
        function methods:RegisterEvent(event)
            if h.unknownEvents[event] then error("Attempt to register unknown event " .. event) end
            self.events[event]=true
        end
        function methods:SetAttribute(key, value)
            if (self.secure or self.hasSecureChild) and not protected("SetAttribute") then return end
            self.attrs[key]=value
        end
        function methods:GetAttribute(key) return self.attrs[key] end
        function methods:RegisterForClicks(...)
            if (self.secure or self.hasSecureChild) and not protected("RegisterForClicks") then return end
            self.clicks={...}
        end
        function methods:SetPoint(...)
            if (self.secure or self.hasSecureChild) and not protected("SetPoint") then return end
            self.points[#self.points+1]={...}
        end
        function methods:ClearAllPoints()
            if (self.secure or self.hasSecureChild) and not protected("ClearAllPoints") then return end
            self.points={}
        end
        function methods:GetPoint() local p=self.points[1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
        function methods:Show()
            if (self.secure or self.hasSecureChild) and not protected("Show") then return end
            if not self.shown then self.shown=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end end
        function methods:Hide()
            if (self.secure or self.hasSecureChild) and not protected("Hide") then return end
            if self.shown then self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end end
        function methods:IsShown() return self.shown end
        function methods:SetText(text) self.text=text end
        function methods:GetText() return self.text end
        function methods:SetTexture(texture) self.texture=texture end
        function methods:SetCooldown(start, duration) self.cd={start, duration} end
        function methods:Clear() self.cd=nil end
        function methods:SetSize(w, h) if (self.secure or self.hasSecureChild) and not protected("SetSize") then return end; self.w, self.h = w, h end
        function methods:SetWidth(w) if (self.secure or self.hasSecureChild) and not protected("SetWidth") then return end; self.w = w end
        function methods:SetHeight(hh) if (self.secure or self.hasSecureChild) and not protected("SetHeight") then return end; self.h = hh end
        function methods:GetWidth() return self.w or 0 end
        function methods:GetHeight() return self.h or 0 end
        function methods:SetScale(v) if (self.secure or self.hasSecureChild) and not protected("SetScale") then return end; self.scale = v end
        function methods:GetScale() return self.scale or 1 end
        function methods:GetEffectiveScale() return self.scale or 1 end
        function methods:SetAlpha(v) self.alpha = v end
        function methods:GetAlpha() return self.alpha or 1 end
        function methods:SetShown(v) if v then self:Show() else self:Hide() end end
        function methods:HookScript(which, fn) self.hooks = self.hooks or {}; self.hooks[which] = self.hooks[which] or {}; table.insert(self.hooks[which], fn) end
        function methods:GetCenter() return self.cx or 0, self.cy or 0 end
        function methods:StartMoving() self.moving = true end
        function methods:StopMovingOrSizing() self.moving = false end
        function methods:SetFrameLevel(v) self.level = v end
        function methods:SetParent(p) self.parent = p end
        function methods:GetFrameLevel() return self.level or 1 end
        function methods:CreateTexture() return object("Texture") end
        function methods:CreateFontString() return object("FontString") end
        function methods:GetTexture() return self.texture end
        function methods:IsMouseOver() return h.hoverAll or h.mouseOver == self end
        function methods:IsOwned(owner) return self.owner==owner end
        function methods:SetOwner(owner) self.owner=owner end
        o.last = {}
        local recorders = {}
        return setmetatable(o, {__index=function(self, key)
            if methods[key] then return methods[key] end
            if type(key)=="string" and string.find(key, "^%u") then
                -- unmodelled widget methods are recorded: o.last.SetDesaturated = {true}
                recorders[key] = recorders[key] or function(me, ...) me.last[key] = {...} end
                return recorders[key]
            end
        end})
    end
    h.object = object
    env.CreateFrame = function(kind, name, parent, template)
        if template=="SecureActionButtonTemplate" and not protected("CreateFrame secure") then return nil end
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
    env.GetCursorInfo = function() return unpack(h.cursor) end
    env.ClearCursor = function() h.cursor={} end
    env.SetOverrideBindingClick = function(owner, priority, key, button, mouse)
        if not protected("SetOverrideBindingClick") then return end
        h.overrides[key] = "CLICK " .. button .. ":" .. (mouse or "LeftButton")
        h.overrideOwner = owner
    end
    env.ClearOverrideBindings = function()
        if not protected("ClearOverrideBindings") then return end
        h.overrides={}; h.cleared=h.cleared+1
    end
    env.GetBindingAction = function(key, checkOverride)
        if checkOverride and h.overrides[key] then return h.overrides[key] end
        return h.ordinary[key] or ""
    end
    env.SetBinding = function() h.setBindingCalls=h.setBindingCalls+1; error("SetBinding must never be used") end
    env.SaveBindings = function() h.setBindingCalls=h.setBindingCalls+1; error("SaveBindings must never be used") end
    env.C_Spell = {
        GetSpellInfo=function(id) local s=h.spells[id]; if s and s.cached then return {name=s.name, iconID=s.icon} end end,
        RequestLoadSpellData=function(id) h.requests[#h.requests+1]="spell:" .. id end,
        GetSpellCooldown=function(id) return h.spellCd[id] end,
        GetSpellCharges=function(id) return h.charges[id] end,
        GetSpellCooldownDuration=function(id) return h.spellDur and h.spellDur[id] end,
        GetSpellChargeDuration=function(id) return h.chargeDur and h.chargeDur[id] end,
    }
    env.C_Item = {
        GetItemIconByID=function(id) local i=h.items[id]; return i and i.icon end,
        GetItemNameByID=function(id) local i=h.items[id]; return i and i.name end,
        GetItemCount=function(id) local i=h.items[id]; return i and i.count or 0 end,
        GetItemCooldown=function(id)
            local i=h.items[id]; local cd=i and i.cd or {0,0,true}
            return cd[1], cd[2], cd[3]
        end,
        GetItemInfoInstant=function(id)
            local i = h.items[id]
            if i and i.class then return id, i.typeName, i.subName, "", i.icon, i.class, i.sub end
            return id
        end,
        GetItemSpell=function(id) local i = h.items[id]; if i and i.spell then return i.spell, 1000 + id end end,
        IsItemDataCachedByID=function(id) local i = h.items[id]; return i ~= nil and i.cached ~= false end,
        GetItemClassInfo=function(c) return h.classNames and h.classNames[c] end,
        GetItemSubClassInfo=function(c, s) return h.subNames and h.subNames[c .. "." .. s] end,
        RequestLoadItemDataByID=function(id) h.requests[#h.requests+1]="item:" .. id end,
    }
    h.bags = options.bags or {}   -- h.bags[bag][slot] = {itemID=, stackCount=}
    env.C_Container = {
        GetContainerNumSlots=function(bag) local b=h.bags[bag]; return b and b.size or 0 end,
        GetContainerItemInfo=function(bag, slot) local b=h.bags[bag]; local i=b and b[slot]; if i then return {itemID=i.itemID, stackCount=i.stackCount} end end,
    }
    env.C_Timer = {After=function(delay, fn) h.timers[#h.timers+1]={delay=delay, fn=fn} end,
        NewTimer=function(delay, fn) local t={delay=delay, fn=fn}; function t:Cancel() self.cancelled=true end
            h.timers[#h.timers+1]=t; return t end}
    for k, v in pairs(options.env or {}) do env[k]=v end
    for _, k in ipairs(options.remove or {}) do env[k]=nil end
    env._G = env
    -- Real Blizzard aliases (libraries use them); the addon itself does not.
    env.tinsert, env.tremove, env.wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k]=nil end return t end
    env.format, env.strmatch, env.strfind, env.strsub, env.strlen = string.format, string.match, string.find, string.sub, string.len
    env.strlower, env.strupper, env.gsub, env.floor, env.ceil, env.max, env.min = string.lower, string.upper, string.gsub, math.floor, math.ceil, math.max, math.min
    env.strlenutf8 = function(str) return #str end
    env.getmetatable, env.rawget, env.rawset, env.xpcall = getmetatable, rawget, rawset, xpcall
    env.geterrorhandler = function() return function(e) error(e, 0) end end
    env.date, env.time, env.os = nil, nil, nil
    env.UnitFactionGroup = function() return "Neutral" end
    env.GetLocale = function() return "enUS" end
    env.UnitClass = function() return "Druid", "DRUID" end
    env.UnitRace = function() return "Night Elf", "NightElf" end
    env.GetRealmName = function() return "TestRealm" end
    env.UnitNameUnmodified = function() return options.name or "Tester" end
    env.GetCurrentRegionName = function() return "US" end
    env.GetCurrentRegion = function() return 1 end
    h.state = {}
    local function st(key, default) local v = h.state[key]; if v == nil then return default end; return v end
    env.UnitExists = function(u) return st("exists", false) end
    env.UnitCanAttack = function() return st("hostile", false) end
    env.IsInGroup = function() return st("group", false) end
    env.IsInRaid = function() return st("raid", false) end
    env.IsInInstance = function() return st("instance", false), st("instanceType", "none") end
    env.UnitIsPVP = function() return st("pvpflag", false) end
    env.IsMounted = function() return st("mounted", false) end
    env.IsResting = function() return st("resting", false) end
    env.IsFlying = function() return st("flying", false) end
    env.UnitCastingInfo = function() return st("casting", nil) end
    env.UnitChannelInfo = function() return st("channel", nil) end
    env.UnitHealth = function() return st("hp", 100) end
    env.UnitHealthMax = function() return st("hpmax", 100) end
    env.IsShiftKeyDown = function() return st("shift", false) end
    env.IsControlKeyDown = function() return st("ctrl", false) end
    env.IsAltKeyDown = function() return st("alt", false) end
    env.securecallfunction = function(fn, ...) return fn(...) end
    env.ReloadUI = function() h.reloaded = (h.reloaded or 0) + 1 end
    env.StaticPopupDialogs = {}
    env.UISpecialFrames = {}
    env.GetCursorPosition = function() return 0, 0 end
    env.StaticPopup_Hide = function(which) h.popupHidden = (h.popupHidden or 0) + 1 end
    env.StaticPopup_Show = function(which, ...) h.popups[#h.popups+1] = {which=which, args={...}}; return {} end
    h.popups = {}
    local allowed = {StreonorDockDB=true, StreonorDockCharDB=true, WOW_PROJECT_ID=true, GetBuildInfo=true,
        GetSpellBaseCooldown=true, NUM_BAG_SLOTS=true, C_SpellBook=true, Enum=true,
        SetOverrideBindingClick=true, ClearOverrideBindings=true, GetBindingAction=true, issecretvalue=true,
        C_Spell=true, C_Item=true, C_Container=true, C_Timer=true, GetCVarBool=true, GetServerTime=true,
        GetTime=true, GetMoney=true, GetCursorInfo=true, ClearCursor=true, GameTooltip=true,
        LoggingChat=true, LoggingCombat=true, C_ChatInfo=true, C_CurrencyInfo=true, LibStub=true, UnitFactionGroup=true, GetLocale=true, UnitClass=true,
        UnitRace=true, GetRealmName=true, UnitNameUnmodified=true, GetCurrentRegionName=true, GetCurrentRegion=true,
        strlenutf8=true, RegionalUniqueNamesEnabled=true, StaticPopupDialogs=true, StaticPopup_Show=true,
        MenuUtil=true, Settings=true, ReloadUI=true, _G=true, LibCustomGlow=true, UISpecialFrames=true,
        SlashCmdList=true, geterrorhandler=true, xpcall=true, getmetatable=true, rawget=true, rawset=true,
        C_Texture=true, CloseMenus=true, L_Create_UIDropDownMenu=true}
    setmetatable(env, {__index=function(_, key)
        if not allowed[key] then error("unexpected global " .. tostring(key), 2) end
    end})
    h.ns = {}
    -- Load exactly what the TOC lists, in order. Libs: a whitelist of the pure-Lua libraries is
    -- loaded with a lenient environment (they read optional globals); everything else is strict.
    local strictIndex = getmetatable(env).__index
    local libWhitelist = {["LibStub.lua"]=true, ["CallbackHandler-1.0.lua"]=true, ["AceDB-3.0.lua"]=true,
        ["AceConfigRegistry-3.0.lua"]=true, ["AceDBOptions-3.0.lua"]=true}
    local function runLua(path, lenient)
        local chunk, err = loadfile(path)
        A.equal(type(chunk), "function", err or path)
        setfenv(chunk, env)
        if lenient then getmetatable(env).__index = function() return nil end end
        local ok, e = pcall(chunk, addonName, h.ns)
        getmetatable(env).__index = strictIndex
        if not ok then error(path .. ": " .. tostring(e), 0) end
    end
    local function loadXml(path, dir)
        local xf = assert(io.open(path, "rb"), "cannot open " .. path); local xml = xf:read("*a"); xf:close()
        xml = string.gsub(xml, "<!%-%-.-%-%->", "")
        for kind, file in string.gmatch(xml, '<(%a+)%s+file%s*=%s*"([^"]+)"') do
            file = string.gsub(file, "\\", "/")
            if kind == "Script" and libWhitelist[string.match(file, "[^/]+$")] then runLua(dir .. file, true)
            elseif kind == "Include" then
                local sub = dir .. file
                loadXml(sub, string.match(sub, "^(.*/)") or "")
            end
        end
    end
    local toc = io.open("src/StreonorDock/StreonorDock.toc", "rb"); local text = toc:read("*a"); toc:close()
    for line in string.gmatch(text, "[^%c]+") do
        local path = string.gsub(line, "\\", "/")
        if string.match(line, "%.lua$") then runLua("src/StreonorDock/" .. path)
        elseif string.match(line, "^Libs.*%.xml$") then loadXml("src/StreonorDock/" .. path, "src/StreonorDock/Libs/")
        elseif string.match(line, "%.xml$") then
            local xf = io.open("src/StreonorDock/" .. line, "rb"); local xml = xf:read("*a"); xf:close()
            for name, inherits in string.gmatch(xml, '<Button name="([%w_]+)" inherits="([%w_]+)"/>') do
                local o = object("Button", name, nil, inherits)
                o.xml = true
                h.frames[#h.frames+1] = o
                rawset(env, name, o)
            end
        end
    end
    for _, f in ipairs(h.frames) do if f.scripts.OnEvent and f.events.ADDON_LOADED then h.eventFrame = f end end
    function h.created() local n=0; for _, f in ipairs(h.frames) do if not rawget(f,"xml") then n=n+1 end end; return n end
    function h.event(name, ...) h.eventFrame.scripts.OnEvent(h.eventFrame, name, ...) end
    function h.slash(text) env.SlashCmdList.STREONORDOCK(text) end
    function h.button(i) return h.named("StreonorDockSlot" .. i) end
    function h.named(name) for _, f in ipairs(h.frames) do if f.name==name then return f end end end
    -- Secure-click simulator. Default: the client honours RegisterForClicks and the template acts only on
    -- the edge named by useOnKeyDown. h.ignoreRegistration: binding delivers BOTH edges regardless of
    -- registration. h.templateIgnoresEdge: the template acts on any edge it receives (worst case).
    h.uses = {}
    function h.click(i, down)
        local b = h.button(i)
        local edge = down and "AnyDown" or "AnyUp"
        local registered = false
        for _, c in ipairs(b.clicks or {}) do if c==edge then registered = true end end
        if not registered and not h.ignoreRegistration then return false end
        if b.scripts.PreClick then b.scripts.PreClick(b, "LeftButton", down) end
        local kind = b.attrs["*type1"]
        if kind and (h.templateIgnoresEdge or (b.attrs.useOnKeyDown==true)==down) then
            h.uses[#h.uses+1] = b.attrs["*" .. kind .. "1"]
        end
        if b.scripts.PostClick then b.scripts.PostClick(b, "LeftButton", down) end
        return true
    end
    function h.login() h.event("ADDON_LOADED", addonName); h.event("PLAYER_LOGIN") end
    function h.said(pattern)
        for _, m in ipairs(h.messages) do if string.find(m, pattern, 1, true) then return true end end
        return false
    end
    -- Fires a frame script and its hooks (simulated user input).
    function h.fire(frame, which, ...)
        if frame.scripts[which] then frame.scripts[which](frame, ...) end
        for _, fn in ipairs(frame.hooks and frame.hooks[which] or {}) do fn(frame, ...) end
    end
    function h.bar(i) return h.named("StreonorDockBarButton" .. i) end
    function h.runTimers() local list=h.timers; h.timers={}; for _, t in ipairs(list) do if not t.cancelled then t.fn() end end end
    return h
end
function ns.copy(value)
    if type(value)~="table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k]=ns.copy(v) end
    return out
end
