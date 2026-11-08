local addonName, ns = ...
local A=ns.Assert
local host, SECRET = ns.host, ns.SECRET
local function fixture()
    return {
        {isHeader=true, name="Misc", isHeaderExpanded=false},
        {currencyID=1901, name="Honor", iconFileID=1005, quantity=250, maxQuantity=0, discovered=true},
        {currencyID=1602, name="Conquest", iconFileID=1006, quantity=0, maxQuantity=1800, discovered=true},
        {currencyID=999, name="NeverHad", iconFileID=1007, quantity=0, discovered=false},
        {isHeader=true, name="Other", isHeaderExpanded=true},
        {currencyID=2000, name="Token", iconFileID=1008, quantity=7, discovered=true},
    }
end
local function rows(h)
    local out = {}
    for _, f in ipairs(h.frames) do if rawget(f, "choice")~=nil and f.shown then out[#out+1]=f end end
    return out
end
local function labels(h)
    local out = {}
    for _, r in ipairs(rows(h)) do out[#out+1]=r.text.text end
    return out
end
local function click(h, index)
    local b = h.editor("readouts", index)
    b.scripts.OnClick(b, "LeftButton")
end
local function choose(h, label)
    for _, r in ipairs(rows(h)) do
        if string.find(r.text.text, label, 1, true) then r.scripts.OnClick(r); return true end
    end
    return false
end

A.test("core: readouts accept money and currency, keys never do; bad ids recover to empty",function()
    local Core = host().ns.Core
    A.equal(Core.formatMoney(123456), "12g 34s 56c")
    A.equal(Core.formatMoney(0), "0c"); A.equal(Core.formatMoney(10000), "1g"); A.equal(Core.formatMoney(-1), "?")
    local state = Core.recover(nil, "p")
    local s2, ok = Core.assign(state, "readouts", 1, {kind="currency", currencyID=1901}, false)
    A.equal(ok, true); A.deep(s2.pages[1].readouts[1], {kind="currency", currencyID=1901})
    local s3, ok3 = Core.assign(s2, "readouts", 2, {kind="money"}, false)
    A.equal(ok3, true); A.deep(s3.pages[1].readouts[2], {kind="money"})
    local _, okKey, why = Core.assign(s3, "slots", 1, {kind="currency", currencyID=1901}, false)
    A.equal(okKey, false); A.equal(why, "slot")
    local _, okBad = Core.assign(s3, "readouts", 1, {kind="currency", currencyID=-3}, false)
    A.equal(okBad, false)
    local rec = Core.recover({pages={{readouts={{kind="currency", currencyID="x"}, {kind="money"}, {kind="currency", currencyID=5}}}}}, "p")
    A.deep(rec.pages[1].readouts, {{kind="empty"}, {kind="money"}, {kind="currency", currencyID=5}})
end)

A.test("picker lists Empty, Money and available currencies only; restores collapsed headers",function()
    local h = host({currencies=fixture()})
    h.login(); click(h, 1)
    A.deep(labels(h), {"Empty", "Money (gold)", "Honor  (250)", "Conquest  (0)", "Token  (7)"})
    A.equal(h.currencies[1].isHeaderExpanded, false); A.equal(h.currencies[5].isHeaderExpanded, true)
    A.equal(#h.expandCalls, 2)
end)

A.test("picking Honor and Money assigns, persists per character and exports exact values",function()
    local h = host({currencies=fixture()})
    h.login(); click(h, 1)
    A.equal(choose(h, "Honor"), true)
    A.deep(h.ns.state.pages[1].readouts[1], {kind="currency", currencyID=1901})
    click(h, 2); A.equal(choose(h, "Money"), true)
    A.deep(h.env.StreonorDockCharDB.pages[1].readouts[2], {kind="money"})
    local e = h.env.StreonorDockDB.export
    A.deep(e.readouts[1], {kind="currency", currencyID=1901, name="Honor", iconFileID=1005, quantity=250})
    A.deep(e.readouts[2], {kind="money", copper=5000})
    A.equal(h.editor("readouts",1).count.text, "250"); A.equal(h.editor("readouts",1).icon.texture, 1005)
    A.equal(h.named("StreonorDockPicker").shown, false)
end)

A.test("max quantity exported; unknown currency exported without invented values; Empty clears",function()
    local h = host({currencies=fixture()})
    h.login(); h.ns.Edit("readouts", 1, {kind="currency", currencyID=1602}); h.ns.Edit("readouts", 2, {kind="currency", currencyID=31337})
    local e = h.env.StreonorDockDB.export
    A.deep(e.readouts[1], {kind="currency", currencyID=1602, name="Conquest", iconFileID=1006, quantity=0, maxQuantity=1800})
    A.deep(e.readouts[2], {kind="currency", currencyID=31337})
    click(h, 1); A.equal(choose(h, "Empty"), true)
    A.deep(h.env.StreonorDockDB.export.readouts[1], {kind="empty"})
end)

A.test("events update the export through the debounce; panel readouts refresh immediately",function()
    local h = host({currencies=fixture()})
    h.login(); h.ns.Edit("readouts", 1, {kind="currency", currencyID=1901}); h.ns.Edit("readouts", 2, {kind="money"})
    h.currencies[2].quantity = 300; h.money = 29999
    h.event("CURRENCY_DISPLAY_UPDATE"); h.event("PLAYER_MONEY")
    A.equal(h.editor("readouts",1).count.text, "300"); A.equal(h.editor("readouts",2).count.text, "2g")
    h.runTimers()
    local e = h.env.StreonorDockDB.export
    A.equal(e.readouts[1].quantity, 300); A.equal(e.readouts[2].copper, 29999)
end)

A.test("logout teardown and implausible zero reads do not export zero currency or money",function()
    local h = host({currencies=fixture()})
    h.login(); h.ns.Edit("readouts", 1, {kind="currency", currencyID=1901}); h.ns.Edit("readouts", 2, {kind="money"})
    h.event("PLAYER_LEAVING_WORLD")
    h.currencies[2].quantity = 0; h.money = 0
    h.env.C_Container.GetContainerNumFreeSlots = function() return 0 end
    h.event("PLAYER_LEAVING_WORLD"); h.event("PLAYER_MONEY"); h.event("CURRENCY_DISPLAY_UPDATE"); h.runTimers()
    h.event("PLAYER_LOGOUT")
    local e = h.env.StreonorDockDB.export
    A.equal(e.readouts[1].quantity, 250); A.equal(e.readouts[2].copper, 5000)
    local h2 = host({currencies=fixture()})
    h2.login(); h2.ns.Edit("readouts", 1, {kind="currency", currencyID=1901}); h2.ns.Edit("readouts", 2, {kind="money"})
    h2.currencies[2].quantity = 0; h2.money = 0
    h2.env.C_Container.GetContainerNumFreeSlots = function() return 0 end
    h2.event("CURRENCY_DISPLAY_UPDATE"); h2.runTimers()
    local e2 = h2.env.StreonorDockDB.export
    A.equal(e2.readouts[1].quantity, 250); A.equal(e2.readouts[2].copper, 5000); A.equal(e2.readouts[1].name, "Honor")
end)

A.test("combat: picker refuses to open, closes when combat starts, no edit is made",function()
    local h = host({currencies=fixture()})
    h.login(); h.combat = true
    click(h, 1)
    A.equal(h.named("StreonorDockPicker"), nil); A.equal(h.said("editing unavailable in combat"), true)
    h.combat = false; click(h, 1); A.equal(#rows(h) > 0, true)
    h.combat = true; h.event("PLAYER_REGEN_DISABLED")
    A.equal(h.named("StreonorDockPicker").shown, false)
    h.ns.Edit("readouts", 1, {kind="money"})
    A.deep(h.ns.state.pages[1].readouts[1], {kind="empty"})
end)

A.test("secret currency data is dropped; missing API degrades to Empty and Money",function()
    local h = host({currencies=fixture()})
    h.login(); h.ns.Edit("readouts", 1, {kind="currency", currencyID=1901})
    h.env.C_CurrencyInfo.GetCurrencyInfo = function() return {name=SECRET, iconFileID=SECRET, quantity=SECRET, maxQuantity=5} end
    h.event("CURRENCY_DISPLAY_UPDATE"); h.runTimers()
    A.deep(h.env.StreonorDockDB.export.readouts[1], {kind="currency", currencyID=1901, maxQuantity=5})
    local h2 = host({remove={"C_CurrencyInfo"}})
    h2.login(); click(h2, 1)
    A.deep(labels(h2), {"Empty", "Money (gold)"})
    h2.slash("probe"); A.equal(h2.said("C_CurrencyInfo.GetCurrencyListInfo: unavailable"), true)
end)

A.test("probe reports currency API and the number of pickable currencies",function()
    local h = host({currencies=fixture()})
    h.login(); h.slash("probe")
    A.equal(h.said("C_CurrencyInfo.GetCurrencyListInfo: available"), true)
    A.equal(h.said("currencies available to pick now: 3"), true)
end)
