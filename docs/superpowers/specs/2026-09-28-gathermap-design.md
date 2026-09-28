# GatherMap: design

Date: 2026-09-28. Status: approved, then revised for WoW Forever (the game outranks
vMaNGOS); the check against real gathers is pending.

## What it is

A WoW Forever addon (client `_classic_beta_` 1.60, interface 16001) that pins
herbs, ore, fishing pools and treasure chests on the world map and the
minimap, with filters. Pins come from two sources: every known spawn,
shipped with the addon, and the places the player has actually gathered.
It adds a minimap button and an icon in the AddOns list, like the other
addons here.

## What the client allows (probed 2026-09-28, Westfall)

- `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition`,
  `C_Map.GetWorldPosFromMapPos` and `C_Map.GetMapPosFromWorldPos` all work,
  and a map → world → map round trip lands on the same point.
- `UnitPosition("player")` returns world yards matching
  `GetWorldPosFromMapPos` (x first, then y), and keeps working in combat,
  as does `GetPlayerMapPosition`.
- `WorldMapFrame.AddDataProvider`, `MapCanvasDataProviderMixin`,
  `Minimap.GetZoom` and `GetLootSourceInfo` exist. `rotateMinimap` is 0.
- A gather's loot source is `GameObject-0-<server>-<instance>-<zone>-<entry>-<spawn>`;
  mining a Copper Vein gave entry 1731, its vMaNGOS `gameobject_template`
  entry.

## vMaNGOS is vanilla; WoW Forever is not

BossLoot learned this the hard way: its vMaNGOS loot was wrong for WoW
Forever, and it grew a recorder and a "not seen on WoW Forever yet" split
after shipping. GatherMap is built the other way round, with the game as
the authority from the start:

1. **Checked before any addon code.** Real gathers (entry and position,
   logged in game with a throwaway `/run`) are compared with vMaNGOS. If most
   match a spawn of the same entry within 15 yards, the database is used; if
   not, the design stops here and is rethought. Result recorded below.
2. **Three kinds of pin**, told apart at a glance:
   - *gathered by you*: full strength, gold edge;
   - *confirmed*: gathered by any player whose recordings were baked into
     the release: full strength;
   - *from the database only*: dimmed (55%), "not seen in WoW Forever yet"
     in its tooltip.
   The source filter becomes "Only places confirmed in game" (yours or baked).
3. **"Not here."** Right-click a pin to mark a spawn where nothing grows;
   it is hidden on every character (`GatherMapDB.missing`), and gathering
   there later clears the mark. A setting shows marked spawns again, so a
   mistaken mark can be undone.
4. **Recordings baked into releases**, as BossLoot's are: saved-variables
   files (`GatherMap.lua` from `WTF/Account/<name>/SavedVariables/`) put in
   `tools/recordings/` are read by the build (BossLoot's
   `parseSavedVariables`). Their new points join the spawns, their gathered
   spawns become confirmed, and a database spawn marked "not here" by any
   recorder and gathered by none is left out.

### Check result

Database: vMaNGOS `db_latest` 13b49dc (downloaded 2026-09-28). The schema is
as the build assumes: `gameobject(id, map, position_x, position_y,
patch_min, patch_max)`, `gameobject_template(entry, patch, type, name,
data1)`, `gameobject_loot_template(entry, item, ChanceOrQuestChance,
mincountOrRef, patch_min, patch_max)`; Copper Vein is entry 1731 (type 3,
loot 1502), with 870 spawns on map 0; 24 fishing pool templates (type 25).

Gather comparison: pending the player's log.

## Data, and the build that makes it

`GatherMap/tools/build-data.mjs` reads the vMaNGOS SQLite dump through
BossLoot's `tools/lib/db.mjs` (same patch, `TARGET_PATCH`), and writes:

