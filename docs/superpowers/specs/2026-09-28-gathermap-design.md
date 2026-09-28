# GatherMap: design

Date: 2026-09-28. Status: sections approved in conversation; written spec
awaiting review.

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

- `Data/EasternKingdoms.lua` and `Data/Kalimdor.lua`: every spawn of those
  nodes on map 0 or 1, as one flat array `entry, x, y, entry, x, y, ...` in
  world yards (vMaNGOS `position_x`, `position_y`, rounded to 0.1 yard).

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
}

GatherMapSettings = {
    enabled = true,                  -- the minimap button's show/hide all
    worldmap = {
        kinds = { herb = true, ore = true, pool = true, chest = true },
        hidden = { ["Peacebloom"] = true },   -- node names switched off
        hideUngatherable = true,
        hideGrey = false,
        onlyGathered = false,
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

One loot window counts once, however many items it holds.

## Skill (`Skills.lua`)

Reads Herbalism and Mining from `GetSkillLineInfo` at login and on
`SKILL_LINES_CHANGED`. Skill lines are matched by the localized profession
name from `GetSpellInfo`, so any client language works. No profession
means skill 0.

## Filters (`Filter.lua`)

One function answers "show this spawn on this map (world map or
minimap)?": the kind is on, the node name is not hidden, and

- `hideUngatherable`: herbs and ore need skill >= required;
- `hideGrey`: herbs and ore that give no skill-up are hidden;
- `onlyGathered`: only spawns in `GatherMapDB.gathered`.

Pools and chests ignore both skill filters. `enabled = false` hides every
pin on both maps.

## World map (`WorldMap.lua`)

A data provider added with `WorldMapFrame:AddDataProvider`, drawing pins
from a pin template through the map's own pin pool, so they zoom and pan
with the map.

On a zone's first open this session, convert its continent's spawns with
`C_Map.GetMapPosFromWorldPos` and keep those inside 0..1; cache per
`uiMapID`. Continent maps show every spawn on the continent. Refilter from
the cache on any filter or skill change.

Pin: the node's icon at `pinSize`; a thin gold ring if gathered. Tooltip:
name, required skill in its skill-up colour, and "Gathered here N times" or
"Known spawn".

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
- only where I have gathered;
- pin size (a slider per column).

## Minimap button and commands

`Minimap.lua`, the same button as the other addons: left-click toggles
`enabled`, right-click opens the panel, drag moves it.

`/gm` opens the panel (falls back to `/gathermap` if `/gm` is taken);
`/gm help` lists commands; `/gm toggle`; `/gm reset gathered` asks for
confirmation before wiping `GatherMapDB.gathered`.

## Icons

Drawn with `tools/draw-icons.mjs`: `icon.tga` (the `.toc`'s
`IconTexture`) and `minimap.tga` (the button, and the settings logo). A map
pin over a leaf and a pickaxe.

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
- Sharing gathered points between players.
- Routes, timers and respawn tracking.
