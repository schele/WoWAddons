# GatherMap rewrite: your own gathers only

Date: 2026-09-28. Status: design approved in conversation; spec awaiting
review. Supersedes `2026-09-28-gathermap-design.md` wherever they differ.

## What it is

GatherMap pins, on the world map and the minimap, the places where the
player has mined a vein or gathered a herb. Nothing else: no pins from any
database, no fishing pools, no chests. Gathers are saved per account, so
every character adds to the same map.

## What goes

- The vMaNGOS build: `GatherMap/tools/` (build-data, lib, tests, nodes.json,
  recordings) and the generated spawn files `Data/EasternKingdoms*.lua`,
  `Data/Kalimdor*.lua`, `Data/Confirmed.lua`.
- Fishing pools and chests, "confirmed" and dimmed pins, `ns.confirmed`,
  `GatherMapDB.missing` and the "not here" mark, `onlyConfirmed` and
  `showMissing`, and their specs.

## What stays

The shell (`GatherMap.lua`), `Geometry.lua`, `Spawns.lua` (now holding only
the player's gathers), `Skills.lua`, `Filter.lua`, `Pins.lua` (one pin per
spot), `WorldMap.lua`, `MinimapPins.lua`, `Settings.lua`, `Minimap.lua`,
`Debug.lua`, the icons, `/gmap where`, `/gmap debug`.

## The node list

`Data/Nodes.lua` becomes a hand-kept file: the herb and ore entries of the
current generated catalog, same shape:

```lua
ns.AddNodes({
    [1731] = { kind = "ore", name = "Copper Vein", skill = 1, item = 2770 },
    [1617] = { kind = "herb", name = "Silverleaf", skill = 1, item = 765 },
})
```

It only supplies names, required skills and icons. A gather of an entry it
does not list is still recorded (see below).

## Recording

1. `UNIT_SPELLCAST_SUCCEEDED` with unit `"player"`: if the spell's name is
   the game's own name for spell 2575 or spell 2366, read through
   `C_Spell.GetSpellName` or `GetSpellInfo`, remember the kind (2575: `ore`,
   2366: `herb`) and `GetTime()`. On this client (probed 2026-09-28) 2575 is
   "Mining" and 2366 "Herbalism"; mining a vein casts 2576, named "Mining",
   so the names match. The herb cast is not yet seen (no Herbalism on the
   probing character) and is expected to be named "Herbalism" the same way.
2. `LOOT_OPENED`: `GetLootSourceInfo(1)` must be a `GameObject` GUID; its
   sixth field is the entry. It is a gather when either the entry is a
   listed herb or ore (the list gives the kind), or a gather spell (step 1)
   succeeded within the last 3 seconds (the spell gives the kind). Anything
   else (a corpse, a chest, fishing, an unlisted object with no gather spell
   before it) is ignored.
3. Position: `UnitPosition("player")`, continent 0 or 1 only.
4. Within 15 yards of an earlier point of the same entry: that point's
   `count` goes up. Otherwise a new point.
5. The point keeps what the list cannot supply: `kind` from the spell, and
   `item`/`itemName` from `GetLootSlotLink(1)`'s item, so an unlisted node
   still has an icon and a name.
6. One visit counts once: a vein is mined several times, each with its own
   loot window (probed: three `Mining` casts on one Copper Vein), so a
   gather on the same point within 60 seconds of the last is not counted
   again.

```lua
GatherMapDB = {
    gathered = {
        ["0:1731:-10133.8:793.8"] = { continent = 0, entry = 1731, x = -10133.8, y = 793.8,
            kind = "ore", item = 2770, itemName = "Copper Ore", count = 3, last = 1790000000 },
    },
}
```

Saved gathers from the first GatherMap load as they are when their entry is
a listed herb or ore (their `kind` comes from the list); pool and chest
points, and points of unknown kind, are dropped at login. `missing` is
removed.

## A gathered point's name, skill and icon

- Listed entry: the list's name, skill and item.
- Unlisted: `itemName` (e.g. "Copper Ore") as the name, no skill (so the
  skill filters never hide it), `item`'s icon, else the kind's icon.

## Showing and filtering

- Pins as now: the icon with a gold edge, one per spot, tooltip with the
  name(s), required skill in its skill-up colour when known, and "Gathered
  here N times".
- Filters per map (world map, minimap): herbs / ore; the node checklist
  (every listed name of that kind plus every unlisted name the player has
  gathered); hide what the skill cannot gather yet; hide grey nodes; pin
  size.
- Clicks: left and plain right-click pass through to the map as now.
  **Shift-right-click forgets that point** (all members of the spot), after
  which it is gone from both maps. The tooltip says "Shift-right-click:
  forget this place".
- `/gmap reset gathered` (asks first) forgets every point.

## Checked before code

A `/run` probe in game, 2026-09-28: 2575 is named "Mining" and 2366
"Herbalism"; `UNIT_SPELLCAST_SUCCEEDED` fires for the player with spell 2576
"Mining" on every mining of a Copper Vein (three per vein). Herbs are not
probed yet; listed herbs are recorded regardless of the spell (Recording,
step 2), so only unlisted herbs depend on the unprobed name.

## Testing

Lua specs as now, rewritten for the new recording: a gather after Mining
counts; a listed herb counts with no spell; an unlisted object with no
gather spell, or more than 3 seconds after it, does not; mining the same
vein three times within 60 seconds counts once;
an unlisted entry is recorded with its loot's name and icon; old saved
pool/chest points are dropped; Shift-right-click forgets a spot; the
filters and both maps draw only gathered points. In game: the probe above,
then gather in Westfall and see the pin appear on both maps.

## Out of scope

Any database of spawns, sharing between players, fishing pools, chests,
routes, respawn timers.
