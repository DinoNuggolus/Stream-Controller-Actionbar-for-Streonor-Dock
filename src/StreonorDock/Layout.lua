local addonName, ns = ...
-- Pure geometry for the action bar (no frames, no game calls). Slot identity (1..15) and its chord
-- never depend on where a cell is drawn.
local Layout = {}
ns.Layout = Layout
Layout.HEADER_HEIGHT = 16
Layout.PAD = 4

-- cfg: mirror (bool), columns (1..15), orientation "horizontal"|"vertical", growX "left"|"right",
-- growY "up"|"down". Returns a dimension table {cols, rows, cell = function(slot) -> col,row},
-- both zero-based from the TOP-LEFT of the grid.
function Layout.grid(cfg)
    cfg = cfg or {}
    local cols, rows
    if cfg.mirror then cols, rows = 5, 3 else
        cols = math.max(1, math.min(15, math.floor(tonumber(cfg.columns) or 5)))
        rows = math.ceil(15 / cols)
    end
    local vertical = (not cfg.mirror) and cfg.orientation == "vertical"
    local usedCols, usedRows = cols, rows
    if vertical then usedCols = math.ceil(15 / rows); usedRows = rows end
    local function cell(slot)
        local i = slot - 1
        if cfg.mirror then
            -- slot 1 bottom-left, numbering right then up
            return i % 5, 2 - math.floor(i / 5)
        end
        local c, r
        if vertical then c, r = math.floor(i / usedRows), i % usedRows
        else c, r = i % usedCols, math.floor(i / usedCols) end
        if cfg.growX == "left" then c = usedCols - 1 - c end
        if cfg.growY == "up" then r = usedRows - 1 - r end
        return c, r
    end
    return {cols=usedCols, rows=usedRows, cell=cell}
end
-- Size in pixels of the button area and the position (offset from the area's TOPLEFT) of a slot.
function Layout.metrics(cfg, size, spacing)
    local grid = Layout.grid(cfg)
    local width = grid.cols * size + (grid.cols - 1) * spacing
    local height = grid.rows * size + (grid.rows - 1) * spacing
    return grid, width, height
end
function Layout.offset(grid, slot, size, spacing)
    local c, r = grid.cell(slot)
    return c * (size + spacing), -(r * (size + spacing))
end
-- Visible slots of a page given the filter (assignment shows all; locked hides empty unless always).
function Layout.visible(page, assigning, always)
    local list = {}
    for i = 1, 15 do
        local slot = page and page[i]
        local filled = slot and slot.kind ~= "empty"
        list[i] = assigning or always or filled or false
    end
    return list
end
-- Offsets for SetPoint("CENTER", UIParent, "CENTER", x, y) preserving the frame's visual centre.
-- cx,cy: frame:GetCenter() in screen pixels (already * effective scale); pcx,pcy: parent centre
-- in the same units; frameScale = frame effective scale. Returns offsets in the frame's own units.
function Layout.centerOffset(cx, cy, pcx, pcy, frameScale)
    if type(cx) ~= "number" or type(cy) ~= "number" or type(pcx) ~= "number" or type(pcy) ~= "number" then return 0, 0 end
    frameScale = (type(frameScale) == "number" and frameScale > 0) and frameScale or 1
    return (cx - pcx) / frameScale, (cy - pcy) / frameScale
end
