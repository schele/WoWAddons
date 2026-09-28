# GatherMap (World of Warcraft AddOn)

Herbs, ore, fishing pools and treasure chests on the world map and the
minimap, with filters for each.

## What it shows

- **Where you have gathered**, with a gold edge. Every herb, vein, chest or
  pool you loot is counted on its spawn; one the database does not have is
  added where you stood. Saved per account.
- **Spawns confirmed in WoW Forever**, at full strength: gathered by players
  whose recordings went into this release.
- **Every other spawn the classic database knows**, dimmed. They come from
  the [vMaNGOS](https://github.com/vmangos/core) vanilla database at patch
  1.12, and WoW Forever is not vanilla, so treat them as a good guess.

Hover a pin for its name, the skill it needs (in its skill-up colour) and
which of the three it is. **Right-click a pin where nothing grows** to mark it
not here: it is hidden on every character, and gathering there later takes
the mark off.

## Sending your recordings

Your gathers and "not here" marks make the next release better for everyone.
Send `WTF/Account/<name>/SavedVariables/GatherMap.lua`; it goes in
`tools/recordings/` and the build bakes it in.

## Filters

Each has a box for the world map and one for the minimap, in `/gmap`:

- Herbs, ore, fishing pools, chests; open a kind with **+** to pick its nodes
  one by one, or **All** / **None**.
- Hide nodes your skill cannot gather yet (on by default).
- Hide grey nodes, the ones that give no more skill-ups.
- Only places confirmed in game (yours, or from the release).
- Show spawns marked not here, to take a mark back off.
- Pin size.

If you have collapsed the Professions header in your skill list, GatherMap
keeps the skills it last saw until you open it again.

## Commands

| Command | What it does |
|---|---|
| `/gmap` | Open the settings |
| `/gmap toggle` | Show or hide every pin |
| `/gmap minimap` | Hide or show the minimap button |
| `/gmap where` | Where the game and GatherMap put you on the map |
| `/gmap reset gathered` | Forget every place you have gathered and every "not here" mark (asks first) |
| `/gmap help` | List the commands |

The minimap button: click to show or hide every pin, right-click for the
settings, drag to move it.

## Rebuilding the data

Needs Node 24 or later. Download `db-sqlite-<commit>.zip` from the
[db_latest release](https://github.com/vmangos/core/releases/tag/db_latest),
unzip it outside the repo, and from the repo root:

    node GatherMap/tools/build-data.mjs <path to>/sqlite-dump/mangos.sqlite

The one file edited by hand is `tools/nodes.json`: the herb and ore names with
the skill each needs, and the chest names. A vein or deposit it does not list
fails the build. Saved-variables files in `tools/recordings/` are baked in
on every build. The data is derived from GPL material.

## Install

    .\package.ps1 GatherMap -Install

See the [repo README](../README.md) for packaging and test commands.
