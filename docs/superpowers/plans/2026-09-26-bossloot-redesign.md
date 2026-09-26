# BossLoot Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give BossLoot an opaque rail / boss list / boss page window with boss portraits, a 3D model header, and a generated map of each instance with numbered boss pins.

**Architecture:** The build script gains a pure map module (spawns and patrol waypoints to a grid of height-banded cells, plus pin projection) and writes `map`, `display` and `pin` into the data. The addon gains `Portrait.lua` (portraits and models with fallbacks) and `MapView.lua` (draws a map of any size), `List.lua` learns grids, and `Window.lua` is rebuilt around them.

**Tech Stack:** Lua 5.1 addon, Node 24 build script (`node:sqlite`, `node:test`), Lua 5.4 spec runner.

**Spec:** `docs/superpowers/specs/2026-09-26-bossloot-redesign-design.md` (builds on `docs/superpowers/specs/2026-09-26-bossloot-design.md`)

## Global Constraints

- Map grid: `96` cells across the longer side; trim `0.01` of points on each side of each axis; `4` height bands; cell entry `index * 4 + band`, `index = row * cols + col`, 0-based.
- Projection: screen right is world -y, screen down is world -x (north up).
- Pins are `{ x, y }` fractions 0 to 1, rounded to 3 decimals, clamped.
- Window about `860 x 520`; opaque background texture alpha `1`.
- Portraits: `SetPortraitTextureFromCreatureDisplayID`; models: `PlayerModel:SetDisplayInfo`; every call guarded.
- A search needs 2 or more characters; under that the normal list shows.
- No shared libraries. Generated data never edited by hand.

## Review Focus

- **An instance with no map data** (no points on the map): the inset and full map show nothing and do not error. (Task 5 tests.)
- **A boss with no pin or no model ID** (summoned bosses; chest-only rows): the list still numbers it, the header falls back to portrait or icon, and no pin is drawn. (Tasks 4 and 6 test.)
- **Switching instances repeatedly**: map textures are reused, not created anew each time. (Task 5 tests.)
- **The portrait or model function raising** (secret values, bad IDs): falls back, never errors. (Task 4 tests.)
- **Full map open while the selection changes** (tab switch, search jump): the map redraws for the new instance or closes; it never shows the old instance's pins. (Task 6 tests.)

---

### Task 1: The map geometry (build script)

**Files:**
- Create: `BossLoot/tools/lib/map.mjs`
- Test: `BossLoot/tools/test/map.test.mjs`

**Interfaces:**
- Produces: `GRID` (96), `TRIM` (0.01), `BANDS` (4); `buildMap(points, { grid?, trim? }) -> { cols, rows, cells: number[], bounds, cell } | null` for `points = [{x, y, z}]`; `pinFor(map, point) -> { x, y } | undefined`.

- [ ] **Step 1: Write the failing tests**

```js
// BossLoot/tools/test/map.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildMap, pinFor, BANDS } from '../lib/map.mjs';

const p = (x, y, z = 0) => ({ x, y, z });

test('fills a cell where points fall, seen from above with north up and east right', () => {
  // North is +x, east is -y.
  const map = buildMap([p(100, 0), p(0, -100)], { grid: 10, trim: 0 });
  assert.equal(map.cols, 10);
  assert.equal(map.rows, 10);
  assert.deepEqual(map.cells, [0 * BANDS, 99 * BANDS], 'north-west corner, then south-east');
});

test('uses square cells, so a long thin instance gets fewer rows', () => {
  const map = buildMap([p(0, 0), p(50, -100)], { grid: 10, trim: 0 });
  assert.equal(map.cols, 10);
  assert.equal(map.rows, 5);
});

test('ignores a stray point far from the rest', () => {
  const points = [];
  for (let i = 0; i < 200; i++) points.push(p(i % 20, -(i % 13)));
  points.push(p(5000, -5000));
  const map = buildMap(points, { grid: 20 });
  assert.ok(map.bounds.x1 < 100, `bounds reach ${map.bounds.x1}`);
});

test('bands cells by height, higher in higher bands', () => {
  const map = buildMap([p(100, 0, 0), p(0, -100, 100)], { grid: 10, trim: 0 });
  assert.deepEqual(map.cells.map((v) => v % BANDS), [0, BANDS - 1]);
});

test('has no map without points', () => {
  assert.equal(buildMap([]), null);
});

test('places a pin as fractions of the map, clamped to it', () => {
  const map = buildMap([p(100, 0), p(0, -100)], { grid: 10, trim: 0 });
  assert.deepEqual(pinFor(map, p(100, 0)), { x: 0, y: 0 });
  assert.deepEqual(pinFor(map, p(50, -50)), { x: 0.5, y: 0.5 });
  assert.deepEqual(pinFor(map, p(-999, 999)), { x: 0, y: 1 });
});

test('has no pin without a point or a map', () => {
  assert.equal(pinFor(null, p(0, 0)), undefined);
  assert.equal(pinFor(buildMap([p(0, 0), p(1, 1)]), undefined), undefined);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `node --no-warnings --test "BossLoot/tools/test/*.test.mjs"`
Expected: FAIL, cannot find `../lib/map.mjs`.

- [ ] **Step 3: Implement**

```js
// BossLoot/tools/lib/map.mjs
// An instance's map, generated: the places its mobs stand and walk, seen from
// above on a grid of square cells. The client has no dungeon maps to borrow.

export const GRID = 96;
export const TRIM = 0.01;
export const BANDS = 4;

function quantile(sorted, q) {
  const index = Math.min(sorted.length - 1, Math.max(0, Math.round(q * (sorted.length - 1))));
  return sorted[index];
}

/**
 * Points ({x, y, z} in world yards) to filled cells. North is up and east is
 * right: screen right is world -y, screen down is world -x. The bounds skip
 * the outermost `trim` of points on each axis, since one stray spawn would
 * otherwise squash the whole instance into a corner.
 */
export function buildMap(points, { grid = GRID, trim = TRIM } = {}) {
  if (!points.length) return null;

  const sorted = (axis) => points.map((point) => point[axis]).sort((a, b) => a - b);
  const xs = sorted('x');
  const ys = sorted('y');
  const zs = sorted('z');
  const bounds = {
    x0: quantile(xs, trim), x1: quantile(xs, 1 - trim),
    y0: quantile(ys, trim), y1: quantile(ys, 1 - trim),
    z0: quantile(zs, trim), z1: quantile(zs, 1 - trim),
  };

  const width = bounds.y1 - bounds.y0;
  const height = bounds.x1 - bounds.x0;
  const cell = Math.max(width, height, 1) / grid;
  const cols = Math.max(1, Math.ceil(width / cell - 1e-9));
  const rows = Math.max(1, Math.ceil(height / cell - 1e-9));

  const heights = new Map();
  for (const point of points) {
    if (point.x < bounds.x0 || point.x > bounds.x1 || point.y < bounds.y0 || point.y > bounds.y1) continue;
    const col = Math.min(cols - 1, Math.floor((bounds.y1 - point.y) / cell));
    const row = Math.min(rows - 1, Math.floor((bounds.x1 - point.x) / cell));
    const index = row * cols + col;
    const sum = heights.get(index) ?? { z: 0, n: 0 };
    sum.z += point.z;
    sum.n += 1;
    heights.set(index, sum);
  }

  const range = bounds.z1 - bounds.z0;
  const band = (z) => {
    if (range <= 0) return 0;
    return Math.min(BANDS - 1, Math.max(0, Math.floor(((z - bounds.z0) / range) * BANDS)));
  };

  const cells = [...heights]
    .sort((a, b) => a[0] - b[0])
    .map(([index, sum]) => index * BANDS + band(sum.z / sum.n));

  return { cols, rows, cells, bounds, cell };
}

