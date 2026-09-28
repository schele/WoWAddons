# GatherMap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new addon, GatherMap, that pins herbs, ore, fishing pools and treasure chests on the world map and minimap, from a shipped vMaNGOS spawn database plus the places the player gathers, with filters per map.

**Architecture:** vMaNGOS is vanilla and WoW Forever is not (BossLoot's lesson), so the game is the authority: Task 0 checks real gathers against the database before any code, pins say whether the game has confirmed them, a spawn can be marked "not here", and players' saved-variables files are baked into releases. A Node build script turns vMaNGOS's SQLite dump plus those recordings into generated Lua data files (a node catalog, flat spawn lists in world yards, confirmed keys). In game, a spawn index (200-yard grid) feeds a shared filter, which the world map (a Blizzard map data provider drawing our own pins on the canvas) and the minimap (a 5 Hz ticker) both use. A recorder turns `LOOT_OPENED` into "gathered here" counts. The addon shell (defaults, commands, login hooks, settings page, minimap button) follows FishScale's.

**Tech Stack:** Lua 5.1 (WoW client 1.60, interface 16001), tested with the repo's own spec runner on Lua 5.4; Node 24 (`node:sqlite`, `node:test`) for the build.

**Spec:** [docs/superpowers/specs/2026-09-28-gathermap-design.md](../specs/2026-09-28-gathermap-design.md)

## Global Constraints

- Client `_classic_beta_`, `## Interface: 11509, 16001`, like every addon here.
- Saved variables, both per account: `GatherMapDB` (`gathered`, `missing`) and `GatherMapSettings` (filters, button).
- Three kinds of pin: gathered by you (full, gold edge), confirmed in a baked recording (full), database only (alpha 0.55, "From the classic database, not seen in WoW Forever yet").
- A spawn in `GatherMapDB.missing` is hidden unless `showMissing`; gathering there clears the mark.
- vMaNGOS database: `db_latest` release of github.com/vmangos/core, `db-sqlite-<commit>.zip`; checked with 13b49dc. It never goes in the repo.
- Kinds are exactly `"herb"`, `"ore"`, `"pool"`, `"chest"`; maps are exactly `"worldmap"` and `"minimap"`.
- Continents are instance IDs `0` (Eastern Kingdoms) and `1` (Kalimdor); nothing else is recorded or drawn.
- Spawn key: `string.format("%d:%d:%.1f:%.1f", continent, entry, x, y)`; world positions rounded to 0.1 yard.
- Match radius: 15 yards for herbs, ore, chests; 30 yards for pools; a pool never makes a new point.
- Skill colours for required `r`, skill `s`: red `s < r`, orange `< r+25`, yellow `< r+50`, green `< r+100`, grey otherwise.
- Minimap diameters in yards by zoom 0..5: outdoors 466.67, 400, 333.33, 266.67, 200, 133.33; indoors 300, 240, 180, 120, 80, 50.
- Slash commands: `/gmap` and `/gathermap`. (`/gm` is the game's own help-ticket command, so the spec's fallback applies from the start.)
- Every call into the client that could raise or return a secret goes through `ns.Guarded`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Decisions made while planning (differences from the spec)

- **Skill names:** the spec said to find Herbalism and Mining through `GetSpellInfo`. The spell IDs' names ("Herb Gathering") are not the skill lines' names, so `Skills.lua` carries the skill-line name in every client language instead.
- **Build reuse:** the build imports `luaString` and `updateToc` from BossLoot's `tools/lib/lua.mjs`, but queries the database itself with `node:sqlite` (BossLoot's `openDb` has no query for "every spawn of these objects").
- **World map pins** are our own frames on the map canvas, not pins from the map's `AcquirePin` pool: that pool needs an XML template, and the data provider is used for its map-changed and zoom events only.
- **Gathered edge:** a gold square frame around the icon, which every client can draw, instead of a ring.

## Review Focus

1. **A continent map holding thousands of spawns** — the map must stay usable, so the world map draws at most `WorldMap.MAX` (2000) pins. Test in Task 6.
2. **The Professions header collapsed in the character's skill list** — the skill lines under it are not listed, and reading that as "skill 0" would hide every herb and vein. Keep the last known ranks while any header is collapsed. Test in Task 4.
3. **A loot window where the client will not give a position** (an instance, a secret) — nothing recorded, nothing raised. Test in Task 5.
4. **Saved data from an older or hand-edited file** (a gathered point missing `count`, `x` or `entry`) — load skips it, recording repairs `count`. Tests in Tasks 3 and 5.
5. **The world map loading after GatherMap** (`Blizzard_WorldMap` on demand) — attach when it loads, not only at login. Test in Task 6.

---

## File structure

```
GatherMap/
  GatherMap.toc          loads everything; data lines between BEGIN/END markers
  GatherMap.lua          shell: defaults, Print, Guarded, commands, login and refresh hooks, data intake
  Data/                  generated: Nodes.lua, EasternKingdoms1.lua..., Kalimdor1.lua...
  Geometry.lua           pure sums: map rects, world -> map, minimap sizes and offsets
  Spawns.lua             spawn index: load, 200-yard grid, Near, Nearest, AddPoint
  Skills.lua             Herbalism/Mining ranks, skill colours
  Filter.lua             filter defaults, Filter.Shows(where, spawn)
  Recorder.lua           LOOT_OPENED -> gathered counts; /gmap reset gathered
  Pins.lua               a pin frame, its icon and tooltip, a pin pool
  WorldMap.lua           data provider, per-map spawn cache, /gmap where
  MinimapPins.lua        ticker, pins around the player
  Settings.lua           the options page
  Minimap.lua            the minimap button, /gmap minimap
  icon.tga, minimap.tga  drawn by tools/draw-icons.mjs
  README.md
  tests/                 runner.lua, wow_stub.lua, helpers.lua, fixture_data.lua, *_spec.lua
  tools/                 build-data.mjs, nodes.json, lib/nodes.mjs, lib/lua.mjs, test/*.test.mjs
```

### Task 0: Check vMaNGOS against the real game (go / no-go)

No addon code until this passes. It is a check, not a build: the script is
throwaway and lives in the session scratchpad (`$SCRATCH`).

**Files:** none in the repo; the result goes into the spec's "Check result".

- [ ] **Step 1: Get the database** (done 2026-09-28: 13b49dc in `$SCRATCH/vmangos/sqlite-dump/mangos.sqlite`)

```bash
gh release download db_latest -R vmangos/core -p "db-sqlite-*.zip" -D "$SCRATCH/vmangos" --clobber
unzip -o -q "$SCRATCH/vmangos/"db-sqlite-*.zip -d "$SCRATCH/vmangos"
```

- [ ] **Step 2: The player logs real gathers**

The player pastes once in game, then gathers 5-10 herbs or veins:

```
/run local f=CreateFrame("Frame") f:RegisterEvent("LOOT_OPENED") f:SetScript("OnEvent",function() local g=GetLootSourceInfo(1) local x,y=UnitPosition("player") print(g and g:match("-(%d+)-%x+$"),string.format("%.1f %.1f",x,y)) end)
```

Each gather prints `entry x y`. Collect the lines into `$SCRATCH/gathers.txt`, one per line.

- [ ] **Step 3: Compare them with the database**

`$SCRATCH/vmangos/check.mjs`:

```js
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
const [dbPath, gathersPath, continent = '0'] = process.argv.slice(2);
const db = new DatabaseSync(dbPath, { readOnly: true });
const nearest = db.prepare(`select id, position_x x, position_y y,
  ((position_x - ?) * (position_x - ?) + (position_y - ?) * (position_y - ?)) d2
  from gameobject where map = ? and id = ? and patch_min <= 10 and 10 <= patch_max order by d2 limit 1`);
let matched = 0, total = 0;
for (const line of readFileSync(gathersPath, 'utf8').split(/\r?\n/).filter(Boolean)) {
  const [entry, x, y] = line.trim().split(/\s+/).map(Number);
  const row = nearest.get(x, x, y, y, Number(continent), entry);
  const yards = row ? Math.sqrt(row.d2) : Infinity;
  total++;
  if (yards <= 15) matched++;
  console.log(`${entry} at ${x}, ${y}: nearest spawn ${yards.toFixed(1)} yards`);
}
console.log(`${matched} of ${total} within 15 yards`);
```

Run: `node --no-warnings "$SCRATCH/vmangos/check.mjs" "$SCRATCH/vmangos/sqlite-dump/mangos.sqlite" "$SCRATCH/gathers.txt"`

- [ ] **Step 4: Decide**

- **Go** if at least 80% are within 15 yards: write the numbers into the spec's "Check result" and carry on with Task 1.
- **No-go** otherwise: stop, show the player the list, and rethink the design (e.g. recordings only, no database) before any code.

---

Run every GatherMap test from the repo root with:

```powershell
.\run-tests.ps1 GatherMap
```

It runs the Lua specs and, once `tools/test` exists, the Node tests.

---

### Task 1: The build — node catalog and spawn export

**Files:**
- Create: `GatherMap/tools/nodes.json`
- Create: `GatherMap/tools/lib/nodes.mjs`
- Create: `GatherMap/tools/lib/lua.mjs`
- Create: `GatherMap/tools/lib/recordings.mjs`, `GatherMap/tools/recordings/README.md`
- Create: `GatherMap/tools/build-data.mjs`
- Test: `GatherMap/tools/test/fixture.mjs`, `GatherMap/tools/test/nodes.test.mjs`, `GatherMap/tools/test/lua.test.mjs`, `GatherMap/tools/test/recordings.test.mjs`

**Interfaces:**
- Consumes: `luaString(value)` and `updateToc(tocText, files)` from `BossLoot/tools/lib/lua.mjs`; `parseSavedVariables(text) -> { [global]: value }` from `BossLoot/tools/lib/savedvars.mjs`.
- Produces: `catalog(db, lists) -> { nodes: [{ entry, kind, name, skill?, item? }], errors: string[] }`; `spawns(db, nodes) -> Map<continent, [{ entry, x, y }]>`; `spawnKey(continent, entry, x, y) -> string` (same as Lua's `Spawns.Key`); `readRecordings(dir) -> { recorders: [{ file, gathered, missing }], warnings }`; `applyRecordings(byContinent, nodes, recorders) -> { confirmed: string[], added, dropped }` (mutates `byContinent`); `nodesFile(nodes)`, `spawnFiles(byContinent) -> [{ file, text }]`, `confirmedFile(keys) -> string`. The generated Lua calls `ns.AddNodes({ [entry] = { kind =, name =, skill =, item = } })`, `ns.AddSpawns(continent, { entry, x, y, ... })` and `ns.AddConfirmed({ key, ... })` (Task 2 defines all three).

- [ ] **Step 1: Write the node lists**

`GatherMap/tools/nodes.json`:

```json
{
  "herb": {
    "Peacebloom": 1, "Silverleaf": 1, "Earthroot": 15, "Mageroyal": 50, "Briarthorn": 70,
    "Stranglekelp": 85, "Bruiseweed": 100, "Wild Steelbloom": 115, "Grave Moss": 120,
    "Kingsblood": 125, "Liferoot": 150, "Fadeleaf": 160, "Goldthorn": 170,
    "Khadgar's Whisker": 185, "Wintersbite": 195, "Firebloom": 205, "Purple Lotus": 210,
    "Arthas' Tears": 220, "Sungrass": 230, "Blindweed": 235, "Ghost Mushroom": 245,
    "Gromsblood": 250, "Golden Sansam": 260, "Dreamfoil": 270, "Mountain Silversage": 280,
    "Plaguebloom": 285, "Icecap": 290, "Black Lotus": 300
  },
  "ore": {
    "Copper Vein": 1, "Tin Vein": 65, "Incendicite Mineral Vein": 65, "Silver Vein": 75,
    "Ooze Covered Silver Vein": 75, "Lesser Bloodstone Deposit": 75, "Iron Deposit": 125,
    "Indurium Mineral Vein": 150, "Gold Vein": 155, "Ooze Covered Gold Vein": 155,
    "Mithril Deposit": 175, "Ooze Covered Mithril Deposit": 175, "Truesilver Deposit": 230,
    "Ooze Covered Truesilver Deposit": 230, "Dark Iron Deposit": 230, "Small Thorium Vein": 230,
    "Ooze Covered Thorium Vein": 230, "Rich Thorium Vein": 255,
    "Ooze Covered Rich Thorium Vein": 255, "Hakkari Thorium Vein": 255
  },
  "chest": [
    "Battered Chest", "Tattered Chest", "Solid Chest", "Large Battered Chest",
    "Large Iron Bound Chest", "Large Solid Chest", "Large Mithril Bound Chest",
    "Buccaneer's Strongbox"
  ]
}
```

- [ ] **Step 2: Write the fixture and the failing tests**

`GatherMap/tools/test/fixture.mjs`:

```js
// A tiny in-memory copy of the vMaNGOS tables the build reads, holding only
// the columns it reads.
import { DatabaseSync } from 'node:sqlite';

export function fixtureDb() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    create table gameobject_template (entry int, patch int default 0, type int, name text, data1 int default 0);
    create table gameobject (guid integer primary key, id int, map int, patch_min int default 0, patch_max int default 10,
      position_x real default 0, position_y real default 0);
    create table gameobject_loot_template (entry int, item int, ChanceOrQuestChance real, mincountOrRef int default 1,
      patch_min int default 0, patch_max int default 10);
  `);
  const add = (table, row) => {
    const columns = Object.keys(row);
    db.prepare(`insert into ${table} (${columns.join(', ')}) values (${columns.map(() => '?').join(', ')})`)
      .run(...Object.values(row));
  };
  return { db, add };
}

export const LISTS = {
  herb: { Silverleaf: 1, Peacebloom: 1 },
  ore: { 'Copper Vein': 1, 'Tin Vein': 65 },
  chest: ['Battered Chest'],
};
```

`GatherMap/tools/test/nodes.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fixtureDb, LISTS } from './fixture.mjs';
import { catalog, spawns } from '../lib/nodes.mjs';

test('herbs, ore and chests are picked by name, pools by type', () => {
  const { db, add } = fixtureDb();
  add('gameobject_template', { entry: 1731, type: 3, name: 'Copper Vein', data1: 1502 });
  add('gameobject_template', { entry: 1617, type: 3, name: 'Silverleaf', data1: 1415 });
  add('gameobject_template', { entry: 2843, type: 3, name: 'Battered Chest', data1: 2264 });
  add('gameobject_template', { entry: 180582, type: 25, name: 'Oily Blackmouth School' });
  add('gameobject_template', { entry: 9999, type: 3, name: 'Wanted Poster' });

  const { nodes, errors } = catalog(db, LISTS);
  assert.deepEqual(errors, []);
  assert.deepEqual(nodes.map((n) => [n.entry, n.kind, n.name, n.skill]), [
    [1617, 'herb', 'Silverleaf', 1],
    [1731, 'ore', 'Copper Vein', 1],
    [2843, 'chest', 'Battered Chest', undefined],
    [180582, 'pool', 'Oily Blackmouth School', undefined],
  ]);
});

test('a herb or vein takes its most likely loot as its item', () => {
  const { db, add } = fixtureDb();
  add('gameobject_template', { entry: 1731, type: 3, name: 'Copper Vein', data1: 1502 });
  add('gameobject_loot_template', { entry: 1502, item: 2835, ChanceOrQuestChance: 40 }); // Rough Stone
  add('gameobject_loot_template', { entry: 1502, item: 2770, ChanceOrQuestChance: 100 }); // Copper Ore
  add('gameobject_loot_template', { entry: 1502, item: -1, ChanceOrQuestChance: 100, mincountOrRef: -5 }); // a reference
  const { nodes } = catalog(db, LISTS);
  assert.equal(nodes[0].item, 2770);
});

test('chests and pools carry no item', () => {
  const { db, add } = fixtureDb();
  add('gameobject_template', { entry: 2843, type: 3, name: 'Battered Chest', data1: 2264 });
  add('gameobject_loot_template', { entry: 2264, item: 4541, ChanceOrQuestChance: 50 });
  const { nodes } = catalog(db, LISTS);
  assert.equal(nodes[0].item, undefined);
});

test('the template in force is the newest not after patch 10', () => {
  const { db, add } = fixtureDb();
  add('gameobject_template', { entry: 1731, patch: 0, type: 3, name: 'Old Name' });
  add('gameobject_template', { entry: 1731, patch: 5, type: 3, name: 'Copper Vein' });
  add('gameobject_template', { entry: 1731, patch: 11, type: 3, name: 'Future Name' });
  const { nodes } = catalog(db, LISTS);
  assert.deepEqual(nodes.map((n) => n.name), ['Copper Vein']);
});

test('a vein or deposit with no skill in nodes.json fails the build', () => {
  const { db, add } = fixtureDb();
  add('gameobject_template', { entry: 4444, type: 3, name: 'Mystery Deposit' });
  const { errors } = catalog(db, LISTS);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /Mystery Deposit/);
});

test('spawns are the catalog\'s objects on both continents, rounded to a tenth of a yard', () => {
  const { db, add } = fixtureDb();
  add('gameobject', { id: 1731, map: 0, position_x: -10603.768, position_y: 1154.0009 });
  add('gameobject', { id: 1731, map: 1, position_x: 100, position_y: 200 });
  add('gameobject', { id: 1731, map: 36, position_x: 5, position_y: 5 }); // an instance
  add('gameobject', { id: 9999, map: 0, position_x: 1, position_y: 1 }); // not in the catalog
  add('gameobject', { id: 1731, map: 0, patch_min: 11, patch_max: 11, position_x: 2, position_y: 2 }); // not yet spawned
  const byContinent = spawns(db, [{ entry: 1731 }]);
  assert.deepEqual(byContinent.get(0), [{ entry: 1731, x: -10603.8, y: 1154 }]);
  assert.deepEqual(byContinent.get(1), [{ entry: 1731, x: 100, y: 200 }]);
});
```

`GatherMap/tools/test/lua.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { nodesFile, spawnFiles, SPAWNS_PER_FILE } from '../lib/lua.mjs';

