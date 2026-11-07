local addonName, ns = ...
-- Reference data for item cooldowns. Pure data, no WoW calls. Loaded before Cooldown.lua.
-- SHIPPED EMPTY ON PURPOSE: no number here may be invented. A separate research task fills it,
-- and every entry stays verified=false until confirmed in game (/sdock probe lists mismatches
-- between this table and readable game data).
--
-- ns.CooldownGroups[groupKey] = {
--     name     = "Health potions",  -- display label
--     duration = <seconds> or nil,  -- reference cooldown length; nil = unknown
--     shared   = true | false | nil,-- true: one timer for every member item (pressing any member
--                                   -- starts it); false/nil (nil = unverified): per-item timers
--     verified = <bool>,            -- confirmed in game on this client
--     source   = "...",             -- where the value came from
-- }
-- ns.ItemGroups[<itemID>] = "<groupKey>"
--
-- Precedence (Cooldown.lua): readable game data > learned value (observed in game, persisted per
-- itemID) > group duration from this table > item base-cooldown API (if probed present) > unknown.
ns.CooldownGroups = {
}
ns.ItemGroups = {
}
