# BossLoot (World of Warcraft AddOn)

Every Classic dungeon and raid, every boss in it, and what each one drops,
with drop chances. Plus the valuable things no boss drops: rare trash drops,
recipes, quest starters, keys, and what is in the chests.

Open it with `/bl` or the minimap button. On the left, the instances
(Dungeons and Raids tabs, with level ranges) and a search box. In the middle,
the bosses in kill order, each with its portrait and a number. On the right,
the boss itself: its model (drag it to turn it, click it for a big one to turn
and zoom), and a map of the instance
with every boss pinned by number; click the map for a big one, with every
boss named beside its pin and the entrance marked, and click a pin to jump to
that boss. On the big map, scroll to zoom in on the cursor or out, drag to move
around, and right-click to see the whole map again.
Under that, the loot in two columns. At the bottom of the boss list,
**Notable drops** holds the trash and chest finds.

The map is a floor plan worked out from where the instance's mobs stand,
how far they wander and where they patrol, so it shows the rooms and
corridors they use rather than every wall. An instance in several parts far
apart, like Scarlet Monastery's four wings, has its parts packed close
together. A boss that only appears when a script summons it has no pin.

A loot row works like an item anywhere else: hover for the tooltip,
shift-click to link it in chat, ctrl-click to preview it on your character.
Items your client has not seen before show as "Loading item..." for a moment
and fill in by themselves; a bar under the boss's name counts the
instance's items as they load. Items the server never sends are counted as
failed on the bar, and a click on it asks for them again. BossLoot saves every item it loads, so the next
session shows them at once without asking the server. After a game patch the
saved items still show, and each is checked with the server again the next
time it is on screen. Changing the client's language starts the saved list
afresh.

The search box finds instances and items, and lists every place an item
drops with its chance; click one to go there. It can only find items BossLoot
has loaded, in this session or an earlier one; opening an instance loads all
of its items, so search gets better as you browse.

## WoW Forever

WoW Forever does not have every vanilla instance. Right-click an instance to
hide it; `/bl unhide` brings them all back.

## Commands

| Command | Does |
|---|---|
| `/bl` | Open or close the window |
| `/bl minimap` | Hide or show the minimap button |
| `/bl unhide` | Bring back every instance you hid |
| `/bl help` | List the commands |

## Where the data comes from

The client has no loot data to give an addon (its Encounter Journal is
empty), so BossLoot carries its own, generated from the open-source
[vMaNGOS](https://github.com/vmangos/core) vanilla database at patch 1.12.
Drop chances are the emulator's researched values, close to Blizzard's but not
Blizzard's own. The data is derived from GPL material.

What is listed:

- **Boss loot**: everything a boss drops except grey items, quest-only drops,
  holiday items and world drops. A few bosses (most of the Stockade) drop
  nothing else, and the window says so.
- **Notable drops** (trash and chests): rare or better gear, recipes, keys and
  quest-starting items, at 0.5% or better.
- **World drops** (the BoE items any mob can drop) are left out for now. An
  item counts as one when mobs on four or more maps, or on both continents,
  can drop it.

## Rebuilding the data

Needs Node 24 or later (it has SQLite built in).

1. Download `db-sqlite-<commit>.zip` from the
   [db_latest release](https://github.com/vmangos/core/releases/tag/db_latest)
   and unzip it anywhere outside the repo.
2. From the repo root:

       node BossLoot/tools/build-data.mjs <path to>/sqlite-dump/mangos.sqlite

The script rewrites `BossLoot/Data/` and the data lines in `BossLoot.toc`.
The one file edited by hand is `tools/instances.json`: the instances, their
level ranges and wings, and each instance's bosses in kill order. Set
`"available": false` on an instance to leave it out of the build. A boss name
the database does not know fails the build with an error naming it; fix it
and run again before committing.

## Install

    .\package.ps1 BossLoot -Install

See the [repo README](../README.md) for packaging and test commands.
