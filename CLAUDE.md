# StreonorDock

- type: original
- status: part 1 implemented and host-tested; no deployment or in-game verification
- Author: DinoNuggolus; license: MIT
- TOC Interface: 16001
- SavedVariables: StreonorDockDB (account snapshot), StreonorDockCharDB (per-character layout)
- Slash: /sdock help, /sdock probe; editor/actions/export deferred to part 2

## Goal
Own a character's 15 controller key slots and 3 item readouts per page, with a
sanitized saved snapshot for a future Streonor companion. This repo currently
implements pure logic and thin loadable scaffolding only.

## Authority and decisions
Read ../CLAUDE.md and ../docs/forever-addon-rules/SystemPrompt.md.
Approved design: ../StreonorWoW/docs/specs/2026-11-07-streonordock-design.md;
its final amendments override earlier text. Part 1 scope comes from the owner's task.
Lua 5.1, namespace first in every Lua file, no libraries or WoW globals in Core/Cooldown.
Ten manual out-of-combat pages, fixed ALT-CTRL-SHIFT chords, no character names exported.
Three empty item-only readouts by default. Unknown cooldown = nil seconds / est source.
No spell cooldowns, secure snippets, persistent bindings, combat log or gameplay automation.

## Workflow
Source: src/StreonorDock/. Tests: tests/run.lua using the installed Lua 5.1 interpreter.
Commit locally. Do not push, create remotes, touch other projects/game/WTF/Streonor, or deploy
without a separate instruction. Future deployment uses ../scripts/deploy.ps1 only.
Update NOTES.md before handing off. See README.md for contracts and verification.
