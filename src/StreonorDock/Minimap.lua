local addonName, ns = ...
-- Minimap button: LibDataBroker launcher shown by LibDBIcon-1.0. Position/hidden flag live in the
-- character table (char.minimap = {hide=, minimapPos=}). Left-click: settings. Right-click: assignment.
local Minimap = {}
ns.Minimap = Minimap
local NAME = "StreonorDock"
local object
local function libs()
    if not _G.LibStub then return nil end
    return LibStub("LibDataBroker-1.1", true), LibStub("LibDBIcon-1.0", true)
end

function Minimap.OnClick(_, button)
    if button == "RightButton" then
        if ns.Assign then ns.Safe("minimap assign", ns.Assign.Toggle) end
    else
        if ns.Options then ns.Safe("minimap settings", ns.Options.Open) end
    end
end
function Minimap.OnTooltip(tooltip)
    tooltip:AddLine("StreonorDock")
    tooltip:AddLine("Left-click: settings", 1, 1, 1)
    tooltip:AddLine("Right-click: toggle assignment mode", 1, 1, 1)
end
function Minimap.Create()
    local ldb, dbicon = libs()
    if not ldb or not dbicon or not ns.char then return false end
    if not object then
        object = ldb:NewDataObject(NAME, {
            type = "launcher",
            text = NAME,
            icon = "Interface\\Icons\\INV_Misc_Gear_01",
            OnClick = Minimap.OnClick,
            OnTooltipShow = Minimap.OnTooltip,
        })
    end
    if not dbicon:IsRegistered(NAME) then dbicon:Register(NAME, object, ns.char.minimap) end
    Minimap.Apply()
    return true
end
-- Re-reads char.minimap.hide (settings toggle, profile switch).
function Minimap.Apply()
    local _, dbicon = libs()
    if not dbicon or not dbicon:IsRegistered(NAME) then return end
    dbicon:Refresh(NAME, ns.char.minimap)
    if ns.char.minimap.hide then dbicon:Hide(NAME) else dbicon:Show(NAME) end
end
function Minimap.SetHidden(hidden)
    ns.char.minimap.hide = hidden and true or false
    Minimap.Apply()
end
