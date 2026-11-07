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

