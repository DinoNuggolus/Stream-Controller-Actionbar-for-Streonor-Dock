# Embedded libraries

Copied unmodified from installed addons under `World of Warcraft\_forever_\Interface\AddOns` (versions as embedded):

| Library | Version | License |
|---|---|---|
| LibStub | r2 | Public domain (`LibStub/LICENSE.txt`) |
| CallbackHandler-1.0 | 8 | BSD (`CallbackHandler-1.0/LICENSE.txt`) |
| AceDB-3.0 | 39 | BSD, Ace3 (`LICENSE-Ace3-BSD.txt`) |
| AceDBOptions-3.0 | 17 | BSD, Ace3 |
| AceGUI-3.0 | 41 | BSD, Ace3 |
| AceConfig-3.0 (Registry 22, Dialog 93, Cmd) | - | BSD, Ace3 |
| LibSharedMedia-3.0 | 12000004 | LGPL v2.1 (see file header) |
| AceGUI-3.0-SharedMediaWidgets | - | see file headers |
| LibDataBroker-1.1 | 4 | Public domain / as in file |
| LibDBIcon-1.0 | 57 | see file header |
| LibCustomGlow-1.0 | 25 | MIT (`LibCustomGlow-1.0/LICENSE`) |
| LibUIDropDownMenu-4.0 | r135 | see file header (fallback menu only) |

Not embedded on purpose: AceAddon/AceEvent/AceConsole/AceHook/AceTimer/AceLocale (this addon uses one event
frame with a handler table and C_Timer, per the project rules), LibActionButton-1.0 (its action-bar slot and
state-driver model cannot give the one-press-one-use contract), LibKeyBound-1.0 (keys are fixed chords).
