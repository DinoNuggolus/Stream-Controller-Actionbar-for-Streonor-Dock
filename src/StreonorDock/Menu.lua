local addonName, ns = ...
-- Menu adapter. A menu is a plain model (array of entries) rendered by the native Blizzard menu system
-- (MenuUtil.CreateContextMenu) when the client has it, else by LibUIDropDownMenu-4.0.
-- Entry: {text=, icon=, checked=bool, disabled=bool, title=true, divider=true, func=fn, submenu={...},
--         scroll=number (max pixel height for a long submenu), tooltip=string}
local Menu = {}
ns.Menu = Menu
Menu.backend = nil

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end

-- Native: description objects expose CreateButton/CreateTitle/CreateDivider/CreateCheckbox.
local function fillNative(desc, entries)
    for _, e in ipairs(entries) do
        if e.divider then
            if has(desc, "CreateDivider") then desc:CreateDivider() end
        elseif e.title then
            if has(desc, "CreateTitle") then desc:CreateTitle(e.text or "") end
        else
            local item
            local func = e.func
            -- The icon is part of the label (inline |T texture |t) so the menu lays out text and icon
            -- together: no overlay texture that can cover the first letters of a row.
            local label = e.text or ""
            if e.icon then label = "|T" .. tostring(e.icon) .. ":16:16:0:0|t " .. label end
            if e.checked ~= nil and has(desc, "CreateCheckbox") then
                item = desc:CreateCheckbox(label, function() return e.checked end, func)
            else
                item = desc:CreateButton(label, e.submenu and nil or func)
            end
            if item then
                if e.disabled and has(item, "SetEnabled") then item:SetEnabled(false) end
                if e.tooltip and has(item, "SetTooltip") then
                    pcall(item.SetTooltip, item, function(tooltip) tooltip:SetText(e.tooltip, 1, 1, 1, 1, true) end)
                end
                if e.submenu then
                    if e.scroll and has(item, "SetScrollMode") then pcall(item.SetScrollMode, item, e.scroll) end
                    fillNative(item, e.submenu)
                end
            end
        end
    end
end

local function showNative(owner, entries, scroll)
    local util = _G.MenuUtil
    if type(util) ~= "table" or type(util.CreateContextMenu) ~= "function" then return false end
    local ok = pcall(util.CreateContextMenu, owner, function(_, root)
        if scroll and has(root, "SetScrollMode") then pcall(root.SetScrollMode, root, scroll) end
        fillNative(root, entries)
    end)
    if ok then Menu.backend = "MenuUtil" end
    return ok
end

-- Fallback: LibUIDropDownMenu-4.0 (standard info tables; submenus through menuList).
local dropFrame
local function showLib(owner, entries)
    local lib = _G.LibStub and LibStub("LibUIDropDownMenu-4.0", true)
    if not lib or type(_G.L_Create_UIDropDownMenu) ~= "function" then return false end
    dropFrame = dropFrame or L_Create_UIDropDownMenu("StreonorDockMenuFrame", UIParent)
    local function initialize(_, level, list)
        local source = list or entries
        for _, e in ipairs(source) do
            local info = L_UIDropDownMenu_CreateInfo()
            if e.divider then
                info.disabled, info.notCheckable, info.text = true, true, ""
            elseif e.title then
                info.isTitle, info.notCheckable, info.text = true, true, e.text
            else
                info.text, info.icon, info.disabled = e.text, e.icon, e.disabled
                if e.checked ~= nil then info.checked = e.checked else info.notCheckable = true end
                info.func = e.func
                if e.submenu then info.hasArrow, info.menuList, info.func = true, e.submenu, nil end
            end
            L_UIDropDownMenu_AddButton(info, level)
        end
    end
    L_UIDropDownMenu_Initialize(dropFrame, initialize, "MENU")
    L_ToggleDropDownMenu(1, nil, dropFrame, owner, 0, 0)
    Menu.backend = "LibUIDropDownMenu"
    return true
end

function Menu.Show(owner, entries, scroll)
    if showNative(owner, entries, scroll) then return true end
    return showLib(owner, entries)
end
function Menu.Close()
    if type(_G.CloseMenus) == "function" then pcall(CloseMenus) end
end
-- Wraps a callback so a menu action that outlives its context (combat began, slot reassigned) is
-- revalidated by the caller; Menu itself never touches game state.
