# StreonorDock

Original WoW: Forever addon by DinoNuggolus, MIT licensed. Gives a character 15 controller keys
(fixed `ALT-CTRL-SHIFT-` chords) and 3 item readouts per page, up to 10 manual pages, and
writes a sanitized **saved snapshot** for a future Streonor S15 companion plugin.

**Status (part 2): built and unit-tested on the host only. Nothing has run in the game yet.**
All in-game behavior (secure clicks, override bindings, secret values, cooldown readability,
drag payloads) is unverified until the staged checklist below is done. Nothing is deployed.

Chords: slot N = `ALT-CTRL-SHIFT-` + `1 2 3 4 5 6 7 8 9 0 - = [ ] \` (N = 1..15, row-major,
3 columns x 5 rows = device keys). Pager keys (next/previous/home) are set by you in
Game Menu > Key Bindings > StreonorDock.

## Commands

| Command | Does |
|---|---|
| `/sdock` or `/sdock help` | Help |
| `/sdock toggle` | Show/hide the editor (allowed in combat; editing is not) |
| `/sdock page next\|prev\|home` | Paging (out of combat only; page 10 is the limit) |
| `/sdock chords` | Each chord, its slot, ordinary binding, effective mapping, conflicts |
| `/sdock probe` | Capability presence, build, CVar, secure/override state, cooldown readability stats, table groups you hold (table vs observed) |
| `/sdock cooldowns` | Learned cooldown data, pool sharing evidence, mismatch/conflict log |
| `/sdock estimates on\|off\|auto` | Press-started timer estimates (auto = off once a readable item cooldown is seen in combat) |
| `/sdock export` | Rebuild the snapshot now; it reaches disk only at `/reload` or logout |

Editor: drag a spell (spellbook) or bag item onto a key; readouts take bag items only. Right-click
clears (editor widgets are plain buttons and never cast). Edits and paging are rejected in combat
with a chat message, never queued.

## File map

| File | Role | WoW calls |
|---|---|---|
| `StreonorDock.toc` | Interface 16001, load order, SavedVariables | - |
| `Bindings.xml` | Next/previous/home key bindings (header StreonorDock) and 15 diagnostic `CLICK StreonorDockSlotN:LeftButton` entries (header "StreonorDock slots") | - |
| `Slots.xml` | Declares the 15 secure buttons `StreonorDockSlot1..15` (no parent, size or anchor), so they exist even after a `/reload` in combat | load time |
| `Core.lua` | Pure layout model, pages, export builder, cursor normalization, slot identity, secure attribute plans, sanitizer | none |
| `CooldownData.lua` | Shipped cooldown reference table (research seed, all `verified=false`) | none |
| `Cooldown.lua` | Pure item timer model: pool/group/item keys, press timers, own-use learning, sharing evidence | none |
| `Panel.lua` | Editor frame (BackdropTemplate), 15 key + 3 readout widgets, pager buttons, cooldown widgets | UI only |
| `Secure.lua` | Configures the XML buttons: click direction, `*type1`/`*spell1`/`*item1` attributes (diffed, stale ones cleared), override bindings, conflict report | protected, out of combat only |
| `Export.lua` | Every game read (guarded by `issecretvalue`), cooldown reconciliation, snapshot write | reads |
| `Init.lua` | One event frame + handler table, SavedVariables init, edit/page entry points, `/sdock` | events |

Tests: `tests/run.lua` (Assert, Host fake client, core/cooldown/adapter specs).

## Data contracts

SavedVariables:
- `StreonorDockCharDB` (per character): `{profileId, revision, currentPage, pages[1..10]}`;
  each page `slots[1..15]`, `readouts[1..3]`. Spell slots may carry `pinned=true` (low rank
  dragged: cast by spell ID; otherwise cast by name, which casts the highest known rank).
- `StreonorDockDB` (account): `export`, `ui` (panel position/shown), `settings.estimates`,
  `probe.combatReadable`, `cooldownLearned = {build, items, groups, pools}`.

Snapshot `StreonorDockDB.export`, schema 1:
`{schema=1, profileId, revision, savedAt, page={index,count}, slots[1..15], readouts[1..3], player?}`.
Empty = `{kind="empty"}`. Keys add `id, chord`; readouts add `itemID`. Optional: `name`,
`iconFileID`, items `count`, `source` (`game`/`est`/`used`) and `endsAt` (server seconds).
`player = {moneyCopper, freeBagSlots}` when readable. No character/realm names, no spell
cooldowns, no secret values; unavailable fields are omitted, never kept stale. Rebuilt on login,
page change, edit, logout and (coalesced, 1 s) bag/money/cooldown events. **Consumers must label
it "saved snapshot" and show its age**: disk writes happen only at `/reload`/logout.

## Item cooldowns (Amendments 2 and 3)

- Timers are absolute and keyed by **pool label** (`shared` in `CooldownData.lua`: every group
  with the same label shares one timer), else by group key, else by item ID. Any slot on any page
  showing a member shows the same timer; paging never resets it.
- A key slot press (our secure button's `PostClick`, works in combat) starts a timer if: estimates
  enabled, bag count is a plain number > 0, nothing running for that key, not dormant, and the game
  reading is not plain out of combat (then the game reports the real cooldown itself). `PostClick`
  means **a press, not proof of a use**: the use can fail (out of range, already locked); the timer
  is an estimate until readable game data reconciles it. A plain ready/GCD-only reading after a
  1.5 s grace clears an estimate or USED marker; a "ready" reading from an item with bag count 0 is
  ignored (the last potion's lock is still real).
- Auto estimates (`/sdock estimates auto`) turn off only after a readable ACTIVE item cooldown
  (> 1.5 s) is seen in combat on this client build with no sealed reading; sealed evidence wins;
  the evidence resets when the client build changes.
- Duration precedence: live game data > item override > group learned/verified value > shipped
  table value (`0` = no use cooldown, dormant; `nil` = unknown) > base-cooldown API (only if
  present) > unknown, shown as `USED <elapsed>` instead of a made-up countdown.
- Learning only from the item's **own** use: readable `C_Item.GetItemCooldown` whose start is within
  1 s of our recorded press. Match (1 s) verifies the whole group for this build; mismatch stores a
  group override; disagreement with an already verified group splits that item out (logged). A lock
  imposed by another item never teaches. Another held pool member showing the same start (0.5 s)
  records `sharedVerified`; a held member staying ready records "not shared" evidence.
- Client build change keeps learned data but marks it unverified. The addon never rewrites
  `CooldownData.lua`; fold `/sdock cooldowns` output into the next release by hand.
- Out of scope for v1 (documented only): cross-lockouts outside this pool model, for example
  Goblin Sapper Charge vs grenades/dynamite and Invisibility Potion vs ordinary potions.
- Spell cooldowns are never read or shown (sealed on this client family).

## Verification on the host

From `G:\WoWFOREVER_ADDONS\StreonorDock` in PowerShell:

```powershell
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\run.lua
Get-ChildItem -Recurse -Filter *.lua | ForEach-Object {
    & 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Syntax failed: $($_.FullName)" }
}
```

The fake host models protected operations (secure attributes, click registration, scripts,
show/hide/points on secure frames, secure frame creation, override bindings) as BLOCKED in combat:
ignored and counted, not thrown, so the addon's own `pcall`/`ns.Safe` cannot hide an attempt.
`tests\run.lua` fails any test whose fake host recorded a blocked attempt or printed an addon
"internal error". Mutation check (2026-11-07): deleting the single combat guard in
`Secure.lua` `applyAll` fails 2 tests; deleting the secret check in `Export.ReadItemCooldown`
fails 2 tests. This covers only the paths the tests drive; it does not prove the real client
behaves like the fake.

## In-game checklist (staged by what the character has)

Deploy only with `..\scripts\deploy.ps1 -Name StreonorDock` to
`G:\World of Warcraft\_forever_\Interface\AddOns\StreonorDock\`; restart the client if the folder
is new. Keep `/console scriptErrors 1` on. Record results in NOTES.md.

### Stage 0: fresh level-1 character (starter spells, starter food/water only)
1. Log in: no Lua errors; `/sdock` prints help.
2. `/sdock probe`: copy the output into NOTES.md (presence list, build/interface 16001,
   `ActionButtonUseKeyDown`, `secure buttons: created`, `overrides: applied (15/15)`, effective lookup
   `15/15` or "not checkable", events not registered, `cooldown table: 0 group(s)`).
3. `/sdock toggle`: panel opens, drags, stays on screen, position survives `/reload`.
4. Drag a starter spell onto key 1 and starter food onto key 2: icons appear (may be `?` briefly).
   Drag a macro or money: rejected, cursor still held. Drag the spell onto a readout: "readouts accept
   bag items only". Drag food onto readout 1: icon + count.
5. Press `ALT-CTRL-SHIFT-1` and `-2` with the panel shown, then hidden: each press casts/uses once.
   Repeat with the whole UI hidden (Alt+Z). Switch Interface > Combat > "Cast action keybinds on key
   down" (ActionButtonUseKeyDown) and repeat: still exactly one activation per press.
   Warning: `/click StreonorDockSlot1` sends an UP click, so it looks broken while key-down is on;
   test with the chord, not `/click`.
6. Keys 11 and 15 use `-` and `\`: `/dump GetBindingAction("ALT-CTRL-SHIFT--", true)` and
   `/dump GetBindingAction("ALT-CTRL-SHIFT-\\", true)` must print `CLICK StreonorDockSlot11:LeftButton`
   / `...Slot15...`, and both chords must fire.
7. A/B binding test: in Key Bindings > "StreonorDock slots (diagnostic)" bind a spare key (e.g. F6) to
   Slot 1. If F6 fires slot 1 but `ALT-CTRL-SHIFT-1` does not, the override path is to blame (report
   it; there is deliberately no SetBinding fallback). Unbind F6 afterwards.
8. Self-cast check: target a friendly player/NPC, put a heal on a key and press its chord (the chord
   holds ALT): note who is healed. If ALT self-casts, record it (the chord modifiers are part of the
   design; the attributes are `*`-prefixed so modifiers do not change which action fires).
9. `/sdock chords`: every effective mapping says `ours`; note any CONFLICT (BindPad, other addons).
10. Paging: next creates empty page 2, home returns with key 1/2 intact, prev at page 1 stays,
   next ten times stops at page 10 with "maximum of 10 pages reached". Bind the three pager keys in
   Key Bindings > StreonorDock and repeat with the keys.
11. Combat (hit a training dummy/mob): drag/right-click/pager -> "editing/paging unavailable in combat",
   state unchanged; keys still fire; panel can still be toggled. After combat no errors.
12. Right-click a filled key: slot clears and nothing is cast/used; the chord then does nothing.
13. `/reload`, then read `WTF\...\SavedVariables\StreonorDock.lua` (read only): `export.schema=1`,
    `profileId` random, no names, `slots[1]` spell with chord, page `{index,count}`, `savedAt`.

### Stage 1: first potions or other cooldown items
1. Put a potion on a key and the same potion on readout 1. Out of combat press the key: readout
   shows the cooldown with no `est`; `/sdock cooldowns` shows the group verified or a mismatch.
2. In combat, before and after drinking:
   `/run local s,d=C_Item.GetItemCooldown(118) print(issecretvalue(s),issecretvalue(d))`
   (prints only true/false). Then `/sdock probe` "readable in combat": true or false. If true,
   estimates auto-turn off (expected); if false, the timer shows `est`, then corrects after combat.
3. In combat, check the cooldown starts immediately when you drink (not paused until combat ends):
   the readout swipe starts at once and `/dump C_Item.GetItemCooldown(118)` shows a non-zero start.
4. Sharing evidence is only recorded for a press **through a dock key** while another potion of the
   same pool is **in your bags**: hold health and mana potions, press the health potion's key, then
   `/sdock cooldowns` should report "pool potion: shared lock seen" (or not-shared evidence).
5. Use your last potion of a kind: the pool timer must keep running (the empty item cannot clear it)
   and `/dump C_Item.GetItemCooldown(<other potion id>)` should still show the lock.
6. Start a cooldown, page away and back: same remaining time on every slot showing that item/pool.
7. Item with unknown length (not in the table) pressed in combat with sealed data: shows
   `USED <elapsed>` until a readable reading arrives (out of combat it shows the game cooldown or nothing).

### Stage 2: sappers, bombs, Jujus, Healthstones, runes (research verification)
1. Use a health potion; `/dump C_Item.GetItemCooldown(13444)` and the protection/Healthstone IDs.
   Repeat Healthstone vs rune.
2. Sapper then grenade, and grenade then sapper, from ready states: inspect 10646, 15993, 18641
   immediately and after 60 s.
3. Use an Invisibility Potion and inspect ordinary potions; then use two different Juju items.
   Record durations and cross-lockouts separately (cross-lockouts are not modelled in v1).

## Retest if the TOC Interface moves off 16001
- `StreonorDock.toc` `## Interface` line; `Bindings.xml` discovery, both headers and the CLICK
  entries; `Slots.xml` secure button creation.
