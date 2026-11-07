# StreonorDock

Original WoW: Forever addon by DinoNuggolus, MIT licensed. **Part 1 only**: tested pure
layout/export/cooldown logic and thin WoW adapter skeletons. No editor, actionable
buttons, override bindings or persisted export wiring yet. Nothing is deployed.

The planned controller has 15 fixed keys and 3 item readouts per character page.
Manual next/previous/home paging works out of combat, up to 10 pages. New pages
start empty; returning to a page restores its contents. The three readouts start
empty. Slot N uses `ALT-CTRL-SHIFT-` plus `1 2 3 4 5 6 7 8 9 0 - = [ ] \`.

## Verification

From `G:\WoWFOREVER_ADDONS\StreonorDock` in PowerShell:

```powershell
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\run.lua
$files = @(rg --files -g '*.lua')
foreach ($file in $files) {
    & 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p $file
    if ($LASTEXITCODE -ne 0) { throw "Syntax failed: $file" }
}
```

Tests have no external dependencies. Only the host test runner/specs use `loadfile`
and `setfenv`; none are loaded by the addon. Every Lua file starts with the namespace
declaration. See [NOTES.md](NOTES.md) for measured results and remaining verification.
Fake-host tests verify adapter lifecycle, not actual client compatibility or secrecy.

## Pure model contracts

TOC-loaded modules publish `ns.Core` and `ns.CooldownTracker`; tests pass the same
namespace to unchanged source chunks. No WoW globals are used by either module.

- `Core.recover(saved, fallbackProfileId)` returns an independent normalized layout:
  `{profileId, revision, currentPage, pages}`. Each page has `slots[1..15]` and
  `readouts[1..3]`. Recovery copies allowlisted fields, repairs invalid slots,
  fills sparse page holes and clamps page selection to valid bounds. At most ten
  pages are recovered. Invalid ID = anything other than a finite positive integer.
- `Core.assign(state, "slots"|"readouts", index, value, inCombat)` returns
  `newState, true` or the original `state, false, reason`. Key slots accept
  `{kind="spell"|"item", id=...}` or `{kind="empty"}`. Readouts accept only
  `{kind="item", itemID=...}` or empty. Accepted edits copy input and increment revision.
- `Core.page(state, "next"|"prev"|"home", inCombat)` follows the same result contract.
  Previous/home at page 1 succeed without a revision change; next at page 10 rejects
  with `limit`. All combat requests reject with `combat` and preserve exact state.
- `Core.chord(index)` returns the fixed WoW string, or nil for invalid indices.
- `Core.buildExport(state, now, issecret, providers)` builds a new allowlisted
  snapshot, never merges an old one. `now` is injected server seconds (nonnegative
  integer). Providers are ID-indexed tables `spells` and `items`, containing ordinary
  `name`, `iconFileID`; items may also provide `count`, `endsAt`, `source`.
  `issecret(value)` is checked before examining provider values. Missing/secret/
  malformed values are omitted; no field retains a previous reading. The adapter
  must sanitize live data *before* passing it here; the predicate adds defense.

Snapshot schema 1:

```text
{schema=1, profileId, revision, savedAt, page={index,count},
 slots[1..15], readouts[1..3]}
```

Empty entries are exactly `{kind="empty"}`. Populated keys include kind/id/chord;
readouts include kind/itemID. Optional metadata fields are as above. Spell count,
spell cooldown, unit identity and arbitrary provider fields are never exported.
No source or input table is mutated. `savedAt` is omitted if the injected time is
invalid/unavailable. Timer `endsAt` uses server seconds in the eventual export.
The plugin must label all disk data **saved snapshot** and show its age: writes
happen at reload/logout, so icons/page/countdown may lag current play.

`CooldownTracker.new()` creates a session-local item-ID-indexed tracker:

- `:observe(itemID, start, duration, now)` learns readable cooldown lengths over
  1.5 seconds and labels them `game`. GCD samples are ignored. `(0,0)` is an explicit
  ready sample and clears an active/unknown timer while retaining learning.
  Missing or invalid data does not erase an active timer. Future start times reject.
- `:useDetected(itemID, now)` starts a learned estimate only when ready; duplicate
  detections cannot extend a running timer. Unknown duration starts an unknown state.
- `:remaining(itemID, now)` returns seconds and `game`/`est`; ready/expired returns
  `0,nil`, unknown length returns `nil,"est"` (display **CD ?**). Invalid arguments
  return `nil,nil`. Unknown stays unknown until a readable cooldown/ready sample.
- `:clear(itemID)` deletes timer and learning. `:changeItem(oldID,newID)` clears
  oldID when changed, preserving independent newID state. The future adapter calls
  it only after the last reference to oldID is removed; multiple slots share a timer.

All tracker times use one injected clock; converting game uptime to server time
belongs to part 2. Item-use detection is a future adapter concern, never inferred
by this pure model from secret data. Spell cooldowns are unsupported.

## WoW skeleton and remaining work

`Init.lua` owns one event frame and a handler table. SavedVariables are initialized
only in this addon's `ADDON_LOADED`. Character layouts use
`SavedVariablesPerCharacter: StreonorDockCharDB`; the account export location will
be `StreonorDockDB.export`. A random opaque profile token avoids player names.
`/sdock help`, `/sdock probe`, `/sdock chords` and `/sdock export` describe the
skeleton. The probe checks availability only and never invokes uncertain APIs.
`Bindings.xml` defines next/previous/home entries without assigning keys; WoW loads
that conventional filename separately from the TOC. Pager callbacks update the pure
layout only. Protected maintenance closures queue to `PLAYER_REGEN_ENABLED`; combat
paging/edits are rejected, never queued. Panel/Secure/Export have TODO(part 2) markers.

Future live verification: load on build 1.60.1.70790, test pager bindings, relog
persistence, random token stability, metadata loading, override behavior, both
ActionButtonUseKeyDown settings, combat restrictions/taint, readable item cooldowns
and secret guards. Capability presence alone proves none of those behaviors.

If Interface changes from **16001**, retest the TOC Interface line, `Bindings.xml`
discovery, `Init.lua` event/lockdown/availability paths, secret-value behavior, and
every future C_Spell/C_Item or secure binding call before claiming support.

Do not deploy part 1 as a finished controller. On separate authorization use the
workspace `scripts\deploy.ps1 -Name StreonorDock`; the target here is
`G:\World of Warcraft\_forever_\Interface\AddOns\StreonorDock` (not the old beta
folder). Restart the client if a newly deployed addon folder does not appear.
