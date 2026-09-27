# BossLoot Design

**Date:** 2026-09-26
**Status:** design approved in conversation; this written spec awaits review

## Purpose

See what every Classic dungeon and raid drops, while planning where to go.

BossLoot is a browsing reference, opened from a slash command or a minimap
button, like AtlasLoot. It lists every dungeon and raid, every boss in each,
and each boss's loot with drop chances. It also lists the valuable things in
an instance that no boss drops: rare trash drops, recipes, quest starters,
keys, and chest contents.

It is not an in-dungeon helper. It does not open by itself when you zone in,
track what you have looted, or keep a wishlist. Any of those can come later
without changing the design below.

## The constraint everything else follows from

**The client has no loot data to give.** The 1.60 client carries the modern
Encounter Journal API, but it is empty: probed in game, `EJ_GetNumTiers()`
returns 0 and no instance comes back from `EJ_GetInstanceByIndex`. There is no
other API that answers "what does this boss drop".

So BossLoot ships its own database, generated offline from an open-source
vanilla world database and checked into the addon as Lua data files.

The client still does what it is good at: turning an item ID into a name,
icon, quality colour and tooltip, in the player's own language. The data
files carry IDs and numbers, never item names.

## Where the data comes from

**vMaNGOS**, an open-source vanilla server, publishes its full world database
as a SQLite file (`db-sqlite-<commit>.zip`, about 42 MB, release tag
`db_latest` on github.com/vmangos/core). The snapshot used while designing
this is `db-sqlite-13b49dc.zip`, dated 2026-09-06.

The tables that matter, with the columns BossLoot reads:

| Table | Used for | Key columns |
|---|---|---|
| `map_template` | Which maps are instances | `entry`, `map_type` (1 dungeon, 2 raid), `map_name` |
| `creature` | What is spawned on each map | `id`, `map`, `patch_min`, `patch_max` |
| `creature_template` | A creature's name and loot table | `entry`, `patch`, `name`, `loot_id` |
| `creature_loot_template` | What a creature drops | `entry`, `item`, `ChanceOrQuestChance`, `groupid`, `mincountOrRef`, `patch_min`, `patch_max` |
| `reference_loot_template` | Loot shared between creatures | same columns as above |
| `gameobject`, `gameobject_template` | Chests and other lootable objects on each map | `id`, `map`; `entry`, `type`, `name`, `data1` (loot ID) |
| `gameobject_loot_template` | What an object contains | same columns as creature loot |
| `item_template` | Deciding what counts as notable | `entry`, `patch`, `quality`, `class`, `start_quest` |

Every table is versioned by patch. BossLoot targets the final vanilla patch,
1.12 (patch `10` in vMaNGOS numbering): rows are kept where
`patch_min <= 10 <= patch_max`, and for templates with a `patch` column, the
row with the highest `patch` not above 10.

**Licence.** vMaNGOS is GPL-licensed, so the generated data is derived from
GPL material. That is fine for personal use. If BossLoot is ever published,
it has to be published under the GPL.

**Accuracy.** Emulator loot tables are researched to match Blizzard's, but
they are not Blizzard's own data. Drop chances in particular are
approximations.

## The one hand-maintained file: the boss list

The database cannot tell a boss from trash. In Blackrock Depths, Emperor
Dagran Thaurissan has the same elite rank as an Anvilrage Captain, and the
script names that might have marked bosses are inconsistent (`boss_magmus`,
but `npc_golem_lord_argelmach` and none at all for Lord Incendius). Nor does
it know kill order, wings, or level ranges.

So one file is written by hand: `BossLoot/tools/instances.json`. For every
instance it gives:

- the vMaNGOS map ID and whether it is a dungeon or a raid,
- the display name and the level range,
- the wings, for instances that have them (Dire Maul East/West/North,
  Stratholme Live/Undead, Scarlet Monastery's four wings, Blackrock Spire
  Lower/Upper),
- the bosses in kill order, grouped by wing, each by name. A boss can also
  name several creatures (The Seven, the Twin Emperors) and the chest its
  loot is in (Cache of the Firelord, Chest of The Seven, Four Horsemen
  Chest). Names are easier to maintain than creature IDs; the build fails
  naming any it cannot find,
- whether the instance is available (`"available": false` leaves it out).
  **WoW Forever does not have every vanilla instance**, and which ones are
  missing is not yet known, so every instance can be switched off here, and
  the window also lets the player hide instances (see below).

About 26 instances and 200 bosses. Nothing else in the data is written by
hand.

A boss that is summoned by a script rather than spawned on the map still
counts: the boss list names it, so the build script reads its loot
regardless of whether it appears in `creature`.

## The build script