test('the nodes file hands the catalog to ns.AddNodes', () => {
  const text = nodesFile([
    { entry: 1731, kind: 'ore', name: 'Copper Vein', skill: 1, item: 2770 },
    { entry: 2843, kind: 'chest', name: "Buccaneer's \"Box\"" },
  ]);
  assert.match(text, /^-- Generated by tools\/build-data\.mjs/);
  assert.match(text, /ns\.AddNodes\(\{/);
  assert.match(text, /\[1731\] = \{ kind = "ore", name = "Copper Vein", skill = 1, item = 2770 \},/);
  assert.match(text, /\[2843\] = \{ kind = "chest", name = "Buccaneer's \\"Box\\"" \},/);
});

test('spawn files hold flat entry, x, y lists, split so no file is too big for the client', () => {
  const many = Array.from({ length: SPAWNS_PER_FILE + 1 }, (_, i) => ({ entry: 1731, x: i, y: -i }));
  const files = spawnFiles(new Map([[0, many], [1, [{ entry: 1617, x: 1.5, y: 2 }]]]));
  assert.deepEqual(files.map((f) => f.file), ['EasternKingdoms1.lua', 'EasternKingdoms2.lua', 'Kalimdor1.lua']);
  assert.match(files[0].text, /ns\.AddSpawns\(0, \{/);
  assert.match(files[0].text, /1731, 0, 0, 1731, 1, -1,/);
  assert.match(files[2].text, /ns\.AddSpawns\(1, \{\n    1617, 1\.5, 2,\n\}\)/);
});

test('a continent with no spawns writes no file', () => {
  assert.deepEqual(spawnFiles(new Map([[0, []], [1, []]])), []);
});
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `cd GatherMap; node --no-warnings --test "tools/test/*.test.mjs"; cd ..`
Expected: FAIL, `Cannot find module '../lib/nodes.mjs'` and `'../lib/lua.mjs'`.

- [ ] **Step 4: Write the build library**

`GatherMap/tools/lib/nodes.mjs`:

```js
// Picking the gatherable objects out of vMaNGOS, and where each is spawned.

// vMaNGOS numbers its content patches 0 (1.2) to 10 (1.12), as BossLoot does.
export const TARGET_PATCH = 10;
export const CONTINENTS = [0, 1];

const P = TARGET_PATCH;
const CHEST = 3; // GAMEOBJECT_TYPE_CHEST: herbs, veins and chests alike
const FISHING_HOLE = 25;

const has = (object, key) => Object.prototype.hasOwnProperty.call(object, key);

// Every herb, vein, chest and pool, by entry, sorted by entry. A vein or
// deposit nodes.json has no skill for is an error, so a new ore can never
// ship unfiltered. Herbs have no such tell-tale name, and a missing one only
// goes unlisted.
export function catalog(db, lists) {
  const templates = db.prepare(`
    select entry, type, name, data1 from gameobject_template t
    where t.type in (${CHEST}, ${FISHING_HOLE})
      and t.patch = (select max(x.patch) from gameobject_template x where x.entry = t.entry and x.patch <= ${P})
    order by entry`).all();
  const mainItem = db.prepare(`
    select item from gameobject_loot_template
    where entry = ? and mincountOrRef > 0 and patch_min <= ${P} and ${P} <= patch_max
    order by ChanceOrQuestChance desc, item limit 1`);
  const chests = new Set(lists.chest);

  const nodes = [];
  const errors = [];
  for (const t of templates) {
    let node;
    if (t.type === FISHING_HOLE) node = { entry: t.entry, kind: 'pool', name: t.name };
    else if (has(lists.herb, t.name)) node = { entry: t.entry, kind: 'herb', name: t.name, skill: lists.herb[t.name] };
    else if (has(lists.ore, t.name)) node = { entry: t.entry, kind: 'ore', name: t.name, skill: lists.ore[t.name] };
    else if (chests.has(t.name)) node = { entry: t.entry, kind: 'chest', name: t.name };
    else {
      if (/ (Vein|Deposit)$/.test(t.name)) errors.push(`"${t.name}" (${t.entry}) looks like ore but nodes.json has no skill for it`);
      continue;
    }
    if (node.skill !== undefined && t.data1) {
      const row = mainItem.get(t.data1);
      if (row) node.item = row.item;
    }
    nodes.push(node);
  }
  return { nodes, errors };
}

const round1 = (value) => Math.round(value * 10) / 10;

// Every spawn of the catalog's objects on the two continents, in guid order.
export function spawns(db, nodes) {
  const wanted = new Set(nodes.map((node) => node.entry));
  const byContinent = new Map(CONTINENTS.map((continent) => [continent, []]));
  const rows = db.prepare(`
    select id, map, position_x as x, position_y as y from gameobject
    where map in (${CONTINENTS.join(', ')}) and patch_min <= ${P} and ${P} <= patch_max
    order by guid`).all();
  for (const row of rows) {
    if (wanted.has(row.id)) byContinent.get(row.map).push({ entry: row.id, x: round1(row.x), y: round1(row.y) });
  }
  return byContinent;
}
```

`GatherMap/tools/lib/lua.mjs`:

```js
// Writing GatherMap's generated Lua data files.
import { luaString } from '../../../BossLoot/tools/lib/lua.mjs';

const HEADER = '-- Generated by tools/build-data.mjs from the vMaNGOS world database. Do not edit.';

// Lua 5.1 allows 262143 constants in one chunk; a file of 5000 spawns holds
// at most 15000, far under it, and the client loads each quickly.
export const SPAWNS_PER_FILE = 5000;
export const CONTINENT_FILES = { 0: 'EasternKingdoms', 1: 'Kalimdor' };

export function nodesFile(nodes) {
  const lines = [HEADER, 'local _, ns = ...', '', 'ns.AddNodes({'];
  for (const node of nodes) {
    const fields = [`kind = ${luaString(node.kind)}`, `name = ${luaString(node.name)}`];
    if (node.skill !== undefined) fields.push(`skill = ${node.skill}`);
    if (node.item !== undefined) fields.push(`item = ${node.item}`);
    lines.push(`    [${node.entry}] = { ${fields.join(', ')} },`);
  }
  lines.push('})', '');
  return lines.join('\n');
}

export function spawnFiles(byContinent) {
  const files = [];
  for (const [continent, list] of byContinent) {
    for (let start = 0, part = 1; start < list.length; start += SPAWNS_PER_FILE, part++) {
      const lines = [HEADER, 'local _, ns = ...', '', `ns.AddSpawns(${continent}, {`];
      const chunk = list.slice(start, start + SPAWNS_PER_FILE);
      for (let i = 0; i < chunk.length; i += 10) {
        lines.push(`    ${chunk.slice(i, i + 10).map((s) => `${s.entry}, ${s.x}, ${s.y},`).join(' ')}`);
      }
      lines.push('})', '');
      files.push({ file: `${CONTINENT_FILES[continent]}${part}.lua`, text: lines.join('\n') });
    }
  }
  return files;
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `cd GatherMap; node --no-warnings --test "tools/test/*.test.mjs"; cd ..`
Expected: PASS, 9 tests.

- [ ] **Step 6: Write the failing recordings tests**

`GatherMap/tools/test/recordings.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { readRecordings, applyRecordings, spawnKey } from '../lib/recordings.mjs';
import { confirmedFile } from '../lib/lua.mjs';

const NODES = [{ entry: 1731, kind: 'ore' }, { entry: 180582, kind: 'pool' }];
const world = () => new Map([
  [0, [{ entry: 1731, x: -10133.8, y: 793.8 }, { entry: 1731, x: -10008.9, y: 878.7 }]],
  [1, []],
]);

test('keys match the addon\'s Spawns.Key', () => {
  assert.equal(spawnKey(0, 1731, -10603.8, 1154), '0:1731:-10603.8:1154.0');
});

test('saved-variables files are read, one recorder each; a broken one is a warning', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gathermap-'));
  try {
    writeFileSync(join(dir, 'a.lua'), [
      'GatherMapDB = {',
      '["gathered"] = { ["0:1731:-10133.8:793.8"] = { ["continent"] = 0, ["entry"] = 1731, ["x"] = -10133.8, ["y"] = 793.8, ["count"] = 2, }, },',
      '["missing"] = { ["0:1731:-10008.9:878.7"] = 1790000000, },',
      '}',
      'GatherMapSettings = { ["enabled"] = true, }',
    ].join('\n'));
    writeFileSync(join(dir, 'b.lua'), 'GatherMapDB = { [');
    writeFileSync(join(dir, 'c.lua'), 'BossLootDB = {}');
    writeFileSync(join(dir, 'notes.txt'), 'ignored');
    const { recorders, warnings } = readRecordings(dir);
    assert.equal(recorders.length, 1);
    assert.equal(recorders[0].file, 'a.lua');
    assert.equal(recorders[0].gathered['0:1731:-10133.8:793.8'].count, 2);
    assert.equal(recorders[0].missing['0:1731:-10008.9:878.7'], 1790000000);
    assert.equal(warnings.length, 2);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a missing folder is no recordings', () => {
  assert.deepEqual(readRecordings(join(tmpdir(), 'no-such-gathermap-folder')), { recorders: [], warnings: [] });
});

test('gathered database spawns are confirmed', () => {
  const byContinent = world();
  const { confirmed } = applyRecordings(byContinent, NODES, [
    { gathered: { '0:1731:-10133.8:793.8': { continent: 0, entry: 1731, x: -10133.8, y: 793.8, count: 1 } }, missing: {} },
  ]);
  assert.deepEqual(confirmed, ['0:1731:-10133.8:793.8']);
});

test('a new point joins the spawns, confirmed; one near an existing spawn confirms that instead', () => {
  const byContinent = world();
  const { confirmed, added } = applyRecordings(byContinent, NODES, [
    { gathered: {
      '0:1731:-10300.0:900.1': { continent: 0, entry: 1731, x: -10300.04, y: 900.06, count: 1, new: true },
      '0:1731:-10130.0:790.0': { continent: 0, entry: 1731, x: -10130, y: 790, count: 1, new: true },
      '0:424242:1.0:2.0': { continent: 0, entry: 424242, x: 1, y: 2, count: 1, new: true },
      '36:1731:1.0:2.0': { continent: 36, entry: 1731, x: 1, y: 2, count: 1, new: true },
      bad: { continent: 0, entry: 1731, new: true },
    }, missing: {} },
  ]);
  assert.equal(added, 1);
  assert.equal(byContinent.get(0).length, 3);
  assert.deepEqual(byContinent.get(0)[2], { entry: 1731, x: -10300, y: 900.1 });
  assert.deepEqual(confirmed, ['0:1731:-10133.8:793.8', '0:1731:-10300.0:900.1']);
});

test('two recorders with the same new point add it once', () => {
  const byContinent = world();
  const point = { continent: 0, entry: 1731, x: -10300, y: 900, count: 1, new: true };
  const { added } = applyRecordings(byContinent, NODES, [
    { gathered: { '0:1731:-10300.0:900.0': point }, missing: {} },
    { gathered: { '0:1731:-10301.0:901.0': { ...point, x: -10301, y: 901 } }, missing: {} },
  ]);
  assert.equal(added, 1);
});

test('a spawn marked not here is dropped, unless someone gathered it', () => {
  const byContinent = world();
  const { dropped } = applyRecordings(byContinent, NODES, [
    { gathered: {}, missing: { '0:1731:-10008.9:878.7': 1, '0:1731:-10133.8:793.8': 1 } },
    { gathered: { '0:1731:-10133.8:793.8': { continent: 0, entry: 1731, x: -10133.8, y: 793.8, count: 1 } }, missing: {} },
  ]);
  assert.equal(dropped, 1);
  assert.deepEqual(byContinent.get(0).map((s) => s.x), [-10133.8]);
});

test('the confirmed file hands the keys to ns.AddConfirmed', () => {
  const text = confirmedFile(['0:1731:-10133.8:793.8']);
  assert.match(text, /ns\.AddConfirmed\(\{\n    "0:1731:-10133\.8:793\.8",\n\}\)/);
  assert.match(confirmedFile([]), /ns\.AddConfirmed\(\{\n\}\)/);
});
```

- [ ] **Step 7: Run them to see them fail**

Run: `cd GatherMap; node --no-warnings --test "tools/test/*.test.mjs"; cd ..`
Expected: FAIL, `Cannot find module '../lib/recordings.mjs'`.

- [ ] **Step 8: Write the recordings library and the confirmed file**

`GatherMap/tools/lib/recordings.mjs`:

```js
// Gathers players recorded in WoW Forever, from saved-variables files put in
// tools/recordings/, baked into the release: the game is the authority,
// vMaNGOS only a first guess (BossLoot's lesson).
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { parseSavedVariables } from '../../../BossLoot/tools/lib/savedvars.mjs';

export const REACH = 15;

const round1 = (value) => Math.round(value * 10) / 10;

// The same key as the addon's Spawns.Key: "%d:%d:%.1f:%.1f".
export function spawnKey(continent, entry, x, y) {
  return `${continent}:${entry}:${x.toFixed(1)}:${y.toFixed(1)}`;
}

/** Each file's GatherMapDB, in file-name order. */
export function readRecordings(dir) {
  if (!existsSync(dir)) return { recorders: [], warnings: [] };
  const recorders = [];
  const warnings = [];
  for (const file of readdirSync(dir).filter((name) => name.endsWith('.lua')).sort()) {
    let vars;
    try {
      vars = parseSavedVariables(readFileSync(join(dir, file), 'utf8'));
    } catch (error) {
      warnings.push(`${file}: ${error.message}`);
      continue;
    }
    const db = vars.GatherMapDB;
    if (!db || typeof db !== 'object') {
      warnings.push(`${file}: no GatherMap recordings`);
      continue;
    }
    recorders.push({ file, gathered: db.gathered ?? {}, missing: db.missing ?? {} });
  }
  return { recorders, warnings };
}

/**
 * Fold the recordings into the database's spawns, in place: new points join,
 * spawns marked "not here" by someone and gathered by no one leave. Returns
 * the keys of every spawn someone gathered, sorted.
 */
export function applyRecordings(byContinent, nodes, recorders) {
  const known = new Set(nodes.map((node) => node.entry));
  const gathered = new Set();
  const missing = new Set();
  for (const recorder of recorders) {
    for (const key of Object.keys(recorder.gathered)) gathered.add(key);
    for (const key of Object.keys(recorder.missing)) missing.add(key);
  }

  let dropped = 0;
  for (const [continent, list] of byContinent) {
    const kept = list.filter((s) => {
      const key = spawnKey(continent, s.entry, s.x, s.y);
      return !(missing.has(key) && !gathered.has(key));
    });
    dropped += list.length - kept.length;
    byContinent.set(continent, kept);
  }

  const confirmed = new Set();
  let added = 0;
  for (const recorder of recorders) {
    for (const [key, point] of Object.entries(recorder.gathered)) {
      const list = byContinent.get(point?.continent);
      if (!list || !known.has(point.entry) || typeof point.x !== 'number' || typeof point.y !== 'number') continue;
      const x = round1(point.x);
      const y = round1(point.y);
      const near = list.find((s) => s.entry === point.entry && Math.hypot(s.x - x, s.y - y) <= REACH);
      if (near) {
        confirmed.add(spawnKey(point.continent, near.entry, near.x, near.y));
      } else if (point.new) {
        list.push({ entry: point.entry, x, y });
        confirmed.add(spawnKey(point.continent, point.entry, x, y));
        added++;
      } else {
        confirmed.add(key);
      }
    }
  }

  return { confirmed: [...confirmed].sort(), added, dropped };
}
```

Append to `GatherMap/tools/lib/lua.mjs`:

```js
export function confirmedFile(keys) {
  const lines = [HEADER, '-- Spawns players have gathered in WoW Forever, from tools/recordings/.', 'local _, ns = ...', '', 'ns.AddConfirmed({'];
  for (const key of keys) lines.push(`    ${luaString(key)},`);
  lines.push('})', '');
  return lines.join('\n');
}
```

(The HEADER comment and the new comment line both start with `--`, so the Lua file still loads.)

`GatherMap/tools/recordings/README.md`:

```markdown
Saved-variables files with GatherMap recordings go here, to be baked into
the next release: `WTF/Account/<name>/SavedVariables/GatherMap.lua`, renamed
to anything ending in `.lua` (one per player). The build reads them all:
their new points join the spawns, their gathers mark spawns confirmed, and a
spawn someone marked "not here" and nobody gathered is left out.
```

- [ ] **Step 9: Run the tests to see them pass**

Run: `cd GatherMap; node --no-warnings --test "tools/test/*.test.mjs"; cd ..`
Expected: PASS, 17 tests.

- [ ] **Step 10: Write the build script**

`GatherMap/tools/build-data.mjs`:

```js
// Regenerates GatherMap/Data/ from vMaNGOS's world database and
// tools/nodes.json.
//
//   node GatherMap/tools/build-data.mjs <path to mangos.sqlite>
//
// The database comes from the db_latest release on github.com/vmangos/core
// (db-sqlite-<commit>.zip). Neither it nor this script ships in the addon.
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { catalog, spawns } from './lib/nodes.mjs';
import { nodesFile, spawnFiles, confirmedFile } from './lib/lua.mjs';
import { readRecordings, applyRecordings } from './lib/recordings.mjs';
import { updateToc } from '../../BossLoot/tools/lib/lua.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const addon = join(here, '..');

const dbPath = process.argv[2];
if (!dbPath) {
  console.error('usage: node GatherMap/tools/build-data.mjs <path to mangos.sqlite>');
  process.exit(2);
}

const lists = JSON.parse(readFileSync(join(here, 'nodes.json'), 'utf8'));
const db = new DatabaseSync(dbPath, { readOnly: true });

const { nodes: all, errors } = catalog(db, lists);
for (const error of errors) console.error(`error ${error}`);

const byContinent = spawns(db, all);

// What players recorded in WoW Forever outranks vMaNGOS.
const { recorders, warnings: recordingWarnings } = readRecordings(join(here, 'recordings'));
for (const warning of recordingWarnings) console.warn(`warn  ${warning}`);
const { confirmed, added, dropped } = applyRecordings(byContinent, all, recorders);
console.log(`ok    ${recorders.length} recordings: ${confirmed.length} confirmed, ${added} new, ${dropped} not there`);

const spawned = new Set([...byContinent.values()].flat().map((s) => s.entry));
const nodes = all.filter((node) => spawned.has(node.entry));

// A name in nodes.json that matched nothing is most likely misspelt.
const names = new Set(nodes.map((node) => node.name));
for (const name of [...Object.keys(lists.herb), ...Object.keys(lists.ore), ...lists.chest]) {
  if (!names.has(name)) console.warn(`warn  "${name}" in nodes.json has no spawns`);
}

const dataDir = join(addon, 'Data');
rmSync(dataDir, { recursive: true, force: true });
mkdirSync(dataDir);

writeFileSync(join(dataDir, 'Nodes.lua'), nodesFile(nodes));
const files = ['Nodes.lua'];
for (const { file, text } of spawnFiles(byContinent)) {
  writeFileSync(join(dataDir, file), text);
  files.push(file);
}
writeFileSync(join(dataDir, 'Confirmed.lua'), confirmedFile(confirmed));
files.push('Confirmed.lua');

const tocPath = join(addon, 'GatherMap.toc');
writeFileSync(tocPath, updateToc(readFileSync(tocPath, 'utf8'), files));

for (const kind of ['herb', 'ore', 'pool', 'chest']) {
  console.log(`ok    ${nodes.filter((n) => n.kind === kind).length} ${kind} nodes`);
}
for (const [continent, list] of byContinent) console.log(`ok    continent ${continent}: ${list.length} spawns`);

if (errors.length) {
  console.error(`${errors.length} error(s): fix tools/nodes.json and run again.`);
  process.exit(1);
}
```

(It needs `GatherMap.toc`, which Task 2 creates; the real run is Task 10.)

- [ ] **Step 11: Commit**

```bash
git add GatherMap/tools
git commit -m "GatherMap: the build that turns vMaNGOS and players' recordings into node and spawn data

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The addon shell and its test harness

**Files:**
- Create: `GatherMap/GatherMap.toc`, `GatherMap/GatherMap.lua`
- Create: `GatherMap/tests/runner.lua` (copy of `FishScale/tests/runner.lua`, unchanged)
- Create: `GatherMap/tests/wow_stub.lua`, `GatherMap/tests/helpers.lua`, `GatherMap/tests/fixture_data.lua`
- Test: `GatherMap/tests/core_spec.lua`

**Interfaces:**
- Produces: `ns.PREFIX`, `ns.AddDefaults(table)`, `ns.Print(msg)`, `ns.Guarded(fn, whenUnknown)`, `ns.RegisterCommand(name, help, handler(rest))`, `ns.OnLogin(fn)`, `ns.OnRefresh(fn)`, `ns.Refresh()`, `ns.SetEnabled(bool)`, `ns.Nodes` (entry -> node), `ns.rawSpawns` (continent -> flat list), `ns.confirmed` (key -> true), `ns.AddNodes(t)`, `ns.AddSpawns(continent, flat)`, `ns.AddConfirmed(keys)`, `ns.db` (= `GatherMapDB`, with `gathered` and `missing`), `ns.settings` (= `GatherMapSettings`, with `enabled`). `ns.OpenSettings` is optional (Task 8): a bare `/gmap` calls it when present.
- Test helpers: `helpers.loadAddon()`, `helpers.loggedIn(setup)`, `helpers.login(ns, env)`, `helpers.fire(env, event, ...)`, `helpers.command(env, text)`, `helpers.printed(env)`, `helpers.FILES`.

- [ ] **Step 1: Write the TOC**

`GatherMap/GatherMap.toc` (later tasks add their file below the markers, in this order):

```
## Interface: 11509, 16001
## Title: GatherMap
## Notes: Herbs, ore, fishing pools and chests on the world map and the minimap.
## IconTexture: Interface\AddOns\GatherMap\icon
## Author: You
## Version: 0.1.0
## SavedVariables: GatherMapDB, GatherMapSettings

GatherMap.lua
# BEGIN GENERATED DATA
# END GENERATED DATA
```

- [ ] **Step 2: Copy the runner, write the stub, fixture and helpers**

Copy `FishScale/tests/runner.lua` to `GatherMap/tests/runner.lua` unchanged.

`GatherMap/tests/wow_stub.lua` (the whole stub; later tasks only use it):

```lua
-- A minimal stand-in for the WoW API, enough to load GatherMap outside the
-- game. Widgets record what was done to them so tests can assert on it.

local stub = {}

local function makeWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        scripts = {},
        registeredEvents = {},
        points = {},
        shown = true,
        scale = 1,
        frameLevel = parent and (parent.frameLevel or 1) + 1 or 1,
    }

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then existing(...) end
            fn(...)
        end
    end
    function widget:SetPoint(...) table.insert(self.points, { ... }) end
    function widget:ClearAllPoints() self.points = {} end
    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then return table.unpack(point) end
    end
    function widget:SetAllPoints() end
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:SetWidth(value) self.width = value end
    function widget:SetHeight(value) self.height = value end
    function widget:GetWidth() return self.width or 0 end
    function widget:GetHeight() return self.height or 0 end
    function widget:SetScale(value) self.scale = value end
    function widget:GetScale() return self.scale end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:GetAlpha() return self.alpha or 1 end
    function widget:GetParent() return self.parent end
    function widget:SetFrameStrata(value) self.strata = value end
    function widget:SetFrameLevel(value) self.frameLevel = value end
    function widget:GetFrameLevel() return self.frameLevel end
    -- Showing and hiding fire their scripts, and only on a real transition.
    function widget:Show()
        if self.shown then return end
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function widget:Hide()
        if not self.shown then return end
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function widget:SetShown(value) if value then self:Show() else self:Hide() end end
    function widget:IsShown() return self.shown end
    function widget:GetCenter() return self.centerX or 0, self.centerY or 0 end
    function widget:GetEffectiveScale() return 1 end
    function widget:CreateTexture() return makeWidget("Texture", self) end
    function widget:CreateFontString() return makeWidget("FontString", self) end
    function widget:SetTexture(value) self.texture = value end
    function widget:GetTexture() return self.texture end
    function widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function widget:SetTexCoord(...) self.texCoord = { ... } end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function widget:SetJustifyH(value) self.justifyH = value end
    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end
    function widget:EnableMouse(value) self.mouseEnabled = value end
    function widget:RegisterForClicks(...) self.clicks = { ... } end
    function widget:RegisterForDrag(...) self.drag = { ... } end
    function widget:SetHighlightTexture(value) self.highlightTexture = value end
    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:GetName() return self.frameName end
    -- Sliders: setting a new value fires OnValueChanged, as the client does.
    function widget:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
    function widget:SetValueStep(value) self.valueStep = value end
    function widget:SetObeyStepOnDrag(value) self.obeyStep = value end
    function widget:SetValue(value)
        if self.value == value then return end
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function widget:GetValue() return self.value end
    function widget:SetScrollChild(child) self.scrollChild = child end
    -- Tooltips.
    function widget:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function widget:GetOwner() return self.owner end
    function widget:AddLine(text, r, g, b)
        self.lines = self.lines or {}
        table.insert(self.lines, { text = text, color = { r, g, b } })
    end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end

    return widget
end

stub.makeWidget = makeWidget

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__printed = {}
    env._G = env

    env.UIParent = makeWidget("Frame")
    env.GameTooltip = makeWidget("GameTooltip", env.UIParent)
    env.GameTooltip.shown = false
    -- SetText starts a tooltip afresh.
    function env.GameTooltip:SetText(value) self.text = value; self.lines = {} end
    env.SlashCmdList = {}

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do pieces[index] = tostring((select(index, ...))) end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent)
        local frame = makeWidget(kind or "Frame", parent)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    -- Time: GetTime in seconds since the client started, time() the clock.
    env.__now = 100
    env.__time = 1790000000
    function env.GetTime() return env.__now end
    function env.time() return env.__time end
    env.C_Timer = { After = function(_, fn) fn() end }
    function env.InCombatLockdown() return false end

    -- The game's options window and the game menu, both closed.
    env.SettingsPanel = makeWidget("Frame", env.UIParent)
    env.SettingsPanel.shown = false
    env.GameMenuFrame = makeWidget("Frame", env.UIParent)
    env.GameMenuFrame.shown = false
    function env.HideUIPanel(frame) if frame and frame.Hide then frame:Hide() end end
    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return { name = name, frame = frame, GetID = function() return "category-id" end }
        end,
        RegisterAddOnCategory = function(category) env.__settingsCategory = category end,
        OpenToCategory = function(id) env.__openedCategory = id end,
    }
    env.C_AddOns = {
        GetAddOnMetadata = function(_, field) return field == "Version" and "9.9.9" or nil end,
    }

    -- Where the player is: UnitPosition's x, y, z and instance. The probe's
    -- spot in Westfall, on continent 0.
    env.__position = { -10603.8, 1154.0, 0, 0 }
    function env.UnitPosition()
        local p = env.__position
        if p then return p[1], p[2], p[3], p[4] end
    end
    env.__facing = 0
    function env.GetPlayerFacing() return env.__facing end
    env.__indoors = false
    function env.IsIndoors() return env.__indoors end
    env.__cvars = { rotateMinimap = "0" }
    function env.GetCVar(name) return env.__cvars[name] end

    -- Maps: each map's continent and the world positions of its top-left
    -- (x0, y0) and bottom-right (x1, y1) corners. A Westfall of round
    -- numbers; 947, the whole world, has no place.
    function env.CreateVector2D(x, y) return { x = x, y = y } end
    env.__maps = {
        [1436] = { continent = 0, x0 = -10000, y0 = 2000, x1 = -11000, y1 = 1000 },
    }
    env.__playerMap = 1436
    env.C_Map = {
        -- A map's x follows world Y and its y follows world X.
        GetWorldPosFromMapPos = function(mapID, pos)
            local m = env.__maps[mapID]
            if not m then return nil end
            return m.continent, env.CreateVector2D(m.x0 + (m.x1 - m.x0) * pos.y, m.y0 + (m.y1 - m.y0) * pos.x)
        end,
        GetBestMapForUnit = function() return env.__playerMap end,
        GetPlayerMapPosition = function(mapID)
            local m, p = env.__maps[mapID], env.__position
            if not m or not p then return nil end
            return env.CreateVector2D((p[2] - m.y0) / (m.y1 - m.y0), (p[1] - m.x0) / (m.x1 - m.x0))
        end,
    }

    -- The minimap, 140 pixels across, at zoom 0.
    env.Minimap = env.CreateFrame("Frame", "Minimap", env.UIParent)
    env.Minimap:SetSize(140, 140)
    env.__zoom = 0
    function env.Minimap:GetZoom() return env.__zoom end

    -- The world map, closed, on 1436; its canvas 1000 by 700 at scale 1.
    env.WorldMapFrame = makeWidget("Frame", env.UIParent)
    env.WorldMapFrame.shown = false
    local canvas = makeWidget("Frame", env.WorldMapFrame)
    canvas:SetSize(1000, 700)
    env.__worldMapID = 1436
    env.__canvasScale = 1
    env.__providers = {}
    function env.WorldMapFrame:GetCanvas() return canvas end
    function env.WorldMapFrame:GetMapID() return env.__worldMapID end
    function env.WorldMapFrame:GetCanvasScale() return env.__canvasScale end
    function env.WorldMapFrame:AddDataProvider(provider)
        table.insert(env.__providers, provider)
        provider:OnAdded(self)
    end
    -- Test helpers: the map turns to another map, or zooms.
    function env.__changeMap(id)
        env.__worldMapID = id
        for _, provider in ipairs(env.__providers) do provider:OnMapChanged() end
    end
    function env.__zoomMap(scale)
        env.__canvasScale = scale
        for _, provider in ipairs(env.__providers) do provider:OnCanvasScaleChanged() end
    end
    env.MapCanvasDataProviderMixin = {
        OnAdded = function(self, map) self.owningMap = map end,
        GetMap = function(self) return self.owningMap end,
        RefreshAllData = function() end,
        RemoveAllData = function() end,
        OnMapChanged = function(self) self:RefreshAllData() end,
        OnCanvasScaleChanged = function() end,
    }
    function env.CreateFromMixins(...)
        local object = {}
        for index = 1, select("#", ...) do
            for key, value in pairs((select(index, ...))) do object[key] = value end
        end
        return object
    end

    -- Loot: the GUID GetLootSourceInfo gives for the open window.
    env.__lootSource = nil
    function env.GetLootSourceInfo() return env.__lootSource end

    -- Skills: { name, isHeader, rank, isExpanded (headers only, default true) }.
    env.__skills = {
        { "Professions", true },
        { "Herbalism", false, 50 },
        { "Mining", false, 70 },
    }
    function env.GetNumSkillLines() return #env.__skills end
    function env.GetSkillLineInfo(index)
        local line = env.__skills[index]
        local expanded = line[4]
        if expanded == nil then expanded = true end
        return line[1], line[2], expanded, line[3] or 0
    end

    -- Item icons: a fake file ID per item.
    env.C_Item = { GetItemIconByID = function(id) return 1000 + id end }

    return env
end

return stub
```

`GatherMap/tests/fixture_data.lua`:

```lua
-- Test data in the shape of the generated Data files: a few nodes, and
-- spawns placed around the probe's spot in Westfall (-10603.8, 1154.0).
local _, ns = ...

ns.AddNodes({
    [1731] = { kind = "ore", name = "Copper Vein", skill = 1, item = 2770 },
    [3764] = { kind = "ore", name = "Tin Vein", skill = 65, item = 2771 },
    [1617] = { kind = "herb", name = "Silverleaf", skill = 1, item = 765 },
    [1618] = { kind = "herb", name = "Peacebloom", skill = 1, item = 2447 },
    [1619] = { kind = "herb", name = "Earthroot", skill = 15, item = 2449 },
    [2045] = { kind = "herb", name = "Stranglekelp", skill = 85, item = 3820 },
    [180582] = { kind = "pool", name = "Oily Blackmouth School" },
    [2843] = { kind = "chest", name = "Battered Chest" },
})

ns.AddSpawns(0, {
    1731, -10603.8, 1154.0,  -- A: under the player
    1731, -10000.0, 1000.0,  -- B: the map's top-right corner, 623 yards off
    3764, -10610.0, 1160.0,  -- C: 8.6 yards off
    1617, -9000.0, 500.0,    -- D: off map 1436
    180582, -10620.0, 1170.0, -- E: a pool 22.8 yards off
    2843, -10700.0, 1300.0,  -- F: a chest 175 yards off
    99999, -10600.0, 1150.0, -- an object the catalog does not know
})

ns.AddSpawns(1, {
    1618, 100.0, 200.0,
})

-- C, the Tin Vein, confirmed by a baked recording.
ns.AddConfirmed({
    "0:3764:-10610.0:1160.0",
})
```

`GatherMap/tests/helpers.lua`:

```lua
local stub = require("wow_stub")

local M = {}

-- In .toc order, with the test data where the generated Data files go.
-- Each task adds its own file here.
M.FILES = {
    "GatherMap.lua",
    "tests/fixture_data.lua",
}

--- Load the addon's files into a stubbed environment, the way WoW would:
-- in .toc order, each chunk receiving (addonName, privateTable).
function M.loadAddon(files)
    local env = stub.newEnv()
    local ns = {}
    for _, path in ipairs(files or M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("GatherMap", ns)
    end
    return ns, env
end

--- Fire an event on every frame registered for it.
function M.fire(env, event, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do frames[index] = frame end
    for _, frame in ipairs(frames) do
        if frame.registeredEvents[event] then frame:Fire(event, ...) end
    end
end

function M.login(ns, env)
    M.fire(env, "ADDON_LOADED", "GatherMap")
    M.fire(env, "PLAYER_LOGIN")
end

--- Loaded, `setup(env)` run on the stub if given, then logged in.
function M.loggedIn(setup)
    local ns, env = M.loadAddon()
    if setup then setup(env) end
    M.login(ns, env)
    return ns, env
end

function M.command(env, text)
    env.SlashCmdList.GATHERMAP(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

return M
```

- [ ] **Step 3: Write the failing core spec**

`GatherMap/tests/core_spec.lua`:

```lua
local helpers = require("helpers")

describe("the saved variables", function()
    it("start with pins on and nothing gathered", function()
        local ns, env = helpers.loggedIn()
        assertTrue(ns.settings.enabled)
        assertEqual(env.GatherMapSettings, ns.settings)
        assertEqual(env.GatherMapDB, ns.db)
        assertEqual("table", type(ns.db.gathered))
        assertEqual("table", type(ns.db.missing))
    end)

    it("keep what was saved", function()
        local ns = helpers.loggedIn(function(env)
            env.GatherMapSettings = { enabled = false }
            env.GatherMapDB = { gathered = { x = { count = 2 } } }
        end)
        assertFalse(ns.settings.enabled)
        assertEqual(2, ns.db.gathered.x.count)
    end)

    it("replace a saved value that is not a table", function()
        local ns = helpers.loggedIn(function(env) env.GatherMapDB = "broken" end)
        assertEqual("table", type(ns.db.gathered))
    end)
end)

describe("the data files", function()
    it("hand over the catalog and the spawns", function()
        local ns = helpers.loadAddon()
        assertEqual("Copper Vein", ns.Nodes[1731].name)
        assertEqual(1731, ns.rawSpawns[0][1])
        assertEqual(1618, ns.rawSpawns[1][1])
        assertTrue(ns.confirmed["0:3764:-10610.0:1160.0"])
    end)
end)

describe("refreshing", function()
    it("runs every refresher", function()
        local ns = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        ns.OnRefresh(function() count = count + 10 end)
        ns.Refresh()
        assertEqual(11, count)
    end)

    it("happens when pins are turned off or on", function()
        local ns = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        ns.SetEnabled(false)
        assertFalse(ns.settings.enabled)
        assertEqual(1, count)
    end)
end)

describe("commands", function()
    it("list themselves for /gmap help", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "help")
        assertMatch("/gmap toggle", helpers.printed(env))
    end)

    it("turn the pins off and on with /gmap toggle, and say so", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "toggle")
        assertFalse(ns.settings.enabled)
        assertMatch("Pins hidden", helpers.printed(env))
        helpers.command(env, "toggle")
        assertTrue(ns.settings.enabled)
        assertMatch("Pins shown", helpers.printed(env))
    end)

    it("name an unknown command and list the rest", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "fly")
        assertMatch("Unknown command: fly", helpers.printed(env))
    end)

    it("answer to /gathermap and /gmap", function()
        local ns, env = helpers.loggedIn()
        assertEqual("/gathermap", env.SLASH_GATHERMAP1)
        assertEqual("/gmap", env.SLASH_GATHERMAP2)
    end)
end)
```

- [ ] **Step 4: Run it to see it fail**

Run: `.\run-tests.ps1 GatherMap`
Expected: FAIL, `cannot open GatherMap.lua`.

- [ ] **Step 5: Write the shell**

`GatherMap/GatherMap.lua`:

```lua
local addonName, ns = ...

ns.PREFIX = "|cff7ccc5cGatherMap|r"

-- Defaults are contributed by each file at load time, so every piece of config
-- lives next to the code that reads it and this file never learns the others.
local defaults = {
    version = 1,
    enabled = true,
}

--- Merge a defaults table into a saved table without clobbering stored values.
local function applyDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            applyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

--- Register additional defaults. Called at file load, before ADDON_LOADED.
function ns.AddDefaults(extra)
    applyDefaults(defaults, extra)
end

function ns.Print(message)
    print(string.format("%s %s", ns.PREFIX, message))
end

--- Call `fn` and return what it returns, or `whenUnknown` if it raises.
-- This client hands addon code some values as secrets: the call succeeds,
-- but comparing or testing the result raises. The branch has to happen
-- inside `fn`, not on a value fetched through here and tested outside.
function ns.Guarded(fn, whenUnknown)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return whenUnknown
end

-- The catalog and the spawns, handed over by the generated Data files as
-- they load. Spawns.lua turns the flat lists into its index at login.
ns.Nodes = {}
ns.rawSpawns = {}
-- Spawns players gathered in WoW Forever, baked into the release.
ns.confirmed = {}

function ns.AddConfirmed(keys)
    for _, key in ipairs(keys) do
        ns.confirmed[key] = true
    end
end

function ns.AddNodes(nodes)
    for entry, node in pairs(nodes) do
        ns.Nodes[entry] = node
    end
end

function ns.AddSpawns(continent, flat)
    local list = ns.rawSpawns[continent]
    if not list then
        list = {}
        ns.rawSpawns[continent] = list
    end
    for index = 1, #flat do
        list[#list + 1] = flat[index]
    end
end

local function ensureDatabase()
    if type(GatherMapDB) ~= "table" then
        GatherMapDB = {}
    end
    if type(GatherMapDB.gathered) ~= "table" then
        GatherMapDB.gathered = {}
    end
    if type(GatherMapDB.missing) ~= "table" then
        GatherMapDB.missing = {}
    end
    ns.db = GatherMapDB

    if type(GatherMapSettings) ~= "table" then
        GatherMapSettings = {}
    end
    applyDefaults(GatherMapSettings, defaults)
    ns.settings = GatherMapSettings
end

-- Whatever draws pins registers here, and redraws when anything they depend
-- on changes: a filter, a skill, a new gather.
local refreshers = {}

function ns.OnRefresh(fn)
    table.insert(refreshers, fn)
end

function ns.Refresh()
    for _, fn in ipairs(refreshers) do
        fn()
    end
end

function ns.SetEnabled(value)
    ns.settings.enabled = value and true or false
    ns.Refresh()
end

-- Slash commands. Each file registers its own, so a feature owns its commands
-- and its help text.
local commands = {}
ns.commands = commands

function ns.RegisterCommand(name, help, handler)
    commands[name] = { help = help, handler = handler }
end

local function showHelp()
    ns.Print("Commands:")
    local names = {}
    for name in pairs(commands) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        ns.Print(string.format("/gmap %s - %s", name, commands[name].help))
    end
end

local function runCommand(msg)
    local input = msg and msg:match("^%s*(.-)%s*$") or ""

    if input == "" and ns.OpenSettings then
        ns.OpenSettings()
        return
    end
    if input == "" or input == "help" then
        showHelp()
        return
    end

    local name, rest = input:match("^(%S+)%s*(.-)$")
    name = name and name:lower() or ""

    local command = commands[name]
    if command then
        command.handler(rest)
        return
    end

    ns.Print(string.format("Unknown command: %s", name))
    showHelp()
end

-- Not /gm: that is the game's own help-ticket command.
SLASH_GATHERMAP1 = "/gathermap"
SLASH_GATHERMAP2 = "/gmap"
SlashCmdList.GATHERMAP = runCommand

ns.RegisterCommand("toggle", "Show or hide every pin", function()
    ns.SetEnabled(not ns.settings.enabled)
    ns.Print(ns.settings.enabled and "Pins shown." or "Pins hidden.")
end)

-- Work to do once the player is in the world and the database exists.
local loginHandlers = {}

function ns.OnLogin(handler)
    table.insert(loginHandlers, handler)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ensureDatabase()
    elseif event == "PLAYER_LOGIN" then
        ensureDatabase()
        for _, handler in ipairs(loginHandlers) do
            handler()
        end
        ns.Print("Loaded. Type /gmap for settings, or /gmap help for commands.")
    end
end)
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `.\run-tests.ps1 GatherMap`
Expected: PASS (all core specs, and Task 1's Node tests).

- [ ] **Step 7: Commit**

```bash
git add GatherMap
git commit -m "GatherMap: the addon shell, its commands and test harness

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Geometry and the spawn index

**Files:**
- Create: `GatherMap/Geometry.lua`, `GatherMap/Spawns.lua`
- Modify: `GatherMap/GatherMap.toc` (append `Geometry.lua`, `Spawns.lua` after the END marker), `GatherMap/tests/helpers.lua` (append the same two to `M.FILES`)
- Test: `GatherMap/tests/geometry_spec.lua`, `GatherMap/tests/spawns_spec.lua`

**Interfaces:**
- Consumes: `ns.Guarded`, `ns.Nodes`, `ns.rawSpawns`, `ns.db.gathered`, `ns.OnLogin`.
- Produces:
  - `ns.Geometry.MapRect(uiMapID) -> { continent, x0, y0, x1, y1 } | nil`
  - `ns.Geometry.ToMap(rect, x, y) -> mapX, mapY`
  - `ns.Geometry.MinimapDiameter(zoom, indoors) -> yards`
  - `ns.Geometry.MinimapOffset(px, py, x, y, facing, rotate) -> right, up` (yards)
  - A spawn is `{ continent, entry, x, y, key }`.
  - `ns.Spawns.Key(continent, entry, x, y) -> string`, `ns.Spawns.Load()`, `ns.Spawns.All(continent) -> spawn[]`, `ns.Spawns.ByKey(key) -> spawn|nil`, `ns.Spawns.Near(continent, x, y, radius, fn(spawn))`, `ns.Spawns.Nearest(continent, entry, x, y, radius) -> spawn|nil`, `ns.Spawns.AddPoint(continent, entry, x, y) -> spawn`, `ns.Spawns.version` (number, bumped by every spawn added after login).

- [ ] **Step 1: Write the failing specs**

`GatherMap/tests/geometry_spec.lua`:

```lua
local helpers = require("helpers")

describe("a map's place in the world", function()
    it("is read from the corners the game reports, and kept", function()
        local ns, env = helpers.loggedIn()
        local rect = ns.Geometry.MapRect(1436)
        assertEqual(0, rect.continent)
        assertEqual(-10000, rect.x0)
        assertEqual(2000, rect.y0)
        assertEqual(-11000, rect.x1)
        assertEqual(1000, rect.y1)
        env.__maps[1436] = nil
        assertTrue(ns.Geometry.MapRect(1436) == rect, "a map's place never moves, so it is asked once")
    end)

    it("is nil for a map the game cannot place, or no map", function()
        local ns = helpers.loggedIn()
        assertNil(ns.Geometry.MapRect(947))
        assertNil(ns.Geometry.MapRect(nil))
    end)

    it("is nil when the client refuses", function()
        local ns, env = helpers.loggedIn()
        env.C_Map.GetWorldPosFromMapPos = function() error("secret") end
        assertNil(ns.Geometry.MapRect(1436))
    end)
end)

describe("a world position on a map", function()
    it("runs across with world Y and down with world X", function()
        local ns = helpers.loggedIn()
        local x, y = ns.Geometry.ToMap(ns.Geometry.MapRect(1436), -10603.8, 1154.0)
        assertNear(0.846, x)
        assertNear(0.6038, y)
    end)

    it("agrees with where the game puts the player", function()
        local ns, env = helpers.loggedIn()
        local game = env.C_Map.GetPlayerMapPosition(1436, "player")
        local x, y = ns.Geometry.ToMap(ns.Geometry.MapRect(1436), -10603.8, 1154.0)
        assertNear(game.x, x)
        assertNear(game.y, y)
    end)
end)

describe("the minimap", function()
    it("is as many yards across as the client draws, by zoom, in and out of doors", function()
        local ns = helpers.loggedIn()
        assertNear(466.667, ns.Geometry.MinimapDiameter(0, false))
        assertNear(133.333, ns.Geometry.MinimapDiameter(5, false))
        assertNear(300, ns.Geometry.MinimapDiameter(0, true))
        assertNear(50, ns.Geometry.MinimapDiameter(5, true))
        assertNear(466.667, ns.Geometry.MinimapDiameter(nil, nil), 0.001, "no zoom reads as zoom 0")
    end)

    it("puts north up and west to the left", function()
        local ns = helpers.loggedIn()
        local right, up = ns.Geometry.MinimapOffset(0, 0, 10, 0)
        assertNear(0, right)
        assertNear(10, up)
        right, up = ns.Geometry.MinimapOffset(0, 0, 0, 10)
        assertNear(-10, right)
        assertNear(0, up)
    end)

    it("turns with the player when the minimap turns", function()
        local ns = helpers.loggedIn()
        local right, up = ns.Geometry.MinimapOffset(0, 0, 0, 10, math.pi / 2, true)
        assertNear(0, right, 0.001, "facing west, west is up")
        assertNear(10, up)
        right, up = ns.Geometry.MinimapOffset(0, 0, 10, 0, math.pi * 1.5, true)
        assertNear(-10, right, 0.001, "facing east, north is to the left")
        assertNear(0, up)
        right, up = ns.Geometry.MinimapOffset(0, 0, 0, 10, math.pi / 2, false)
        assertNear(-10, right, 0.001, "a still minimap ignores the facing")
    end)
end)
```

`GatherMap/tests/spawns_spec.lua`:

```lua
local helpers = require("helpers")

local A = "0:1731:-10603.8:1154.0"

describe("the spawn index", function()
    it("takes every data spawn the catalog knows, per continent", function()
        local ns = helpers.loggedIn()
        assertEqual(6, #ns.Spawns.All(0), "the unknown object is left out")
        assertEqual(1, #ns.Spawns.All(1))
        assertEqual(0, #ns.Spawns.All(36))
    end)

    it("keys a spawn by continent, entry and position to a tenth of a yard", function()
        local ns = helpers.loggedIn()
        assertEqual(A, ns.Spawns.Key(0, 1731, -10603.8, 1154))
        local spawn = ns.Spawns.ByKey(A)
        assertEqual(1731, spawn.entry)
        assertEqual(0, spawn.continent)
    end)

    it("finds what is within reach, and nothing further", function()
        local ns = helpers.loggedIn()
        local found = {}
        ns.Spawns.Near(0, -10603.8, 1154.0, 15, function(spawn) found[#found + 1] = spawn.entry end)
        table.sort(found)
        assertEqual(2, #found)
        assertEqual(1731, found[1])
        assertEqual(3764, found[2])
    end)

    it("looks across a cell border", function()
        local ns = helpers.loggedIn()
        local found = 0
        ns.Spawns.Near(0, -10001, 999, 5, function() found = found + 1 end)
        assertEqual(1, found, "B sits on the corner of four cells")
    end)

    it("finds the nearest spawn of one entry", function()
        local ns = helpers.loggedIn()
        assertEqual(A, ns.Spawns.Nearest(0, 1731, -10600, 1150, 15).key)
        assertEqual(3764, ns.Spawns.Nearest(0, 3764, -10603.8, 1154.0, 15).entry)
        assertNil(ns.Spawns.Nearest(0, 180582, -10603.8, 1154.0, 15), "the pool is 22.8 yards off")
        assertEqual(180582, ns.Spawns.Nearest(0, 180582, -10603.8, 1154.0, 30).entry)
        assertNil(ns.Spawns.Nearest(1, 1731, -10603.8, 1154.0, 30), "another continent")
    end)

    it("adds a new point, rounded, and counts the change", function()
        local ns = helpers.loggedIn()
        local version = ns.Spawns.version
        local spawn = ns.Spawns.AddPoint(0, 1731, -10555.04, 1111.06)
        assertEqual("0:1731:-10555.0:1111.1", spawn.key)
        assertTrue(ns.Spawns.ByKey(spawn.key) == spawn)
        assertEqual(version + 1, ns.Spawns.version)
        assertTrue(ns.Spawns.AddPoint(0, 1731, -10555.04, 1111.06) == spawn, "the same place twice is one point")
    end)

    it("loads the new points the player found before", function()
        local key = "0:1731:-10500.0:1100.0"
        local ns = helpers.loggedIn(function(env)
            env.GatherMapDB = { gathered = {
                [key] = { continent = 0, entry = 1731, x = -10500.0, y = 1100.0, count = 1, new = true },
                ["0:1731:-10603.8:1154.0"] = { continent = 0, entry = 1731, x = -10603.8, y = 1154.0, count = 4 },
            } }
        end)
        assertEqual(key, ns.Spawns.ByKey(key).key)
        assertEqual(7, #ns.Spawns.All(0), "a gathered data spawn is not added twice")
    end)

    it("skips a saved point it cannot place", function()
        local ns = helpers.loggedIn(function(env)
            env.GatherMapDB = { gathered = {
                bad1 = { continent = 0, entry = 1731, new = true },
                bad2 = { continent = 0, x = 1, y = 2, new = true },
                bad3 = { continent = 0, entry = 424242, x = 1, y = 2, new = true },
            } }
        end)
        assertEqual(6, #ns.Spawns.All(0))
    end)
end)
```

- [ ] **Step 2: Add the files to the list and run to see them fail**

Append `"Geometry.lua", "Spawns.lua",` to `M.FILES` in `GatherMap/tests/helpers.lua`, and `Geometry.lua` and `Spawns.lua` (one per line) at the end of `GatherMap.toc`.

Run: `.\run-tests.ps1 GatherMap`
Expected: FAIL, `cannot open Geometry.lua`.

- [ ] **Step 3: Write Geometry.lua**

```lua
local addonName, ns = ...

-- The sums that put a world position, in yards, on a map or the minimap.
-- World X runs north and Y west; a map's x runs east and its y south, so a
-- map's x follows world Y and its y follows world X.

local Geometry = {}
ns.Geometry = Geometry

-- How many yards across the minimap is at each zoom level, 0 to 5, as the
-- client draws it, out of doors and in.
Geometry.OUTDOOR = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
Geometry.INDOOR = { 300, 240, 180, 120, 80, 50 }

local rects = {}

--- Where map `uiMapID` sits in the world: its continent, and the world
-- positions of its top-left (x0, y0) and bottom-right (x1, y1) corners. Nil
-- for a map the client cannot place, such as the whole world. Kept once
-- known, refusals included: a map's place never moves.
function Geometry.MapRect(uiMapID)
    if not uiMapID then
        return nil
    end
    if rects[uiMapID] == nil then
        rects[uiMapID] = ns.Guarded(function()
            local continent, topLeft = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(0, 0))
            local _, bottomRight = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(1, 1))
            if not continent or not topLeft or not bottomRight then
                return false
            end
            if topLeft.x == bottomRight.x or topLeft.y == bottomRight.y then
                return false
            end
            return { continent = continent, x0 = topLeft.x, y0 = topLeft.y, x1 = bottomRight.x, y1 = bottomRight.y }
        end, false)
    end
    return rects[uiMapID] or nil
end

--- A world position on the map `rect` describes: 0..1 each way inside it.
function Geometry.ToMap(rect, x, y)
    return (y - rect.y0) / (rect.y1 - rect.y0), (x - rect.x0) / (rect.x1 - rect.x0)
end

function Geometry.MinimapDiameter(zoom, indoors)
    local sizes = indoors and Geometry.INDOOR or Geometry.OUTDOOR
    return sizes[(zoom or 0) + 1] or sizes[1]
end

--- Where a spawn at (x, y) sits from the player at (px, py) on the
-- minimap, in yards: right and up. With the minimap turning, the direction
-- faced (`facing`, radians anticlockwise from north) is up.
function Geometry.MinimapOffset(px, py, x, y, facing, rotate)
    local right, up = py - y, x - px
    if rotate and facing then
        local c, s = math.cos(facing), math.sin(facing)
        right, up = right * c + up * s, -right * s + up * c
    end
    return right, up
end
```

- [ ] **Step 4: Write Spawns.lua**

```lua
local addonName, ns = ...

-- Every spawn GatherMap knows: the data files' and the new points the
-- player found. Each is { continent, entry, x, y, key }, filed in a grid of
-- 200-yard cells per continent, so the minimap and the recorder look only at
-- the few cells around the player.

local Spawns = {}
ns.Spawns = Spawns

local CELL = 200
Spawns.CELL = CELL
-- Bumped by every spawn added after login, so a cache built from the index
-- can tell it is out of date.
Spawns.version = 0

local lists = {}
local grids = {}
local byKey = {}

function Spawns.Key(continent, entry, x, y)
    return string.format("%d:%d:%.1f:%.1f", continent, entry, x, y)
end

local function cellKey(cx, cy)
    return cx .. ":" .. cy
end

local function add(continent, entry, x, y)
    local key = Spawns.Key(continent, entry, x, y)
    if byKey[key] then
        return byKey[key]
    end

    local spawn = { continent = continent, entry = entry, x = x, y = y, key = key }
    byKey[key] = spawn

    lists[continent] = lists[continent] or {}
    table.insert(lists[continent], spawn)

    grids[continent] = grids[continent] or {}
    local cell = cellKey(math.floor(x / CELL), math.floor(y / CELL))
    local bucket = grids[continent][cell]
    if not bucket then
        bucket = {}
        grids[continent][cell] = bucket
    end
    table.insert(bucket, spawn)

    Spawns.version = Spawns.version + 1
    return spawn
end

local function round(value)
    return math.floor(value * 10 + 0.5) / 10
end

--- Take the data files' spawns and the saved new points. Once, at login.
function Spawns.Load()
    for continent, flat in pairs(ns.rawSpawns) do
        for index = 1, #flat - 2, 3 do
            if ns.Nodes[flat[index]] then
                add(continent, flat[index], flat[index + 1], flat[index + 2])
            end
        end
    end
    ns.rawSpawns = {}

    for _, point in pairs(ns.db.gathered) do
        if type(point) == "table" and point.new and type(point.continent) == "number"
            and type(point.x) == "number" and type(point.y) == "number" and ns.Nodes[point.entry] then
            add(point.continent, point.entry, round(point.x), round(point.y))
        end
    end
end

--- A place the data does not have, rounded to a tenth of a yard.
function Spawns.AddPoint(continent, entry, x, y)
    return add(continent, entry, round(x), round(y))
end

function Spawns.All(continent)
    return lists[continent] or {}
end

function Spawns.ByKey(key)
    return byKey[key]
end

--- Call fn(spawn) for every spawn within `radius` yards of (x, y).
function Spawns.Near(continent, x, y, radius, fn)
    local grid = grids[continent]
    if not grid then
        return
    end
    local limit = radius * radius
    for cx = math.floor((x - radius) / CELL), math.floor((x + radius) / CELL) do
        for cy = math.floor((y - radius) / CELL), math.floor((y + radius) / CELL) do
            local bucket = grid[cellKey(cx, cy)]
            if bucket then
                for _, spawn in ipairs(bucket) do
                    local dx, dy = spawn.x - x, spawn.y - y
                    if dx * dx + dy * dy <= limit then
                        fn(spawn)
                    end
                end
            end
        end
    end
end

--- The nearest spawn of `entry` within `radius` yards of (x, y), or nil.
function Spawns.Nearest(continent, entry, x, y, radius)
    local best, bestDistance
    Spawns.Near(continent, x, y, radius, function(spawn)
        if spawn.entry == entry then
            local distance = (spawn.x - x) ^ 2 + (spawn.y - y) ^ 2
            if not bestDistance or distance < bestDistance then
                best, bestDistance = spawn, distance
            end
        end
    end)
    return best
end

ns.OnLogin(Spawns.Load)
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `.\run-tests.ps1 GatherMap`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add GatherMap
git commit -m "GatherMap: map and minimap geometry, and the spawn index

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Skills and the filter

**Files:**
- Create: `GatherMap/Skills.lua`, `GatherMap/Filter.lua`
- Modify: `GatherMap/GatherMap.toc`, `GatherMap/tests/helpers.lua` (append `Skills.lua`, `Filter.lua`)
- Test: `GatherMap/tests/skills_spec.lua`, `GatherMap/tests/filter_spec.lua`

**Interfaces:**
- Consumes: `ns.Guarded`, `ns.OnLogin`, `ns.Refresh`, `ns.AddDefaults`, `ns.Nodes`, `ns.settings`, `ns.db.gathered`; a spawn's `entry` and `key`.
- Produces:
  - `ns.Skills.Read()`, `ns.Skills.Get(kind) -> number`, `ns.Skills.Color(required, skill) -> "red"|"orange"|"yellow"|"green"|"grey"`, `ns.Skills.RGB[color] -> { r, g, b }`, `ns.Skills.LABEL[kind] -> "Herbalism"|"Mining"`.
  - Settings `ns.settings.worldmap` and `ns.settings.minimap`, each `{ kinds = { herb, ore, pool, chest }, hidden = { [name] = true }, hideUngatherable, hideGrey, onlyConfirmed, showMissing, pinSize }` (pinSize 12 world map, 10 minimap).
  - `ns.Filter.Confirmed(spawn) -> boolean` (gathered by you, or in `ns.confirmed`).
  - `ns.Filter.Shows(where, spawn) -> boolean`.

- [ ] **Step 1: Write the failing specs**

`GatherMap/tests/skills_spec.lua`:

```lua
local helpers = require("helpers")

describe("the player's skills", function()
    it("are read from the skill list by name, skipping headers", function()
        local ns = helpers.loggedIn()
        assertEqual(50, ns.Skills.Get("herb"))
        assertEqual(70, ns.Skills.Get("ore"))
    end)

    it("are found in another client language", function()
        local ns = helpers.loggedIn(function(env)
            env.__skills = { { "Berufe", true }, { "Bergbau", false, 120 }, { "Kräuterkunde", false, 30 } }
        end)
        assertEqual(120, ns.Skills.Get("ore"))
        assertEqual(30, ns.Skills.Get("herb"))
    end)

    it("are 0 without the profession", function()
        local ns = helpers.loggedIn(function(env) env.__skills = { { "Professions", true } } end)
        assertEqual(0, ns.Skills.Get("herb"))
        assertEqual(0, ns.Skills.Get("ore"))
        assertEqual(0, ns.Skills.Get("pool"))
    end)

    it("are read again when they change, and the pins redrawn", function()
        local ns, env = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        env.__skills[3] = { "Mining", false, 71 }
        helpers.fire(env, "SKILL_LINES_CHANGED")
        assertEqual(71, ns.Skills.Get("ore"))
        assertEqual(1, count)
    end)

    it("stay as they were when the client refuses", function()
        local ns, env = helpers.loggedIn()
        env.GetSkillLineInfo = function() error("secret") end
        ns.Skills.Read()
        assertEqual(70, ns.Skills.Get("ore"))
    end)

    it("stay as they were while a header is collapsed and hides one", function()
        local ns, env = helpers.loggedIn()
        env.__skills = { { "Professions", true, nil, false } }
        ns.Skills.Read()
        assertEqual(70, ns.Skills.Get("ore"), "a collapsed header is not a forgotten profession")
        assertEqual(50, ns.Skills.Get("herb"))
    end)
end)

describe("a node's colour", function()
    it("follows the skill-up bands", function()
        local ns = helpers.loggedIn()
        assertEqual("red", ns.Skills.Color(100, 99))
        assertEqual("orange", ns.Skills.Color(100, 100))
        assertEqual("orange", ns.Skills.Color(100, 124))
        assertEqual("yellow", ns.Skills.Color(100, 125))
        assertEqual("yellow", ns.Skills.Color(100, 149))
        assertEqual("green", ns.Skills.Color(100, 150))
        assertEqual("green", ns.Skills.Color(100, 199))
        assertEqual("grey", ns.Skills.Color(100, 200))
    end)
end)
```

`GatherMap/tests/filter_spec.lua`:

```lua
local helpers = require("helpers")

local A = "0:1731:-10603.8:1154.0"     -- Copper Vein, skill 1
local C = "0:3764:-10610.0:1160.0"     -- Tin Vein, skill 65
local E = "0:180582:-10620.0:1170.0"   -- a pool
local F = "0:2843:-10700.0:1300.0"     -- a chest

local function shows(ns, where, key)
    return ns.Filter.Shows(where, ns.Spawns.ByKey(key))
end

describe("the filter", function()
    it("shows every kind on both maps by default", function()
        local ns = helpers.loggedIn()
        for _, key in ipairs({ A, C, E, F }) do
            assertTrue(shows(ns, "worldmap", key), key)
            assertTrue(shows(ns, "minimap", key), key)
        end
    end)

    it("hides everything while pins are off", function()
        local ns = helpers.loggedIn()
        ns.SetEnabled(false)
        assertFalse(shows(ns, "worldmap", A))
        assertFalse(shows(ns, "minimap", E))
    end)

    it("hides a kind on one map and not the other", function()
        local ns = helpers.loggedIn()
        ns.settings.minimap.kinds.chest = false
        assertFalse(shows(ns, "minimap", F))
        assertTrue(shows(ns, "worldmap", F))
    end)

    it("hides a node by name", function()
        local ns = helpers.loggedIn()
        ns.settings.worldmap.hidden["Copper Vein"] = true
        assertFalse(shows(ns, "worldmap", A))
        assertTrue(shows(ns, "worldmap", C))
    end)

    it("hides what the skill cannot gather yet, unless asked not to", function()
        local ns, env = helpers.loggedIn(function(env) env.__skills[3] = { "Mining", false, 50 } end)
        assertFalse(shows(ns, "worldmap", C), "Tin needs 65")
        assertTrue(shows(ns, "worldmap", A))
        ns.settings.worldmap.hideUngatherable = false
        assertTrue(shows(ns, "worldmap", C))
    end)

    it("hides grey nodes when asked", function()
        local ns = helpers.loggedIn(function(env) env.__skills[3] = { "Mining", false, 200 } end)
        assertTrue(shows(ns, "minimap", A))
        ns.settings.minimap.hideGrey = true
        assertFalse(shows(ns, "minimap", A), "Copper is grey at 200")
        assertTrue(shows(ns, "minimap", C), "Tin is green at 200")
    end)

    it("never hides pools or chests for skill", function()
        local ns = helpers.loggedIn(function(env) env.__skills = { { "Professions", true } } end)
        ns.settings.worldmap.hideGrey = true
        assertTrue(shows(ns, "worldmap", E))
        assertTrue(shows(ns, "worldmap", F))
        assertFalse(shows(ns, "worldmap", A), "no Mining: the vein is out of reach")
    end)

    it("shows only spawns confirmed in game when asked: yours, or the release's", function()
        local ns = helpers.loggedIn()
        ns.settings.worldmap.onlyConfirmed = true
        assertFalse(shows(ns, "worldmap", A), "only the database has it")
        assertTrue(shows(ns, "worldmap", C), "a baked recording confirmed it")
        ns.db.gathered[A] = { continent = 0, entry = 1731, x = -10603.8, y = 1154.0, count = 1 }
        assertTrue(shows(ns, "worldmap", A))
        assertTrue(shows(ns, "minimap", E), "the minimap's own setting is still off")
    end)

    it("tells confirmed spawns apart", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.Filter.Confirmed(ns.Spawns.ByKey(A)))
        assertTrue(ns.Filter.Confirmed(ns.Spawns.ByKey(C)))
        ns.db.gathered[A] = { count = 1 }
        assertTrue(ns.Filter.Confirmed(ns.Spawns.ByKey(A)))
    end)

    it("hides a spawn marked not here, unless asked to show those", function()
        local ns = helpers.loggedIn()
        ns.db.missing[A] = 1790000000
        assertFalse(shows(ns, "worldmap", A))
        assertFalse(shows(ns, "minimap", A))
        ns.settings.minimap.showMissing = true
        assertTrue(shows(ns, "minimap", A))
        assertFalse(shows(ns, "worldmap", A))
    end)

    it("shows nothing for an object the catalog does not know", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.Filter.Shows("worldmap", { entry = 424242, key = "x" }))
    end)
end)
```

- [ ] **Step 2: Add the files and run to see them fail**

Append `"Skills.lua", "Filter.lua",` to `M.FILES`, and both to the end of `GatherMap.toc`.

Run: `.\run-tests.ps1 GatherMap`
Expected: FAIL, `cannot open Skills.lua`.

- [ ] **Step 3: Write Skills.lua**

```lua
local addonName, ns = ...

-- The player's Herbalism and Mining, read from the skill list, and how a
-- node's required skill looks against them.

local Skills = {}
ns.Skills = Skills

-- The skill list gives names, not IDs, so each profession is looked for
-- under its name in every client language.
local NAMES = {
    herb = { "Herbalism", "Kräuterkunde", "Herboristerie", "Herboristería", "Erbalismo", "Herborismo",
        "Травничество", "약초채집", "草药学", "草藥學" },
    ore = { "Mining", "Bergbau", "Minage", "Minería", "Estrazione", "Mineração",
        "Горное дело", "채광", "采矿", "採礦" },
}

local kindOf = {}
for kind, names in pairs(NAMES) do
    for _, name in ipairs(names) do
        kindOf[name] = kind
    end
end

Skills.LABEL = { herb = "Herbalism", ore = "Mining" }

Skills.RGB = {
    red = { 1, 0.1, 0.1 },
    orange = { 1, 0.5, 0.25 },
    yellow = { 1, 1, 0 },
    green = { 0.25, 0.75, 0.25 },
    grey = { 0.5, 0.5, 0.5 },
}

local ranks = { herb = 0, ore = 0 }

--- Read both skills again. A refusal leaves them as they were, and so does
-- a collapsed header: the lines under it are not listed, and reading that as
-- "no profession" would hide every herb and vein.
function Skills.Read()
    ns.Guarded(function()
        local found = { herb = 0, ore = 0 }
        local collapsed = false
        for index = 1, GetNumSkillLines() do
            local name, isHeader, isExpanded, rank = GetSkillLineInfo(index)
            if isHeader then
                if not isExpanded then
                    collapsed = true
                end
            elseif kindOf[name] then
                found[kindOf[name]] = rank or 0
            end
        end
        if collapsed then
            for kind, rank in pairs(found) do
                if rank == 0 then
                    found[kind] = ranks[kind]
                end
            end
        end
        ranks = found
    end)
end

function Skills.Get(kind)
    return ranks[kind] or 0
end

--- How a node needing `required` looks at `skill`: "red" cannot be
-- gathered; then the skill-up colours, "orange" to "grey".
function Skills.Color(required, skill)
    if skill < required then
        return "red"
    elseif skill < required + 25 then
        return "orange"
    elseif skill < required + 50 then
        return "yellow"
    elseif skill < required + 100 then
        return "green"
    end
    return "grey"
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:SetScript("OnEvent", function()
    Skills.Read()
    ns.Refresh()
end)

ns.OnLogin(Skills.Read)
```

- [ ] **Step 4: Write Filter.lua**

```lua
local addonName, ns = ...

-- Whether a spawn is shown on the world map or the minimap. The one place
-- every filter is applied, so the two maps can never disagree about what a
-- setting means.

local Filter = {}
ns.Filter = Filter

local function filters(pinSize)
    return {
        kinds = { herb = true, ore = true, pool = true, chest = true },
        hidden = {},
        hideUngatherable = true,
        hideGrey = false,
        onlyConfirmed = false,
        showMissing = false,
        pinSize = pinSize,
    }
end

ns.AddDefaults({
    worldmap = filters(12),
    minimap = filters(10),
})

--- Whether the game has shown this spawn is real: the player gathered it,
-- or a recording baked into the release did. vMaNGOS alone is a guess.
function Filter.Confirmed(spawn)
    return ns.db.gathered[spawn.key] ~= nil or ns.confirmed[spawn.key] == true
end

--- Whether `spawn` is shown on `where`: "worldmap" or "minimap".
function Filter.Shows(where, spawn)
    local settings = ns.settings
    if not settings.enabled then
        return false
    end

    local node = ns.Nodes[spawn.entry]
    if not node then
        return false
    end

    local chosen = settings[where]
    if not chosen.kinds[node.kind] or chosen.hidden[node.name] then
        return false
    end
    if chosen.onlyConfirmed and not Filter.Confirmed(spawn) then
        return false
    end
    if ns.db.missing[spawn.key] and not chosen.showMissing then
        return false
    end

    if node.skill then
        local color = ns.Skills.Color(node.skill, ns.Skills.Get(node.kind))
        if chosen.hideUngatherable and color == "red" then
            return false
        end
        if chosen.hideGrey and color == "grey" then
            return false
        end
    end

    return true
end
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `.\run-tests.ps1 GatherMap`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add GatherMap
git commit -m "GatherMap: skills, skill-up colours and the filter

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Recording gathers

**Files:**
- Create: `GatherMap/Recorder.lua`
- Modify: `GatherMap/GatherMap.toc`, `GatherMap/tests/helpers.lua` (append `Recorder.lua`)
- Test: `GatherMap/tests/recorder_spec.lua`

**Interfaces:**
- Consumes: `ns.Spawns.Nearest`, `ns.Spawns.AddPoint`, `ns.Nodes`, `ns.db.gathered`, `ns.Refresh`, `ns.Guarded`, `ns.RegisterCommand`, `ns.Print`.
- Produces: `ns.Recorder.EntryFromGUID(guid) -> number|nil`, `ns.Recorder.LootOpened()`, `ns.Recorder.ToggleMissing(spawn) -> boolean` (true when now marked), `ns.Recorder.REACH` (15), `POOL_REACH` (30), `REPEAT` (5). A gathered point: `ns.db.gathered[key] = { continent, entry, x, y, count, last, new }`. Command `/gmap reset gathered`.

- [ ] **Step 1: Write the failing spec**

`GatherMap/tests/recorder_spec.lua`:

```lua
local helpers = require("helpers")

local A = "0:1731:-10603.8:1154.0"
local E = "0:180582:-10620.0:1170.0"

local function guid(entry)
    return string.format("GameObject-0-6782-0-79720-%d-00003A1A8E", entry)
end

local function loot(env, entry)
    env.__lootSource = guid(entry)
    helpers.fire(env, "LOOT_OPENED")
end

describe("reading a loot window's source", function()
    it("takes the object's entry from its GUID", function()
        local ns = helpers.loggedIn()
        assertEqual(1731, ns.Recorder.EntryFromGUID("GameObject-0-6782-0-79720-1731-00003A1A8E"))
        assertNil(ns.Recorder.EntryFromGUID("Creature-0-6782-0-79720-1731-00003A1A8E"))
        assertNil(ns.Recorder.EntryFromGUID(nil))
    end)
end)

describe("a gather", function()
    it("counts the spawn it was taken from", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1731)
        local point = ns.db.gathered[A]
        assertEqual(1, point.count)
        assertEqual(env.__time, point.last)
        assertFalse(point.new)
        assertEqual(1731, point.entry)
    end)

    it("counts again next time, but not twice for one window", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1731)
        env.__now = env.__now + 2
        loot(env, 1731)
        assertEqual(1, ns.db.gathered[A].count, "reopened within 5 seconds")
        env.__now = env.__now + 6
        loot(env, 1731)
        assertEqual(2, ns.db.gathered[A].count)
    end)

    it("makes a new point where the data has no spawn", function()
        local ns, env = helpers.loggedIn(function(env) env.__position = { -10300.04, 900.06, 0, 0 } end)
        loot(env, 1731)
        local key = "0:1731:-10300.0:900.1"
        assertEqual(1, ns.db.gathered[key].count)
        assertTrue(ns.db.gathered[key].new)
        assertEqual(key, ns.Spawns.ByKey(key).key, "and the maps can draw it")
    end)

    it("counts a pool from the shore, up to 30 yards off", function()
        local ns, env = helpers.loggedIn()
        loot(env, 180582)
        assertEqual(1, ns.db.gathered[E].count)
    end)

    it("never makes a new point for a pool", function()
        local ns, env = helpers.loggedIn(function(env) env.__position = { -10300, 900, 0, 0 } end)
        loot(env, 180582)
        assertNil(next(ns.db.gathered))
    end)

    it("works on Kalimdor too", function()
        local ns, env = helpers.loggedIn(function(env) env.__position = { 100.0, 200.0, 0, 1 } end)
        loot(env, 1618)
        assertEqual(1, ns.db.gathered["1:1618:100.0:200.0"].count)
    end)

    it("ignores corpses, unknown objects, instances and a hidden position", function()
        local ns, env = helpers.loggedIn()
        env.__lootSource = "Creature-0-6782-0-79720-1731-00003A1A8E"
        helpers.fire(env, "LOOT_OPENED")
        loot(env, 424242)
        env.__position = { -10603.8, 1154.0, 0, 36 }
        loot(env, 1731)
        env.__position = nil
        loot(env, 1731)
        env.GetLootSourceInfo = function() error("secret") end
        helpers.fire(env, "LOOT_OPENED")
        assertNil(next(ns.db.gathered))
    end)

    it("repairs a saved point with no count", function()
        local ns, env = helpers.loggedIn(function(env)
            env.GatherMapDB = { gathered = { [A] = { continent = 0, entry = 1731, x = -10603.8, y = 1154.0 } } }
        end)
        loot(env, 1731)
        assertEqual(1, ns.db.gathered[A].count)
    end)

    it("redraws the pins", function()
        local ns, env = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        loot(env, 1731)
        assertEqual(1, count)
    end)

    it("clears a not-here mark on the spawn it was taken from", function()
        local ns, env = helpers.loggedIn()
        ns.db.missing[A] = 1
        loot(env, 1731)
        assertNil(ns.db.missing[A])
    end)
end)

describe("marking a spawn not here", function()
    it("toggles, stamped with the time, and redraws", function()
        local ns, env = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        local spawn = ns.Spawns.ByKey(A)
        assertTrue(ns.Recorder.ToggleMissing(spawn))
        assertEqual(env.__time, ns.db.missing[A])
        assertFalse(ns.Recorder.ToggleMissing(spawn))
        assertNil(ns.db.missing[A])
        assertEqual(2, count)
    end)
end)

describe("/gmap reset gathered", function()
    it("asks first, then forgets on a second go within 10 seconds", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1731)
        helpers.command(env, "reset gathered")
        assertEqual(1, ns.db.gathered[A].count, "not yet")
        assertMatch("again within 10 seconds", helpers.printed(env))
        env.__now = env.__now + 3
        ns.db.missing["0:2843:-10700.0:1300.0"] = 1
        helpers.command(env, "reset gathered")
        assertNil(next(ns.db.gathered))
        assertNil(next(ns.db.missing), "the not-here marks go too")
        assertMatch("Forgot every place", helpers.printed(env))
    end)

    it("asks again when the second go comes too late", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1731)
        helpers.command(env, "reset gathered")
        env.__now = env.__now + 11
        helpers.command(env, "reset gathered")
        assertEqual(1, ns.db.gathered[A].count)
    end)

    it("says how to use it without 'gathered'", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "reset")
        assertMatch("/gmap reset gathered", helpers.printed(env))
    end)
end)
```

- [ ] **Step 2: Add the file and run to see it fail**

Append `"Recorder.lua",` to `M.FILES` and `Recorder.lua` to the TOC.

Run: `.\run-tests.ps1 GatherMap`
Expected: FAIL, `cannot open Recorder.lua`.

- [ ] **Step 3: Write Recorder.lua**

```lua
local addonName, ns = ...

-- Turns a loot window from a herb, vein, chest or pool into "gathered here":
-- the loot's source is the object's GUID, whose sixth field is its entry,
-- and the spawn is the nearest of that entry to the player.

local Recorder = {}
ns.Recorder = Recorder

-- How far off a gathered node's spawn can be. A player stands at a herb,
-- vein or chest; they fish a pool from 10 to 20 yards away.
Recorder.REACH = 15
Recorder.POOL_REACH = 30
-- A loot window on the same spawn again within this many seconds is the
-- same gather, reopened.
Recorder.REPEAT = 5

function Recorder.EntryFromGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local entry = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return entry and tonumber(entry)
end

local lastKey, lastTime

local function record(spawn, isNew)
    local now = GetTime()
    if spawn.key == lastKey and now - lastTime < Recorder.REPEAT then
        return
    end
    lastKey, lastTime = spawn.key, now

    local point = ns.db.gathered[spawn.key]
    if type(point) ~= "table" then
        point = { continent = spawn.continent, entry = spawn.entry, x = spawn.x, y = spawn.y, new = isNew }
        ns.db.gathered[spawn.key] = point
    end
    point.count = (point.count or 0) + 1
    point.last = time()
    -- Something grew here after all.
    ns.db.missing[spawn.key] = nil
    ns.Refresh()
end

--- Mark `spawn` "not here", or take the mark off. True when now marked.
function Recorder.ToggleMissing(spawn)
    local marked = not ns.db.missing[spawn.key]
    ns.db.missing[spawn.key] = marked and time() or nil
    ns.Refresh()
    return marked
end

--- A loot window opened. Counted when it came from a node GatherMap knows,
-- on one of the two continents, and the client says where the player is.
function Recorder.LootOpened()
    local entry = Recorder.EntryFromGUID(ns.Guarded(function()
        return (GetLootSourceInfo(1))
    end))
    local node = entry and ns.Nodes[entry]
    if not node then
        return
    end

    local x, y, _, continent = UnitPosition("player")
    if type(x) ~= "number" or (continent ~= 0 and continent ~= 1) then
        return
    end

    if node.kind == "pool" then
        local spawn = ns.Spawns.Nearest(continent, entry, x, y, Recorder.POOL_REACH)
        if spawn then
            record(spawn, false)
        end
        return
    end

    local spawn = ns.Spawns.Nearest(continent, entry, x, y, Recorder.REACH)
    if spawn then
        record(spawn, false)
    else
        record(ns.Spawns.AddPoint(continent, entry, x, y), true)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_OPENED")
frame:SetScript("OnEvent", function()
    ns.Guarded(Recorder.LootOpened)
end)

local resetAsked

ns.RegisterCommand("reset", "Forget every place you have gathered: /gmap reset gathered", function(rest)
    if rest ~= "gathered" then
        ns.Print("To forget every place you have gathered: /gmap reset gathered")
        return
    end

    local now = GetTime()
    if resetAsked and now - resetAsked <= 10 then
        resetAsked = nil
        for key in pairs(ns.db.gathered) do
            ns.db.gathered[key] = nil
        end
        for key in pairs(ns.db.missing) do
            ns.db.missing[key] = nil
        end
        ns.Print("Forgot every place you have gathered, and every spawn marked not here.")
        ns.Refresh()
        return
    end

    resetAsked = now
    ns.Print("This forgets every place you have gathered and every spawn marked not here, on every character. "
        .. "Type /gmap reset gathered again within 10 seconds to do it.")
end)
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `.\run-tests.ps1 GatherMap`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add GatherMap
git commit -m "GatherMap: record where the player gathers

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Pins and the world map

**Files:**
- Create: `GatherMap/Pins.lua`, `GatherMap/WorldMap.lua`
- Modify: `GatherMap/GatherMap.toc`, `GatherMap/tests/helpers.lua` (append `Pins.lua`, `WorldMap.lua`)
- Test: `GatherMap/tests/worldmap_spec.lua`

**Interfaces:**
- Consumes: `ns.Geometry.MapRect`, `ns.Geometry.ToMap`, `ns.Spawns.All`, `ns.Spawns.version`, `ns.Filter.Shows`, `ns.Filter.Confirmed`, `ns.Recorder.ToggleMissing`, `ns.db.missing`, `ns.Skills.*`, `ns.Nodes`, `ns.db.gathered`, `ns.settings.worldmap.pinSize`, `ns.OnLogin`, `ns.OnRefresh`, `ns.RegisterCommand`.
- Produces:
  - `ns.Pins.DIM` (0.55, the alpha of a database-only pin), `ns.Pins.KIND_ICONS[kind]`, `ns.Pins.Icon(node) -> texture`, `ns.Pins.ShowTooltip(owner, spawn)`, `ns.Pins.Create(parent) -> pin` (pin has `.icon`, `.edge`, `.spawn`), `ns.Pins.Set(pin, spawn, size)`, `ns.Pins.Pool(parent) -> pool` with `pool:Begin()`, `pool:Acquire() -> pin`, `pool:Finish()`, `pool.used`, `pool.pins`.
  - `ns.WorldMap.SpawnsOn(uiMapID) -> { { spawn, x, y }, ... }`, `ns.WorldMap.Refresh()`, `ns.WorldMap.Shown() -> pin[]`, `ns.WorldMap.MAX` (2000). Command `/gmap where`.

- [ ] **Step 1: Write the failing spec**

`GatherMap/tests/worldmap_spec.lua`:

```lua
local helpers = require("helpers")

local A = "0:1731:-10603.8:1154.0"

local function opened(setup)
    local ns, env = helpers.loggedIn(setup)
    env.WorldMapFrame:Show()
    return ns, env
end

local function shownEntries(ns)
    local entries = {}
    for _, pin in ipairs(ns.WorldMap.Shown()) do
        entries[#entries + 1] = pin.spawn.entry
    end
    table.sort(entries)
    return table.concat(entries, ",")
end

local function pinFor(ns, key)
    for _, pin in ipairs(ns.WorldMap.Shown()) do
        if pin.spawn.key == key then return pin end
    end
end

describe("the world map", function()
    it("joins the map as a data provider", function()
        local ns, env = helpers.loggedIn()
        assertEqual(1, #env.__providers)
    end)

    it("draws every spawn inside the open map", function()
        local ns = opened()
        assertEqual("1731,1731,2843,3764,180582", shownEntries(ns), "Silverleaf lies off this map")
    end)

    it("puts a pin where its spawn is on the canvas", function()
        local ns, env = opened()
        local point, relativeTo, relativePoint, x, y = pinFor(ns, A):GetPoint(1)
        assertEqual("CENTER", point)
        assertEqual(env.WorldMapFrame:GetCanvas(), relativeTo)
        assertEqual("TOPLEFT", relativePoint)
        assertNear(846, x, 0.01)
        assertNear(-422.66, y, 0.01)
        assertEqual(12, pinFor(ns, A):GetWidth())
    end)

    it("keeps pins the same size on screen as the map zooms", function()
        local ns, env = opened()
        env.__zoomMap(2)
        local pin = pinFor(ns, A)
        assertNear(0.5, pin:GetScale())
        local _, _, _, x = pin:GetPoint(1)
        assertNear(1692, x, 0.01, "the offset is in the pin's own, halved, units")
    end)

    it("follows the filters", function()
        local ns = opened()
        ns.settings.worldmap.kinds.ore = false
        ns.Refresh()
        assertEqual("2843,180582", shownEntries(ns))
    end)

    it("shows nothing on a map it cannot place", function()
        local ns, env = opened()
        env.__changeMap(947)
        assertEqual("", shownEntries(ns))
    end)

    it("draws nothing while the map is closed", function()
        local ns, env = helpers.loggedIn()
        ns.Refresh()
        assertEqual("", shownEntries(ns))
    end)

    it("picks up a point gathered after the map was first opened", function()
        local ns, env = opened()
        env.__position = { -10300.0, 1500.0, 0, 0 }
        env.__lootSource = "GameObject-0-6782-0-79720-1731-00003A1A8E"
        helpers.fire(env, "LOOT_OPENED")
        assertEqual("1731,1731,1731,2843,3764,180582", shownEntries(ns))
    end)

    it("draws no more than its limit of pins", function()
        local ns = opened(function(env) end)
        for index = 1, ns.WorldMap.MAX + 50 do
            ns.Spawns.AddPoint(0, 1731, -10500 - index * 0.2, 1500)
        end
        ns.Refresh()
        assertEqual(ns.WorldMap.MAX, #ns.WorldMap.Shown())
    end)

    it("attaches when the world map loads after GatherMap", function()
        local ns, env = helpers.loadAddon()
        local map = env.WorldMapFrame
        env.WorldMapFrame = nil
        helpers.login(ns, env)
        assertEqual(0, #env.__providers)
        env.WorldMapFrame = map
        helpers.fire(env, "ADDON_LOADED", "Blizzard_WorldMap")
        assertEqual(1, #env.__providers)
        map:Show()
        assertEqual("1731,1731,2843,3764,180582", shownEntries(ns))
    end)

    it("loads on a client without the map framework", function()
        local ns, env = helpers.loggedIn(function(env) env.MapCanvasDataProviderMixin = nil end)
        assertEqual(0, #env.__providers)
        ns.Refresh()
    end)
end)

describe("a pin", function()
    it("shows its node's loot as its icon, or its kind's", function()
        local ns = opened()
        assertEqual(1000 + 2770, pinFor(ns, A).icon:GetTexture())
        assertEqual(ns.Pins.KIND_ICONS.chest, pinFor(ns, "0:2843:-10700.0:1300.0").icon:GetTexture())
    end)

    it("names the node, its skill in its colour, and that only the database has it", function()
        local ns, env = opened()
        local pin = pinFor(ns, A)
        pin.scripts.OnEnter(pin)
        assertEqual("Copper Vein", env.GameTooltip.text)
        assertEqual("Mining 1", env.GameTooltip.lines[1].text)
        assertEqual(0.25, env.GameTooltip.lines[1].color[1], "green at 70")
        assertEqual("From the classic database, not seen in WoW Forever yet", env.GameTooltip.lines[2].text)
        assertEqual("Right-click: not here", env.GameTooltip.lines[3].text)
        assertFalse(pin.edge:IsShown())
        assertEqual(ns.Pins.DIM, pin:GetAlpha(), "a database guess is drawn dimmed")
    end)

    it("draws a spawn confirmed in the release at full strength", function()
        local ns, env = opened()
        local pin = pinFor(ns, "0:3764:-10610.0:1160.0")
        assertEqual(1, pin:GetAlpha())
        assertFalse(pin.edge:IsShown(), "the gold edge is for the player's own gathers")
        pin.scripts.OnEnter(pin)
        assertEqual("Confirmed in WoW Forever", env.GameTooltip.lines[2].text)
    end)

    it("marks its spawn not here on a right-click, and the pin goes", function()
        local ns, env = opened()
        local pin = pinFor(ns, A)
        pin.scripts.OnEnter(pin)
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertEqual(env.__time, ns.db.missing[A])
        assertEqual("1731,2843,3764,180582", shownEntries(ns))
        assertFalse(env.GameTooltip:IsShown(), "no tooltip left for a pin that has gone")
    end)

    it("shows marked spawns when asked, and a right-click takes the mark off", function()
        local ns, env = opened()
        ns.db.missing[A] = 1
        ns.settings.worldmap.showMissing = true
        ns.Refresh()
        local pin = pinFor(ns, A)
        pin.scripts.OnEnter(pin)
        assertEqual("Marked not here. Right-click to undo.", env.GameTooltip.lines[3].text)
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertNil(ns.db.missing[A])
        assertEqual("Right-click: not here", env.GameTooltip.lines[3].text, "the tooltip keeps up")
    end)

    it("ignores a left click", function()
        local ns, env = opened()
        local pin = pinFor(ns, A)
        pin.scripts.OnMouseUp(pin, "LeftButton")
        assertNil(ns.db.missing[A])
    end)

    it("says how often the player gathered there, with a gold edge", function()
        local ns, env = opened()
        ns.db.gathered[A] = { continent = 0, entry = 1731, x = -10603.8, y = 1154.0, count = 3 }
        ns.Refresh()
        local pin = pinFor(ns, A)
        pin.scripts.OnEnter(pin)
        assertEqual("Gathered here 3 times", env.GameTooltip.lines[2].text)
        assertTrue(pin.edge:IsShown())
    end)
end)

describe("/gmap where", function()
    it("prints the game's place for the player beside GatherMap's", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "where")
        assertMatch("Map 1436%. Game: 0%.846, 0%.604%. GatherMap: 0%.846, 0%.604%.", helpers.printed(env))
    end)

    it("says so where the game will not tell", function()
        local ns, env = helpers.loggedIn(function(env) env.__playerMap = 947 end)
        helpers.command(env, "where")
        assertMatch("will not say", helpers.printed(env))
    end)
end)
```

- [ ] **Step 2: Add the files and run to see it fail**

Append `"Pins.lua", "WorldMap.lua",` to `M.FILES`, and both to the TOC.

Run: `.\run-tests.ps1 GatherMap`
Expected: FAIL, `cannot open Pins.lua`.

- [ ] **Step 3: Write Pins.lua**

```lua
local addonName, ns = ...

-- A pin, the same on the world map and the minimap: the node's icon, a gold
-- edge where the player has gathered, dimmed where only vMaNGOS says so, a
-- tooltip, and a right-click for "not here".

local Pins = {}
ns.Pins = Pins

-- A spawn only the database has is a guess: WoW Forever is not vanilla.
Pins.DIM = 0.55

-- For nodes with no loot to take an icon from, and herbs or ore whose item
-- the client does not know.
Pins.KIND_ICONS = {
    herb = "Interface\\Icons\\INV_Misc_Herb_07",
    ore = "Interface\\Icons\\INV_Ore_Copper_01",
    pool = "Interface\\Icons\\INV_Misc_Fish_02",
    chest = "Interface\\Icons\\INV_Box_01",
}

local GOLD = { 1, 0.82, 0 }

local icons = {}

function Pins.Icon(node)
    if node.item and icons[node.item] == nil then
        icons[node.item] = ns.Guarded(function()
            if C_Item and C_Item.GetItemIconByID then
                return C_Item.GetItemIconByID(node.item)
            end
            return GetItemIcon(node.item)
        end) or false
    end
    return (node.item and icons[node.item]) or Pins.KIND_ICONS[node.kind]
end

function Pins.ShowTooltip(owner, spawn)
    local node = ns.Nodes[spawn.entry]
    if not node or not GameTooltip then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(node.name)
    if node.skill then
        local rgb = ns.Skills.RGB[ns.Skills.Color(node.skill, ns.Skills.Get(node.kind))]
        GameTooltip:AddLine(string.format("%s %d", ns.Skills.LABEL[node.kind], node.skill), rgb[1], rgb[2], rgb[3])
    end

    local point = ns.db.gathered[spawn.key]
    if type(point) == "table" and point.count then
        GameTooltip:AddLine(string.format("Gathered here %d %s", point.count, point.count == 1 and "time" or "times"), 1, 1, 1)
    elseif ns.confirmed[spawn.key] then
        GameTooltip:AddLine("Confirmed in WoW Forever", 1, 1, 1)
    else
        GameTooltip:AddLine("From the classic database, not seen in WoW Forever yet", 0.7, 0.7, 0.7)
    end

    if ns.db.missing[spawn.key] then
        GameTooltip:AddLine("Marked not here. Right-click to undo.", 1, 0.5, 0.25)
    else
        GameTooltip:AddLine("Right-click: not here", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

-- The pin under the cursor may be drawn for another spawn, or gone, once
-- the maps redraw, so the tooltip follows the spawn rather than the frame.
local function toggleMissing(pin)
    local spawn = pin.spawn
    ns.Recorder.ToggleMissing(spawn)
    if not GameTooltip then
        return
    end
    if pin:IsShown() and pin.spawn == spawn then
        Pins.ShowTooltip(pin, spawn)
    else
        GameTooltip:Hide()
    end
end

function Pins.Create(parent)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetFrameLevel(parent:GetFrameLevel() + 5)
    pin:EnableMouse(true)

    local edge = pin:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(pin)
    edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    pin.edge = edge

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
    -- Trimmed of the icon art's own dark rim, which at this size is most of it.
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pin.icon = icon

    pin:SetScript("OnEnter", function(self)
        if self.spawn then
            Pins.ShowTooltip(self, self.spawn)
        end
    end)
    pin:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    pin:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "RightButton" and self.spawn then
            toggleMissing(self)
        end
    end)
    return pin
end

--- Point `pin` at `spawn`, `size` pixels across, and show it.
function Pins.Set(pin, spawn, size)
    pin.spawn = spawn
    pin:SetSize(size, size)
    pin.icon:SetTexture(Pins.Icon(ns.Nodes[spawn.entry]))
    pin.edge:SetShown(ns.db.gathered[spawn.key] ~= nil)
    pin:SetAlpha(ns.Filter.Confirmed(spawn) and 1 or Pins.DIM)
    pin:Show()
end

--- Pins on one parent, reused from draw to draw: Begin, then Acquire one per
-- spawn drawn, then Finish hides whatever was not acquired.
function Pins.Pool(parent)
    local pool = { pins = {}, used = 0 }

    function pool:Begin()
        self.used = 0
    end

    function pool:Acquire()
        self.used = self.used + 1
        local pin = self.pins[self.used]
        if not pin then
            pin = Pins.Create(parent)
            self.pins[self.used] = pin
        end
        return pin
    end

    function pool:Finish()
        for index = self.used + 1, #self.pins do
            self.pins[index]:Hide()
            self.pins[index].spawn = nil
        end
    end

    return pool
end
```

- [ ] **Step 4: Write WorldMap.lua**

```lua
local addonName, ns = ...

-- Pins on the world map. A data provider tells GatherMap when the map
-- changes or zooms; the pins are GatherMap's own frames on the map's canvas,
-- so they pan and zoom with it.

local WorldMap = {}
ns.WorldMap = WorldMap

-- A continent map holds thousands of spawns; past this many pins the map
-- stops being usable, so the rest are left off.
WorldMap.MAX = 2000

-- Per map: every spawn inside it, with its place, as of Spawns.version.
local cache = {}
local pool, provider

function WorldMap.SpawnsOn(uiMapID)
    local cached = cache[uiMapID]
    if cached and cached.version == ns.Spawns.version then
        return cached.places
    end

    local places = {}
    local rect = ns.Geometry.MapRect(uiMapID)
    if rect then
        for _, spawn in ipairs(ns.Spawns.All(rect.continent)) do
            local x, y = ns.Geometry.ToMap(rect, spawn.x, spawn.y)
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                table.insert(places, { spawn = spawn, x = x, y = y })
            end
        end
    end
    if uiMapID then
        cache[uiMapID] = { version = ns.Spawns.version, places = places }
    end
    return places
end

function WorldMap.Refresh()
    if not pool then
        return
    end
    pool:Begin()

    if WorldMapFrame:IsShown() then
        local canvas = WorldMapFrame:GetCanvas()
        local width, height = canvas:GetWidth(), canvas:GetHeight()
        -- Pins stay the same size on screen however far the map is zoomed.
        local scale = 1 / (ns.Guarded(function() return WorldMapFrame:GetCanvasScale() end) or 1)
        local size = ns.settings.worldmap.pinSize

        for _, place in ipairs(WorldMap.SpawnsOn(WorldMapFrame:GetMapID())) do
            if pool.used >= WorldMap.MAX then
                break
            end
            if ns.Filter.Shows("worldmap", place.spawn) then
                local pin = pool:Acquire()
                ns.Pins.Set(pin, place.spawn, size)
                pin:SetScale(scale)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", place.x * width / scale, -place.y * height / scale)
            end
        end
    end

    pool:Finish()
end

--- The pins on the map now.
function WorldMap.Shown()
    local shown = {}
    if pool then
        for index = 1, pool.used do
            shown[index] = pool.pins[index]
        end
    end
    return shown
end

local function attach()
    if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider
        and CreateFromMixins and MapCanvasDataProviderMixin) then
        return
    end

    pool = ns.Pins.Pool(WorldMapFrame:GetCanvas())
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RefreshAllData() WorldMap.Refresh() end
    function provider:RemoveAllData() pool:Begin(); pool:Finish() end
    function provider:OnMapChanged() WorldMap.Refresh() end
    function provider:OnCanvasScaleChanged() WorldMap.Refresh() end
    WorldMapFrame:AddDataProvider(provider)
    WorldMapFrame:HookScript("OnShow", WorldMap.Refresh)
end

ns.OnLogin(function()
    ns.Guarded(attach)
end)

-- The world map can load after GatherMap, on demand.
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_WorldMap" and ns.settings then
        ns.Guarded(attach)
    end
end)

ns.OnRefresh(WorldMap.Refresh)

ns.RegisterCommand("where", "Show where the game and GatherMap put you on the map", function()
    local said = ns.Guarded(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local rect = ns.Geometry.MapRect(mapID)
        local x, y = UnitPosition("player")
        local game = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not rect or type(x) ~= "number" or not game then
            return false
        end
        local mx, my = ns.Geometry.ToMap(rect, x, y)
        ns.Print(string.format("Map %d. Game: %.3f, %.3f. GatherMap: %.3f, %.3f.", mapID, game.x, game.y, mx, my))
        return true
    end)
    if not said then
        ns.Print("The game will not say where you are here.")
    end
end)
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `.\run-tests.ps1 GatherMap`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add GatherMap
git commit -m "GatherMap: pins and the world map

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Minimap pins

**Files:**
- Create: `GatherMap/MinimapPins.lua`
- Modify: `GatherMap/GatherMap.toc`, `GatherMap/tests/helpers.lua` (append `MinimapPins.lua`)
- Test: `GatherMap/tests/minimappins_spec.lua`

**Interfaces:**
- Consumes: `ns.Geometry.MinimapDiameter`, `ns.Geometry.MinimapOffset`, `ns.Spawns.Near`, `ns.Filter.Shows`, `ns.Pins.Pool`, `ns.Pins.Set`, `ns.settings.minimap.pinSize`, `ns.settings.enabled`.
- Produces: `ns.MinimapPins.Refresh()`, `ns.MinimapPins.Shown() -> pin[]`, `ns.MinimapPins.ticker` (frame with `OnUpdate`), `INTERVAL` (0.2), `MAX` (100).

- [ ] **Step 1: Write the failing spec**

`GatherMap/tests/minimappins_spec.lua`:

```lua
local helpers = require("helpers")

local C = "0:3764:-10610.0:1160.0"

local function entries(ns)
    local list = {}
    for _, pin in ipairs(ns.MinimapPins.Shown()) do list[#list + 1] = pin.spawn.entry end
    table.sort(list)
    return table.concat(list, ",")
end

local function pinFor(ns, key)
    for _, pin in ipairs(ns.MinimapPins.Shown()) do
        if pin.spawn.key == key then return pin end
    end
end

local function refreshed(setup)
    local ns, env = helpers.loggedIn(setup)
    ns.MinimapPins.Refresh()
    return ns, env
end

describe("the minimap pins", function()
    it("show what is in the minimap's range", function()
        local ns = refreshed()
        assertEqual("1731,2843,3764,180582", entries(ns), "the far copper vein is 623 yards off")
    end)

    it("sit where their spawn is, north up and west left", function()
        local ns, env = refreshed()
        local point, relativeTo, relativePoint, x, y = pinFor(ns, C):GetPoint(1)
        assertEqual("CENTER", point)
        assertEqual(env.Minimap, relativeTo)
        assertEqual("CENTER", relativePoint)
        local scale = 140 / (466 + 2 / 3)
        assertNear(-6 * scale, x)
        assertNear(-6.2 * scale, y)
        assertEqual(10, pinFor(ns, C):GetWidth())
    end)

    it("narrow with the zoom", function()
        local ns = refreshed(function(env) env.__zoom = 5 end)
        assertEqual("1731,3764,180582", entries(ns), "the chest is 175 yards off")
    end)

    it("narrow indoors", function()
        local ns = refreshed(function(env) env.__indoors = true end)
        assertEqual("1731,3764,180582", entries(ns))
    end)

    it("turn with a turning minimap", function()
        local ns = refreshed(function(env)
            env.__cvars.rotateMinimap = "1"
            env.__facing = math.pi / 2
        end)
        local _, _, _, x, y = pinFor(ns, C):GetPoint(1)
        local scale = 140 / (466 + 2 / 3)
        assertNear(-6.2 * scale, x)
        assertNear(6 * scale, y)
    end)

    it("follow the minimap filters", function()
        local ns = helpers.loggedIn()
        ns.settings.minimap.kinds.ore = false
        ns.MinimapPins.Refresh()
        assertEqual("2843,180582", entries(ns))
    end)

    it("hide while pins are off", function()
        local ns = refreshed()
        ns.SetEnabled(false)
        assertEqual("", entries(ns))
    end)

    it("hide when the client will not say where the player is", function()
        local ns, env = refreshed()
        env.__position = nil
        ns.MinimapPins.Refresh()
        assertEqual("", entries(ns))
        env.UnitPosition = function() error("secret") end
        ns.MinimapPins.Refresh()
        assertEqual("", entries(ns))
    end)

    it("move five times a second, not every frame", function()
        local ns, env = helpers.loggedIn()
        local tick = ns.MinimapPins.ticker.scripts.OnUpdate
        tick(ns.MinimapPins.ticker, 0.1)
        assertEqual("", entries(ns), "not yet")
        tick(ns.MinimapPins.ticker, 0.1)
        assertEqual("1731,2843,3764,180582", entries(ns))
    end)

    it("stop at their limit", function()
        local ns = helpers.loggedIn()
        for index = 1, ns.MinimapPins.MAX + 20 do
            ns.Spawns.AddPoint(0, 1731, -10603.8 + index * 0.5, 1154.0)
        end
        ns.MinimapPins.Refresh()
        assertEqual(ns.MinimapPins.MAX, #ns.MinimapPins.Shown())
    end)
end)
```

- [ ] **Step 2: Add the file and run to see it fail**

Append `"MinimapPins.lua",` to `M.FILES` and `MinimapPins.lua` to the TOC.

Run: `.\run-tests.ps1 GatherMap`
Expected: FAIL, `cannot open MinimapPins.lua`.

- [ ] **Step 3: Write MinimapPins.lua**

```lua
local addonName, ns = ...

-- Pins on the minimap for what is in its range, redrawn five times a second
-- from the player's position in world yards. The position keeps coming in
-- combat (probed 2026-09-28), so the pins keep moving through a fight.

local MinimapPins = {}
ns.MinimapPins = MinimapPins

MinimapPins.INTERVAL = 0.2
MinimapPins.MAX = 100

local pool

function MinimapPins.Refresh()
    if not pool then
        return
    end
    pool:Begin()

    ns.Guarded(function()
        if not ns.settings.enabled then
            return
        end
        local x, y, _, continent = UnitPosition("player")
        if type(x) ~= "number" then
            return
        end

        local size = ns.settings.minimap.pinSize
        local diameter = ns.Geometry.MinimapDiameter(Minimap:GetZoom(), IsIndoors and IsIndoors())
        local scale = Minimap:GetWidth() / diameter
        -- Short of the edge by half a pin, so no pin hangs off the round map.
        local radius = diameter / 2 - size / 2 / scale
        local rotate = GetCVar("rotateMinimap") == "1"
        local facing = rotate and GetPlayerFacing and GetPlayerFacing()

        ns.Spawns.Near(continent, x, y, radius, function(spawn)
            if pool.used < MinimapPins.MAX and ns.Filter.Shows("minimap", spawn) then
                local right, up = ns.Geometry.MinimapOffset(x, y, spawn.x, spawn.y, facing, rotate)
                local pin = pool:Acquire()
                ns.Pins.Set(pin, spawn, size)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", Minimap, "CENTER", right * scale, up * scale)
            end
        end)
    end)

    pool:Finish()
end

function MinimapPins.Shown()
    local shown = {}
    if pool then
        for index = 1, pool.used do
            shown[index] = pool.pins[index]
        end
    end
    return shown
end

ns.OnLogin(function()
    if not Minimap then
        return
    end
    pool = ns.Pins.Pool(Minimap)

    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= MinimapPins.INTERVAL - 1e-9 then
            elapsed = 0
            MinimapPins.Refresh()
        end
    end)
    MinimapPins.ticker = ticker
end)

ns.OnRefresh(MinimapPins.Refresh)
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `.\run-tests.ps1 GatherMap`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add GatherMap
git commit -m "GatherMap: pins around the player on the minimap

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The settings page

**Files:**
- Create: `GatherMap/Settings.lua`
- Modify: `GatherMap/GatherMap.toc`, `GatherMap/tests/helpers.lua` (append `Settings.lua`)
- Test: `GatherMap/tests/settings_spec.lua`

**Interfaces:**
- Consumes: `ns.settings.enabled`, `ns.settings.worldmap|minimap` (Task 4's fields), `ns.Nodes`, `ns.SetEnabled`, `ns.Refresh`, `ns.RegisterCommand`, `ns.OnLogin`, `ns.Print`.
- Produces: `ns.OpenSettings()`, `ns.ToggleSettings()`, `ns.SettingsPanel` with `.panel`, `.logo`, `.enabled` (CheckButton), `.kinds[kind]` and `.nodes[name]` (pairs: `{ buttons = { worldmap, minimap }, label, toggle?, all?, none? }`), `.filters.hideUngatherable|hideGrey|onlyConfirmed|showMissing` (pairs), `.sizes.worldmap|minimap` (sliders), `.NodeNames(kind) -> { { name, skill }, ... }`, `.Refresh()`. Command `/gmap settings`; a bare `/gmap` opens the page.

- [ ] **Step 1: Write the failing spec**

`GatherMap/tests/settings_spec.lua`:

```lua
local helpers = require("helpers")

local function opened()
    local ns, env = helpers.loggedIn()
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.SettingsPanel
end

--- Click a checkbox the way the player does: the tick flips, then OnClick.
local function click(checkbox)
    checkbox:SetChecked(not checkbox:GetChecked())
    checkbox.scripts.OnClick(checkbox)
end

describe("the settings page", function()
    it("is a page in the game's options, named GatherMap, with its logo", function()
        local ns, env, panel = opened()
        assertEqual("GatherMap", env.__settingsCategory.name)
        assertEqual("Interface\\AddOns\\GatherMap\\minimap", panel.logo:GetTexture())
    end)

    it("opens from a bare /gmap and from /gmap settings", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "")
        assertEqual("category-id", env.__openedCategory)
        env.__openedCategory = nil
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)

    it("shows what is saved", function()
        local ns, env = helpers.loggedIn()
        ns.settings.minimap.kinds.chest = false
        ns.settings.worldmap.hidden.Silverleaf = true
        ns.settings.minimap.hideGrey = true
        ns.settings.worldmap.pinSize = 16
        local panel = ns.SettingsPanel
        panel.panel:Show()
        assertFalse(panel.kinds.chest.buttons.minimap:GetChecked())
        assertTrue(panel.kinds.chest.buttons.worldmap:GetChecked())
        assertFalse(panel.nodes.Silverleaf.buttons.worldmap:GetChecked())
        assertTrue(panel.nodes.Silverleaf.buttons.minimap:GetChecked())
        assertTrue(panel.filters.hideGrey.buttons.minimap:GetChecked())
        assertTrue(panel.filters.hideUngatherable.buttons.worldmap:GetChecked())
        assertEqual(16, panel.sizes.worldmap:GetValue())
        assertTrue(panel.enabled:GetChecked())
    end)
end)

describe("the page's switches", function()
    it("turn every pin off and on", function()
        local ns, env, panel = opened()
        click(panel.enabled)
        assertFalse(ns.settings.enabled)
        click(panel.enabled)
        assertTrue(ns.settings.enabled)
    end)

    it("turn a kind off on one map and redraw", function()
        local ns, env, panel = opened()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        click(panel.kinds.herb.buttons.minimap)
        assertFalse(ns.settings.minimap.kinds.herb)
        assertTrue(ns.settings.worldmap.kinds.herb)
        assertEqual(1, count)
    end)

    it("hide and show one node by name", function()
        local ns, env, panel = opened()
        click(panel.nodes["Copper Vein"].buttons.worldmap)
        assertTrue(ns.settings.worldmap.hidden["Copper Vein"])
        click(panel.nodes["Copper Vein"].buttons.worldmap)
        assertNil(ns.settings.worldmap.hidden["Copper Vein"])
    end)

    it("set the skill and source filters per map", function()
        local ns, env, panel = opened()
        click(panel.filters.hideUngatherable.buttons.minimap)
        click(panel.filters.hideGrey.buttons.worldmap)
        click(panel.filters.onlyConfirmed.buttons.minimap)
        click(panel.filters.showMissing.buttons.worldmap)
        assertFalse(ns.settings.minimap.hideUngatherable)
        assertTrue(ns.settings.worldmap.hideGrey)
        assertTrue(ns.settings.minimap.onlyConfirmed)
        assertFalse(ns.settings.worldmap.onlyConfirmed)
        assertTrue(ns.settings.worldmap.showMissing)
        assertFalse(ns.settings.minimap.showMissing)
    end)

    it("size the pins", function()
        local ns, env, panel = opened()
        panel.sizes.minimap:SetValue(14.4)
        assertEqual(14, ns.settings.minimap.pinSize)
    end)
end)

describe("a kind's checklist", function()
    it("lists its node names once each, by required skill, with the skill", function()
        local ns = helpers.loggedIn()
        local names = {}
        for _, node in ipairs(ns.SettingsPanel.NodeNames("herb")) do names[#names + 1] = node.name end
        assertEqual("Peacebloom,Silverleaf,Earthroot,Stranglekelp", table.concat(names, ","))
        ns.SettingsPanel.panel:Show()
        assertEqual("Earthroot (15)", ns.SettingsPanel.nodes.Earthroot.label:GetText())
        assertEqual("Battered Chest", ns.SettingsPanel.nodes["Battered Chest"].label:GetText())
    end)

    it("is folded away until its kind is opened", function()
        local ns, env, panel = opened()
        assertFalse(panel.nodes.Silverleaf.buttons.worldmap:IsShown())
        panel.kinds.herb.toggle.scripts.OnClick(panel.kinds.herb.toggle)
        assertTrue(panel.nodes.Silverleaf.buttons.worldmap:IsShown())
        assertTrue(panel.nodes.Silverleaf.label:IsShown())
        assertFalse(panel.nodes["Copper Vein"].buttons.worldmap:IsShown(), "other kinds stay folded")
        panel.kinds.herb.toggle.scripts.OnClick(panel.kinds.herb.toggle)
        assertFalse(panel.nodes.Silverleaf.buttons.worldmap:IsShown())
    end)

    it("hides or shows every node of its kind, on both maps, at once", function()
        local ns, env, panel = opened()
        panel.kinds.ore.none.scripts.OnClick(panel.kinds.ore.none)
        assertTrue(ns.settings.worldmap.hidden["Copper Vein"])
        assertTrue(ns.settings.minimap.hidden["Tin Vein"])
        assertNil(ns.settings.worldmap.hidden.Silverleaf, "herbs untouched")
        assertFalse(panel.nodes["Tin Vein"].buttons.minimap:GetChecked())
        panel.kinds.ore.all.scripts.OnClick(panel.kinds.ore.all)
        assertNil(ns.settings.worldmap.hidden["Copper Vein"])
        assertTrue(panel.nodes["Tin Vein"].buttons.minimap:GetChecked())
    end)
end)
```

- [ ] **Step 2: Add the file and run to see it fail**

Append `"Settings.lua",` to `M.FILES` and `Settings.lua` to the TOC.

Run: `.\run-tests.ps1 GatherMap`
Expected: FAIL, `cannot open Settings.lua`.

- [ ] **Step 3: Write Settings.lua**

```lua
local addonName, ns = ...

-- GatherMap's page in the game's options window. Every filter has two
-- checkboxes, one for the world map and one for the minimap; each kind folds
-- open into a checklist of its nodes.

local PADDING = 16
local LOGO_SIZE = 24
local ROW_HEIGHT = 26
local PANEL_WIDTH = 560
local COLUMN = 30 -- one checkbox column
local LABEL_X = PADDING + COLUMN * 2 + 6
local WHERES = { "worldmap", "minimap" }
local KINDS = { "herb", "ore", "pool", "chest" }
local KIND_LABEL = { herb = "Herbs", ore = "Ore", pool = "Fishing pools", chest = "Chests" }

local Panel = {}
ns.SettingsPanel = Panel
Panel.kinds, Panel.nodes, Panel.filters, Panel.sizes = {}, {}, {}, {}

local panel, category, built, content
local rows = {}   -- in page order: { height, frames, visible }
local pairs_ = {} -- every checkbox pair, for Refresh
local expanded = {}
local startY

--- Every node name of `kind` once, by required skill, then name.
function Panel.NodeNames(kind)
    local seen, names = {}, {}
    for _, node in pairs(ns.Nodes) do
        if node.kind == kind and not seen[node.name] then
            seen[node.name] = true
            table.insert(names, { name = node.name, skill = node.skill })
        end
    end
    table.sort(names, function(a, b)
        if (a.skill or 0) ~= (b.skill or 0) then
            return (a.skill or 0) < (b.skill or 0)
        end
        return a.name < b.name
    end)
    return names
end

--- Stack the rows that are showing, top to bottom.
local function layout()
    local y = startY
    for _, row in ipairs(rows) do
        local show = not row.visible or row.visible()
        for _, frame in ipairs(row.frames) do
            frame:SetShown(show)
            if show then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", content, "TOPLEFT", frame.gmX, y + frame.gmY)
            end
        end
        if show then
            y = y - row.height
        end
    end
    content:SetHeight(-y + PADDING)
end

local function place(frame, x, y)
    frame.gmX, frame.gmY = x, y or 0
    return frame
end

local function text(label, x, y, font)
    local fontString = content:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fontString:SetText(label)
    return place(fontString, x, y)
end

local function button(label, width, x)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(label)
    return place(b, x, -2)
end

--- A row with a checkbox per map. `get(where)` reads, `set(where, value)`
-- writes; `visible` folds the row away when it returns false.
local function checkPair(label, get, set, indent, visible)
    local pair = { get = get, buttons = {} }
    local frames = {}
    for index, where in ipairs(WHERES) do
        local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        place(check, PADDING + COLUMN * (index - 1))
        check:SetScript("OnClick", function(self)
            set(where, self:GetChecked() and true or false)
            ns.Refresh()
            Panel.Refresh()
        end)
        pair.buttons[where] = check
        table.insert(frames, check)
    end
    pair.label = text(label, LABEL_X + (indent or 0), -5)
    table.insert(frames, pair.label)
    pair.frames = frames
    table.insert(pairs_, pair)
    table.insert(rows, { height = ROW_HEIGHT, frames = frames, visible = visible })
    return pair
end

local function addKind(kind)
    local pair = checkPair(KIND_LABEL[kind],
        function(where) return ns.settings[where].kinds[kind] end,
        function(where, value) ns.settings[where].kinds[kind] = value end)
    Panel.kinds[kind] = pair

    local names = Panel.NodeNames(kind)
    local function setAll(hidden)
        for _, where in ipairs(WHERES) do
            for _, node in ipairs(names) do
                ns.settings[where].hidden[node.name] = hidden or nil
            end
        end
        ns.Refresh()
        Panel.Refresh()
    end

    pair.toggle = button("+", 24, LABEL_X + 110)
    pair.toggle:SetScript("OnClick", function()
        expanded[kind] = not expanded[kind]
        Panel.Refresh()
        layout()
    end)
    pair.all = button("All", 44, LABEL_X + 140)
    pair.all:SetScript("OnClick", function() setAll(false) end)
    pair.none = button("None", 50, LABEL_X + 188)
    pair.none:SetScript("OnClick", function() setAll(true) end)
    table.insert(pair.frames, pair.toggle)
    table.insert(pair.frames, pair.all)
    table.insert(pair.frames, pair.none)

    for _, node in ipairs(names) do
        local label = node.skill and string.format("%s (%d)", node.name, node.skill) or node.name
        Panel.nodes[node.name] = checkPair(label,
            function(where) return not ns.settings[where].hidden[node.name] end,
            function(where, value) ns.settings[where].hidden[node.name] = (not value) or nil end,
            20, function() return expanded[kind] end)
    end
end

local function addFilter(key, label)
    Panel.filters[key] = checkPair(label,
        function(where) return ns.settings[where][key] end,
        function(where, value) ns.settings[where][key] = value end)
end

local function addSize(where, label, low, high)
    local caption = text(label, PADDING, -4)
    local slider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(200)
    place(slider, PADDING + 170, -4)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if ns.settings[where].pinSize ~= value then
            ns.settings[where].pinSize = value
            ns.Refresh()
        end
    end)
    Panel.sizes[where] = slider
    table.insert(rows, { height = ROW_HEIGHT + 10, frames = { caption, slider } })
end

--- Show what is saved. Safe to call before the page is built.
function Panel.Refresh()
    if not built then
        return
    end
    Panel.enabled:SetChecked(ns.settings.enabled)
    for _, pair in ipairs(pairs_) do
        for where, check in pairs(pair.buttons) do
            check:SetChecked(pair.get(where))
        end
    end
    for kind, pair in pairs(Panel.kinds) do
        pair.toggle:SetText(expanded[kind] and "-" or "+")
    end
    for where, slider in pairs(Panel.sizes) do
        slider:SetValue(ns.settings[where].pinSize)
    end
end

local function ensureBuilt()
    if built or not panel then
        return
    end
    built = true

    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    if ok and scroll then
        -- Room on the right for the template's scroll bar.
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 4)
        content = CreateFrame("Frame", nil, scroll)
        content:SetSize(PANEL_WIDTH, 1)
        scroll:SetScrollChild(content)
    else
        content = panel
    end

    -- The minimap icon, not the AddOns list one: that carries a square tile.
    local logo = content:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", PADDING, -PADDING)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\minimap")
    Panel.logo = logo

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("GatherMap")

    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))

    local hint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", PADDING, -PADDING - 30)
    hint:SetWidth(PANEL_WIDTH - PADDING * 2)
    hint:SetJustifyH("LEFT")
    hint:SetText("Each row has two boxes: the world map, then the minimap. "
        .. "Open a kind with + to pick its nodes one by one. Dimmed pins come from "
        .. "the classic database and are not seen in WoW Forever yet; right-click "
        .. "a pin where nothing grows to mark it not here.")

    startY = -PADDING - 84 -- below the title and the three-line hint

    local enabled = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    place(enabled, PADDING)
    enabled:SetScript("OnClick", function(self)
        ns.SetEnabled(self:GetChecked() and true or false)
    end)
    Panel.enabled = enabled
    table.insert(rows, { height = ROW_HEIGHT + 6, frames = { enabled, text("Show pins", PADDING + COLUMN, -5) } })

    table.insert(rows, { height = 18, frames = {
        text("Map", PADDING, 0, "GameFontNormalSmall"),
        text("Mini", PADDING + COLUMN, 0, "GameFontNormalSmall"),
    } })

    for _, kind in ipairs(KINDS) do
        addKind(kind)
    end
    addFilter("hideUngatherable", "Hide nodes my skill cannot gather yet")
    addFilter("hideGrey", "Hide grey nodes (no skill-ups left)")
    addFilter("onlyConfirmed", "Only places confirmed in game (yours, or from the release)")
    addFilter("showMissing", "Show spawns marked not here")
    addSize("worldmap", "World map pin size", 8, 24)
    addSize("minimap", "Minimap pin size", 6, 20)

    Panel.Refresh()
    layout()
end

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden: the Settings system shows it when the category is
    -- opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "GatherMap"
    Panel.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Panel.Refresh()
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, "GatherMap")
    Settings.RegisterAddOnCategory(category)
end

-- Whether the page on screen was opened from here rather than through the
-- game menu. Decides where closing it should leave the player.
local openedByUs = false
-- Armed while the client is closing a page we opened, so the game menu it
-- puts up on the way out can be turned away at the door.
local suppressGameMenu = false
local closeHooked = false

local function dismissGameMenu(frame)
    suppressGameMenu = false
    if HideUIPanel then
        HideUIPanel(frame)
    else
        frame:Hide()
    end
end

local function watchForClose()
    if closeHooked or not SettingsPanel or not SettingsPanel.HookScript then
        return
    end
    closeHooked = true

    SettingsPanel:HookScript("OnHide", function()
        if not openedByUs then
            return
        end
        openedByUs = false
        suppressGameMenu = true
        C_Timer.After(0, function()
            if suppressGameMenu then
                if GameMenuFrame and GameMenuFrame:IsShown() then
                    dismissGameMenu(GameMenuFrame)
                end
                suppressGameMenu = false
            end
        end)
    end)

    if GameMenuFrame and GameMenuFrame.HookScript then
        GameMenuFrame:HookScript("OnShow", function(self)
            if suppressGameMenu then
                dismissGameMenu(self)
            end
        end)
    end
end

function ns.OpenSettings()
    if not category then
        ns.Print("This client has no settings panel. Use /gmap help for commands.")
        return
    end
    watchForClose()
    openedByUs = true
    ensureBuilt()
    Settings.OpenToCategory(category:GetID())
    Panel.Refresh()
end

--- Close the options window if it is showing this page; otherwise open it here.
function ns.ToggleSettings()
    if panel and panel:IsShown() and SettingsPanel and SettingsPanel:IsShown() then
        if HideUIPanel then
            HideUIPanel(SettingsPanel)
        else
            SettingsPanel:Hide()
        end
        return
    end
    ns.OpenSettings()
end

ns.RegisterCommand("settings", "Open the settings page", function()
    ns.OpenSettings()
end)

-- Whatever else changes a setting (a command, the minimap button) is shown
-- on the page too.
ns.OnRefresh(Panel.Refresh)

ns.OnLogin(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    end
end)
```

Note: `Panel.Refresh` calls `slider:SetValue`, whose `OnValueChanged` calls `ns.Refresh`, which calls `Panel.Refresh` again. It cannot loop: `SetValue` with the value already set does nothing, and the handler only refreshes when the saved size changes.

- [ ] **Step 4: Run the tests to see them pass**

Run: `.\run-tests.ps1 GatherMap`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add GatherMap
git commit -m "GatherMap: the settings page, with filters for each map

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: The minimap button

**Files:**
- Create: `GatherMap/Minimap.lua`
- Modify: `GatherMap/GatherMap.toc`, `GatherMap/tests/helpers.lua` (append `Minimap.lua`)
- Test: `GatherMap/tests/minimap_spec.lua`

**Interfaces:**
- Consumes: `ns.settings.enabled`, `ns.SetEnabled`, `ns.ToggleSettings`, `ns.AddDefaults`, `ns.OnLogin`, `ns.RegisterCommand`, `ns.Print`.
- Produces: `ns.MinimapButton.PositionFor(angle, radius)`, `.AngleFor(dx, dy)`, `.Button()`; settings `ns.settings.button = { angle = 220, hide = false }`; command `/gmap minimap`.

- [ ] **Step 1: Write the failing spec**

`GatherMap/tests/minimap_spec.lua`:

```lua
local helpers = require("helpers")

describe("the minimap button's geometry", function()
    local ns = helpers.loadAddon()

    it("puts angle 0 to the right and 90 at the top", function()
        local x, y = ns.MinimapButton.PositionFor(0, 80)
        assertNear(80, x)
        assertNear(0, y)
        x, y = ns.MinimapButton.PositionFor(90, 80)
        assertNear(0, x)
        assertNear(80, y)
    end)

    it("turns a cursor offset back into an angle between 0 and 360", function()
        assertNear(0, ns.MinimapButton.AngleFor(10, 0))
        assertNear(90, ns.MinimapButton.AngleFor(0, 10))
        assertNear(225, ns.MinimapButton.AngleFor(-10, -10))
    end)
end)

describe("the minimap button", function()
    it("sits on the minimap at its own angle, with GatherMap's icon", function()
        local ns, env = helpers.loggedIn()
        local button = ns.MinimapButton.Button()
        assertEqual(env.Minimap, button:GetParent())
        assertEqual(220, ns.settings.button.angle)
        assertEqual("Interface\\AddOns\\GatherMap\\minimap", button.icon:GetTexture())
    end)

    it("shows and hides every pin on a click, and says which in the tooltip", function()
        local ns, env = helpers.loggedIn()
        local button = ns.MinimapButton.Button()
        button.scripts.OnClick(button, "LeftButton")
        assertFalse(ns.settings.enabled)
        button.scripts.OnEnter(button)
        assertMatch("hidden", env.GameTooltip.text)
        button.scripts.OnClick(button, "LeftButton")
        assertTrue(ns.settings.enabled)
        assertMatch("shown", env.GameTooltip.text, "the tooltip under the cursor keeps up")
    end)

    it("opens the settings on a right-click", function()
        local ns, env = helpers.loggedIn()
        local button = ns.MinimapButton.Button()
        assertEqual("RightButtonUp", button.clicks[2])
        button.scripts.OnClick(button, "RightButton")
        assertEqual("category-id", env.__openedCategory)
        assertTrue(ns.settings.enabled, "a right-click leaves the pins alone")
    end)

    it("hides and shows with /gmap minimap, and remembers", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "minimap")
        assertFalse(ns.MinimapButton.Button():IsShown())
        assertTrue(ns.settings.button.hide)
        assertMatch("/gmap minimap brings it back", helpers.printed(env))
        helpers.command(env, "minimap")
        assertTrue(ns.MinimapButton.Button():IsShown())
    end)
end)
```

- [ ] **Step 2: Add the file and run to see it fail**

Append `"Minimap.lua",` to `M.FILES` and `Minimap.lua` to the TOC.

Run: `.\run-tests.ps1 GatherMap`
Expected: FAIL, `cannot open Minimap.lua`.

- [ ] **Step 3: Write Minimap.lua**

```lua
local addonName, ns = ...

