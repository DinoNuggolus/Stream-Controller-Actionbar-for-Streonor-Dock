# StreonorDock

Original WoW: Forever addon by DinoNuggolus, MIT licensed. An optional on-screen action bar whose 15 buttons mirror
the 15 fixed controller chords of a Streonor S15, plus the chord targets themselves, up to 10 pages per profile
and a minimal icon export for the Streonor plugin.

Use the S15 in landscape. In the Streonor app, manually place Dock Key 1 at bottom-left, then Dock Key 2-5 across the
bottom to the right. Place Dock Key 6-10 across the middle and Dock Key 11-15 across the top. Dock Key 15 is top-right.
These action settings refer to stable slot numbers, not assumed host row/column coordinates. Keep Mirror controller
layout ON for the same arrangement in game. Each press makes one use attempt. Reload or logout after assignment
changes to update controller icons. The plugin never rewrites your device profile.

Chords: slot N = `ALT-CTRL-SHIFT-` + `1 2 3 4 5 6 7 8 9 0 - = [ ] \` (N = 1..15). One physical press is exactly one
use attempt (the addon acts on the key-down edge only; no hold repeat, no second attempt on release).

## Using it

* The bar is ON and centred on first run. Drag the thin header to move it (out of combat). Header: padlock
  (assignment mode) and cog (settings), each can be hidden in General. `/sdock settings` always opens settings.
* Assign: click the padlock (or `/sdock assign`, or right-click the minimap button). All 15 buttons appear with a `+`
  (full strength when empty, half when filled). Drag a known spell from the spellbook or a carried bag item onto a
  button, or click a button for **Spells** (by spellbook tab) / **Items** (by game item class, with stack totals) /
  **Clear slot**. Drag a filled button onto another to swap or move; drop it outside the bar to clear it; Escape or
  right-click cancels a drag. Lock again to finish: if something really changed you get one **Reload / Cancel**
  prompt; Cancel is final (no reminders). Reload writes the new icons for the controller.
* With the bar hidden, `/sdock assign` and the minimap button reveal it temporarily and hide it again on lock.
* Locked buttons: left-click performs one use attempt. Right-click opens the menu (or the configured action).
* Buttons show carried stack totals (0 stays visible, dimmed), spell charges and an OmniCC-style cooldown: dimmed
  remaining region, clockwise sweep, centred number (seconds below 90 s, `2m` from 90 s, `2h` from 90 min).
* Everything is out-of-combat only. Changes needing protected frames wait for combat to end.

## Commands

| Command | Does |
|---|---|
| `/sdock settings` | Settings window (also Interface > AddOns > StreonorDock) |
| `/sdock assign` | Toggle assignment mode |
| `/sdock toggle` | Show/hide the bar |
| `/sdock reset position` | Centre the bar |
| `/sdock page next\|prev\|home\|<n>` | Paging (out of combat) |
| `/sdock chords` | Each chord, its slot, ordinary binding, effective mapping, conflicts |
| `/sdock probe` | Capability presence (menu, settings, popup, spellbook, cooldown APIs), secure state |
| `/sdock spellprobe` | Dumps spellbook skill lines and bag classes (debug; saved to `StreonorDockDB.global.spellProbe`) |
| `/sdock clicks [reset]` | Per-slot input edge counters (routing evidence only) |
| `/sdock export` | Summary of the in-memory icon export |

## Controller export

`StreonorDockDB.export = {schemaVersion=2, enabled, profileId, page, icons[1..15]}`; each icon is `{}` (empty),
`{iconFileID=n}` or `{unresolved=true}`. No action IDs, counts, timers or telemetry. WoW writes it on reload/logout.

## Data

AceDB-3.0 with one profile per character by default (`StreonorDockDB`; `StreonorDockCharDB` only keeps the
sanitized rollback archive of the pre-0.3 data). Removed in 0.3: LCD readouts, money/currency, client logging
switches, press-started timers and estimates, learned cooldown durations, count/status export.

## Libraries

Embedded in `Libs/` (see `Libs/LIBRARIES.md`): LibStub, CallbackHandler, AceDB, AceDBOptions, AceGUI, AceConfig,
LibSharedMedia, AceGUI-SharedMediaWidgets, LibDataBroker, LibDBIcon, LibCustomGlow, LibUIDropDownMenu (fallback).

## Tests

`lua tests/run.lua` from this folder (Lua 5.1; fake WoW host, real AceDB/AceConfigRegistry). Host tests prove
lifecycle and secure-call discipline only; they cannot prove client behavior. See NOTES.md for the in-game checklist.

## License

MIT (addon code). Embedded libraries keep their own licenses.