`BossLoot/tools/build-data.mjs`, run with Node 24, which has SQLite built in
(`node:sqlite`), so nothing needs installing. It is a repo tool: neither the
script nor the database ships in the addon zip.

```
node BossLoot/tools/build-data.mjs <path to mangos.sqlite>
```

It reads the boss list and the database and writes `BossLoot/Data/`. Every
run regenerates every data file, so a rebuild shows up as a readable git
diff.

### Resolving a loot table

A creature's loot table is its `creature_loot_template` rows under its
`loot_id`. Resolving one into "item, chance" pairs follows the emulator's
rules:

- **Plain rows** (`groupid` 0, `mincountOrRef` positive): the item drops with
  `ChanceOrQuestChance` percent, independently of everything else.
- **Grouped rows** (`groupid` above 0): at most one item from the group drops.
  Rows with an explicit chance keep it. Rows with chance 0 share whatever
  chance is left over in the group equally.
- **References** (`mincountOrRef` negative): the row points at a
  `reference_loot_template` entry, resolved the same way. Its items' chances
  are multiplied by the reference row's own chance.
- **Quest drops** (`ChanceOrQuestChance` negative): only drop for players on
  the quest. Left out: a quest objective is not loot.
- **Conditional rows** (`condition_id` not 0): holiday items (Emperor
  Thaurissan has a Winter Veil hat at 100%) and drops gated on quest state.
  Left out.

An item reachable by more than one route keeps its highest chance. A chance
that rounds to 0.00% is dropped.

### Deciding what to keep

**Boss loot** keeps everything a boss can drop except:

- poor-quality (grey) items,
- quest-only drops,
- world drops (below).

**Notable drops** are items from creatures that are not in the boss list, and
from chests and other lootable objects on the map. They are kept only if they
are one of these four kinds:

| Kind | Test on `item_template` |
|---|---|
| Rare, epic and legendary gear | `quality` 3 or higher |
| Recipes, plans, formulas, patterns | `class` 9 |
| Quest-starting items | `start_quest` above 0 |
| Keys and attunement items | `class` 13 |

and only if their best chance in the instance is at least **0.5%**. The
threshold applies to notable drops, never to boss loot: a 0.3% epic off a boss
is exactly the kind of thing worth knowing about.

