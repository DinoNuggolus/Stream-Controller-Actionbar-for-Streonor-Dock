local addonName, ns = ...
local A = ns.Assert
local function host(options) return ns.host(options) end

-- Fake spellbook: lines = {{name=, specID=, items={{id=, name=, rank=, low=, passive=, known=}}}}
local function world(lines)
    local flat, infos = {}, {}
    for i, line in ipairs(lines) do
        line.offset = #flat
        for _, it in ipairs(line.items) do flat[#flat + 1] = it end
    end
    local known = {}
    for _, it in ipairs(flat) do if it.known ~= false then known[it.id] = true end end
    local book = {
        GetNumSpellBookSkillLines = function() return #lines end,
        GetSpellBookSkillLineInfo = function(i)
            local l = lines[i]
            return {name = l.name, itemIndexOffset = l.offset, numSpellBookItems = #l.items, iconID = 1, specID = l.specID}
        end,
        GetSpellBookItemInfo = function(index)
            local it = flat[index]
            if not it then return nil end
            return {itemType = 1, spellID = it.id, name = it.name, subName = it.rank, iconID = 100 + it.id, isPassive = it.passive}
        end,
        IsSpellKnown = function(id) return known[id] == true end,
        IsSpellBookItemLowRank = function(index) return flat[index] and flat[index].low == true end,
        FindSpellBookSlotForSpell = function(id) for i, it in ipairs(flat) do if it.id == id then return i, 0 end end end,
        GetSpellBookItemType = function(slot) local it = flat[slot]; if it then return 1, it.id end end,
    }
    return {C_SpellBook = book, Enum = {SpellBookSpellBank = {Player = 0, Pet = 1}, SpellBookItemType = {Spell = 1}, BagIndex = {ReagentBag = 5}},
        NUM_BAG_SLOTS = 4}, known
end
local druid = {
    {name = "General", items = {{id = 1, name = "Attack"}, {id = 2, name = "Zeal", passive = true}}},
    {name = "Restoration", specID = 105, items = {
        {id = 774, name = "Rejuvenation", rank = "Rank 3"},
        {id = 773, name = "Rejuvenation", rank = "Rank 2", low = true},
        {id = 5185, name = "Healing Touch", rank = "Rank 1"},
        {id = 999, name = "Future Spell", known = false}}},
    {name = "Balance", specID = 102, items = {}},
}
local function started(options)
    options = options or {}
    local env, known = world(options.lines or druid)
    local h = host({env = env, bags = options.bags})
    h.known = known
    h.items[8] = {name = "Water", icon = 500, count = 5, class = 0, sub = 5, typeName = "Consumable", subName = "Food & Drink", spell = "Drink"}
    h.items[9] = {name = "Bandage", icon = 501, count = 3, class = 0, sub = 7, typeName = "Consumable", subName = "Bandage", spell = "First Aid"}
    h.items[10] = {name = "Ore", icon = 502, count = 2, class = 7, sub = 7, typeName = "Trade Goods", subName = "Metal & Stone"}
    h.items[11] = {name = "Mystery", icon = 503, count = 1}   -- no class data yet
    h.classNames = {[0] = "Consumable", [7] = "Trade Goods"}
    h.subNames = {["0.5"] = "Food & Drink", ["0.7"] = "Bandage", ["7.7"] = "Metal & Stone"}
    h.bags[0] = {size = 4, {itemID = 8, stackCount = 3}, {itemID = 8, stackCount = 2}, {itemID = 9, stackCount = 3}}
    h.bags[1] = {size = 2, {itemID = 10, stackCount = 2}, {itemID = 11, stackCount = 1}}
    h.login()
    return h
end
local function menuCapture(h)
    local captured = {}
    h.ns.Menu.Show = function(owner, entries) captured.owner, captured.entries = owner, entries; return true end
    return captured
end

A.test("unlock shows all fifteen buttons with overlays: + at 100% empty, 50% filled; lock hides empties", function()
    local h = host(); h.login(); local bar = h.ns.Bar
    h.ns.Edit(4, {kind = "item", id = 8})
    for i = 1, 15 do A.equal(bar.buttons[i]:IsShown(), i == 4) end
    A.equal(h.ns.Assign.Unlock(), true); A.equal(h.ns.Assign.IsActive(), true)
    for i = 1, 15 do
        local b = bar.buttons[i]
        A.equal(b:IsShown(), true, "button " .. i); A.equal(b.overlay:IsShown(), true)
        A.equal(b.overlay.plusH.alpha, i == 4 and 0.5 or 1.0); A.equal(b.overlay.plusV.alpha, i == 4 and 0.5 or 1.0)
    end
    A.equal(h.ns.Assign.Lock(), true)
    for i = 1, 15 do A.equal(bar.buttons[i]:IsShown(), i == 4); A.equal(bar.buttons[i].overlay:IsShown(), false) end
    h.ns.profile.general.alwaysShowButtons = true; h.ns.Assign.Unlock(); h.ns.Assign.Lock()
    for i = 1, 15 do A.equal(bar.buttons[i]:IsShown(), true) end
    A.equal(h.internalErrors, 0)
end)
A.test("temporary reveal when the bar is disabled: restored on lock without touching the saved setting", function()
    local h = host(); h.login(); local bar = h.ns.Bar
    h.ns.profile.general.showActionBar = false; bar.Layout()
    A.equal(bar.IsShown(), false)
    h.slash("assign"); A.equal(bar.IsShown(), true); A.equal(h.ns.Assign.IsTemporary(), true)
    A.equal(h.ns.profile.general.showActionBar, false)
    h.slash("assign"); A.equal(bar.IsShown(), false); A.equal(h.ns.profile.general.showActionBar, false)
    A.equal(#h.popups, 0)
end)
A.test("reload popup: only when something changed, exactly Reload/Cancel, no reminders", function()
    local h = host(); h.items[9] = {name = "Bandage", icon = 501, count = 1}; h.login()
    h.ns.Assign.Unlock(); h.ns.Assign.Lock(); A.equal(#h.popups, 0, "no-edit relock is silent")
    h.ns.Assign.Unlock(); h.ns.Edit(1, {kind = "item", id = 8}); h.ns.Edit(1, {kind = "empty"}); h.ns.Assign.Lock()
    A.equal(#h.popups, 0, "undo back to the baseline is silent")
    h.ns.Assign.Unlock(); h.ns.Edit(1, {kind = "item", id = 8}); h.ns.Assign.Lock()
    A.equal(#h.popups, 1); A.equal(h.popups[1].which, "STREONORDOCK_RELOAD")
    local dialog = h.env.StaticPopupDialogs.STREONORDOCK_RELOAD
    A.equal(dialog.button1, "Reload"); A.equal(dialog.button2, "Cancel"); A.equal(dialog.hideOnEscape, true)
    A.equal(dialog.button3, nil); A.equal(dialog.text, "Spells or items changed. Reload the UI now so the controller shows the new icons?")
    dialog.OnCancel()
    h.ns.Assign.Unlock(); h.ns.Assign.Lock(); A.equal(#h.popups, 1, "Cancel leaves no pending state")
    A.equal(h.ns.CurrentPage()[1].id, 8, "accepted edits remain applied")
    -- accept path
    h.ns.Assign.Unlock(); h.ns.Edit(2, {kind = "item", id = 9}); h.ns.Assign.Lock(); A.equal(#h.popups, 2)
    h.combat = true; dialog.OnAccept(); A.equal(h.reloaded, nil, "never reloads in combat"); h.combat = false
    dialog.OnAccept(); A.equal(h.reloaded, 1)
    A.deep(h.env.StreonorDockDB.export.icons[2], {iconFileID = 501}, "export regenerated before the reload")
end)
A.test("page changes during assignment count; appearance-only edits do not", function()
    local h = host(); h.login()
    h.ns.Core.setPageCount(h.ns.profile, 2)
    h.ns.Assign.Unlock(); h.ns.profile.bar.scale = 1.5; h.ns.profile.bar.backgroundOpacity = 0.3; h.ns.LayoutChanged(); h.ns.Assign.Lock()
    A.equal(#h.popups, 0)
    h.ns.Assign.Unlock(); h.slash("page next"); h.ns.Assign.Lock(); A.equal(#h.popups, 1)
    h.ns.Assign.Unlock(); h.ns.db.global.exportEnabled = false; h.ns.Assign.Lock(); A.equal(#h.popups, 2, "export switch is part of the identity")
end)
A.test("combat: unlock refused; onset pauses (drag, popup, menu), edits rejected, queued lock runs after", function()
    local h = host(); h.login()
    h.combat = true; A.equal(h.ns.Assign.Unlock(), false); A.equal(h.ns.Assign.IsActive(), false); h.combat = false
    h.ns.Assign.Unlock(); h.ns.Edit(1, {kind = "item", id = 8})
    h.combat = true; h.event("PLAYER_REGEN_DISABLED")
    A.equal(h.ns.Assign.IsPaused(), true); A.equal(h.ns.Assign.IsActive(), true)
    A.equal(h.ns.Edit(2, {kind = "item", id = 9}), false)
    A.equal(h.ns.Assign.Lock(), false)
    A.equal(h.blocked, 0)
    h.combat = false; h.event("PLAYER_REGEN_ENABLED")
    A.equal(h.ns.Assign.IsActive(), false, "explicitly queued lock executes once combat ends")
    A.equal(#h.popups, 1)
end)
A.test("escape routes through lock; escape during a drag only cancels the drag", function()
    local h = host(); h.login()
    h.ns.Assign.Unlock()
    local escape = h.named("StreonorDockAssignEscape")
    A.equal(h.env.UISpecialFrames[1], "StreonorDockAssignEscape"); A.equal(escape:IsShown(), true)
    h.ns.Edit(1, {kind = "item", id = 8})
    h.ns.Assign.OnDragStart(1); A.equal(h.ns.Assign.IsDragging(), true)
    escape:Hide(); A.equal(h.ns.Assign.IsDragging(), false); A.equal(h.ns.Assign.IsActive(), true); A.equal(escape:IsShown(), true)
    escape:Hide(); A.equal(h.ns.Assign.IsActive(), false); A.equal(#h.popups, 1)
end)

-- Drag and drop -----------------------------------------------------------------------------------
A.test("cursor drop: spell and item accepted, low rank pinned, rejected payloads stay on the cursor", function()
    local h = started(); h.ns.Assign.Unlock()
    h.cursor = {"spell", 3, "spell", 774}
    A.equal(h.ns.Assign.OnDrop(2), true); A.deep(h.ns.CurrentPage()[2], {kind = "spell", id = 774}); A.deep(h.cursor, {})
    h.cursor = {"spell", 3, "spell", 773}
    h.ns.Assign.OnDrop(3); A.deep(h.ns.CurrentPage()[3], {kind = "spell", id = 773, pinned = true})
    h.cursor = {"item", 8}
    h.ns.Assign.OnDrop(4); A.deep(h.ns.CurrentPage()[4], {kind = "item", id = 8})
    h.cursor = {"macro", 1}
    A.equal(h.ns.Assign.OnDrop(5), false); A.equal(h.cursor[1], "macro", "unsupported payload stays intact")
    A.deep(h.ns.CurrentPage()[5], {kind = "empty"})
    h.combat = true; h.cursor = {"item", 8}; A.equal(h.ns.Assign.OnDrop(5), false); A.equal(h.cursor[1], "item"); h.combat = false
    h.ns.Assign.Lock(); h.cursor = {"item", 8}; A.equal(h.ns.Assign.OnDrop(5), false, "ignored when not assigning")
end)
A.test("internal drag: swap, move, same slot cancels, outside drop clears, right-click and combat cancel", function()
    local h = started(); h.ns.Assign.Unlock(); local bar = h.ns.Bar
    h.ns.Edit(1, {kind = "item", id = 8}); h.ns.Edit(2, {kind = "item", id = 9})
    h.ns.Assign.OnDragStart(1); h.mouseOver = bar.buttons[2].overlay; h.ns.Assign.OnDragStop(1)
    A.equal(h.ns.CurrentPage()[1].id, 9); A.equal(h.ns.CurrentPage()[2].id, 8)
    h.ns.Assign.OnDragStart(1); h.mouseOver = bar.buttons[6].overlay; h.ns.Assign.OnDragStop(1)
    A.deep(h.ns.CurrentPage()[1], {kind = "empty"}); A.equal(h.ns.CurrentPage()[6].id, 9)
    h.ns.Assign.OnDragStart(6); h.mouseOver = bar.buttons[6].overlay; h.ns.Assign.OnDragStop(6)
    A.equal(h.ns.CurrentPage()[6].id, 9, "same slot cancels")
    h.ns.Assign.OnDragStart(6); h.mouseOver = nil; h.ns.Assign.OnDragStop(6)
    A.deep(h.ns.CurrentPage()[6], {kind = "empty"}, "deliberate outside drop clears")
    h.ns.Assign.OnDragStart(2); h.ns.Assign.OnSlotClick(3, "RightButton", bar.buttons[3].overlay)
    A.equal(h.ns.Assign.IsDragging(), false); A.equal(h.ns.CurrentPage()[2].id, 8, "right-click cancels without clearing")
    h.ns.Assign.OnDragStart(2); h.combat = true; h.event("PLAYER_REGEN_DISABLED"); h.mouseOver = nil; h.ns.Assign.OnDragStop(2)
    A.equal(h.ns.CurrentPage()[2].id, 8, "combat cancels without clearing"); h.combat = false
    A.equal(h.blocked, 0)
end)
A.test("empty slots cannot start a drag; a held cursor payload blocks it", function()
    local h = started(); h.ns.Assign.Unlock()
    h.ns.Assign.OnDragStart(1); A.equal(h.ns.Assign.IsDragging(), false)
    h.ns.Edit(1, {kind = "item", id = 8}); h.cursor = {"item", 9}
    h.ns.Assign.OnDragStart(1); A.equal(h.ns.Assign.IsDragging(), false)
end)

-- Dropdown ---------------------------------------------------------------------------------------
A.test("click opens Spells / Items / Clear slot; spell tabs by skill line, ranks, known only", function()
    local h = started(); h.ns.Assign.Unlock()
    local cap = menuCapture(h)
    h.ns.Assign.OnSlotClick(2, "LeftButton", h.ns.Bar.buttons[2].overlay)
    local e = cap.entries
    A.equal(e[1].text, "Spells"); A.equal(e[2].text, "Items"); A.equal(e[3].divider, true); A.equal(e[4].text, "Clear slot")
    A.equal(e[4].disabled, true, "nothing to clear")
    local tabs = e[1].submenu
    A.equal(#tabs, 2, "empty Balance tab has no entry; General and Restoration remain")
    A.equal(tabs[1].text, "General"); A.equal(#tabs[1].submenu, 1, "passive excluded"); A.equal(tabs[1].submenu[1].text, "Attack")
    local resto = tabs[2].submenu
    A.equal(tabs[2].text, "Restoration"); A.equal(#resto, 3, "future/unlearned excluded")
    A.equal(resto[1].text, "Healing Touch"); A.equal(resto[2].text, "Rejuvenation"); A.equal(resto[3].text, "Rejuvenation (Rank 2)")
    resto[2].func(); A.deep(h.ns.CurrentPage()[2], {kind = "spell", id = 774})
    cap.entries = nil; h.ns.Assign.OnSlotClick(2, "LeftButton", h.ns.Bar.buttons[2].overlay)
    A.equal(cap.entries[1].submenu[2].submenu[2].checked, true, "current choice is checked")
    cap.entries[1].submenu[2].submenu[3].func()
    A.deep(h.ns.CurrentPage()[2], {kind = "spell", id = 773, pinned = true}, "explicit lower rank is pinned")
    cap.entries = nil; h.ns.Assign.OnSlotClick(2, "LeftButton", h.ns.Bar.buttons[2].overlay)
    A.equal(cap.entries[4].disabled, false)
    cap.entries[4].func(); A.deep(h.ns.CurrentPage()[2], {kind = "empty"})
end)
A.test("items: only items with a use effect, grouped by game class, stack totals, empty categories gone", function()
    local h = started(); h.ns.Assign.Unlock()
    local cap = menuCapture(h)
    h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    local items = cap.entries[2].submenu
    A.equal(#items, 1, "Trade Goods (Ore has no use effect) and the unclassified item are gone")
    A.equal(items[1].text, "Consumable")
    local subs = items[1].submenu
    A.equal(subs[1].text, "Bandage"); A.equal(subs[2].text, "Food & Drink")
    A.equal(subs[2].submenu[1].text, "Water x5", "stacks across bag slots are totalled")
    A.equal(subs[1].submenu[1].text, "Bandage x3")
    subs[2].submenu[1].func(); A.deep(h.ns.CurrentPage()[1], {kind = "item", id = 8})
end)
A.test("usable filter: trinket with an on-use effect stays, plain gear and quest items without one go", function()
    local h = started()
    h.items[20] = {name = "Sunfire Trinket", icon = 600, count = 1, class = 4, sub = 0, typeName = "Armor", subName = "Miscellaneous", spell = "Sunfire"}
    h.items[21] = {name = "Plain Helm", icon = 601, count = 1, class = 4, sub = 1, typeName = "Armor", subName = "Cloth"}
    h.items[22] = {name = "Quest Letter", icon = 602, count = 1, class = 12, sub = 0, typeName = "Quest", subName = "Quest"}
    h.items[23] = {name = "Linen Cloth", icon = 603, count = 6, class = 7, sub = 5, typeName = "Trade Goods", subName = "Cloth"}
    h.bags[2] = {size = 4, {itemID = 20, stackCount = 1}, {itemID = 21, stackCount = 1}, {itemID = 22, stackCount = 1}, {itemID = 23, stackCount = 6}}
    h.classNames[4] = "Armor"; h.subNames["4.0"] = "Miscellaneous"
    h.ns.Assign.Unlock(); local cap = menuCapture(h)
    h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    local labels = {}
    for _, c in ipairs(cap.entries[2].submenu) do labels[#labels + 1] = c.text end
    A.deep(labels, {"Armor", "Consumable"})
    A.equal(cap.entries[2].submenu[1].submenu[1].submenu[1].text, "Sunfire Trinket")
end)
A.test("item data not loaded yet: excluded until known, requested, then the menu rebuilds once and keeps its items", function()
    local h = started()
    h.items[30] = {name = "Elixir", icon = 700, count = 2, class = 0, sub = 2, typeName = "Consumable", subName = "Elixir", cached = false}
    h.bags[3] = {size = 1, {itemID = 30, stackCount = 2}}
    h.subNames["0.2"] = "Elixir"
    h.ns.Assign.Unlock(); local cap = menuCapture(h)
    h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    local function hasElixir(entries)
        for _, c in ipairs(entries[2].submenu) do for _, s in ipairs(c.submenu) do for _, it in ipairs(s.submenu) do
            if it.text:find("Elixir") then return true end end end end
        return false
    end
    A.equal(hasElixir(cap.entries), false); A.equal(h.requests[#h.requests], "item:30")
    h.items[30].cached = nil; h.items[30].spell = "Elixir Effect"
    cap.entries = nil; h.event("GET_ITEM_INFO_RECEIVED", 30, true)
    A.equal(cap.entries ~= nil and hasElixir(cap.entries), true, "menu rebuilt with the item")
    cap.entries = nil; h.event("GET_ITEM_INFO_RECEIVED", 30, true)
    A.equal(cap.entries, nil, "rebuilt once only")
    h.items[30].spell = nil   -- data churn must not drop a known-usable item
    h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    A.equal(hasElixir(cap.entries), true)
end)
A.test("empty menus say None available; missing enumeration APIs explain instead of guessing", function()
    local h = host(); h.login(); h.ns.Assign.Unlock()
    local cap = menuCapture(h)
    h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    A.equal(cap.entries[1].submenu[1].disabled, true); A.equal(cap.entries[1].submenu[1].text:find("not available") ~= nil, true)
    local h2 = started({lines = {}}); h2.ns.Assign.Unlock()
    local cap2 = menuCapture(h2); h2.ns.Assign.OnSlotClick(1, "LeftButton", h2.ns.Bar.buttons[1].overlay)
    A.equal(cap2.entries[1].submenu[1].text, "None available")
end)
A.test("stale menu choices are revalidated: unlearned spell, consumed item, lock, combat", function()
    local h = started(); h.ns.Assign.Unlock()
    local cap = menuCapture(h)
    h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    local rejuv = cap.entries[1].submenu[2].submenu[2]
    h.known[774] = nil
    -- the fake spellbook still lists the spell, so mark the scan result absent too
    local book = h.env.C_SpellBook; local info = book.IsSpellKnown; book.IsSpellKnown = function(id) return h.known[id] == true end
    rejuv.func(); A.deep(h.ns.CurrentPage()[1], {kind = "empty"}); A.equal(h.said("no longer available"), true)
    cap.entries = nil; h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    local water = cap.entries[2].submenu[1].submenu[2].submenu[1]
    h.bags[0] = {size = 4}; h.items[8].count = 0; water.func(); A.deep(h.ns.CurrentPage()[1], {kind = "empty"})
    -- stale generation
    cap.entries = nil; h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    local attack = cap.entries[1].submenu[1].submenu[1]
    h.ns.Assign.Lock(); attack.func(); A.deep(h.ns.CurrentPage()[1], {kind = "empty"}); A.equal(h.said("out of date"), true)
    h.ns.Assign.Unlock(); cap.entries = nil; h.ns.Assign.OnSlotClick(1, "LeftButton", h.ns.Bar.buttons[1].overlay)
    attack = cap.entries[1].submenu[1].submenu[1]
    h.combat = true; attack.func(); h.combat = false
    A.deep(h.ns.CurrentPage()[1], {kind = "empty"}); A.equal(h.blocked, 0)
end)
A.test("right-click in assignment mode offers Clear slot", function()
    local h = host(); h.login(); h.ns.Assign.Unlock()
    local cap = menuCapture(h)
    h.ns.Edit(3, {kind = "item", id = 8})
    h.ns.Assign.OnSlotClick(3, "RightButton", h.ns.Bar.buttons[3].overlay)
    local last = cap.entries[#cap.entries]
    A.equal(last.text, "Clear slot"); last.func(); A.deep(h.ns.CurrentPage()[3], {kind = "empty"})
end)
A.test("spellprobe prints findings and stores them for documentation", function()
    local h = started(); h.slash("spellprobe")
    A.equal(h.said("skill lines: 3"), true); A.equal(h.said("line 2 'Restoration'"), true)
    A.equal(type(h.ns.db.global.spellProbe), "table"); A.equal(#h.ns.db.global.spellProbe.spellLines, 3)
end)
A.test("padlock and cog buttons route to assignment and settings", function()
    local h = host(); h.login(); local bar = h.ns.Bar
    local opened = 0
    h.ns.Options.Open = function() opened = opened + 1 end
    h.fire(bar.header.padlock, "OnClick"); A.equal(h.ns.Assign.IsActive(), true)
    h.fire(bar.header.cog, "OnClick"); A.equal(opened, 1)
    h.fire(bar.header.padlock, "OnClick"); A.equal(h.ns.Assign.IsActive(), false)
end)

A.test("page or profile change while locked prompts the reload popup immediately; not in combat", function()
    local h = host(); h.login()
    h.ns.Core.setPageCount(h.ns.profile, 2)
    h.slash("page next"); A.equal(#h.popups, 1)
    h.ns.Assign.Unlock(); h.slash("page prev"); A.equal(#h.popups, 1, "during a session the lock decides")
    h.ns.Assign.Lock(); A.equal(#h.popups, 2)
    h.ns.db:SetProfile("Other"); A.equal(#h.popups, 3, "profile switch while locked")
    h.combat = true; h.slash("page next"); A.equal(#h.popups, 3); h.combat = false
end)

A.test("menu rows carry their icon inline in the label (no overlay texture can clip the first letters)", function()
    local h = host(); h.login()
    local rows, initializers = {}, 0
    local function node()
        local n = {}
        function n:CreateButton(text, fn) local c = node(); rows[#rows+1] = text; c.AddInitializer = function() initializers = initializers + 1 end; return c end
        function n:CreateCheckbox(text) local c = node(); rows[#rows+1] = text; return c end
        function n:CreateTitle() return node() end
        function n:CreateDivider() end
        function n:SetEnabled() end
        return n
    end
    h.env.MenuUtil = {CreateContextMenu = function(owner, gen) gen(owner, node()) end}
    h.ns.Menu.Show(h.env.UIParent, {{text = "General", icon = 136243, submenu = {{text = "Attack", icon = 132223}}},
        {text = "Items", submenu = {{text = "Water x5", icon = "Interface\Icons\INV_Drink_01", checked = true}}}})
    A.equal(initializers, 0, "no initializer repositions textures")
    A.equal(rows[1], "|T136243:16:16:0:0|t General"); A.equal(rows[2], "|T132223:16:16:0:0|t Attack")
    A.equal(rows[3], "Items"); A.equal(rows[4]:find("^|T") ~= nil and rows[4]:find("Water x5", 1, true) ~= nil, true)
    A.equal(h.ns.Menu.backend, "MenuUtil")
end)
