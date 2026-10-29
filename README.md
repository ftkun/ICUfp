# ICUfp — I See You (forward port)

World of Warcraft forever addon for Hunters (and Druids in Cat Form). Click a tracking blip on the minimap to identify the unit, target it, mark it, ping it, or announce it to chat.

Forward port of the original **ICU** addon by Jebji (Dwarf Hunter, Blackrock, 2005), later modded by Sorren of Bleeding Hollow. Port by Ftkun, 2026.

- Interface: `16001`
- Version: 2.0.01 (alpha)

## Features

- Click a minimap blip: popup listing the units under the cursor (out of combat), or announce only (in combat)
- Configurable popup row actions per mouse button / key + modifiers: target, focus, raid mark, announce, ping
- Announce channels: Auto, Party, Raid, Say, Yell, Self
- Text templates with `[tag]` syntax: `[name] [level] [race] [class] <[guild]> [[hp%]]`, plus `rank`, `reaction`, `type`, `family`, `power`, `target` and more
- Popup styling via LibSharedMedia: bar/background/border textures, font, size, opacity, class/reaction/custom bar colors, portraits
- Anchor the popup to a minimap corner/side, the cursor, or a free position
- Close behavior: timer, Esc, click outside, custom binding

## Installation

Copy the `ICUfp` folder into:

```
World of Warcraft\_classic_\Interface\AddOns\
```

## Commands

| Command | Effect |
|---|---|
| `/icu` | Open the options window |
| `/icu config` | Open the Blizzard options panel |
| `/icu announce <auto\|party\|raid\|say\|yell\|self>` | Toggle a chat channel |
| `/icu anchor <top\|topleft\|topright\|bottom\|bottomleft\|bottomright\|left\|right\|cursor\|free>` | Set popup anchor |
| `/icu debug` | Toggle debug output |

Default bindings: click blip = popup; Ctrl-click minimap = ping; right-click = close popup.

## Bundled libraries

Embedded in `libs/` and loaded via `embeds.xml`:

- [Ace3](https://www.wowace.com/projects/ace3): LibStub, CallbackHandler-1.0, AceGUI-3.0, AceConfig-3.0 (Cmd, Dialog, Registry)
- [LibSharedMedia-3.0](https://www.wowace.com/projects/libsharedmedia-3-0)
- [AceGUI-3.0-SharedMediaWidgets](https://www.wowace.com/projects/ace-gui-3-0-shared-media-widgets)

Each library is the work of its respective authors and remains under its own license.

## License

ICUfp is released under the **GNU General Public License v2.0** (GPL-2.0). See <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>.

Bundled libraries in `libs/` are excluded from this license and keep their original licenses.

## Credits

Forward port developed with assistance from Claude (Anthropic).
