# StreonorDock

- type: original
- status: part 2 implemented and host-tested (56 tests, fix round applied); NOT deployed, NOT verified in game
- Author: DinoNuggolus; license: MIT
- TOC Interface: 16001
- SavedVariables: StreonorDockDB (account: export, ui, settings, probe, cooldownLearned), StreonorDockCharDB (per-character layout)
- Slash: /sdock help | toggle | page | chords | probe | cooldowns | estimates | export

## Goal
Own a character's 15 controller key slots and 3 item readouts per page, with a
sanitized saved snapshot for a future Streonor companion. This repo currently
implements the full v1 addon (editor, secure keys, overrides, cooldown timers, snapshot);
none of it has run in the game yet. See README.md for the staged in-game checklist.

## Authority and decisions
Read ../CLAUDE.md and ../docs/forever-addon-rules/SystemPrompt.md.
Approved design: ../StreonorWoW/docs/specs/2026-11-07-streonordock-design.md;
its amendments (1-3) override earlier text.
Lua 5.1, namespace first in every Lua file, no libraries or WoW globals in Core/Cooldown.
Ten manual out-of-combat pages, fixed ALT-CTRL-SHIFT chords, no character names exported.
Three empty item-only readouts by default. Item cooldowns: Amendments 2+3 (press timers,
pooled table in CooldownData.lua, self-verifying learning); unknown length shows USED.
No spell cooldowns, secure snippets, persistent bindings, combat log or gameplay automation.

## Workflow
Source: src/StreonorDock/. Tests: tests/run.lua using the installed Lua 5.1 interpreter.
Commit locally. Do not push, create remotes, touch other projects/game/WTF/Streonor, or deploy
without a separate instruction. Future deployment uses ../scripts/deploy.ps1 only.
Update NOTES.md before handing off. See README.md for contracts and verification.
