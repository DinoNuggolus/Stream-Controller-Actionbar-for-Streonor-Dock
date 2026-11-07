# StreonorDock dev log

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