**World drops** are the BoE items that can drop from any mob of the right
level, anywhere. The emulator keeps them in shared reference tables. A
reference table counts as a world-drop table if creatures spawned on **four
or more** maps use it. Its items are left out of both boss loot and notable
drops. Measured on the 2026-09-06 snapshot: tables made for one instance span
1 to 3 maps (Ruins of Ahn'Qiraj shares some with Silithus, and the Ahn'Qiraj
enchanting formulas span both Ahn'Qiraj instances and Silithus), while
world-drop tables span 4 to 16. "More than one map" would have wrongly dropped
the Ahn'Qiraj tables.

**World drops will be added later**, in a view of their own, not mixed into
each instance. The build script already identifies the world-drop tables, so
the later phase adds output, not new analysis.

## The data files

Plain Lua tables, one file per instance, loaded in `.toc` order into the
addon's private table.

The shape, with illustrative values:

```lua
-- Data/BlackrockDepths.lua (generated -- do not edit)
local _, ns = ...
ns.AddInstance({
    key = "BlackrockDepths",
    name = "Blackrock Depths",
    kind = "dungeon",
    levels = { 52, 60 },
    bosses = {
        {
            name = "Emperor Dagran Thaurissan",
            wing = nil,
            loot = { { 11684, 1.8 }, { 11815, 3.2 }, ... },
        },
        ...
    },
    notable = {
        trash = { { 11810, 0.9, { "Anvilrage Overseer" } }, ... },
        objects = { { 11000, 100, { "Tribute Chest" } }, ... },
    },
})
```

Loot entries are `{ itemID, chancePercent }`. Notable entries add the names of
what drops them, so the loot column can say where to look. Creature, boss and
object names are English: the client cannot translate them. Item names are
never stored.

Expected size: a few thousand loot entries, a few hundred KB of Lua in all.

## The window

Three columns, like AtlasLoot. `/bl` (or `/bossloot`) toggles it. It can be
dragged, remembers its position, and reopens on the instance and boss last
viewed.

```
+-------------------------------------------------------------------+
| BossLoot                                                        X |
+-------------------+----------------------+------------------------+
| [Search...]       | Lord Roccor          | [ico] Ironfoe      1.8%|
| [Dungeons][Raids] | ...                  | [ico] Hand of J... 3.2%|
| Stratholme  58-60 | Emperor Thaurissan * | ...                    |
| Blackrock D. 52-60| -- Notable drops --  |                        |
| ...               | From trash           |                        |
|                   | Chests & objects     |                        |
+-------------------+----------------------+------------------------+
```

**Instances column.** Dungeons and Raids tabs. Instances in rough level
order, each with its level range in grey. Right-clicking an instance hides
it (saved, account-wide) for instances WoW Forever does not have;
`/bl unhide` brings them all back.

**Bosses column.** Bosses in kill order, under wing headings where the
instance has wings. At the bottom, a "Notable drops" heading with two
entries: *From trash* and *Chests & objects*. An entry with nothing in it is
not shown.

**Loot column.** One row per item: icon, name in its quality colour, slot or
type in grey (`Two-Hand Mace`, `Recipe`), and the drop chance on the right.
Sorted by quality, then by chance. Chances under 10% show one decimal
(`1.8%`), from 10% up they are whole numbers (`14%`), and anything under
0.1% shows as `<0.1%`.

For notable drops, each row also says what drops it (*Anvilrage Overseer*) or
where it is found (*Tribute Chest*).

Each row behaves like an item anywhere else in the game:

- hovering shows its tooltip,
- Shift-click links it in chat,
- Ctrl-click previews it on the character.

An item the client has not seen yet comes back from `GetItemInfo` empty. Its
row shows a grey placeholder and fills in when the client reports the item
loaded (`GET_ITEM_INFO_RECEIVED`).

**Search.** One box at the top of the instances column. It matches instance
names, and item names: typing `hand of justice` lists the places that drop it,
and choosing one jumps to that instance and boss. Item names are only known
once the client has loaded them, so search covers items it has seen. Opening
an instance asks the client for all of its items, which fills the cache as
you browse.

## The minimap button

A round button on the minimap's rim with a loot-bag icon.

- Left-click toggles the window.
- Dragging slides it around the rim; its angle is saved.
- The tooltip reads "BossLoot. Click to open, drag to move."
- `/bl minimap` hides or shows it.

Built by hand, as no addon in this repo uses a shared library.

## Commands

| Command | Does |
|---|---|
| `/bl` | Toggle the window |
| `/bl minimap` | Hide or show the minimap button |
| `/bl unhide` | Bring back every instance hidden from the list |
| `/bl help` | List the commands |

## Code layout

| File | Job |
|---|---|
| `BossLoot.toc` | File list; the generated data files are listed here too |
| `BossLoot.lua` | Core: saved variables and defaults, slash commands, login. Same shape as FishScale and UrlCopy |
| `Data/*.lua` | Generated. One file per instance, each calling `ns.AddInstance` |
| `Index.lua` | Built once after the data loads: instances by kind in level order, and item ID to every place it drops, for search |
| `Format.lua` | Pure helpers: chance text, sorting rows, the slot or type label |
| `LootRow.lua` | One loot row: icon, name, chance, source; tooltip and clicks; the not-yet-loaded placeholder |
| `Window.lua` | The three-column window, its selection state, scrolling lists and search box |
| `Minimap.lua` | The minimap button and its drag-around-the-rim maths |
| `tools/instances.json` | The hand-maintained boss list |
| `tools/build-data.mjs` | The build script |
| `tools/test/` | The build script's tests and a small sample database |

## Testing

**The addon** gets the usual Lua spec suite under `BossLoot/tests/`, with a
WoW stub, run by `run-tests.ps1`. It covers:

- the index, and search by instance and by item,
- chance formatting and row sorting,
- the window's selection state: switching tabs, picking an instance, picking
  a boss, the remembered last view,
- loot rows filling in when a not-yet-loaded item arrives,
- the minimap button's angle-to-position maths and saved angle.

**The build script** is tested with Node's built-in test runner
(`node --test BossLoot/tools/test`) against a small SQLite database built by
the tests themselves, holding a few hand-made creatures, loot tables and
items. It covers each rule above: plain, grouped and referenced chances, quest
drops left out, grey items left out of boss loot, the four notable kinds, the
0.5% threshold, world-drop tables left out, and patch filtering.

**In game**, by the player: the window and minimap button, and spot checks of
a few loot tables against what they know.

## Implementation order

1. **One instance end to end.** The build script resolves Blackrock Depths
   from the real database into a data file, and a bare window lists its bosses
   and loot. This is where the world-drop rule and the notable filter get
   checked against real data, before anything else is built on them.
2. **Every instance.** The full boss list, and the build script's tests.
3. **The window.** All three columns, tabs, loot rows with tooltips and
   clicks, the loading placeholder, the remembered view.
4. **Search.**
5. **The minimap button.**

**Later, not in this design's scope:** a world-drops view; class and slot
filters; opening on the current instance; a wishlist.
