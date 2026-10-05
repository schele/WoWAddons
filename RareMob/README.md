# RareMob (World of Warcraft AddOn)

Rare and rare elite mobs: a skull pin on the world map and the minimap where
each one spawns, a sound when a living one is near you, and a list of your
zone's rares with when each was last seen.

## Pins

| Pin | Means |
|---|---|
| Bright skull | Seen on WoW Forever, by you or by a player whose sightings ship with this release |
| Dimmed skull | From the classic database only, not seen on WoW Forever yet |
| Gold edge | You saw it yourself |
| Pulsing glow | It is near you now (until it dies, or nothing has shown it for 30 seconds) |

Hover a pin for the rare's name, level, whether it is a rare or a rare
elite, when it was last seen, and whether WoW Forever has it. A rare seen
somewhere the database has no spawn of it gets a pin where it was seen.

## Noticing a rare

RareMob looks at every nameplate as it appears, your target and whatever is
under the mouse. A living rare or rare elite among them is a sighting: saved
with where you stood (you were within nameplate range of it) and when. While
it stays near it counts once. Turn on enemy nameplates to spot rares before
you click them.

When one comes near, RareMob sounds the raid warning: once per rare in five
minutes, and never while you are resting in a city or an inn.

## The zone list

`/rm` or a click on the minimap button: your zone's rares, from the database
and from sightings, by level, each with its level, when it was last seen
("never" when no one has) and whether WoW Forever has it. Click a rare to
open the world map on the zone with its pins glowing.

## Settings

Esc, Options, AddOns, RareMob (or right-click the minimap button). All on at
first:

- Show pins on the world map
- Show pins on the minimap
- Show rares only in the database (off: only rares seen on WoW Forever)
- Alert sound
- Pin size (14 at first)
- Show the minimap button

## Commands

| Command | What it does |
|---|---|
| `/rm` | Open or close the zone list |
| `/rm settings` | Open the settings |
| `/rm minimap` | Hide or show the minimap button |
| `/rm probe` | Say which of the game calls RareMob uses this client has, and what it says of you and your target |
| `/rm help` | List the commands |

`/raremob` works too.

## Where the data comes from

The rares (`creature_template` rank 2, rare elite, and 4, rare) and their
spawns on the two continents come from the
[vMaNGOS](https://github.com/vmangos/core) vanilla database at patch 1.12,
snapshot `db-sqlite-4641790`: 409 rares (137 elite), 415 spawns, 338 of the
rares spawned outside dungeons. WoW Forever is not vanilla, so the database
is only a guide: the pins say which rares someone has really seen.

## Rebuilding the data

Needs Node 24 or later (it has SQLite built in).

1. Download `db-sqlite-<commit>.zip` from the
   [db_latest release](https://github.com/vmangos/core/releases/tag/db_latest)
   and unzip it anywhere outside the repo.
2. From the repo root:

       node RareMob/tools/build-data.mjs <path to>/sqlite-dump/mangos.sqlite

The script rewrites `Data/Rares.lua`, `Data/SpawnsEasternKingdoms.lua` and
`Data/SpawnsKalimdor.lua`, and fails if it finds no rares or no spawns.
Update the snapshot name above.

## Baking in players' sightings

Put players' `WTF/Account/<name>/SavedVariables/RareMob.lua` files in
`tools/recordings/` (any name ending in `.lua`), then from the repo root:

    node RareMob/tools/bake-recordings.mjs

That rewrites `Data/Recorded.lua` from every file there; keep the files, as
each bake starts afresh. A player's own baked sightings are left out in
their game, so nothing counts twice.

## Install

    .\package.ps1 RareMob -Install

See the [repo README](../README.md) for packaging and test commands.
