# StreonorDock dev log

## 0.3.0 rebuild (2026-11-08): ui-spec V4 phases 1-4
Status: host-tested only; not yet verified in the game client. Older entries below are history of the
removed LCD/currency/timer design.

### Done
* Phase 1: removed readouts, currency, logging switches, press timers/estimates/learning, count/status export.
  AceDB-3.0 profile per character (schema 2), idempotent migration of the 0.2 data (slots/pages/profile id/
  current page/CENTER position kept; readouts, revision, settings, learned data archived under
  `StreonorDockCharDB.archive` and `StreonorDockDB.global.archive.account`). Minimal icon export schema 2.
* Phase 2: bar wrapper (single alpha owner: `ns.Bar.SetFadeAlpha`), header with padlock/cog, 5x3 controller
  layout (slot 1 bottom-left, right then up), Mirror/row/column/orientation/grow, scale/size/spacing/opacity,
  AceConfig settings (General, Bar [Layout, Appearance, empty Visibility placeholder], Buttons, Assignment,
  Controller, Profiles, Diagnostics, About), minimap button.
* Phase 3: assignment mode, overlay, drag/drop (cursor + internal swap/move/outside-clear), Spells/Items menu,
  reload popup, temporary reveal, combat pause.
* Phase 4: stack badge, charge badge, OmniCC-style cooldown, shared 10 Hz ticker, coalesced events.

### Decisions
* Libs: Ace3 event/timer/console/hook/locale NOT embedded (project rule: one event frame + C_Timer).
  LibActionButton-1.0 NOT used: its action-slot/state-driver model cannot give one-press-one-use; chord targets and
  bar buttons stay plain SecureActionButtonTemplate with `*type1` attributes and AnyDown + useOnKeyDown.
  LibKeyBound not used (fixed chords).
* Menus: native `MenuUtil.CreateContextMenu` first, LibUIDropDownMenu-4.0 fallback; chosen backend shown in
  Settings > Diagnostics once a menu was opened.
* Custom (non-Ace) elements: header padlock/cog glyphs (drawn from rectangles), dashed assignment frame, the
  drag icon. Everything else is AceConfig/AceGUI/LSM widgets. The spec's checkbox dropdown belongs to the
  Visibility engine and is not built here.
* Grayscale cooldown is approximated: the swipe texture is the icon tinted grey (true per-region desaturation is
  not available through the Cooldown widget). Verify the look in game.
* Minimap icon uses the client's `Interface\Icons\INV_Misc_Gear_01` by path (no art stored in the repo).

### Not built (by request)
Visibility-conditions engine, tutorial tips. `Bar.SetFadeAlpha(alpha)` is the hook; Settings > Bar > Visibility is
an empty placeholder page.

### In-game checklist (after /reload)
1. One press = one use: press each of a spell key and an item key once (also hold ~3 s): `/sdock clicks` must show
   down 1, up 0, attempts 1 per press; the action happens once. Try with the bar hidden and in combat.
2. Bar: centred; drag header; padlock; cog; `/sdock reset position`; Mirror layout slot order 1..5 bottom row.
3. Assignment: drag spell/item; click menu (Spells by tab, Items by class, stack counts); swap; drop outside to clear;
   Escape cancels drag; lock shows Reload/Cancel only if something changed; Cancel then relock = silent.
4. `/sdock spellprobe`: report General vs spec tab lines and whether passives/lower ranks look right.
5. Cooldown: use an item/spell with a cooldown out of and in combat; 89/90 s style thresholds; numbers; zero stack.
6. `/sdock probe`: note MenuUtil / Settings / StaticPopup availability.
7. Reload and check the plugin keys show the new icons (restart Streonor after deploying the plugin).


---

# StreonorDock dev log

## First-playtest export fix (2026-11-07)
- User evidence: the saved export had moneyCopper=0, freeBagSlots=0, and count=0 for
  Hearthstone, Refreshing Spring Water and Shiny Red Apple; iconFileID remained correct.
  PLAYER_LOGOUT called Export.Refresh during teardown and replaced the earlier good snapshot.
- Logout now only stamps savedAt/revision on the existing export. PLAYER_LEAVING_WORLD flushes
  a pending dirty rebuild once before setting the teardown flag. Generation checks invalidate
  queued debounce and entry callbacks; teardown blocks new dirty work until entering world.
- Collect avoids live data reads during teardown. Core's plausibility guard retains only
  allowlisted previous same-profile player values and item counts matched by identity when
  teardown is active or money/free-slots both read zero. Adds optional countsStale=true,
  schema still 1. Missing previous values stay omitted; normal zero counts remain valid.
  Simultaneous zero is a heuristic: broke + full bags also sets stale.
