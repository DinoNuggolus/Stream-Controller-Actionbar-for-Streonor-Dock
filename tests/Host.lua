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
        cursor={}, keyDown=true, items={}, spells={}, spellCd={}, charges={}, requests={}, timers={}, money=5000,
        unknownEvents=options.unknownEvents or {}, protectedCalls=0, setBindingCalls=0, cleared=0,
        blocked=0, blockedNames={}, internalErrors=0}
    ns.hosts[#ns.hosts+1] = h
    local env = {type=type,pairs=pairs,ipairs=ipairs,tostring=tostring,tonumber=tonumber,select=select,
        math=math,string=string,table=table,setmetatable=setmetatable,pcall=pcall,unpack=unpack,next=next,
        error=error,rawequal=rawequal,
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
        local methods = {}
        function methods:GetName() return self.name end
        function methods:SetScript(which, fn)
            if self.secure and not protected("SetScript") then return end
            self.scripts[which]=fn
        end
        function methods:GetScript(which) return self.scripts[which] end
        function methods:RegisterEvent(event)
            if h.unknownEvents[event] then error("Attempt to register unknown event " .. event) end
            self.events[event]=true
        end
        function methods:SetAttribute(key, value)
            if self.secure and not protected("SetAttribute") then return end
            self.attrs[key]=value
        end
        function methods:GetAttribute(key) return self.attrs[key] end
        function methods:RegisterForClicks(...)
            if self.secure and not protected("RegisterForClicks") then return end
            self.clicks={...}
        end
        function methods:SetPoint(...)
            if self.secure and not protected("SetPoint") then return end
            self.points[#self.points+1]={...}
        end
        function methods:ClearAllPoints()
            if self.secure and not protected("ClearAllPoints") then return end
            self.points={}
        end
        function methods:GetPoint() local p=self.points[1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
        function methods:Show()
            if self.secure and not protected("Show") then return end
            if not self.shown then self.shown=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end end
        function methods:Hide()
            if self.secure and not protected("Hide") then return end
            if self.shown then self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end end
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
        return setmetatable(o, {__index=function(_, key) return methods[key] or ((type(key)=="string" and string.find(key, "^%u")) and noop or nil) end})
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
    env.GetMoney = function() return h.money end
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
    -- Currency list model: h.currencies = array of CurrencyInfo-like rows (headers collapse their
    -- children; the fake honours ExpandCurrencyList so tests can prove the collapse state is restored).
    h.currencies = options.currencies or {}
    h.expandCalls = {}
    local function visible()
        local rows, hidden = {}, false
        for i, c in ipairs(h.currencies) do
            if c.isHeader then rows[#rows+1] = c; hidden = c.isHeaderExpanded == false
            elseif not hidden then rows[#rows+1] = c end
        end
        return rows
    end
    env.C_CurrencyInfo = {
        GetCurrencyListSize = function() return #visible() end,
        GetCurrencyListInfo = function(i) local c = visible()[i]; if c then return ns.copy(c) end end,
        GetCurrencyInfo = function(id) for _, c in ipairs(h.currencies) do if c.currencyID == id and not c.isHeader then return ns.copy(c) end end end,
        ExpandCurrencyList = function(i, expand)
            h.expandCalls[#h.expandCalls+1] = {i, expand}
            local c = visible()[i]; if c then c.isHeaderExpanded = expand end
        end,
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
        GetTime=true, GetMoney=true, GetCursorInfo=true, ClearCursor=true, GameTooltip=true,
        LoggingChat=true, LoggingCombat=true, C_ChatInfo=true, C_CurrencyInfo=true}
    setmetatable(env, {__index=function(_, key)
        if not allowed[key] then error("unexpected global " .. tostring(key), 2) end
    end})
    h.ns = {}
    -- Load exactly what the TOC lists, in order. XML files: model the declared secure buttons
    -- (created by the client at load time, even in combat).
    local toc = io.open("src/StreonorDock/StreonorDock.toc", "rb"); local text = toc:read("*a"); toc:close()
    for line in string.gmatch(text, "[^\r\n]+") do
        if string.match(line, "%.lua$") then
            local chunk, err = loadfile("src/StreonorDock/" .. line)
            A.equal(type(chunk), "function", err or line)
            setfenv(chunk, env); chunk(addonName, h.ns)
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
    for _, f in ipairs(h.frames) do if f.scripts.OnEvent then h.eventFrame = f end end
    function h.created() local n=0; for _, f in ipairs(h.frames) do if not rawget(f,"xml") then n=n+1 end end; return n end
    function h.event(name, ...) h.eventFrame.scripts.OnEvent(h.eventFrame, name, ...) end
    function h.slash(text) env.SlashCmdList.STREONORDOCK(text) end
    function h.button(i) return h.named("StreonorDockSlot" .. i) end
    function h.named(name) for _, f in ipairs(h.frames) do if f.name==name then return f end end end
    function h.editor(area, index) for _, f in ipairs(h.frames) do if f.area==area and f.index==index then return f end end end
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
    function h.runTimers() local list=h.timers; h.timers={}; for _, t in ipairs(list) do if not t.cancelled then t.fn() end end end
    return h
end
function ns.copy(value)
    if type(value)~="table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k]=ns.copy(v) end
    return out
end
