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