-- A round button on the minimap's rim: click to show or hide every pin,
-- right-click for the settings, drag to slide it round the rim. Built by
-- hand, as the other addons' buttons are.

local MinimapButton = {}
ns.MinimapButton = MinimapButton

ns.AddDefaults({
    -- Degrees anticlockwise from the right, apart from the other addons' buttons.
    button = { angle = 220, hide = false },
})

local SIZE = 31
local RIM_OFFSET = 10 -- how far past the minimap's edge the button's centre sits
local ICON = "Interface\\AddOns\\GatherMap\\minimap"

local button

function MinimapButton.PositionFor(angle, radius)
    local radians = math.rad(angle)
    return math.cos(radians) * radius, math.sin(radians) * radius
end

-- Lua 5.1 has math.atan2; later versions take two arguments to math.atan.
local atan2 = math.atan2 or math.atan

function MinimapButton.AngleFor(dx, dy)
    local angle = math.deg(atan2(dy, dx))
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

local function radius()
    return (Minimap:GetWidth() / 2) + RIM_OFFSET
end

local function place()
    local x, y = MinimapButton.PositionFor(ns.settings.button.angle, radius())
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Guarded: a drag that raised every frame would flood the error log.
local function followCursor()
    pcall(function()
        local centerX, centerY = Minimap:GetCenter()
        local cursorX, cursorY = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        ns.settings.button.angle = MinimapButton.AngleFor(cursorX / scale - centerX, cursorY / scale - centerY)
        place()
    end)
