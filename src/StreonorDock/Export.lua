local addonName, ns = ...
-- Minimal controller export (schema 2): StreonorDockDB.export = {schemaVersion=2, enabled, profileId,
-- page, icons[1..15]}. Icons only: no action IDs, counts, timers, revisions or telemetry. It reaches
-- disk only when WoW writes SavedVariables (reload/logout/exit), which is the sync boundary.
local Export = {}
ns.Export = Export
local dirtyScheduled = false
local generation = 0
local teardown = false
local function lib(name) local t = _G[name]; if type(t)=="table" then return t end; return {} end

-- Rebuilds the export in memory from the current page. Late icon metadata just calls this again.
function Export.Refresh()
    dirtyScheduled = false
    generation = generation + 1  -- invalidates an already queued debounce callback
    if teardown or not ns.profile or type(StreonorDockDB) ~= "table" then return false end
    local enabled = ns.db.global.exportEnabled ~= false
    StreonorDockDB.export = ns.Core.buildExport(enabled, ns.profile.id, ns.char.currentPage,
        ns.CurrentPage(), ns.Game.SlotIcon)
    return true
end
-- Coalesce bursts of changes into one rebuild a second later.
function Export.MarkDirty()
    if teardown or dirtyScheduled then return end
    local timer = lib("C_Timer")
    if type(timer.After) == "function" then
        dirtyScheduled = true
        local mine = generation
        local ok = pcall(timer.After, 1, function()
            if not teardown and dirtyScheduled and mine == generation then ns.Safe("export", Export.Refresh) end
        end)
        if ok then return end
        dirtyScheduled = false
    end
    Export.Refresh()
end
-- The boundary flush runs BEFORE teardown starts, so a pending change still reaches the file.
function Export.LeavingWorld()
    if teardown then return end
    if dirtyScheduled then Export.Refresh() end
    teardown = true
end
function Export.EnteringWorld()
    teardown = false
    local timer = lib("C_Timer")
    -- Safety net: metadata requested before the client could answer must not leave unresolved
    -- icons in the export until the next reload.
    if type(timer.After) == "function" then
        for _, delay in ipairs({3, 8}) do
            pcall(timer.After, delay, function()
                if teardown then return end
                ns.Game.ForgetRequests()
                ns.Safe("redraw", function() if ns.Bar then ns.Bar.Refresh() end end)
                ns.Safe("secure", ns.Secure.Request)
                Export.MarkDirty()
            end)
        end
    end
    Export.MarkDirty()
end
function Export.Summary()
    local e = type(StreonorDockDB) == "table" and StreonorDockDB.export
    if type(e) ~= "table" then return nil end
    local resolved, unresolved = 0, 0
    for i = 1, 15 do
        local entry = type(e.icons) == "table" and e.icons[i] or nil
        if type(entry) == "table" then
            if entry.iconFileID then resolved = resolved + 1 elseif entry.unresolved then unresolved = unresolved + 1 end
        end
    end
    return {enabled = e.enabled, profileId = e.profileId, page = e.page, resolved = resolved, unresolved = unresolved}
end