- `Init.lua`: every event name in the handler table (probe lists unregistered ones), CVAR_UPDATE
  payload, `GetBuildInfo`, `WOW_PROJECT_ID`.
- `Secure.lua`: `SecureActionButtonTemplate`, `useOnKeyDown` / `RegisterForClicks`,
  `SetOverrideBindingClick`, `ClearOverrideBindings`, `GetBindingAction(key, true)`, PostClick.
- `Panel.lua`: `GetCursorInfo` payloads, `ClearCursor`, `BackdropTemplate`, `CooldownFrameTemplate`
  `SetCooldown`/`Clear`, `GameTooltip:SetSpellByID/SetItemByID`, `C_Timer.NewTimer`.
- `Export.lua`: `issecretvalue`, `C_Spell.GetSpellInfo/GetSpellTexture/RequestLoadSpellData`,
  `C_Item.GetItemIconByID/GetItemNameByID/GetItemInfo/RequestLoadItemDataByID/GetItemCount/
  GetItemCooldown/GetItemSpell`, `C_SpellBook` rank functions, `C_Container.GetContainerNumFreeSlots`,
  `GetMoney`, `GetServerTime`, `GetTime`, any base-cooldown API.
- `CooldownData.lua`: every value (a build change already unverifies learned data).

## Unverified assumptions
See NOTES.md, "Unverified assumptions (part 2)". Every one is a reason to run the checklist.
