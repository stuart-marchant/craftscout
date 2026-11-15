# CraftScout

A profession helper for **WoW Forever**. One window, one tab per profession, showing:

- **Craft now**: recipes you know that still give skill-ups and that you have the mats for, with how many you can make.
- **Skill-ups, missing mats**: the same, but what you're short on.
- **Trainers (next rank)**: when your next rank (Journeyman / Expert / Artisan) is due, and the nearest trainers for your faction. Click one to set a waypoint.
- **Learn now**: recipes you don't know yet that you can already learn and that would give skill-ups, with where to get them (nearest trainer or vendor, drop, quest...). Click to set a waypoint.
- **Coming up**: recipes that unlock in the next few skill points.
- **Disenchant tooltips** (Enchanters): what an item disenchants into, which results your skill-ups need, and a **sell or disenchant** suggestion.

Recipe names are colored by skill-up chance: orange, yellow, green.

## Install

1. Download the repository (**Code → Download ZIP**, or `git clone`).
2. Put it in your AddOns folder **as a folder named `CraftScout`**. WoW only loads it if the folder name matches `CraftScout.toc`.
   - Windows: `World of Warcraft\_forever_\Interface\AddOns\CraftScout\`
   - macOS: `/Applications/World of Warcraft/_forever_/Interface/AddOns/CraftScout/`

   If you downloaded a ZIP, rename the extracted `craftscout-main` folder to `CraftScout`.
3. Restart the game client fully. A `/reload` is not enough for a newly added addon.

### Recommended addons

| Addon | Why |
|---|---|
| **Questie** | NPC names, titles, locations and factions. Without it CraftScout can't place trainers and vendors on the map, so the trainer list and the "where" lines will be mostly empty. |
| **TomTom** | Clicking a trainer or vendor sets a TomTom waypoint. Without it you get a pin on the world map. |
| Auctionator (optional) | When none of your skill-ups need an item's disenchant results, CraftScout compares their auction value with the vendor price. |

## First-time setup (important)

The game only tells addons about your recipes and trainers at certain moments, so CraftScout needs a few things from you.

1. **Open each profession window once** (Tailoring, Enchanting...). This is how CraftScout learns which recipes you know. Until you do, that tab shows a red note asking you to. After that, recipes you learn are added automatically. Opening the window again re-checks everything.
2. **Talk to trainers.** CraftScout first guesses which rank a trainer teaches from their title (for example "Expert Tailor"), shown as `(Expert?)` with a question mark. When you open a trainer's window, it records what they really teach. From then on that trainer is shown as confirmed, without the `?`. `/craftscout trainers` lists the trainers you've recorded.
3. **Open your bank once per session** if you want bank items counted as available mats. The game only reports bank contents after the bank has been opened. This can be turned off in the options.

## Using it

- `/craftscout` (or `/cscout`): show or hide the window. You can also left-click **CraftScout** in the addon menu by the minimap; right-clicking it opens the options.
- Click a profession tab to switch. Click a section title to collapse it.
- **Hover** a recipe to see its reagents (have / need), its skill-up thresholds, and every known source.
- **Click** a trainer, or a recipe in "Learn now", to set a waypoint to the nearest one for your faction.
- Drag the title bar to move the window and the bottom-right corner to resize it.

Other commands: `/craftscout config` (options), `/craftscout scan` (re-read the open profession window), `/craftscout trainers`, `/craftscout resetui`.

### Disenchant tooltips

On characters with Enchanting, green, blue and purple weapons and armor get a section like:

```
Disenchant (item level 33)
  75%  2-5 x Soul Dust  needed
  20%  1-2 x Lesser Mystic Essence
  5%   1 x Small Glowing Shard
Disenchant: Soul Dust for Enchant Bracer - Stamina (+3 more)
```

- **needed** (green): one of your known skill-up recipes uses this mat and you're short on it. **used**: you already have enough for at least one craft.
- **Disenchant** is suggested when a likely result (20%+, or a blue's guaranteed shard) is a mat your skill-ups use.
- Otherwise it suggests **Sell** and shows the vendor price.
- Lesser and greater essences count for each other, since they convert 3:1.

## Options

Esc → Options → AddOns → **CraftScout**: window lock and opacity, count bank items, hide opposite-faction NPCs, which sections to show, drop-only recipes, how far ahead "Coming up" looks, rows per section, and the disenchant tooltip and suggestion.

Window and option settings are shared across your characters. Known recipes are saved per character.

## How accurate is it?

WoW Forever is new and its data isn't fully documented yet. CraftScout says when something is a guess:

- **Rank rules** use Classic's: Journeyman at 50 skill and level 10, Expert at 125 and level 20, Artisan at 200 and level 35. They aren't confirmed for Forever.
- **Recipe sources and some skill requirements** come from LibProfessionDB. Where nothing Forever-specific exists, the library uses Classic data, and the tooltip notes that the source is unconfirmed.
- **Trainer ranks** are guesses from their titles until you visit them (see setup above).
- **Disenchant results**: which item levels give which mats comes from the Forever game files. The percentages and quantities are Classic numbers. The Enchanting skill needed to disenchant each item level also uses Classic rules.

If something looks wrong, a report with the recipe or item name and what the trainer or tooltip actually showed in game is very helpful.

## Troubleshooting

- **The window doesn't appear:** type `/craftscout`. If it was closed with the X button, it stays hidden until you show it again.
- **A tab says to open the profession window:** open that profession's window once (see setup above).
- **Trainer list or "where" lines are empty:** install or enable Questie and give it a few seconds after login.
- **Errors:** CraftScout records them instead of popping up error windows. They're saved in your character's `SavedVariables/CraftScout.lua` (inside `WTF/Account/<account>/.../<character>/`) under `errors`, written when you `/reload` or log out. That file is useful to include in a bug report.

## Credits and licenses

CraftScout is MIT licensed (see `LICENSE`). Bundled data and libraries:

- **LibProfessionDB-1.0**, MIT, © 2026 Pimptasty: WoW Forever recipe data.
- **DisenchantForever** data, MIT, © 2026 APGM82: Forever disenchant brackets. [github.com/APGM82/DisenchantForever](https://github.com/APGM82/DisenchantForever)
- **LibStub**, public domain.

See `NOTICE.md` and the `LICENSE` files in `Libs/` for details.
