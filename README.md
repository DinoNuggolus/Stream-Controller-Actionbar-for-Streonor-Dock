# Stream Controller Actionbar for Streonor Dock

An optional on-screen action bar for **World of Warcraft: Forever** whose 15 buttons mirror the 15 keys of a
**Streonor S15** stream controller. Assign spells, items and macros to the buttons in game; each controller key
fires its slot with one press and shows the matching icon. (Addon folder and in-game name: **StreonorDock**.)

> Screenshots: _(placeholder - add `docs/bar.png`, `docs/settings.png`, `docs/s15.jpg`)_

## REQUIRED: the Streonor plugin

The controller keys are driven by a small Streonor plugin. Without it the bar still works with the mouse, but the S15
does nothing.

**Plugin repository: <https://github.com/DinoNuggolus/StreonorWoW>** - install it like this:

1. On the plugin repo's **Releases** page download `StreonorDock-Plugin-<version>.zip` and extract it.
2. Double-click **Install StreonorDock Plugin.bat** (no commands, no PowerShell window to type in). It asks before closing
   Streonor and before starting it again. Windows may warn about the `.bat`: *More info > Run anyway*.
3. Restart Streonor if it did not start by itself.
4. Open your S15 profile and place **Dock Key 1 ... Dock Key 15** with the S15 in **landscape**:

   | Row | Keys, left to right |
   |---|---|
   | Top | Dock Key 11 - 12 - 13 - 14 - 15 |
   | Middle | Dock Key 6 - 7 - 8 - 9 - 10 |
   | Bottom | Dock Key 1 - 2 - 3 - 4 - 5 |

   Dock Key 1 is bottom-left, Dock Key 15 is top-right. The plugin never rewrites your profile. Keep **Mirror controller
   layout** ON (default) so the on-screen bar uses the same arrangement.

## Install the addon

1. Download `StreonorDock-<version>.zip` from this repo's **Releases** page and extract it.
2. Copy the folder **StreonorDock** into `<your WoW folder>\_forever_\Interface\AddOns\` so that
   `...\AddOns\StreonorDock\StreonorDock.toc` exists. Libraries are included.
3. Start the game (enable StreonorDock on the AddOns screen) or `/reload`.

Interface 16001 (WoW: Forever). Updating: extract over the old folder; your settings are kept.

## Quick start

* `/sdock` shows the commands. `/sdock settings` opens the settings window (also in Interface > AddOns).
* The bar appears centred on first run. Drag its thin header to move it (out of combat). The header has a **padlock**
  (assignment mode) and a **cog** (settings); it fades when the mouse is away.
* **Assign:** click the padlock (or `/sdock assign`, or right-click the minimap button). All 15 buttons appear with a `+`.
  Drag a spell from the spellbook, a bag item or a macro from the macro window onto a button, **or** click a button and
  pick from **Spells** (by spellbook tab) / **Items** (usable bag items by type, with stack counts) / **Macros**
  (General and your character's) / **Clear slot**. Drag a filled button onto another to swap; drop it outside to clear.
  Escape or right-click cancels a drag.
* **Lock again** to finish. If assignments, page or profile changed you get one **Reload / Cancel** prompt: Reload writes
  the new icons for the controller (WoW saves addon data on reload/logout); Cancel closes it with no reminder.
* **One press = one use attempt.** The addon acts on the key-down edge only; holding a key does not repeat.
* **Right-click** anywhere on the panel opens a menu (settings, assignment mode, reload); what right-click does is
  configurable.
* A short tutorial runs once on the first login. **X** hides tutorial popups permanently; replay it in Settings > General.
* Pages (1-10 per profile), a profile per character, cooldown and stack display on bar buttons (seconds, `2m`, `2h`).

## Settings overview

* **General:** show bar, always show buttons (off: empty slots are hidden while locked), padlock/cog, right-click
  behaviour, minimap button, tutorial replay and "hide tutorial popups".
* **Bar:** *Layout* (Mirror controller layout / single row / single column / columns, rows, growth, scale, size,
  spacing, reset position), *Appearance* (Flat / Slate / Parchment-lite presets, SharedMedia border, background and
  font pickers, opacity, header fade, glow style and colour), *Visibility* (fade by condition).
* **Visibility:** faded and visible opacity, fade in/out and delay, ANY/ALL, hide completely, and a checkbox list of
  conditions (mouseover, combat, target, hostile target, group, raid, instance, PvP, mounted, resting, flying
  [best effort], casting, low health, modifier key). Mouseover raises opacity only if ticked. Assignment mode always
  shows the bar fully.
* **Buttons:** stack counts, tooltips, cooldown look and thresholds, ready glow, labels.
* **Assignment:** pages, page keys. **Controller:** export switch, chord list, Reload UI. **Profiles / Diagnostics / About.**

## Commands

| Command | Does |
|---|---|
| `/sdock settings` | Settings window |
| `/sdock assign` | Toggle assignment mode (works with the bar hidden: it shows the bar temporarily) |
| `/sdock toggle` | Show/hide the bar |
| `/sdock reset position` | Centre the bar |
| `/sdock page next\|prev\|home\|<n>` | Paging (out of combat) |
| `/sdock chords` | Each chord, its slot, bindings and conflicts |
| `/sdock probe`, `spellprobe`, `macroprobe` | Capability / debug dumps |
| `/sdock clicks [reset]` | Per-slot input edge counters (routing evidence only) |
| `/sdock export` | Summary of the controller icon export |
| `/sdock bar` | Which bar buttons are shown (debug) |

## Troubleshooting

* **Controller keys are black / do nothing:** install the plugin (above), restart Streonor, place the Dock Keys, make sure
  the addon is enabled, and `/reload` once. `/sdock export` should report resolved icons.
* **Keys show a question mark:** the plugin has no icon file for that spell (see the plugin README, *Icons*).
* **"Running scripts is disabled" (execution policy):** use the plugin's `.bat` installer; it starts PowerShell with the
  right switch itself, so you never type a command.
* **A chord also triggers another action:** `/sdock chords` marks conflicts; the addon's bindings take precedence while loaded.
* **Nothing happens in combat after login:** the addon sets up its protected buttons after combat ends.
* **Menu looks wrong:** `/sdock probe` and Settings > Diagnostics show which menu system the client provides.

## How it works (short)

15 fixed chords (`ALT-CTRL-SHIFT-` + `1 2 3 4 5 6 7 8 9 0 - = [ ] \`) are bound to 15 secure buttons that exist even when
the bar is hidden. The bar's buttons are separate secure targets with the same actions. The addon writes
`StreonorDockDB.export` (icons only: no action IDs, counts or timers) which the plugin reads. Data uses AceDB with a
profile per character; the addon never reads the combat log.

## Development

`lua tests/run.lua` from this folder (Lua 5.1; fake WoW host, real AceDB/AceConfigRegistry). Build a release zip:
`powershell -File scripts\build-release.ps1` (output in git-ignored `dist\`). See `NOTES.md` for the in-game test checklist.

## Credits and licenses

Addon code: MIT, see `LICENSE`. Embedded libraries (unchanged, each with its own license; see
`src/StreonorDock/Libs/LIBRARIES.md`): LibStub, CallbackHandler-1.0, AceDB-3.0, AceDBOptions-3.0, AceGUI-3.0,
AceConfig-3.0 (Ace3, BSD), LibSharedMedia-3.0 (LGPL), AceGUI-3.0-SharedMediaWidgets, LibDataBroker-1.1, LibDBIcon-1.0,
LibCustomGlow-1.0 (MIT) and LibUIDropDownMenu-4.0. No Blizzard artwork is included.
