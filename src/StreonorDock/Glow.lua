local addonName, ns = ...
-- Highlight/glow through LibCustomGlow-1.0 (pixel / autocast / button / proc). Style and colour come
-- from the profile (highlight.style, highlight.color; both pickable in settings). Used for the drop
-- target, the slot whose menu is open, and the cooldown-ready flash. Decoration only: plain
-- non-secure child frames, never touches secure attributes, safe in combat.
local Glow = {}
ns.Glow = Glow
Glow.STYLES = {pixel="Pixel", autocast="Autocast sparks", button="Button glow", proc="Proc"}
Glow.ORDER = {"pixel", "autocast", "button", "proc"}
local active = setmetatable({}, {__mode = "k"})   -- frame -> style it was started with
local KEY = "StreonorDock"

local function lib()
    return _G.LibStub and LibStub("LibCustomGlow-1.0", true) or nil
end
function Glow.Available() return lib() ~= nil end
local function settings()
    local hl = ns.profile and ns.profile.highlight
    local style = hl and hl.style or "pixel"
    local color = hl and hl.color or {0.96, 0.80, 0.20, 1}
    return style, {color[1], color[2], color[3], color[4]}
end
local stoppers = {
    pixel = function(g, f) g.PixelGlow_Stop(f, KEY) end,
    autocast = function(g, f) g.AutoCastGlow_Stop(f, KEY) end,
    button = function(g, f) g.ButtonGlow_Stop(f) end,
    proc = function(g, f) g.ProcGlow_Stop(f, KEY) end,
}
function Glow.Stop(frame)
    local style = active[frame]
    if not style then return end
    active[frame] = nil
    local g = lib()
    if g and stoppers[style] then pcall(stoppers[style], g, frame) end
end
-- styleOverride is for the settings preview; normal callers pass nothing.
function Glow.Start(frame, styleOverride)
    local g = lib()
    if not g or not frame then return false end
    Glow.Stop(frame)
    local style, color = settings()
    style = styleOverride or style
    local ok
    if style == "pixel" then ok = pcall(g.PixelGlow_Start, frame, color, nil, nil, nil, nil, 0, 0, false, KEY)
    elseif style == "autocast" then ok = pcall(g.AutoCastGlow_Start, frame, color, nil, nil, nil, 0, 0, KEY)
    elseif style == "button" then ok = pcall(g.ButtonGlow_Start, frame, color)
    elseif style == "proc" then ok = pcall(g.ProcGlow_Start, frame, {color = color, key = KEY})
    end
    if ok then active[frame] = style end
    return ok == true
end
function Glow.IsActive(frame) return active[frame] ~= nil end
-- One-shot flash (ready notification): glows for `seconds`, then stops, unless restarted meanwhile.
local tokens = setmetatable({}, {__mode = "k"})
function Glow.Flash(frame, seconds)
    if not Glow.Start(frame) then return false end
    tokens[frame] = (tokens[frame] or 0) + 1
    local mine = tokens[frame]
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(seconds or 1.5, function() if tokens[frame] == mine then Glow.Stop(frame) end end)
    end
    return true
end
function Glow.StopAll()
    for frame in pairs(active) do Glow.Stop(frame) end
end