- `Data/Nodes.lua`: the catalog, by entry.

  ```lua
  ns.Nodes = {
      [1731] = { kind = "ore", name = "Copper Vein", skill = 1, item = 2770 },
      [1617] = { kind = "herb", name = "Silverleaf", skill = 1, item = 765 },
      -- kind is "herb", "ore", "pool" or "chest"; pools and chests have no skill
  }
  ```

  `item` is the node's main loot (the most likely item in its
  `gameobject_loot_template`: Copper Ore, Silverleaf), for herbs and ore;
  the pin shows `GetItemIcon(item)`. Pools and chests have no `item` and
  show one icon per kind.

  Nodes are picked by name: known herb and ore node names, fishing pool
  names, and treasure chest names (Battered Chest, Solid Chest, ...), all
  kept as lists in the build. Several entries can share a name (e.g. two
  Copper Veins); each is its own entry with the same name, and the filter
  checklist groups by name.

  vMaNGOS has no lock or skill data, so required skills are a hand-written
  table in the build, by node name (Copper 1, Tin 65, Silver 75, Iron 125,
  Gold 155, Mithril 175, Truesilver 230, ... Peacebloom 1, Earthroot 15,
  Mageroyal 50, ... Black Lotus 300). The build fails on a herb or ore node
  with no entry in that table.

- `Data/EasternKingdoms1.lua`, `Data/Kalimdor1.lua`, ...: every spawn of
  those nodes on map 0 or 1, as flat arrays `entry, x, y, entry, x, y, ...`
  in world yards (vMaNGOS `position_x`, `position_y`, rounded to 0.1 yard),
  at most 5000 spawns a file.
- `Data/Confirmed.lua`: the keys of every spawn a baked recording gathered
  (see "Recordings in the release").

Skill-up colour of a node, from its required skill `r` and the player's
skill `s`: orange `s < r + 25`, yellow `< r + 50`, green `< r + 100`, grey
otherwise; red (cannot gather) `s < r`.

## Saved variables

Both are per account.

```lua
GatherMapDB = {
    gathered = {
        -- key "<continent>:<entry>:<x>:<y>" of the spawn it matched, or of
        -- the new point where there was none
        ["0:1731:-10603.8:1154.0"] = { continent = 0, entry = 1731, x = -10603.8, y = 1154.0,
                                       count = 3, last = 1790000000, new = false },
    },
    missing = {
        -- spawns marked "not here", by key, with when
        ["0:1731:-10133.8:793.8"] = 1790000000,
    },
}

GatherMapSettings = {
    enabled = true,                  -- the minimap button's show/hide all
    worldmap = {
        kinds = { herb = true, ore = true, pool = true, chest = true },
        hidden = { ["Peacebloom"] = true },   -- node names switched off
        hideUngatherable = true,
        hideGrey = false,
        onlyConfirmed = false,
        showMissing = false,
        pinSize = 12,
    },
    minimap = { --[[ same fields ]] pinSize = 10 },
    button = { angle = 200, hide = false },
}
```

## Recording (`Recorder.lua`)

On `LOOT_OPENED`, read `GetLootSourceInfo(1)`; take the entry from the
GUID's sixth field. Ignore anything that is not a `GameObject` or not in
the catalog.

- Herb, ore, chest: the player stands at the node. Take `UnitPosition`,
  and match the nearest known spawn of the same entry within 15 yards; bump
  its count. No match: save a new point at the player's position.
- Pool: the player stands 10-20 yards off. Match the nearest known pool of
  the same entry within 30 yards; no match, record nothing.

One loot window counts once, however many items it holds. A gather on a
spawn marked "not here" clears the mark.

Right-click on any pin toggles its spawn in `GatherMapDB.missing`.

## Skill (`Skills.lua`)

Reads Herbalism and Mining from `GetSkillLineInfo` at login and on
`SKILL_LINES_CHANGED`. Skill lines are matched by name, with the
profession's name in every client language carried in the file (the spell
names `GetSpellInfo` gives, such as "Herb Gathering", are not the skill
lines' names). No profession means skill 0; a collapsed skill header keeps
the last ranks seen.

## Filters (`Filter.lua`)

One function answers "show this spawn on this map (world map or
minimap)?": the kind is on, the node name is not hidden, and

- `hideUngatherable`: herbs and ore need skill >= required;
- `hideGrey`: herbs and ore that give no skill-up are hidden;
- `onlyConfirmed`: only spawns in `GatherMapDB.gathered` or confirmed in
  the release;
- spawns in `GatherMapDB.missing` are hidden unless `showMissing`.

Pools and chests ignore both skill filters. `enabled = false` hides every
pin on both maps.

