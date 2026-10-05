# RareMob: design

Notices rare and rare elite mobs: pins their spawn points on the world map
and minimap, plays a sound when a living one is near, and lists the zone's
rares with when each was last seen.

## Data

**Database.** `RareMob/tools/build-data.mjs` (Node 24, built-in SQLite)
reads the vMaNGOS database (`db-sqlite-<commit>.zip`, release `db_latest` on
github.com/vmangos/core), reusing BossLoot's `tools/lib/db.mjs` approach
(copied, not shared: addons are self-contained). It keeps, as of 1.12
(patch 10 rows, as BossLoot filters them):

- every `creature_template` with `rank` 2 (rare elite) or 4 (rare): `entry`,
  `name`, `level_min`, `level_max`, elite or not;
- every `creature` spawn of those entries on map 0 or 1, in world yards
  (`position_x`, `position_y`, rounded to 0.1).

Output: `Data/Rares.lua` (`ns.AddRares({ [entry] = { name, minLevel,
maxLevel, elite } })`) and `Data/SpawnsEasternKingdoms.lua`,
`Data/SpawnsKalimdor.lua` (flat arrays `entry, x, y, ...`). The build fails
loudly on an empty result.

**Sightings.** In game, a mob counts when `UnitClassification(unit)` is
`"rare"` or `"rareelite"` and it is not dead (`UnitIsDead`). Units looked at:
nameplates (`NAME_PLATE_UNIT_ADDED`), `target` (`PLAYER_TARGET_CHANGED`),
`mouseover` (`UPDATE_MOUSEOVER_UNIT`). The creature id comes from
`UnitGUID` (`Creature-0-...-<id>-...`). A sighting stores id, name, level,
elite, zone `uiMapID`, map position (`C_Map.GetPlayerMapPosition` of the
player: the rare is within nameplate range) and time.

Saved per account in `RareMobDB.sightings[id] = { name, level, elite,
count, last, places = { { map, x, y, time }, ... (at most 20, newest) } }`
and `RareMobDB.recorder` (random id, made once).

**Seen on WoW Forever.** A rare is seen when its id has a sighting, the
player's own or baked. Not seen: "from the classic database". A rare met in
game that the database lacks is added from the sighting alone.

**Recordings.** `tools/bake-recordings.mjs <RareMob.lua saved variables...>`
writes `Data/Recorded.lua` (`ns.AddRecordings(recorderId, sightings)`). At
runtime the merged view leaves out the baked copy of the player's own
recorder id, as BossLoot does.

**Probe.** `/rm probe` prints, for each call RareMob uses, whether this
client has it: `UnitClassification`, `UnitGUID`, `UnitIsDead`,
`C_NamePlate.GetNamePlateForUnit`, `C_Map.GetBestMapForUnit`,
`C_Map.GetPlayerMapPosition`, `C_Map.GetWorldPosFromMapPos`,
`WorldMapFrame.AddDataProvider`, `PlaySound`. Run in game before trusting the
data (not yet done; the build ships anyway).

## What the player sees

**Pins** on the world map and the minimap for the rares of the zone shown.
Placement: each zone's corners from two `C_Map.GetWorldPosFromMapPos` calls,
then plain sums, cached per `uiMapID` (GatherMap's first design). World map
pins are RareMob's own frames on the canvas, above the map art, scaled
against the canvas zoom (GatherMap's fix). Minimap pins follow GatherMap's
minimap placement (smooth map position, whole screen pixels).

- Skull icon. Bright: seen on WoW Forever. Dimmed: database only. Gold edge:
  the player's own sighting.
- Tooltip: name, level (range), "Rare" or "Rare elite", "Last seen 3 days
  ago" when seen, then "Seen on WoW Forever" or "From the classic database,
  not seen on WoW Forever yet".
- A rare spotted near the player: its pins pulse until it dies or is gone
  (no nameplate, not target or mouseover, for 30 seconds).
- Sighting places with no database spawn get a pin at the sighting's spot.

**Alert.** `PlaySound(SOUNDKIT.RAID_WARNING)` (guarded; fallback sound id
8959) when a living rare is spotted; once per rare id per 5 minutes; never
while `IsResting()` (cities, inns).

**Zone list.** `/rm` or minimap left-click. Window with BossLoot's frame and
an opaque background. The current zone's rares (database and sightings),
sorted by level, each row: name, level, last seen ("never" when not), seen
on WoW Forever or not. Clicking a row opens the world map on that zone with
that rare's pins highlighted.

**Minimap button.** Left-click: the list. Right-click: settings. Hideable.

**Settings page** (canvas page like the other addons, rows hanging under the
hint with the 16px gap): Show pins on the world map; Show pins on the
minimap; Show rares only in the database; Alert sound; Pin size (slider);
Show the minimap button. All on by default; pin size 14.

## Files

`RareMob.lua` (database, commands, `ns.Guarded`), `Data/*` (generated),
`Rares.lua` (merged view: rares of a zone, seen or not, last seen),
`Spotter.lua` (units, sightings, spotted/gone events), `Alert.lua`,
`WorldMap.lua`, `MinimapPins.lua`, `List.lua`, `Minimap.lua`,
`Settings.lua`, `tools/` (build, bake, tests), `tests/` (Lua specs with a
stub game).

## Failure handling

Every game call through `ns.Guarded`. A missing call turns its feature off
quietly; `/rm probe` names it. A unit whose classification or GUID cannot be
read, or a player with no map position, is skipped.

## Testing

Lua specs: spotter (rare, rare elite, dead, normal, unreadable, quiet time,
resting), merged view (database only, sighting only, both, baked, own baked
copy left out), pin placement maths and filtering by settings, list contents
and order, settings page. Node tests for the build and the bake.
