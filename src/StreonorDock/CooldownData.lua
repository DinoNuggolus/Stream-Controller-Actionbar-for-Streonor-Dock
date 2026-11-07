local addonName, ns = ...
-- Reference data for item cooldowns. Pure data, no WoW calls. Loaded before Cooldown.lua.
-- Entries below are copied UNCHANGED from StreonorWoW/docs/research/CooldownData.seed.lua
-- (report: consumable-cooldowns.md). Classic references; every entry is verified=false until
-- confirmed in game on this client. /sdock probe prints table vs observed durations.
--
-- ns.CooldownGroups[groupKey] = {
--     name     = "Health potions",
--     duration = <seconds> | 0 | nil, -- 0: no use cooldown (slot stays dormant); nil: unknown
--     shared   = "<pool label>" | nil,-- groups with the same label share ONE timer keyed by the
--                                     -- label; nil: one timer per group key
--     verified = <bool>, source = "...",
-- }
-- ns.ItemGroups[<itemID>] = "<groupKey>"
-- Precedence (Cooldown.lua): readable game data > learned value (observed, persisted per itemID)
-- > the pressed item's group duration > item base-cooldown API (if present) > unknown (USED).
-- Out of scope for v1 (docs only): cross-lockouts outside this pool model, e.g. sapper vs
-- explosives and invisibility vs potions.
ns.CooldownGroups = {
  health_potion = { name = "Health potions", duration = 120, shared = "potion", verified = false, source = "https://classicdb.ch/?item=13446" },
  mana_potion = { name = "Mana potions", duration = 120, shared = "potion", verified = false, source = "https://classicdb.ch/?item=13444" },
  rejuvenation = { name = "Rejuvenation potions", duration = 120, shared = "potion", verified = false, source = "https://classicdb.ch/?item=18253" },
  utility_potion = { name = "Utility potions", duration = 120, shared = "potion", verified = false, source = "https://classicdb.ch/?item=3387" },
  protection = { name = "Protection potions", duration = 120, shared = "potion", verified = false, source = "https://classicdb.ch/?item=13457" },
  invisibility = { name = "Invisibility potion", duration = 600, shared = nil, verified = false, source = "https://classicdb.ch/?item=9172" },
  healthstone = { name = "Healthstones", duration = 120, shared = "stone_rune", verified = false, source = "https://classicdb.ch/?item=9421" },
  rune = { name = "Runes", duration = 120, shared = "stone_rune", verified = false, source = "https://classicdb.ch/?item=12662" },
  juju_flurry = { name = "Juju Flurry", duration = 60, shared = nil, verified = false, source = "https://classicdb.ch/?item=12450" },
  juju_power = { name = "Juju Power", duration = 60, shared = nil, verified = false, source = "https://classicdb.ch/?item=12451" },
  juju_ember = { name = "Juju Ember", duration = 60, shared = nil, verified = false, source = "https://classicdb.ch/?item=12455" },
  juju_chill = { name = "Juju Chill", duration = 60, shared = nil, verified = false, source = "https://classicdb.ch/?item=12457" },
  juju_guile = { name = "Juju Guile", duration = 60, shared = nil, verified = false, source = "https://classicdb.ch/?item=12458" },
  juju_escape = { name = "Juju Escape", duration = 60, shared = nil, verified = false, source = "https://classicdb.ch/?item=12459" },
  juju_might = { name = "Juju Might", duration = 60, shared = nil, verified = false, source = "https://classicdb.ch/?item=12460" },
  explosives = { name = "Grenades and dynamite", duration = 60, shared = "explosives", verified = false, source = "https://classicdb.ch/?item=15993" },
  sapper = { name = "Goblin Sapper Charge", duration = 300, shared = nil, verified = false, source = "https://classicdb.ch/?item=10646" },
  trolls_blood = { name = "Major Troll's Blood", duration = nil, shared = nil, verified = false, source = "https://classicdb.ch/?item=20004" },
  bandage = { name = "Bandages", duration = 0, shared = nil, verified = false, source = "https://classicdb.ch/?item=14530" },
  food_drink = { name = "Ordinary food and drink", duration = 0, shared = nil, verified = false, source = "https://classicdb.ch/?item=13935" },
  talisman = { name = "Talisman of Ephemeral Power", duration = 90, shared = nil, verified = false, source = "https://classicdb.ch/?item=18820" },
  barov = { name = "Barov Peasant Caller", duration = 600, shared = nil, verified = false, source = "https://classicdb.ch/?item=14022" },
}
ns.ItemGroups = {
  [118] = "health_potion", [13446] = "health_potion",
  [2455] = "mana_potion", [13444] = "mana_potion",
  [18253] = "rejuvenation",
  [3387] = "utility_potion", [5634] = "utility_potion",
  [2459] = "utility_potion", [20008] = "utility_potion",
  [9036] = "utility_potion", [4623] = "utility_potion",
  [9030] = "utility_potion", [12190] = "utility_potion",
  [13457] = "protection", [13458] = "protection",
  [13459] = "protection", [9172] = "invisibility",
  [9421] = "healthstone", [19012] = "healthstone",
  [19013] = "healthstone",
  [12662] = "rune", [20520] = "rune",
  [12450] = "juju_flurry", [12451] = "juju_power",
  [12455] = "juju_ember", [12457] = "juju_chill",
  [12458] = "juju_guile", [12459] = "juju_escape",
  [12460] = "juju_might",
  [15993] = "explosives", [18641] = "explosives",
  [10646] = "sapper", [20004] = "trolls_blood",
  [14530] = "bandage",
  [13935] = "food_drink", [8766] = "food_drink",
  [18820] = "talisman", [14022] = "barov",
}