## World map (`WorldMap.lua`)

A data provider added with `WorldMapFrame:AddDataProvider`, for its
map-changed and zoom events; the pins are GatherMap's own frames on the
map's canvas (the map's pin pool needs an XML template), scaled against the
canvas zoom so they keep their size on screen.

On a zone's first open this session, place its continent's spawns with the
map's corners (two `C_Map.GetWorldPosFromMapPos` calls, then plain sums)
and keep those inside 0..1; cache per `uiMapID`. Continent maps show every
spawn on the continent, up to 2000 pins. Refilter from the cache on any
filter or skill change.

Pin: the node's icon at `pinSize`; a gold edge if you gathered there;
dimmed if only the database has it. Tooltip: name, required skill in its
skill-up colour, then "Gathered here N times", "Confirmed in WoW Forever" or
"From the classic database, not seen in WoW Forever yet", and "Right-click:
not here" (or "Marked not here. Right-click to undo").

## Minimap (`MinimapPins.lua`)

A pool of pin frames on `Minimap`, updated 5 times a second from
`UnitPosition`. Spawns are bucketed per continent into 200-yard cells at
load; each update looks only at the cells within the minimap's radius.

The radius comes from `Minimap:GetZoom()` and whether the player is
indoors, using the client's minimap sizes. With `rotateMinimap` on, pins
turn with `GetPlayerFacing()`. Spawns beyond the edge are hidden, not
pinned to the rim. Same tooltip as the world map.

## Settings panel (`Settings.lua`)

Scrolling panel in the AddOns options, logo beside the title, like the
other addons. Two columns, World map and Minimap, a checkbox in each for:

- each kind; under each kind, its node names sorted by required skill,
  shown as `Silverleaf (1)`, with all / none buttons;
- hide nodes I cannot gather yet; hide grey nodes;
- only places confirmed in game;
- show spawns marked "not here";
- pin size (a slider per column).

## Minimap button and commands

`Minimap.lua`, the same button as the other addons: left-click toggles
`enabled`, right-click opens the panel, drag moves it.

`/gmap` opens the panel (`/gm` is the game's help-ticket command, so not
that; `/gathermap` also works); `/gmap help` lists commands; `/gmap toggle`;
`/gmap where` prints the game's and GatherMap's map position side by side;
`/gmap reset gathered` asks for confirmation before wiping
`GatherMapDB.gathered` and `GatherMapDB.missing`.

## Recordings in the release (`tools/lib/recordings.mjs`)

The build reads every `*.lua` in `GatherMap/tools/recordings/` with
BossLoot's `parseSavedVariables` and takes each file's `GatherMapDB`:

- `gathered` points with `new = true`, of a catalog entry on continent 0
  or 1, that are not within 15 yards of a database spawn of the same entry
  (or of an earlier recording's point), are added to the spawns;
- every gathered key, database or new, is written to `Data/Confirmed.lua`
  (`ns.AddConfirmed({ key, ... })`);
- a database spawn in any recorder's `missing` and in no recorder's
  `gathered` is left out of the spawns.

A file that does not parse, or has no `GatherMapDB`, is a warning, not an
error, as in BossLoot.

## Icons

Drawn with `tools/draw-icons.mjs`: `icon.tga` (the `.toc`'s
`IconTexture`) and `minimap.tga` (the button, and the settings logo). A
green map pin with a leaf in its head.

## Testing

- Lua specs under `GatherMap/tests` with `wow_stub.lua`, `helpers.lua` and
  `runner.lua`, run by `run-tests.ps1`: GUID parsing, spawn matching (15 and
  30 yards, new points, pools never new), skill colours, every filter on
  both maps, the world map cache, minimap radius per zoom and indoors,
  rotation, settings round trip, the slash commands, the button.
- Node tests under `GatherMap/tools/test` against a fixture database: node
  selection by name, the skill table covering every herb and ore, the spawn
  export.
- In game: Elwynn Forest and Westfall, world map and minimap, a gather
  recorded, each filter.

## Out of scope

- Nodes inside instances, and maps other than 0 and 1.
- Lockpicking and key requirements for chests.
- Sharing gathered points between players in game (they are shared through
  releases instead).
- Routes, timers and respawn tracking.