- PLAYER_ENTERING_WORLD schedules MarkDirty after 2 s (then the normal 1 s debounce), covering
  loaded counts even without BAG_UPDATE_DELAYED. /sdock export now prints the current in-memory
  summary without rebuilding; sealed values are never printed.
- Documentation checked: the supplied forever-ui-docs mirror exists;
  Interface/AddOns/Blizzard_APIDocumentationGenerated/SystemDocumentation.lua:145-148 lists
  PLAYER_LEAVING_WORLD and SynchronousEvent=true. It does NOT document bag validity/order versus
  teardown. Valid bag data at this boundary and the 2-3 s entry delay remain unverified in game.
- Regression RED: 62 tests / 3491 assertions / 7 failures (six new cases plus changed diagnostics
  expectation). GREEN including two additional edge cases: 64 tests / 3562 assertions / 0 failures.
- Staged check: after entry wait 3 s, /sdock export before /reload, compare counts with bags,
  then inspect saved file read-only. Repeat using an item then reloading inside the debounce;
  also test logout/zoning and stale-marker recovery. See README Stage 0 step 13.
- No staging, commits, deployment, game-folder or WTF changes made. Manager owns the commit.

## 2026-11-07
- Project created (original).

## Part 1 progress
- Read workspace rules, full approved design/amendments, review C and value restrictions.
- Core RED: 8 tests failed on missing Core. GREEN: 8 tests / 1298 assertions.
- Cooldown RED: 6 new tests failed on missing tracker (Core tests remained green).
- Owner already approved design and requested implementation; execute inline in this new repo.
- Keep all changes inside this repo; root workspace index update intentionally omitted.
- Ruling: unknown item cooldown returns nil seconds and est source until readable observation
  or ready sample. changeItem clears old timer and learning; adapter must avoid clearing an
  ID still referenced by another slot. Learning is session-local in part 1.

## Part 1 verification and handoff (2026-11-07)
- Completed Core.lua and Cooldown.lua plus thin Panel/Secure/Export/Init skeletons,
  TOC16001 and three pager bindings. Added MIT LICENSE (DinoNuggolus) and README contracts.
- Cooldown GREEN: 14 total tests / 1366 assertions / 0 failures.
- Adapter RED: four new tests failed on missing skeletons. Initial fake host then
  rejected missing SavedVariables globals and setmetatable; corrected the fixture's
  host environment (production code did not need changing for that failure).
- Final suite: 18 tests / 1427 assertions / 0 failures, run with
  C:\Program Files (x86)\Lua\5.1\lua.exe tests\run.lua from this repo root.
- All 11 Lua files pass C:\Program Files (x86)\Lua\5.1\luac.exe -p and the exact
  first-line namespace check. Bindings.xml parses with three pager entries.
- Fresh read-only reviewer independently reran suite and syntax checks: same results,
  no important defects. See README for remaining actual client tests.
- Ruling: previous/home already at page 1 succeeds without revision change;
  accepted assignments increment revision, next at page 10 rejects. Recovery fills
  sparse page holes and clamps selection. IDs are finite positive integers.
- Ruling: explicit readable (start=0,duration=0) means ready and clears a timer but
  retains learning; other duration <=1.5 samples are ignored as GCD. Unavailable
  observations retain active timers. Unknown duration stays CD ? until readable data.
- No game/client/API behavior verified. No secure actions, editor, bindings installed,
  metadata callbacks, runtime item observations or export refresh wiring implemented.
  Uncertain API names are availability probes only; no signature/behavior claim.
- Deviations: scope is deliberately part 1 as requested; parent workspace index left
  untouched to keep all work in the independent addon repo. Test-only host loading
  uses loadfile/setfenv, which never appears in TOC-loaded code.
- Next: part 2 only after capability tests on the real Forever client; preserve the
  secret boundary and current-slot identity checks when adding metadata callbacks.
- Nothing deployed, pushed or remotely created; no game/WTF/Streonor/other-project edits.


## Part 2 (2026-11-07): game-facing code, host-tested only
- Implemented Secure.lua, Panel.lua, Export.lua, Init.lua wiring; extended Core.lua (cursor
  normalization, forArea, identity/findSlots, itemReferenced/pageItems, secureAttributes,
  chordKey, sanitize, player export, `used` source) and rewrote Cooldown.lua for Amendments 2+3.