end

local function showTooltip(self)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("GatherMap: pins " .. (ns.settings.enabled and "|cff40ff40shown|r" or "|cffff4040hidden|r"))
    GameTooltip:AddLine("Click to show or hide every pin.", 1, 1, 1)
    GameTooltip:AddLine("Right-click for the settings, drag to move.", 1, 1, 1)
    GameTooltip:Show()
end

local function onClick(self, mouseButton)
    if mouseButton == "RightButton" then
        ns.ToggleSettings()
        return
    end
    ns.SetEnabled(not ns.settings.enabled)
    ns.Print(ns.settings.enabled and "Pins shown." or "Pins hidden.")
    if GameTooltip and GameTooltip:GetOwner() == self then
        showTooltip(self)
    end
end

local function create()
    button = CreateFrame("Button", "GatherMapMinimapButton", Minimap)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- The standard minimap-button layers: a dark disc, the icon on it, and
    -- the gold tracking ring over both.
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    button:SetScript("OnClick", onClick)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", followCursor) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    place()
    button:SetShown(not ns.settings.button.hide)
end

function MinimapButton.Button()
    return button
end

ns.OnLogin(function()
    if Minimap then
        create()
    end
end)

ns.RegisterCommand("minimap", "Hide or show the minimap button", function()
    ns.settings.button.hide = not ns.settings.button.hide
    if button then
        button:SetShown(not ns.settings.button.hide)
    end
    if ns.settings.button.hide then
        ns.Print("Minimap button hidden. /gmap minimap brings it back.")
    else
        ns.Print("Minimap button shown.")
    end
end)
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `.\run-tests.ps1 GatherMap`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add GatherMap
git commit -m "GatherMap: the minimap button

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Icons, real data, docs, and the in-game check

