# PADChat

**PADChat** is a World of Warcraft addon that brings quick-chat to gamepad and controller players. Inspired by the Voice Game System (VGS) from Tribes 2, it lets you send tactical callouts, group readiness checks, and social emotes in seconds, without touching a keyboard.

---

## Why?

I've played World of Warcraft with a controller for many years, and communicating with other players has always been the biggest drawback. Now that World of Warcraft: Forever supports controllers, more people are playing this way, and this addon is my attempt to ease that frustration. I hope it helps you!

## Features

- **Button combos:** Navigate chat menus up to 4 presses deep using the face buttons (**A / X / Y** or **Cross / Square / Triangle**).
- **Context tabs:** Tap **LB / RB** (bumpers) to switch between **Whisper**, **Say**, **Group**, and **Battleground** channels. Say is always the tab you start on.
- **Whispers:** The Whisper tab sends your Say messages privately. A list of your online **Recent Allies** (people you've grouped, traded or whispered with), most recent first, appears beside the overlay; pick one with **D-pad Up / Down**.
- **Looking For Group integration:** Select a group or player in the Looking For Group window and press **Y** to whisper them with quick chat. A **Y** prompt appears beside **Send Message**. In the window's **Who** tab, move the cursor onto a player and press **Y**; the row shows the **Y** prompt. Turn both off under **Settings → Integrations → Enhance LFG Window**.
- **Recent Allies integration:** Move the cursor onto an online ally in the Recent Allies window and press **Y** to whisper them with quick chat. The ally's tooltip shows the **Y** prompt. Turn it off under **Settings → Integrations → Enhance Recent Allies Window**.
- **Built-in editor:** Customize messages, categories, emotes, and `{location}` placeholders from the minimap button.
- **Normal and compact modes:** Pick the overlay size that suits your UI.

## Screenshots

**Normal mode**

![Normal mode](https://media.forgecdn.net/attachments/description/null/description_5517e305-2c61-48c4-aaf9-3c2cec566149.png)

**Compact mode**

![Compact mode](https://media.forgecdn.net/attachments/description/null/description_43fcd6cc-57be-48e1-bf3c-515f01e9f937.png)

**Settings and customization**

![Settings](https://media.forgecdn.net/attachments/description/null/description_86a4cfd7-1ea3-4a2d-9725-4ff35cdfa012.png)

## Installation

1. Download the latest release (or clone this repository).
2. Place the `PADChat` folder in your WoW AddOns directory, for example:
   `World of Warcraft/_classic_/Interface/AddOns/PADChat`
3. Restart the game or run `/reload`, then make sure **PAD Chat** is enabled in the AddOns list.

## Getting started

1. Place the generated **`PADChat`** macro on any action bar slot bound to your controller.
2. Press the macro in-game to open the quick-chat overlay.
3. Click the minimap button at any time to open the editor and tailor your callouts to your playstyle.

## Default controls

| Button | Action |
| --- | --- |
| **Action bar macro (`PADChat`)** | Open quick chat |
| **A / X / Y** *(Cross / Square / Triangle)* | Select a category or message |
| **B** *(Circle)* | Cancel / close the menu |
| **LB / RB** *(left / right bumper)* | Switch tabs (Whisper / Say / Group / BG) |
| **D-pad Up / Down** *(Whisper tab only)* | Choose who to whisper |
| **Y** *(Looking For Group window, listing selected)* | Whisper that listing's leader |
| **Y** *(Looking For Group Who tab, on a player)* | Whisper that player |
| **Y** *(Recent Allies window, on an online ally)* | Whisper that ally |

## Project layout

| File | Purpose |
| --- | --- |
| `PADChat.toc` | Addon manifest |
| `PADChat.lua` | Core overlay, input handling, and chat sending |
| `Messages.lua` | Default message tree |
| `Integrations.lua` | Looking For Group and Recent Allies window enhancements |
| `Editor.lua` | In-game message and settings editor |
| `MinimapButton.lua` | Minimap button |
| `Media/` | Icon and logo assets |
| `tests/` | Tests |

## Coming soon

Location-based callouts in Battlegrounds (for example, "Incoming Mine!" or "Incoming BS!"). I'll release this once Battlegrounds are in-game and I can test it.

## Contributing

Issues, suggestions, and pull requests are welcome. Fork it, change it, and make it your own.

## License

PADChat is released under the [MIT License](LICENSE). You're free to use, copy, modify, merge, publish, distribute, sublicense, and sell copies of it, as long as the copyright notice and license text are kept with it.

World of Warcraft is a trademark of Blizzard Entertainment, Inc. This project is not affiliated with or endorsed by Blizzard Entertainment.