- Coordinator changes absorbed mid-task: Amendment 2 (press-activated timers), cooldown group
  table (CooldownData.lua, seed from StreonorWoW/docs/research/CooldownData.seed.lua copied
  unchanged below an 18-line header; no BOM), pool-label sharing, Amendment 3 (self-verifying
  table, cooldownLearned store, /sdock cooldowns), staged in-game checklist.
- Ruling (conflicting instructions): one message ordered "table before learned", another said
  "learned overrides the table"; Amendment 3 settles it: game > item override > group
  learned/verified > shipped table > base API > USED. Base API sits after the table.
- Ruling: a pool member's reading never clears/replaces the starter's running pool timer; it is
  sharing evidence only (and teaches its own length if it was our own press). Absent items are
  never read for evidence.
- Ruling: press time is recorded even when estimates are off or the key's timer is running, so
  a real use is still learned when the estimate was wrong.
- Ruling: game data proving a dormant (duration 0) table entry wrong overrides it (logged).
- Ruling: spells cast by name (highest known rank) unless dragged as a lower rank (pinned, ID);
  decided once at drop time via C_SpellBook rank APIs (BindPad's approach on this client).
- Ruling: overrides bound for all 15 chords even when a slot is empty (empty slot = no-op), so a
  chord never falls through to some other binding. isPriority=false.
- Result: 49 tests / 3177 assertions / 0 failures; luac -p clean on all 13 Lua files (7 addon, 6 test).
- Nothing deployed, pushed or remotely created. No game/WTF/Streonor edits.

### Unverified assumptions (part 2)
1. `SetOverrideBindingClick(owner,false,chord,"StreonorDockSlotN","LeftButton")` fires a hidden,
   unanchored SecureActionButtonTemplate button on this client (BindPad's zero-size buttons are
   the evidence; behavior with override bindings is untested).
2. `GetBindingAction(key, true)` returns the effective (override-aware) action; probe reports
   "not checkable"/mismatch if not.
3. Modern template filters clicks by `useOnKeyDown`; `AnyDown`/`AnyUp` + attribute = one
   activation per press (copied from BindPad). Default assumed key-down if the CVar is unreadable.
4. Plain `type`/`spell`/`item` attributes apply under ALT-CTRL-SHIFT modifiers (no modifier
   prefixed attributes needed).
5. `spell` attribute accepts a name (highest rank) or numeric ID (exact rank); `item="item:<id>"`
   uses the item (equippable items not equipped would be equipped instead).
6. `GetCursorInfo()` = `"spell", slot, book, spellID` / `"item", itemID, link`; spellbook
   fallback via `C_SpellBook.GetSpellBookItemType`; low-rank detection via
   `FindSpellBookSlotForSpell` + `IsSpellBookItemLowRank`.
7. `C_Item.GetItemCooldown` returns `(start, duration, enabled)` on the `GetTime()` clock;
   readability in combat unknown (docs carry no secret flag). `enabled==false/0` = paused.
8. `C_Item.GetItemCount`, `GetMoney`, `GetContainerNumFreeSlots` are plain in and out of combat.
9. `GetSpellBaseCooldown` (C_Spell or global) is absent from the Forever docs; if present its
   first return is treated as milliseconds.
10. `RegisterEvent` throws for unknown events (guarded with pcall either way).
11. `CooldownFrameTemplate`, `BackdropTemplate`, `UIPanelButtonTemplate`, `UIPanelCloseButton`,
    fonts `NumberFontNormalSmallGray`/`GameFontDisableSmall` exist (non-secure fallbacks used).
12. `GameTooltip:SetSpellByID/SetItemByID/IsOwned`, `C_Timer.NewTimer/After` exist (checked).
13. Own-use window 1 s, sharing window 0.5 s, GCD 1.5 s, pre-ack grace 1.5 s are adequate.
14. Every value in CooldownData.lua (Classic references, verified=false), especially pool sharing.
15. SavedVariables persistence on this build (beta was reported losing data before 70009).

### Next
- Run the staged in-game checklist in README.md (Stage 0 first), paste `/sdock probe` output here.
- If override bindings fail: stop (spec decision 5), no SetBinding fallback.
- Fold `/sdock cooldowns` output into CooldownData.lua after Stage 1/2 tests.

## Fix round (2026-11-07): code review + BindPad technique study
All 14 items applied (see commit 2c63dc5 and README). Notes and deviations:
- Item 2 / mutation: Secure.lua previously had two redundant combat guards (Request and applyAll),
  so deleting either alone could never fail a test. Now there is ONE guard, at the top of
  applyAll (Secure.Request = applyAll). Deleting it fails 2 tests; deleting the secret check in
  Export.ReadItemCooldown fails 2 tests. The fake host counts blocked attempts (no throw) and
  run.lua fails on any blocked attempt or addon "internal error".
- Item 1: probe evidence is `StreonorDockDB.probe = {build, combatReadable, sealedSeen}`; a sealed
  reading in combat sets false and blocks a later true on the same build.
- Item 3: estimates are skipped at press time when GetItemCooldown is plain out of combat; the
  panel timer now calls ObserveItems before redrawing.
- Item 4: `observe(itemID, start, duration, now, count)`; count 0 + ready/GCD reading is ignored.
- Item 9: re-apply after combat/SPELLS_CHANGED is now diff-based: attributes only where the plan
  changed, click direction only when the CVar value changed, overrides only when the last block
  was not 15/15 or GetBindingAction(key, true) no longer shows ours for every chord.
- Item 11: buttons come from Slots.xml (parentless). Secure.lua keeps a parentless CreateFrame
  fallback, used only out of combat, if an XML button is missing; probe reports the template.
- Item 12: Bindings.xml CLICK entries have an empty body; the addon never sets/saves bindings
  (a test greps all addon Lua for SetBinding(/SaveBindings( outside comments).
- Item 13: confirmed: CVAR_UPDATE handles both CVar names and PLAYER_REGEN_ENABLED re-runs Request.
- TOC BOM removed (tests now assert no BOM in TOC, Bindings.xml, Slots.xml and all Lua).
- Result: 56 tests / 3447 assertions / 0 failures; luac -p clean.

Assumption updates (replace items 1 and 4 above):
1. XML-declared, parentless SecureActionButtonTemplate buttons are fired by
   SetOverrideBindingClick on this client (BindPad proves the CLICK-binding path with SetBinding,
   not the override path: README Stage 0 step 7 is the A/B test).
4. `*type1`/`*spell1`/`*item1` match any modifier with the LeftButton binding click.
16. Bindings.xml `<Binding name="CLICK StreonorDockSlotN:LeftButton"></Binding>` (empty body)
    appears in the Key Bindings UI under its header.

## Login population (2026-11-07)
- Host login with uncached data and with a missed *_DATA_LOAD_RESULT: panel filled via events already. Added Export.RetryMetadata 3s/8s after PLAYER_ENTERING_WORLD as a safety net (66 tests). Unverified in game.
- SavedVariables reach disk only on /reload or logout, so the controller shows the previous save right after login.

## Client logging switches (2026-11-08)
- Init.lua applies LoggingChat/LoggingCombat once per session (guarded, pcall, read-back via C_ChatInfo when present);
  settings logChat/logCombat default true; `/sdock log`. Tests: 68 / 3680 assertions. Forever behavior unverified in game.

## Currency and money readouts (2026-11-08)
- Readout slots accept {kind="currency",currencyID} and {kind="money"} (Core.slot/forArea). Click a readout -> custom
  plain-frame picker (Panel.OpenPicker): Empty, Money, then Export.ListCurrencies() (C_CurrencyInfo list, headers
  skipped, discovered==false skipped, collapsed headers expanded then re-collapsed deepest first, never in combat).
- Export: currency {currencyID,name,iconFileID,quantity,maxQuantity?}, money {copper}; stale/teardown rebuilds reuse the previous
  quantity/name/icon (same rule as item counts). Events: CURRENCY_DISPLAY_UPDATE and PLAYER_MONEY refresh the panel and use the
  existing 1s debounce. PLAYER_REGEN_DISABLED closes the picker. Probe lists the four C_CurrencyInfo functions.
- Tests: tests/currency_spec.lua (fake C_CurrencyInfo in Host.lua). Unverified in game: the picker layout, ExpandCurrencyList behavior,
  whether Honor appears in the currency list on Forever.

## Spell cooldown timers (2026-11-08)
- Export.SpellBase/SpellTimer/ObserveSpell/OnSpellPress/MaxCharges, Secure postClick spell branch, `/sdock cdprobe`;
  Tracker precedence is now learned > group learned > dormant > game base > shipped table. Export field `cooldownSource`
  gains base/category and `verified` is now a boolean (was source "verified"). 81 tests. Units/returns of
  GetSpellBaseCooldown on Forever unverified (not in the API mirror).

## One press = one use (2026-11-08)
- Secure.lua: AnyDown only + useOnKeyDown=true always; PreClick/PostClick edge counters, OOC up-edge neutralisation; `/sdock clicks`.
  Host.lua gained a click simulator (h.click, h.uses, ignoreRegistration, templateIgnoresEdge); fake frames no longer return
  noop for missing lowercase fields. 84 tests. Root cause of the in-game double attempt not proven (needs the user's /sdock clicks).