**Files:**
- Modify: `tools/draw-icons.mjs` (add GatherMap's theme and symbol)
- Create: `GatherMap/icon.tga`, `GatherMap/minimap.tga` (generated)
- Create: `GatherMap/Data/*.lua` (generated), Modify: `GatherMap/GatherMap.toc` (data lines, generated)
- Create: `GatherMap/README.md`; Modify: `README.md` (the addon table)

**Interfaces:**
- Consumes: everything above; `build-data.mjs` from Task 1.
- Produces: an installable addon.

- [ ] **Step 1: Draw the icons**

In `tools/draw-icons.mjs`, change the first comment line to name GatherMap too ("Draws the 64x64 icons for BossLoot, FishScale, BankBags and GatherMap, ..."), then add before `const root = process.argv[2];`:

```js
// GatherMap: a map pin with a leaf in its head, in green.
const green = {
  dark: [8, 18, 6], glow: [40, 96, 30], ring: [118, 204, 92],
  light: [206, 250, 180], mid: [110, 192, 84], outline: [22, 58, 14], detail: [34, 86, 24],
};
const mapPin = union(circle(32, 25, 15), triangle(19.5, 31, 44.5, 31, 32, 55));
const intersect = (a, b) => (x, y) => Math.max(a(x, y), b(x, y));
const pinDetails = union(
  intersect(circle(27.5, 29.5, 8.5), circle(36.5, 20.5, 8.5)), // the leaf, a lens across the head
  segment(26.5, 31, 33, 24.5, 0.6), // its vein, drawn in the outline colour below
);
const pinShine = ellipse(26, 16.5, 5, 1.6);
```

and after the BankBags lines:

```js
writeTga(path.join(root, 'GatherMap', 'icon.tga'), draw(green, mapPin, pinDetails, pinShine));
writeTga(path.join(root, 'GatherMap', 'minimap.tga'), draw(green, mapPin, pinDetails, pinShine, { tile: false, zoom: 1.35 }));
```

Run: `node tools/draw-icons.mjs .`
Expected: `written`. Then `git status --short` shows only `GatherMap/icon.tga`, `GatherMap/minimap.tga` and `tools/draw-icons.mjs`: the other addons' icons come out byte-identical. If any other `.tga` shows as modified, stop and find out why before going on.

- [ ] **Step 2: Get the vMaNGOS database and build the data**

Task 0 already downloaded it; only if `$SCRATCH/vmangos/sqlite-dump/mangos.sqlite` is gone:

```bash
gh release download db_latest -R vmangos/core -p "db-sqlite-*.zip" -D "$SCRATCH/vmangos" --clobber
unzip -o -q "$SCRATCH/vmangos/"db-sqlite-*.zip -d "$SCRATCH/vmangos"
```

Then build:

```bash
node GatherMap/tools/build-data.mjs "$SCRATCH/vmangos/sqlite-dump/mangos.sqlite"
```

(`$SCRATCH` is the session scratchpad directory; the database never goes in the repo.) Expect `ok    0 recordings: 0 confirmed, 0 new, 0 not there` until someone sends one.

Expected: `ok` lines with a count per kind (tens of herbs, about 20 ore, a dozen or so pools, the chests) and per continent (thousands each), and no `error` line. Fix any `warn "<name>" in nodes.json has no spawns` by checking the database's spelling:

```bash
node -e "const {DatabaseSync}=require('node:sqlite');const db=new DatabaseSync(process.argv[1]);console.log(db.prepare(\"select distinct name from gameobject_template where type=3 and name like ?\").all('%'+process.argv[2]+'%'))" "$SCRATCH/vmangos/sqlite-dump/mangos.sqlite" Steelbloom
```

then correct `nodes.json` and build again. Check `GatherMap.toc` now lists `Data\Nodes.lua` and the spawn files between the markers.

- [ ] **Step 3: Write the README**

`GatherMap/README.md`:

```markdown
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
```

In the root `README.md` table, add after the BossLoot row:

```markdown
| [GatherMap](GatherMap/) | Herbs, ore, fishing pools and chests on the world map and minimap, with filters |
```

- [ ] **Step 4: Run every test and package**

Run: `.\run-tests.ps1`
Expected: every addon's suite passes, GatherMap's Lua and Node tests included.

Run: `.\package.ps1 GatherMap -Install`
Expected: `Packaged N files -> ...GatherMap-0.1.0.zip` and `Installed -> ...\_classic_beta_\Interface\AddOns\GatherMap`.

- [ ] **Step 5: Commit**

```bash
git add tools/draw-icons.mjs GatherMap README.md
git commit -m "GatherMap: icons, the vMaNGOS data, and the README

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: Check it in game (with the user)**

Hand the user this list and wait for their answers; fix anything that fails with a failing test first, in the task that owns it:

1. Login: the chat line "GatherMap Loaded…", no Lua error, the green icon on the minimap rim and in the AddOns list.
2. `/gmap where` in Westfall and Elwynn: the Game and GatherMap numbers match to 3 decimals.
3. World map on Westfall: copper and tin pins where veins really are; hover one for its tooltip; zoom the map in (pins stay the same size); open Eastern Kingdoms (pins shown, map still responsive).
4. Minimap: pins around you, moving as you ride and in a fight; change minimap zoom; indoors (a cave) the range narrows.
5. Gather a node: its pin goes from dimmed to full with a gold edge, and the tooltip says "Gathered here 1 time".
5b. Find a dimmed pin where nothing grows, right-click it: it disappears from both maps; turn on "Show spawns marked not here" and right-click it again to take the mark off.
5c. `/reload`, then check `WTF/Account/<name>/SavedVariables/GatherMap.lua` holds `gathered` and `missing`; copy it to `GatherMap/tools/recordings/`, rebuild, and see `1 recordings: N confirmed` (remove it again unless the player wants it in the release).
6. `/gmap`: the page, each filter on each map, a kind's + checklist, All / None, both pin sizes.
7. Right-click the minimap button opens the settings; click hides and shows every pin.
```