/** Where a world point falls on the map, as fractions 0 to 1, clamped. */
export function pinFor(map, point) {
  if (!map || !point) return undefined;
  const clamp = (value) => Math.min(1, Math.max(0, value));
  const round = (value) => Math.round(value * 1000) / 1000;
  return {
    x: round(clamp((map.bounds.y1 - point.y) / (map.cols * map.cell))),
    y: round(clamp((map.bounds.x1 - point.x) / (map.rows * map.cell))),
  };
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `node --no-warnings --test "BossLoot/tools/test/*.test.mjs"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BossLoot/tools/lib/map.mjs BossLoot/tools/test/map.test.mjs
git commit -m "BossLoot: generate an instance map from where its mobs stand and walk"
```

---

### Task 2: Map, pins and model IDs in the data

**Files:**
- Modify: `BossLoot/tools/lib/db.mjs`, `BossLoot/tools/lib/instance.mjs`, `BossLoot/tools/lib/lua.mjs`
- Modify: `BossLoot/tools/test/fixture.mjs` (positions, `display_id1`, `creature_movement`)
- Test: `BossLoot/tools/test/instance.test.mjs`, `BossLoot/tools/test/lua.test.mjs` (append)
- Generated: `BossLoot/Data/*.lua`

**Interfaces:**
- Consumes: `buildMap`, `pinFor` (Task 1).
- Produces: `db.mapPoints(map) -> {x,y,z}[]`, `db.creatureSpawn(entry, map) -> {x,y,z}|undefined`, `db.objectSpawn(entry, map) -> {x,y,z}|undefined`.
- Produces in `buildInstance` output: `instance.map = { cols, rows, cells } | undefined`; each boss `display?: number`, `pin?: { x, y }`.
- Produces in Lua data: `map = { cols = C, rows = R, cells = { ... } }` on the instance; `display = N` and `pin = { x, y }` on bosses that have them.

- [ ] **Step 1: Extend the fixture**

In `fixture.mjs`, give `creature` and `gameobject` position columns, `creature_template` a `display_id1`, and add `creature_movement`:

```js
    create table creature_template (entry int, patch int default 0, name text, loot_id int default 0, display_id1 int default 0);
    create table creature (guid integer primary key, id int, id2 int default 0, id3 int default 0,
      id4 int default 0, id5 int default 0, map int, patch_min int default 0, patch_max int default 10,
      position_x real default 0, position_y real default 0, position_z real default 0);
    create table gameobject_template (entry int, patch int default 0, type int, name text, data1 int default 0);
    create table gameobject (guid integer primary key, id int, map int, patch_min int default 0, patch_max int default 10,
      position_x real default 0, position_y real default 0, position_z real default 0);
    create table creature_movement (id int, point int, position_x real, position_y real, position_z real);
```

- [ ] **Step 2: Write the failing tests**

Append to `instance.test.mjs`:

```js
test('draws a map of where mobs stand and walk, with the boss pinned where it stands', () => {
  const { db, add } = world();
  db.exec('update creature set position_x = 100, position_y = 0 where id = 1');
  db.exec('update creature set position_x = 0, position_y = -100 where id = 2');
  add('creature_movement', { id: 2, point: 1, position_x: 50, position_y: -50, position_z: 0 });
  const { instance } = buildInstance(openDb(db), def);
  assert.ok(instance.map.cells.length >= 3, 'two spawns, a chest and a waypoint');
  assert.deepEqual(instance.bosses[0].pin, { x: 0, y: 0 });
});

test('pins a chest-only boss at its chest, and gives a summoned boss no pin', () => {
  const { db, add } = world();
  db.exec('update creature set position_x = 100, position_y = 0 where id = 1');
  db.exec('update gameobject set position_x = 0, position_y = -100 where id = 50');
  add('creature_template', { entry: 3, name: 'Summoned Boss', loot_id: 1 });
  const bosses = [{ name: 'Chest Only', creatures: [], objects: ['Old Chest'] }, 'Summoned Boss'];
  const { instance } = buildInstance(openDb(db), { ...def, bosses });
  assert.deepEqual(instance.bosses[0].pin, { x: 1, y: 1 });
  assert.equal(instance.bosses[1].pin, undefined);
});

test("records the boss's model, for its portrait", () => {
  const { db } = world();
  db.exec('update creature_template set display_id1 = 8807 where entry = 1');
  const { instance } = buildInstance(openDb(db), def);
  assert.equal(instance.bosses[0].display, 8807);
});

test('an instance with nothing on its map has no map', () => {
  const { db } = world();
  const { instance } = buildInstance(openDb(db), { ...def, map: 999 });
  assert.equal(instance.map, undefined);
});
```

Append to `lua.test.mjs`:

```js
test('writes the map, and each boss model and pin', () => {
  const text = instanceFile({
    key: 'Test', name: 'Test Depths', kind: 'dungeon', levels: [52, 60],
    map: { cols: 96, rows: 71, cells: [0, 5, 9] },
    bosses: [{ name: 'Boss One', display: 8807, pin: { x: 0.25, y: 0.5 }, loot: [] }],
    notable: { trash: [], objects: [] },
  });
  assert.match(text, /map = \{ cols = 96, rows = 71, cells = \{\n\s+0, 5, 9,\n\s+\} \},/);
  assert.match(text, /display = 8807,/);
  assert.match(text, /pin = \{ 0\.25, 0\.5 \},/);
});
```

- [ ] **Step 3: Run to verify they fail**

Run: `node --no-warnings --test "BossLoot/tools/test/*.test.mjs"`
Expected: FAIL: `instance.map` undefined, no `pin`, no `display`, Lua lacks the fields.

- [ ] **Step 4: Implement the queries (db.mjs)**

Add inside the returned object in `openDb`:

```js
    // Everything that marks out an instance's shape: where creatures and
    // objects are spawned, and every waypoint of the creatures' patrols.
    mapPoints(map) {
      const points = [
        ...prepare(`select position_x as x, position_y as y, position_z as z from creature where map = ? and ${SPAWNED}`).all(map),
        ...prepare(`select position_x as x, position_y as y, position_z as z from gameobject where map = ? and ${SPAWNED}`).all(map),
      ];
      try {
        points.push(...prepare(`
          select m.position_x as x, m.position_y as y, m.position_z as z
          from creature_movement m join creature c on c.guid = m.id
          where c.map = ? and c.patch_min <= ${P} and ${P} <= c.patch_max
        `).all(map));
      } catch {
        // A dump without patrol paths still has its spawns.
      }
      return points;
    },
    creatureSpawn: (entry, map) => prepare(`select position_x as x, position_y as y, position_z as z from creature where id = ? and map = ? and ${SPAWNED} order by guid limit 1`).get(entry, map),
    objectSpawn: (entry, map) => prepare(`select position_x as x, position_y as y, position_z as z from gameobject where id = ? and map = ? and ${SPAWNED} order by guid limit 1`).get(entry, map),
```

- [ ] **Step 5: Implement map, pins and models (instance.mjs)**

Import `import { buildMap, pinFor } from './map.mjs';`. After `claimedObjects` is declared, add:

```js
  const map = buildMap(db.mapPoints(def.map));
```

Inside the boss loop, after the creatures and chests are gathered (before `const entries = ...`), track the first model and position:

```js
    // The portrait: the first of the boss's creatures that has a model.
    const modelled = creatures.find((c) => c.display_id1 > 0);
    // The pin: where the boss stands, or its chest for a chest-only boss. A
    // boss a script summons has no spawn, and no pin.
    const spawn = creatures.map((c) => db.creatureSpawn(c.entry, def.map)).find(Boolean)
      ?? chestsUsed.map((o) => db.objectSpawn(o.entry, def.map)).find(Boolean);
```

where `chestsUsed` collects the chests the loop claims (declare `const chestsUsed = [];` before the objects loop and `chestsUsed.push(chest);` inside it). Then extend `out`:

```js
    if (modelled) out.display = modelled.display_id1;
    const pin = pinFor(map, spawn);
    if (pin) out.pin = pin;
```

In the returned instance add `map: map ? { cols: map.cols, rows: map.rows, cells: map.cells } : undefined,`.

- [ ] **Step 6: Implement the Lua output (lua.mjs)**

After the `levels` line, write the map when present:

```js
  if (instance.map) {
    lines.push(`    map = { cols = ${instance.map.cols}, rows = ${instance.map.rows}, cells = {`);
    for (let i = 0; i < instance.map.cells.length; i += 20) {
      lines.push(`        ${instance.map.cells.slice(i, i + 20).join(', ')},`);
    }
    lines.push('    } },');
  }
```

After a boss's `wing` line:

```js
    if (boss.display) lines.push(`            display = ${boss.display},`);
    if (boss.pin) lines.push(`            pin = { ${boss.pin.x}, ${boss.pin.y} },`);
```

- [ ] **Step 7: Run the tests, then rebuild the data**

Run: `node --no-warnings --test "BossLoot/tools/test/*.test.mjs"` — Expected: PASS.
Run: `node --no-warnings BossLoot/tools/build-data.mjs <mangos.sqlite>` — Expected: 26 instances, exit 0. Spot-check that `Data/BlackrockDepths.lua` has a `map` with several hundred cells and that Emperor Dagran Thaurissan has `display = 8807` and a `pin`.

- [ ] **Step 8: Commit**

```bash
git add BossLoot/tools BossLoot/Data BossLoot/BossLoot.toc
git commit -m "BossLoot: maps, boss pins and boss models in the data"
```

---

### Task 3: Grids and the "more below" line in List

**Files:**
- Modify: `BossLoot/List.lua`
- Test: `BossLoot/tests/list_spec.lua` (append)

**Interfaces:**
- Produces: `options.columns` (default 1) and `options.columnWidth` (default `options.width`); rows are laid out left to right, top to bottom; `List.Scroll(list, lines)` moves by whole lines; `list.more` is a FontString under the list reading `N more` (with an arrow) when entries are below, hidden otherwise.

- [ ] **Step 1: Write the failing tests**

```lua
describe("a list laid out as a grid", function()
    local function grid(ns, env)
        return ns.List.Create(env.UIParent, {
            width = 200, columnWidth = 100, columns = 2, rowHeight = 20, rows = 2,
            createRow = ns.List.TextRow(function() end), renderRow = ns.List.RenderText,
        })
    end

    it("fills rows left to right, then top to bottom", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = grid(ns, env)
        assertEqual(4, #list.rows)
        local _, _, _, x2, y2 = list.rows[2]:GetPoint(1)
        local _, _, _, x3, y3 = list.rows[3]:GetPoint(1)
        assertEqual(100, x2); assertEqual(0, y2)
        assertEqual(0, x3); assertEqual(-20, y3)
    end)

    it("scrolls a whole line at a time", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = grid(ns, env)
        ns.List.SetEntries(list, entries(7))
        ns.List.Scroll(list, 1)
        assertEqual(2, list.offset)
        assertEqual("Entry 3", list.rows[1].text:GetText())
        ns.List.Scroll(list, 5)
        assertEqual(4, list.offset, "four lines of entries, two shown")
    end)
end)

describe("the more-below line", function()
    it("says how many entries are below the visible rows", function()
        local ns, env = helpers.loadAddon({ "BossLoot.lua", "List.lua" })
        local list = textList(ns, env, 3)
        ns.List.SetEntries(list, entries(10))
        assertTrue(list.more:IsShown())
        assertMatch("7 more", list.more:GetText())
        ns.List.Scroll(list, 100)
        assertFalse(list.more:IsShown())
    end)
end)
```

- [ ] **Step 2: Run to verify they fail**

Run: `.\run-tests.ps1 BossLoot` — Expected: FAIL (4 rows expected, no `list.more`).

- [ ] **Step 3: Implement**

Replace `List.Render`, `List.Scroll` and `List.Create` with:

```lua
local MORE_ARROW = "|TInterface\\Buttons\\Arrow-Down-Up:12:12|t "

local function columns(list)
    return list.options.columns or 1
end

function List.Render(list)
    for index, row in ipairs(list.rows) do
        local entry = list.entries[index + list.offset]
        if entry then
            list.options.renderRow(row, entry)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end

    local below = #list.entries - list.offset - #list.rows
    if below > 0 then
        list.more:SetText(MORE_ARROW .. below .. " more")
        list.more:Show()
    else
        list.more:Hide()
    end
end

--- Move by whole lines; a line is one row per column.
function List.Scroll(list, lines)
    local perLine = columns(list)
    local totalLines = math.ceil(#list.entries / perLine)
    local maxOffset = math.max(0, totalLines - list.options.rows) * perLine
    list.offset = math.min(maxOffset, math.max(0, list.offset + lines * perLine))
    List.Render(list)
end

function List.Create(parent, options)
    local list = CreateFrame("Frame", nil, parent)
    local perLine = options.columns or 1
    local columnWidth = options.columnWidth or options.width
    list:SetSize(options.width, options.rowHeight * options.rows)
    list.options = options
    list.rows = {}
    list.entries = {}
    list.offset = 0

    for index = 1, options.rows * perLine do
        local column = (index - 1) % perLine
        local line = math.floor((index - 1) / perLine)
        local row = options.createRow(list, index)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", column * columnWidth, -line * options.rowHeight)
        row:Hide()
        list.rows[index] = row
    end

    list.more = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    list.more:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -2)
    list.more:Hide()

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        List.Scroll(self, -delta * WHEEL_STEP)
    end)

    return list
end
```

Keep `WHEEL_STEP = 3` (now lines). In `List.TextRow`, size rows with `list.options.columnWidth or list.options.width`. In `LootRow.Create`, size the row with `list.options.columnWidth or list.options.width`.

- [ ] **Step 4: Run to verify they pass** — `.\run-tests.ps1 BossLoot`, Expected: PASS (existing list specs unchanged: one column behaves as before).

- [ ] **Step 5: Commit**

```bash
git add BossLoot/List.lua BossLoot/LootRow.lua BossLoot/tests/list_spec.lua
git commit -m "BossLoot: lists as grids, and a line saying how many more are below"
```

---

### Task 4: Portraits and models

**Files:**
- Create: `BossLoot/Portrait.lua`
- Modify: `BossLoot/BossLoot.toc` (add `Portrait.lua` and `MapView.lua` after `LootRow.lua`), `BossLoot/tests/helpers.lua` (same order in `M.FILES`), `BossLoot/tests/wow_stub.lua`
- Test: `BossLoot/tests/portrait_spec.lua`

**Interfaces:**
- Produces: `ns.Portrait.ICONS = { trash, objects, unknown }`; `ns.Portrait.Set(texture, display, fallbackIcon) -> "portrait" | "icon"`; `ns.Portrait.SetModel(model, display) -> boolean`.

- [ ] **Step 1: Stub additions** (in `wow_stub.lua`)

In `makeWidget`: `SetFacing(v) self.facing = v end`, `SetDisplayInfo(id) self.display = id end` (raises if `env.__badDisplay == id`), `SetNormalFontObject(f) self.normalFont = f end`, `SetFontObject(f) self.fontObject = f end`. In `newEnv`:

```lua
    env.__portraits = true
    function env.SetPortraitTextureFromCreatureDisplayID(texture, display)
        if display == env.__badDisplay then error("bad display") end
        texture.portraitDisplay = display
    end
```

and let `SetDisplayInfo` raise the same way. A test removes the portrait function by setting it to nil.

- [ ] **Step 2: Write the failing spec**

```lua
-- BossLoot/tests/portrait_spec.lua
local helpers = require("helpers")
local FILES = { "BossLoot.lua", "Portrait.lua" }

describe("a boss portrait", function()
    it("is drawn from the boss's model", function()
        local ns, env = helpers.loadAddon(FILES)
        local texture = env.UIParent:CreateTexture()
        assertEqual("portrait", ns.Portrait.Set(texture, 8807))
        assertEqual(8807, texture.portraitDisplay)
    end)

    it("falls back to an icon without a model", function()
        local ns, env = helpers.loadAddon(FILES)
        local texture = env.UIParent:CreateTexture()
        assertEqual("icon", ns.Portrait.Set(texture, nil, "Interface\\Icons\\INV_Box_02"))
        assertEqual("Interface\\Icons\\INV_Box_02", texture:GetTexture())
    end)

    it("falls back to the skull on a client without portraits", function()
        local ns, env = helpers.loadAddon(FILES)
        env.SetPortraitTextureFromCreatureDisplayID = nil
        local texture = env.UIParent:CreateTexture()
        assertEqual("icon", ns.Portrait.Set(texture, 8807))
        assertEqual(ns.Portrait.ICONS.unknown, texture:GetTexture())
    end)

    it("falls back when the client refuses the model", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__badDisplay = 666
        local texture = env.UIParent:CreateTexture()
        assertEqual("icon", ns.Portrait.Set(texture, 666))
    end)
end)

describe("a boss model", function()
    it("shows the boss's model", function()
        local ns, env = helpers.loadAddon(FILES)
        local model = env.CreateFrame("PlayerModel")
        assertTrue(ns.Portrait.SetModel(model, 8807))
        assertEqual(8807, model.display)
    end)

    it("says it could not, without a model id or when the client refuses", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__badDisplay = 666
        local model = env.CreateFrame("PlayerModel")
        assertFalse(ns.Portrait.SetModel(model, nil))
        assertFalse(ns.Portrait.SetModel(model, 666))
    end)
end)
```

- [ ] **Step 3: Run to verify it fails** — Expected: `ns.Portrait` nil.

- [ ] **Step 4: Implement**

```lua
-- BossLoot/Portrait.lua
local addonName, ns = ...

-- Boss pictures, drawn by the client from the model IDs in the data: a round
-- portrait for the boss list, a 3D model for the boss page. Both calls are
-- guarded -- an ID the client does not know, or a value it keeps secret,
-- falls back to an icon rather than an error.

local Portrait = {}
ns.Portrait = Portrait

Portrait.ICONS = {
    trash = "Interface\\Icons\\INV_Misc_Bag_10",
    objects = "Interface\\Icons\\INV_Box_02",
    unknown = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
}

--- A round portrait of the creature with this model on `texture`, or the
-- fallback icon. Returns which it drew.
function Portrait.Set(texture, display, fallbackIcon)
    if display and SetPortraitTextureFromCreatureDisplayID then
        if pcall(SetPortraitTextureFromCreatureDisplayID, texture, display) then
            return "portrait"
        end
    end
    texture:SetTexture(fallbackIcon or Portrait.ICONS.unknown)
    return "icon"
end

--- The creature's 3D model on a PlayerModel frame. False when there is no
-- model to show, so the caller can show a portrait instead.
function Portrait.SetModel(model, display)
    if not (display and model and model.SetDisplayInfo) then
        return false
    end
    return pcall(model.SetDisplayInfo, model, display) and true or false
end
```

- [ ] **Step 5: Run to verify it passes; commit**

```bash
git add BossLoot/Portrait.lua BossLoot/BossLoot.toc BossLoot/tests
git commit -m "BossLoot: boss portraits and models, with fallbacks"
```

---

### Task 5: The map view

**Files:**
- Create: `BossLoot/MapView.lua`
- Test: `BossLoot/tests/mapview_spec.lua`

**Interfaces:**
- Produces: `ns.MapView.Layout(map, width, height) -> scale, offsetX, offsetY`; `ns.MapView.Create(parent, width, height, options) -> view` where `options = { pinSize, onPinClick(bossIndex) }`; `ns.MapView.Show(view, instance, selectedBossIndex|nil)`; `view.cells` (textures, pooled), `view.pins` (buttons, pooled; `pin.boss`, `pin.text`, `pin.selected`).

- [ ] **Step 1: Write the failing spec**

```lua
-- BossLoot/tests/mapview_spec.lua
local helpers = require("helpers")
local FILES = { "BossLoot.lua", "MapView.lua" }

local instance = {
    key = "T", name = "T", kind = "dungeon", levels = { 1, 2 },
    map = { cols = 4, rows = 2, cells = { 0 * 4 + 0, 7 * 4 + 3 } },
    bosses = {
        { name = "A", pin = { 0.25, 0.5 }, loot = {} },
        { name = "Summoned", loot = {} },
        { name = "C", pin = { 1, 1 }, loot = {} },
    },
    notable = { trash = {}, objects = {} },
}

local function shown(list)
    local n = 0
    for _, item in ipairs(list) do if item:IsShown() then n = n + 1 end end
    return n
end

describe("the map view", function()
    it("scales a map to fit and centres it", function()
        local ns = helpers.loadAddon(FILES)
        local scale, ox, oy = ns.MapView.Layout({ cols = 4, rows = 2 }, 200, 200)
        assertEqual(50, scale); assertEqual(0, ox); assertEqual(50, oy)
    end)

    it("draws a square per filled cell, where the cell is", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        assertEqual(2, shown(view.cells))
        local _, _, _, x, y = view.cells[2]:GetPoint(1)
        assertEqual(175, x, "column 3 of 4, centred")
        assertEqual(-125, y, "row 1 of 2, below the top margin")
    end)

    it("colours higher cells lighter", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        assertTrue(view.cells[2].colorTexture[3] > view.cells[1].colorTexture[3])
    end)

    it("pins every boss that has a place, numbered by its place in the list", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance, 3)
        assertEqual(2, shown(view.pins))
        assertEqual("1", view.pins[1].text:GetText())
        assertEqual("3", view.pins[2].text:GetText())
        assertTrue(view.pins[2].selected)
        assertFalse(view.pins[1].selected)
    end)

    it("hands a pin click to its owner", function()
        local ns, env = helpers.loadAddon(FILES)
        local clicked
        local view = ns.MapView.Create(env.UIParent, 200, 200, { onPinClick = function(boss) clicked = boss end })
        ns.MapView.Show(view, instance)
        view.pins[2].scripts.OnClick(view.pins[2], "LeftButton")
        assertEqual(3, clicked)
    end)

    it("reuses its textures from one instance to the next", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        ns.MapView.Show(view, instance)
        assertEqual(2, #view.cells)
    end)

    it("shows nothing, and does not fail, for an instance without a map", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        ns.MapView.Show(view, { bosses = {}, notable = {} })
        assertEqual(0, shown(view.cells))
        assertEqual(0, shown(view.pins))
        ns.MapView.Show(view, nil)
    end)
end)
```

- [ ] **Step 2: Run to verify it fails** — Expected: `ns.MapView` nil.

- [ ] **Step 3: Implement**

```lua
-- BossLoot/MapView.lua
local addonName, ns = ...

-- Draws an instance's generated map into a frame of any size: a small square
-- per filled cell, lighter the higher it lies, and a numbered pin per boss
-- that has a place. The same view serves the header's inset and the full map.

local MapView = {}
ns.MapView = MapView

local BANDS = 4
-- Cells are drawn larger than their spacing so neighbours merge into areas.
local SPREAD = 1.5
local BAND_COLOURS = {
    { 0.20, 0.25, 0.40 },
    { 0.27, 0.34, 0.54 },
    { 0.36, 0.45, 0.68 },
    { 0.50, 0.60, 0.84 },
}
local PIN = "Interface\\COMMON\\Indicator-Red"
local PIN_SELECTED = "Interface\\COMMON\\Indicator-Yellow"

--- How a map of cols by rows cells fits a width by height view: the size of
-- a cell, and the margins that centre the map.
function MapView.Layout(map, width, height)
    local scale = math.min(width / map.cols, height / map.rows)
    return scale, (width - map.cols * scale) / 2, (height - map.rows * scale) / 2
end

function MapView.Create(parent, width, height, options)
    options = options or {}
    local view = CreateFrame("Button", nil, parent)
    view:SetSize(width, height)
    view.options = options
    view.cells = {}
    view.pins = {}

    view.background = view:CreateTexture(nil, "BACKGROUND")
    view.background:SetAllPoints()
    view.background:SetColorTexture(0.02, 0.02, 0.03, 1)

    return view
end

local function pin(view, index)
    local button = view.pins[index]
    if button then
        return button
    end

    local size = view.options.pinSize or 16
    button = CreateFrame("Button", nil, view)
    button:SetSize(size, size)
    button:SetFrameLevel(view:GetFrameLevel() + 2)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)

    if view.options.onPinClick then
        button:SetScript("OnClick", function(self)
            view.options.onPinClick(self.boss)
        end)
    else
        -- The inset: a click on a pin is a click on the map, which opens it.
        button:EnableMouse(false)
    end

    view.pins[index] = button
    return button
end

function MapView.Show(view, instance, selected)
    for _, cell in ipairs(view.cells) do
        cell:Hide()
    end
    for _, button in ipairs(view.pins) do
        button:Hide()
    end

    local map = instance and instance.map
    if not map then
        return
    end

    local scale, offsetX, offsetY = MapView.Layout(map, view:GetWidth(), view:GetHeight())
    local size = math.max(1, scale * SPREAD)

    for index, value in ipairs(map.cells) do
        local band = value % BANDS
        local cellIndex = (value - band) / BANDS
        local column = cellIndex % map.cols
        local row = (cellIndex - column) / map.cols

        local cell = view.cells[index]
        if not cell then
            cell = view:CreateTexture(nil, "ARTWORK")
            view.cells[index] = cell
        end
        cell:ClearAllPoints()
        cell:SetSize(size, size)
        cell:SetPoint("CENTER", view, "TOPLEFT", offsetX + (column + 0.5) * scale, -(offsetY + (row + 0.5) * scale))
        local colour = BAND_COLOURS[band + 1]
        cell:SetColorTexture(colour[1], colour[2], colour[3], 0.9)
        cell:Show()
    end

    local count = 0
    for bossIndex, boss in ipairs(instance.bosses or {}) do
        if boss.pin then
            count = count + 1
            local button = pin(view, count)
            button.boss = bossIndex
            button.selected = bossIndex == selected
            button.text:SetText(tostring(bossIndex))
            button.icon:SetTexture(button.selected and PIN_SELECTED or PIN)
            button:ClearAllPoints()
            button:SetPoint("CENTER", view, "TOPLEFT",
                offsetX + boss.pin[1] * map.cols * scale, -(offsetY + boss.pin[2] * map.rows * scale))
            button:Show()
        end
    end
end
```

- [ ] **Step 4: Run to verify it passes; commit**

```bash
git add BossLoot/MapView.lua BossLoot/tests/mapview_spec.lua
git commit -m "BossLoot: draw an instance map with numbered boss pins"
```

---

### Task 6: The new window

**Files:**
- Modify: `BossLoot/Window.lua` (rebuild the frame and drawing; keep the pure entry builders and selection)
- Test: `BossLoot/tests/window_spec.lua` (keep existing specs; append new)

**Interfaces:**
- Consumes: `ns.List` (grid options, `list.more`), `ns.LootRow`, `ns.Portrait.Set/SetModel/ICONS`, `ns.MapView.Create/Show`.
- Produces (unchanged): `Window.InstanceEntries/BossEntries/LootEntries/Current/SelectKind/SelectInstance/SelectBoss/SelectItem/HideInstance/Refresh/Open/Toggle/Frame`. New: `Window.OpenMap()`, `Window.CloseMap()`. Boss entries gain `number` (boss index) and `display`; notable entries gain `icon`. Frame fields: `background`, `search`, `searchHint`, `tabs`, `instances`, `bosses` (portrait rows: `row.portrait`, `row.number`), `header` (`model`, `portrait`, `title`, `subtitle`), `inset` (a MapView, clickable), `fullMap` (frame with `view` and `close`), `loot` (2-column grid), `empty`.

- [ ] **Step 1: Write the failing specs** (append to `window_spec.lua`)

```lua
describe("the redesigned window", function()
    it("is opaque", function()
        local ns = opened()
        assertEqual(1, ns.Window.Frame().background.colorTexture[4])
    end)

    it("numbers each boss and gives it a portrait", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.bosses[1].display = 8807
        helpers.login(ns, env)
        ns.Window.Open()
        local row = ns.Window.Frame().bosses.rows[2]
        assertEqual("First Boss", row.text:GetText())
        assertEqual("1", row.number:GetText())
        assertEqual(8807, row.portrait.portraitDisplay)
    end)

    it("gives the notable lists a bag and a chest", function()
        local ns = opened()
        local entries = ns.Window.BossEntries(ns.instanceByKey.Depths, 1)
        assertEqual(ns.Portrait.ICONS.trash, entries[#entries].icon)
    end)

    it("heads the page with the boss's model, name and instance", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.bosses[1].display = 8807
        helpers.login(ns, env)
        ns.Window.Open()
        local header = ns.Window.Frame().header
        assertEqual("First Boss", header.title:GetText())
        assertEqual("Test Depths, East", header.subtitle:GetText())
        assertEqual(8807, header.model.display)
        assertTrue(header.model:IsShown())
        assertFalse(header.portrait:IsShown())
    end)

    it("falls back to an icon in the header for a boss without a model", function()
        local ns = opened()
        local header = ns.Window.Frame().header
        assertFalse(header.model:IsShown())
        assertTrue(header.portrait:IsShown())
    end)

    it("heads a notable list with its icon and name", function()
        local ns = opened()
        ns.Window.SelectBoss("trash")
        local header = ns.Window.Frame().header
        assertEqual("From trash", header.title:GetText())
        assertEqual(ns.Portrait.ICONS.trash, header.portrait:GetTexture())
    end)

    it("shows the instance map in the header, the selected boss's pin lit", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.map = { cols = 2, rows = 2, cells = { 0, 12 } }
        ns.instanceByKey.Depths.bosses[2].pin = { 0.5, 0.5 }
        helpers.login(ns, env)
        ns.Window.Open()
        ns.Window.SelectBoss(2)
        local inset = ns.Window.Frame().inset
        assertTrue(inset.pins[1]:IsShown())
        assertTrue(inset.pins[1].selected)
    end)

    it("opens the full map from the inset, and a pin there picks that boss", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.map = { cols = 2, rows = 2, cells = { 0, 12 } }
        ns.instanceByKey.Depths.bosses[3].pin = { 0.5, 0.5 }
        helpers.login(ns, env)
        ns.Window.Open()
        local frame = ns.Window.Frame()
        frame.inset.scripts.OnClick(frame.inset, "LeftButton")
        assertTrue(frame.fullMap:IsShown())
        local pin = frame.fullMap.view.pins[1]
        pin.scripts.OnClick(pin, "LeftButton")
        assertEqual(3, ns.db.view.boss)
        assertFalse(frame.fullMap:IsShown())
    end)

    it("closes the full map when the instance changes", function()
        local ns = opened()
        ns.Window.OpenMap()
        ns.Window.SelectInstance("Spire")
        assertFalse(ns.Window.Frame().fullMap:IsShown())
    end)

    it("lays the loot out in two columns", function()
        local ns = opened()
        assertEqual(2, ns.Window.Frame().loot.options.columns)
    end)

    it("shows placeholder text in an empty search box", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        assertTrue(frame.searchHint:IsShown())
        frame.search:SetText("sp")
        assertFalse(frame.searchHint:IsShown())
    end)

    it("shows the normal list for a single letter", function()
        local ns = helpers.loggedIn()
        local entries = ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "z")
        assertEqual(2, #entries)
    end)

    it("gives a plain fallback button a font, so its label shows", function()
        local ns, env = helpers.loadAddon(nil, function(env) env.__missingTemplates.UIPanelButtonTemplate = true end)
        helpers.sampleInstances(ns)
        helpers.login(ns, env)
        ns.Window.Open()
        assertEqual("GameFontNormal", ns.Window.Frame().tabs.dungeon.normalFont)
    end)
end)
```

- [ ] **Step 2: Run to verify they fail** — Expected: FAIL (no `background`, `header`, `inset`, `searchHint`, etc.).

- [ ] **Step 3: Rebuild the window**

Keep from the current `Window.lua`: defaults, `instanceEntry`, `itemName`, `placeEntry`, `NOTABLE_NAMES`, `Window.InstanceEntries` (change its search test to `#trimmed >= 2`, where `trimmed = searchText and searchText:match("^%s*(.-)%s*$") or ""`), `Window.LootEntries`, `lootSource`, `validSelection`, `Window.Current`, `preload`, the `Select*` functions (make `SelectInstance` and `SelectKind` call `Window.CloseMap()`), `HideInstance`, `onInstanceClick`, `onBossClick`, `savePosition`, `Toggle`/`Open`/`Frame`, `DefaultCommand`, `unhide`, and the item-arrival redraw.

Change `Window.BossEntries` so boss entries carry `number = index, display = boss.display`, and the two notable entries carry `icon = ns.Portrait.ICONS.trash` / `ns.Portrait.ICONS.objects`.

Replace the layout constants, `createFrame`, `createTab`, `create` and `Window.Refresh` with the following (full code):

```lua
local WIDTH = 860
local HEIGHT = 520
local PADDING = 12
local TITLE_HEIGHT = 28
local TOP = PADDING + TITLE_HEIGHT
local GAP = 8
local RAIL_WIDTH = 170
local BOSS_WIDTH = 230
local PAGE_LEFT = PADDING + RAIL_WIDTH + GAP + BOSS_WIDTH + GAP
local PAGE_WIDTH = WIDTH - PAGE_LEFT - PADDING
local HEADER_HEIGHT = 96
local SEARCH_HEIGHT = 20
local TAB_HEIGHT = 22
local RAIL_ROW = 18
local BOSS_ROW = 34
local LOOT_ROW = ns.LootRow.HEIGHT + 2
local INSET_WIDTH, INSET_HEIGHT = 150, 84
local MORE_HEIGHT = 16

-- A template this client lacks raises rather than returning nil, so every
-- templated frame is asked for through here. The plain fallback gets a font,
-- or its label would be blank and an edit box would refuse text.
local function createFrame(kind, name, parent, template)
    local ok, created = pcall(CreateFrame, kind, name, parent, template)
    if ok and created then
        return created
    end
    created = CreateFrame(kind, name, parent)
    if kind == "Button" and created.SetNormalFontObject then
        created:SetNormalFontObject("GameFontNormal")
    elseif kind == "EditBox" and created.SetFontObject then
        created:SetFontObject("ChatFontNormal")
    end
    return created
end

local function panel(parent, left, top, width, height, shade)
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
    texture:SetSize(width, height)
    texture:SetColorTexture(shade, shade * 0.8, shade * 0.6, 1)
    return texture
end

local function createTab(parent, kind, label, x)
    local tab = createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    tab:SetSize(80, TAB_HEIGHT)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(TOP + SEARCH_HEIGHT + 6))
    tab:SetText(label)
    tab:SetScript("OnClick", function()
        Window.SelectKind(kind)
    end)
    return tab
end

-- A boss row: portrait, number, name. Headings keep just their text.
local function bossRow(list)
    local row = ns.List.TextRow(onBossClick)(list)
    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(BOSS_ROW - 4, BOSS_ROW - 4)
    row.portrait:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.number = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.number:SetPoint("LEFT", row.portrait, "RIGHT", 4, 0)
    row.number:SetWidth(18)
    row.number:SetJustifyH("RIGHT")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.number, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    return row
end

local function renderBoss(row, entry)
    ns.List.RenderText(row, entry)
    if entry.kind == "heading" then
        row.portrait:Hide()
        row.number:SetText("")
        return
    end
    if entry.icon then
        row.portrait:SetTexture(entry.icon)
    else
        ns.Portrait.Set(row.portrait, entry.display)
    end
    row.portrait:Show()
    row.number:SetText(entry.number and tostring(entry.number) or "")
end

local function header(parent)
    local top = TOP
    local h = CreateFrame("Frame", nil, parent)
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", PAGE_LEFT, -top)
    h:SetSize(PAGE_WIDTH, HEADER_HEIGHT)

    h.model = CreateFrame("PlayerModel", nil, h)
    h.model:SetSize(84, 84)
    h.model:SetPoint("LEFT", h, "LEFT", 4, 0)
    h.model.facing = 0
    h.model:SetScript("OnUpdate", function(self, elapsed)
        self.facing = (self.facing + (elapsed or 0) * 0.4) % (math.pi * 2)
        if self.SetFacing then
            self:SetFacing(self.facing)
        end
    end)

    h.portrait = h:CreateTexture(nil, "ARTWORK")
    h.portrait:SetSize(64, 64)
    h.portrait:SetPoint("LEFT", h, "LEFT", 14, 0)

    h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.title:SetPoint("TOPLEFT", h, "TOPLEFT", 100, -22)
    h.title:SetPoint("RIGHT", h, "RIGHT", -(INSET_WIDTH + 12), 0)
    h.title:SetJustifyH("LEFT")

    h.subtitle = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.subtitle:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -4)
    h.subtitle:SetJustifyH("LEFT")

    return h
end

local function create()
    frame = createFrame("Frame", "BossLootFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", savePosition)

    local saved = ns.db.window
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)

    -- Opaque, whatever the backdrop does: the dialog background is
    -- translucent by design, and may not load at all.
    frame.background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.background:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    frame.background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    frame.background:SetColorTexture(0.06, 0.045, 0.03, 1)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    local listHeight = HEIGHT - TOP - PADDING
    panel(frame, PADDING, TOP, RAIL_WIDTH, listHeight, 0.035)
    panel(frame, PADDING + RAIL_WIDTH + GAP, TOP, BOSS_WIDTH, listHeight, 0.05)
    panel(frame, PAGE_LEFT, TOP, PAGE_WIDTH, HEADER_HEIGHT, 0.12)

    table.insert(UISpecialFrames, "BossLootFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 6, -PADDING - 4)
    title:SetText("BossLoot")

    local close = createFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    if not close.GetNormalTexture or not close:GetNormalTexture() then
        close:SetText("X")
    end
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- The rail: search, tabs, instances.
    local search = createFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(RAIL_WIDTH - 14, SEARCH_HEIGHT)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 8, -TOP - 2)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    frame.searchHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.searchHint:SetPoint("LEFT", search, "LEFT", 4, 0)
    frame.searchHint:SetText("Search...")
    search:SetScript("OnTextChanged", function(self)
        frame.searchHint:SetShown(self:GetText() == "")
        Window.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    frame.search = search

    frame.tabs = {
        dungeon = createTab(frame, "dungeon", "Dungeons", PADDING + 4),
        raid = createTab(frame, "raid", "Raids", PADDING + 86),
    }

    local railTop = TOP + SEARCH_HEIGHT + TAB_HEIGHT + 12
    frame.instances = ns.List.Create(frame, {
        width = RAIL_WIDTH, rowHeight = RAIL_ROW,
        rows = math.floor((HEIGHT - railTop - PADDING) / RAIL_ROW),
        createRow = ns.List.TextRow(onInstanceClick), renderRow = ns.List.RenderText,
    })
    frame.instances:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -railTop)

    -- The boss list.
    frame.bosses = ns.List.Create(frame, {
        width = BOSS_WIDTH, rowHeight = BOSS_ROW,
        rows = math.floor((listHeight - MORE_HEIGHT) / BOSS_ROW),
        createRow = bossRow, renderRow = renderBoss,
    })
    frame.bosses:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + RAIL_WIDTH + GAP, -TOP)

    -- The boss page: header with model and map inset, then the loot grid.
    frame.header = header(frame)

    frame.inset = ns.MapView.Create(frame.header, INSET_WIDTH, INSET_HEIGHT)
    frame.inset:SetPoint("RIGHT", frame.header, "RIGHT", -6, 0)
    frame.inset:SetScript("OnClick", function()
        Window.OpenMap()
    end)

    local lootTop = TOP + HEADER_HEIGHT + 6
    frame.loot = ns.List.Create(frame, {
        width = PAGE_WIDTH, columnWidth = PAGE_WIDTH / 2, columns = 2, rowHeight = LOOT_ROW,
        rows = math.floor((HEIGHT - lootTop - PADDING - MORE_HEIGHT) / LOOT_ROW),
        createRow = ns.LootRow.Create, renderRow = ns.LootRow.Render,
    })
    frame.loot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_LEFT, -lootTop)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_LEFT + 6, -lootTop - 6)
    frame.empty:SetText(EMPTY_TEXT)
    frame.empty:Hide()

    -- The full map, over the boss page.
    local fullHeight = HEIGHT - TOP - PADDING
    frame.fullMap = CreateFrame("Frame", nil, frame)
    frame.fullMap:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_LEFT, -TOP)
    frame.fullMap:SetSize(PAGE_WIDTH, fullHeight)
    frame.fullMap:SetFrameLevel(frame:GetFrameLevel() + 20)
    frame.fullMap.view = ns.MapView.Create(frame.fullMap, PAGE_WIDTH, fullHeight, {
        pinSize = 20,
        onPinClick = function(bossIndex)
            Window.SelectBoss(bossIndex)
            Window.CloseMap()
        end,
    })
    frame.fullMap.view:SetPoint("TOPLEFT", frame.fullMap, "TOPLEFT", 0, 0)
    frame.fullMap.close = createFrame("Button", nil, frame.fullMap, "UIPanelCloseButton")
    frame.fullMap.close:SetPoint("TOPRIGHT", frame.fullMap, "TOPRIGHT", 0, 0)
    frame.fullMap.close:SetScript("OnClick", function()
        Window.CloseMap()
    end)
    frame.fullMap:Hide()

    frame:SetScript("OnShow", function()
        local instance = Window.Current()
        if instance then
            preload(instance)
        end
        Window.Refresh()
    end)

    frame:Hide()
end

function Window.OpenMap()
    if not frame then
        return
    end
    frame.fullMap:Show()
    Window.Refresh()
end

function Window.CloseMap()
    if frame then
        frame.fullMap:Hide()
    end
end

local function drawHeader(instance, selection)
    local h = frame.header
    h.model:Hide()
    h.portrait:Hide()

    if not instance then
        h.title:SetText("")
        h.subtitle:SetText("")
        return
    end

    if type(selection) == "number" then
        local boss = instance.bosses[selection]
        h.title:SetText(boss.name)
        h.subtitle:SetText(boss.wing and (instance.name .. ", " .. boss.wing) or instance.name)
        if ns.Portrait.SetModel(h.model, boss.display) then
            h.model:Show()
        else
            ns.Portrait.Set(h.portrait, boss.display)
            h.portrait:Show()
        end
    else
        h.title:SetText(NOTABLE_NAMES[selection])
        h.subtitle:SetText(instance.name)
        h.portrait:SetTexture(ns.Portrait.ICONS[selection])
        h.portrait:Show()
    end
end

function Window.Refresh()
    if not frame then
        return
    end

    local view = ns.db.view
    local instance, selection = Window.Current()

    ns.List.SetEntries(frame.instances, Window.InstanceEntries(view, frame.search:GetText()), true)
    ns.List.SetEntries(frame.bosses, Window.BossEntries(instance, selection), true)

    local loot = Window.LootEntries(instance, selection)
    local key = tostring(view.instance) .. ":" .. tostring(selection)
    ns.List.SetEntries(frame.loot, loot, key == lastSelection)
    lastSelection = key
    frame.empty:SetShown(instance ~= nil and #loot == 0)

    drawHeader(instance, selection)
    local pinned = type(selection) == "number" and selection or nil
    ns.MapView.Show(frame.inset, instance, pinned)
    if frame.fullMap:IsShown() then
        ns.MapView.Show(frame.fullMap.view, instance, pinned)
    end

    for kind, tab in pairs(frame.tabs) do
        if kind == view.kind then
            tab:LockHighlight()
        else
            tab:UnlockHighlight()
        end
    end
end
```

(`EMPTY_TEXT`, `frame` and `lastSelection` stay declared at the top of the file as now. `bossRow` and `renderBoss` must be defined after `onBossClick`.)

- [ ] **Step 4: Run to verify they pass** — `.\run-tests.ps1 BossLoot`, Expected: PASS, including every earlier window spec.

- [ ] **Step 5: Commit**

```bash
git add BossLoot/Window.lua BossLoot/tests/window_spec.lua BossLoot/tests/wow_stub.lua
git commit -m "BossLoot: the new window, with portraits, model, map and loot grid"
```

---

### Task 7: Data checks, README, package

**Files:**
- Modify: `BossLoot/tests/data_spec.lua` (append), `BossLoot/README.md`

- [ ] **Step 1: Append data checks, watch them run**

```lua
    it("keeps every map cell and pin inside its map", function()
        for _, instance in ipairs(ns.instances) do
            if instance.map then
                local limit = instance.map.cols * instance.map.rows * 4
                for _, value in ipairs(instance.map.cells) do
                    assertTrue(value >= 0 and value < limit, instance.key .. " cell " .. value)
                end
            end
            for _, boss in ipairs(instance.bosses) do
                if boss.pin then
                    assertTrue(boss.pin[1] >= 0 and boss.pin[1] <= 1 and boss.pin[2] >= 0 and boss.pin[2] <= 1,
                        instance.key .. " " .. boss.name .. " pin")
                end
                if boss.display then
                    assertTrue(math.type(boss.display) == "integer" and boss.display > 0, boss.name .. " model")
                end
            end
        end
    end)

    it("has a map for every instance", function()
        for _, instance in ipairs(ns.instances) do
            assertTrue(instance.map ~= nil and #instance.map.cells > 0, instance.key .. " map")
        end
    end)
```

Run: `.\run-tests.ps1 BossLoot` — Expected: PASS (the data came from Task 2's rebuild).

- [ ] **Step 2: README**

Replace the window description paragraph of `BossLoot/README.md` with:

```markdown
Open it with `/bl` or the minimap button. On the left, the instances
(Dungeons and Raids tabs, with level ranges) and a search box. In the middle,
the bosses in kill order, each with its portrait and a number. On the right,
the boss itself: its model, and a map of the instance with every boss pinned
by number; click the map for a big one, and a pin to jump to that boss.
Under that, the loot in two columns. At the bottom of the boss list,
**Notable drops** holds the trash and chest finds.

The map is drawn from where the instance's mobs stand and walk, so it shows
rooms and corridors as a sketch rather than a picture; higher ground is
lighter. A boss that only appears when a script summons it has no pin.
```

- [ ] **Step 3: Full suite, package, install, commit**

Run: `.\run-tests.ps1` then `.\package.ps1 BossLoot -Install` — Expected: all suites PASS; package includes `Portrait.lua` and `MapView.lua`.

```bash
git add BossLoot/tests/data_spec.lua BossLoot/README.md
git commit -m "BossLoot: README for the new window, and data checks for maps"
```
