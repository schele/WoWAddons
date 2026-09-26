# BossLoot Loot Recorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record what really drops in WoW Forever (and what quests, merchants and professions offer), show recorded loot first in BossLoot's lists with the vanilla list dimmed below, list unknown instances, and bake players' recordings into releases.

**Architecture:** `Recorder.lua` listens to game events and writes into `BossLootDB.recorded`. `Recordings.lua` merges the player's own recordings with baked ones (`Data/Recorded.lua`, per recorder id) and lays them onto the instances (`boss.recorded`, `boss.recordedKills`, `instance.recordedNotable`, recorded instances). The index, the window and the loot rows read those. The build gains a saved-variables parser and writes `Data/Recorded.lua`. The instance data gains `mapID`, `npcs` and `objects`.

**Tech Stack:** WoW addon Lua (client Lua 5.1; tests on Lua 5.4 with `tests/wow_stub.lua`), Node 24 build tools (`node:test`, `node:sqlite`).

**Spec:** `docs/superpowers/specs/2026-09-26-bossloot-recorder-design.md`

## Global Constraints

- Addon code runs on the client's Lua 5.1: no `goto`, no `//`, no `table.unpack` or `unpack` in addon files. `select` is fine.
- Every client call the recorder makes is feature checked (`if GetLootSourceInfo then`), and events are registered through `pcall`, so a client missing one never errors.
- Saved variables: `BossLootDB`; new defaults through `ns.AddDefaults`.
- The instance's map id is written as `mapID` (the field `map` is already the floor plan).
- Files are CRLF in git. Before any string-matched edit, run `sed -i 's/\r$//' <file>`. Write any text containing backslashes with the Write tool (or a node script written with the Write tool), never through shell quoting.
- Lua tests, from `BossLoot/`: `lua tests/runner.lua tests/<name>_spec.lua`. Node tests, from `BossLoot/`: `node --test "tools/test/*.test.mjs"`. Whole suite, from the repo root in PowerShell: `.\run-tests.ps1 BossLoot`.
- Data rebuild, from the repo root: `node BossLoot/tools/build-data.mjs <scratchpad>/vmangos/sqlite-dump/mangos.sqlite`.
- Install, from the repo root in PowerShell: `.\package.ps1 BossLoot -Install`.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- UI text in plain English: "Classic loot", "Not seen on WoW Forever yet", counts as `3/5` for bosses and `×2` for notable items.

## Review Focus

- One loot slot from several corpses at once (area looting): each corpse counts one kill and gets the item once. Test: Task 4 "keeps each corpse apart when several are looted at once".
- Reopening a corpse after `/reload`: no second kill. Test: Task 4 "remembers corpses looted before a reload".
- A saved-variables file that is not BossLoot's, or predates the recorder: skipped with a warning, the build goes on. Test: Task 3 "skips a file without recordings, and says so".
- A recorded instance with trash but no named boss: listed, and opens on From trash. Test: Task 7 "opens a recorded instance with no named boss on its trash".
- A client missing any recorder call or event: no error, the rest recorded. Tests: Task 4 "does nothing, and does not fail, on a client without the loot calls"; Task 5 "records nothing, and does not fail, without the quest, merchant or profession calls".

---

### Task 1: The instance data carries its map id, and each boss its creatures and chests

**Files:**
- Modify: `BossLoot/tools/lib/instance.mjs` (the boss loop and the returned instance)
- Modify: `BossLoot/tools/lib/lua.mjs` (`instanceFile`)
- Test: `BossLoot/tools/test/instance.test.mjs`, `BossLoot/tools/test/lua.test.mjs`
- Regenerate: `BossLoot/Data/*.lua`

**Interfaces:**
- Produces: in the generated Lua, `mapID = <number>` on each instance; `npcs = { <entry>, ... }` on each boss with creatures; `objects = { <entry>, ... }` on each chest boss. In JS, `instance.mapID`, `boss.npcs`, `boss.objects` (arrays of numbers, left out when empty).

- [ ] **Step 1: Write the failing tests**

Append to `BossLoot/tools/test/instance.test.mjs`:

```js
test("records the instance's map id and each boss's creatures and chests", () => {
  const { db } = world();
  const withChest = { ...def, bosses: ['Boss One', { name: 'Chest Boss', objects: ['Old Chest'] }] };
  const { instance } = buildInstance(openDb(db), withChest);
  assert.equal(instance.mapID, MAP);
  assert.deepEqual(instance.bosses[0].npcs, [1]);
  assert.equal(instance.bosses[0].objects, undefined);
  assert.deepEqual(instance.bosses[1].objects, [50]);
  assert.equal(instance.bosses[1].npcs, undefined);
});
```

Append to `BossLoot/tools/test/lua.test.mjs`:

```js
test("writes the map id, and each boss's creatures and chests", () => {
  const text = instanceFile({
    key: 'Test', name: 'Test Depths', kind: 'dungeon', levels: [52, 60], mapID: 230,
    bosses: [{ name: 'Boss One', npcs: [1, 2], loot: [] }, { name: 'Chest', objects: [50], loot: [] }],
    notable: { trash: [], objects: [] },
  });
  assert.match(text, /mapID = 230,/);
  assert.match(text, /npcs = \{ 1, 2 \},/);
  assert.match(text, /objects = \{ 50 \},/);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test "tools/test/*.test.mjs"` (from `BossLoot/`)
Expected: the two new tests fail (`instance.mapID` is undefined; no `mapID =` in the text).

- [ ] **Step 3: Implement**

In `tools/lib/instance.mjs`, after `if (boss.wing) out.wing = boss.wing;`:

```js
    // Which creatures and chests are the boss, so loot recorded in game can
    // be matched to it.
    const npcs = [...new Set(creatures.map((c) => c.entry))];
    if (npcs.length) out.npcs = npcs;
    const objects = [...new Set(chestsUsed.map((o) => o.entry))];
    if (objects.length) out.objects = objects;
```

In the returned `instance` object, after `levels: def.levels,`:

```js
      mapID: def.map,
```

In `tools/lib/lua.mjs` `instanceFile`, after the `levels = { ... }` line:

```js
  if (instance.mapID) lines.push(`    mapID = ${instance.mapID},`);
```

and in the boss loop, after the `display` line:

```js
    if (boss.npcs) lines.push(`            npcs = { ${boss.npcs.join(', ')} },`);
    if (boss.objects) lines.push(`            objects = { ${boss.objects.join(', ')} },`);
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `node --test "tools/test/*.test.mjs"`
Expected: all pass.

- [ ] **Step 5: Rebuild the data and run the whole suite**

Run (repo root): `node BossLoot/tools/build-data.mjs <scratchpad>/vmangos/sqlite-dump/mangos.sqlite`
Expected: `26 instances written to Data/.`, and `grep -c "mapID" BossLoot/Data/Uldaman.lua` gives 1.
Run: `.\run-tests.ps1 BossLoot` — Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add BossLoot/tools/lib/instance.mjs BossLoot/tools/lib/lua.mjs BossLoot/tools/test/instance.test.mjs BossLoot/tools/test/lua.test.mjs BossLoot/Data
git commit -F - <<'EOF'
BossLoot: the data carries each instance's map id, and each boss's creatures and chests

So loot recorded in game can be matched to its instance and boss.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: A parser for saved-variables files

**Files:**
- Create: `BossLoot/tools/lib/savedvars.mjs`
- Test: `BossLoot/tools/test/savedvars.test.mjs`

**Interfaces:**
- Produces: `parseSavedVariables(text) -> { [name]: value }`. Lua tables become plain objects: `["key"] =` and `key =` give string keys, `[n] =` and positional items give numeric-string keys (`"1"`, `"2"`), `nil` gives `null`. Throws `Error("saved variables: <what> at <offset>")` on text it cannot read.

- [ ] **Step 1: Write the failing test**

Create `BossLoot/tools/test/savedvars.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseSavedVariables } from '../lib/savedvars.mjs';

test('reads what the game writes: nested tables, keys of each kind, comments', () => {
  const text = [
    '',
    'BossLootDB = {',
    '\t["recorded"] = {',
    '\t\t["recorder"] = "a1b2c3d4",',
    '\t\t["sources"] = {',
    '\t\t\t["npc:6910"] = {',
    '\t\t\t\t["kills"] = 5,',
    '\t\t\t\t["name"] = "Revelosh",',
    '\t\t\t\t["items"] = {',
    '\t\t\t\t\t[9387] = 2,',
    '\t\t\t\t},',
    '\t\t\t},',
    '\t\t},',
    '\t\t["seen"] = {',
    '\t\t\t"Creature-0-1-70-47-6910-A", -- [1]',
    '\t\t},',
    '\t\t["ratio"] = -0.25,',
    '\t\t["on"] = true,',
    '\t\t["off"] = false,',
    '\t\t["none"] = nil,',
    '\t},',
    '}',
    'Other = 3',
  ].join('\n');
  const vars = parseSavedVariables(text);
  const recorded = vars.BossLootDB.recorded;
  assert.equal(recorded.recorder, 'a1b2c3d4');
  assert.equal(recorded.sources['npc:6910'].kills, 5);
  assert.equal(recorded.sources['npc:6910'].items['9387'], 2);
  assert.equal(recorded.seen['1'], 'Creature-0-1-70-47-6910-A');
  assert.equal(recorded.ratio, -0.25);
  assert.equal(recorded.on, true);
  assert.equal(recorded.off, false);
  assert.equal(recorded.none, null);
  assert.equal(vars.Other, 3);
});

test('reads escapes in strings', () => {
  const vars = parseSavedVariables('X = "Doom\'rel \\"the\\" \\\\ a\\nb\\065"');
  assert.equal(vars.X, 'Doom\'rel "the" \\ a\nbA');
});

test('refuses what it cannot read', () => {
  assert.throws(() => parseSavedVariables('X = {'), /saved variables/);
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `node --test "tools/test/*.test.mjs"`
Expected: FAIL (cannot find `../lib/savedvars.mjs`).

- [ ] **Step 3: Implement**

Create `BossLoot/tools/lib/savedvars.mjs`:

```js
// Reading the saved-variables files the game writes (WTF/Account/<name>/
// SavedVariables/<Addon>.lua): a small part of Lua -- assignments of tables,
// strings, numbers, booleans and nil, with "-- [n]" comments after list items.

export function parseSavedVariables(text) {
  let i = 0;
  const fail = (what) => { throw new Error(`saved variables: ${what} at ${i}`); };

  const skip = () => {
    for (;;) {
      while (i < text.length && /\s/.test(text[i])) i++;
      if (text.startsWith('--[[', i)) {
        const end = text.indexOf(']]', i);
        if (end < 0) fail('unterminated comment');
        i = end + 2;
      } else if (text.startsWith('--', i)) {
        while (i < text.length && text[i] !== '\n') i++;
      } else {
        return;
      }
    }
  };

  const expect = (c) => {
    skip();
    if (text[i] !== c) fail(`expected "${c}"`);
    i++;
  };

  const identifier = () => {
    const match = /^[A-Za-z_][A-Za-z0-9_]*/.exec(text.slice(i, i + 200));
    if (!match) return null;
    i += match[0].length;
    return match[0];
  };

  const string = () => {
    const quote = text[i++];
    let out = '';
    for (;;) {
      if (i >= text.length) fail('unterminated string');
      const c = text[i++];
      if (c === quote) return out;
      if (c !== '\\') { out += c; continue; }
      const e = text[i++];
      if (e === 'n') out += '\n';
      else if (e === 't') out += '\t';
      else if (e === 'r') out += '\r';
      else if (/[0-9]/.test(e)) {
        let digits = e;
        while (digits.length < 3 && /[0-9]/.test(text[i])) digits += text[i++];
        out += String.fromCharCode(Number(digits));
      } else out += e;
    }
  };

  let value;

  const table = () => {
    i++; // {
    const out = {};
    let position = 1;
    for (;;) {
      skip();
      if (i >= text.length) fail('unterminated table');
      if (text[i] === '}') { i++; return out; }
      if (text[i] === '[') {
        i++;
        const key = value();
        expect(']');
        expect('=');
        out[String(key)] = value();
      } else {
        const start = i;
        const name = identifier();
        skip();
        if (name !== null && text[i] === '=' && text[i + 1] !== '=') {
          i++;
          out[name] = value();
        } else {
          i = start;
          out[String(position++)] = value();
        }
      }
      skip();
      if (text[i] === ',' || text[i] === ';') i++;
    }
  };

  value = () => {
    skip();
    const c = text[i];
    if (c === '{') return table();
    if (c === '"' || c === "'") return string();
    if (text.startsWith('true', i)) { i += 4; return true; }
    if (text.startsWith('false', i)) { i += 5; return false; }
    if (text.startsWith('nil', i)) { i += 3; return null; }
    const match = /^-?(0x[0-9a-fA-F]+|\d+(\.\d+)?([eE][-+]?\d+)?|\.\d+)/.exec(text.slice(i, i + 64));
    if (!match) fail('expected a value');
    i += match[0].length;
    return Number(match[0]);
  };

  const vars = {};
  for (;;) {
    skip();
    if (i >= text.length) return vars;
    const name = identifier();
    if (name === null) fail('expected a name');
    expect('=');
    vars[name] = value();
  }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `node --test "tools/test/*.test.mjs"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add BossLoot/tools/lib/savedvars.mjs BossLoot/tools/test/savedvars.test.mjs
git commit -F - <<'EOF'
BossLoot: read saved-variables files in the build

The part of Lua the game writes, so recordings players send in can be
baked into a release.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: Bake recordings into `Data/Recorded.lua`

**Files:**
- Create: `BossLoot/tools/lib/recordings.mjs`, `BossLoot/tools/recordings/README.md`
- Modify: `BossLoot/tools/build-data.mjs`, `BossLoot/BossLoot.lua`, `BossLoot/tests/data_spec.lua`
- Test: `BossLoot/tools/test/recordings.test.mjs`, `BossLoot/tests/data_spec.lua`
- Generate: `BossLoot/Data/Recorded.lua`, TOC data lines

**Interfaces:**
- Consumes: `parseSavedVariables` (Task 2), `luaString` from `lua.mjs`.
- Produces (JS): `readRecordings(dir) -> { recordings: [{ recorder, data, file }], warnings: [string] }`, `toLua(value, indent?) -> string`, `recordedFile(recordings) -> string`. `data` holds `sources`, `quests`, `merchants`, `crafts`, `items` (never `seen`).
- Produces (Lua): `ns.bakedRecordings` (recorder id -> data) and `ns.AddRecordings(recorder, data)` in `BossLoot.lua`.

- [ ] **Step 1: Write the failing tests**

Create `BossLoot/tools/test/recordings.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { readRecordings, recordedFile, toLua } from '../lib/recordings.mjs';

const saved = (recorder, kills) => [
  'BossLootDB = {',
  '\t["recorded"] = {',
  `\t\t["recorder"] = "${recorder}",`,
  `\t\t["sources"] = { ["npc:6910"] = { ["kills"] = ${kills}, ["items"] = { [9387] = 1 } } },`,
  '\t\t["seen"] = { "Creature-0-1-70-47-6910-A" },',
  '\t},',
  '}',
].join('\n');

function folder(files) {
  const dir = mkdtempSync(join(tmpdir(), 'recordings-'));
  for (const [name, text] of Object.entries(files)) writeFileSync(join(dir, name), text);
  return dir;
}

test("reads each recorder's recordings, without the corpses seen", () => {
  const { recordings, warnings } = readRecordings(folder({ 'a.lua': saved('aaaa', 5), 'b.lua': saved('bbbb', 2) }));
  assert.deepEqual(warnings, []);
  assert.deepEqual(recordings.map((r) => r.recorder), ['aaaa', 'bbbb']);
  assert.equal(recordings[0].data.sources['npc:6910'].kills, 5);
  assert.equal(recordings[0].data.seen, undefined);
  assert.deepEqual(recordings[0].data.quests, {});
});

test('skips a file without recordings, and says so', () => {
  const { recordings, warnings } = readRecordings(folder({ 'old.lua': 'BossLootDB = { ["view"] = {} }', 'bad.lua': 'X = {' }));
  assert.equal(recordings.length, 0);
  assert.equal(warnings.length, 2);
});

test('keeps the later file when one recorder was sent twice', () => {
  const { recordings } = readRecordings(folder({ '1-old.lua': saved('aaaa', 1), '2-new.lua': saved('aaaa', 9) }));
  assert.equal(recordings.length, 1);
  assert.equal(recordings[0].data.sources['npc:6910'].kills, 9);
});

test('has nothing to read without the folder', () => {
  assert.deepEqual(readRecordings(join(tmpdir(), 'no-such-folder-bossloot')), { recordings: [], warnings: [] });
});

test('writes Lua: numeric keys, names, quoted keys, nesting', () => {
  assert.equal(toLua({ 9387: 2, kills: 5, 'npc:1': 'x' }), '{\n    [9387] = 2,\n    kills = 5,\n    ["npc:1"] = "x",\n}');
  assert.equal(toLua({}), '{}');
});

test('the recorded file hands each recorder to ns.AddRecordings', () => {
  const { recordings } = readRecordings(folder({ 'a.lua': saved('aaaa', 5) }));
  const text = recordedFile(recordings);
  assert.match(text, /^-- Generated by tools\/build-data\.mjs/);
  assert.match(text, /ns\.AddRecordings\("aaaa", \{/);
  assert.match(text, /\["npc:6910"\] = \{/);
  assert.match(recordedFile([]), /local _, ns = \.\.\./);
});
```

In `BossLoot/tests/data_spec.lua`, replace the test `"has one instance for each data file listed in the .toc, besides the items"` with:

```lua
    it("has one instance for each data file listed in the .toc, besides the items and recordings", function()
        assertTrue(#files > 2)
        assertEqual(#files - 2, #ns.instances)
        assertTrue(type(ns.bakedRecordings) == "table")
    end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `node --test "tools/test/*.test.mjs"` — Expected: FAIL (no `../lib/recordings.mjs`).

- [ ] **Step 3: Implement the build side**

Create `BossLoot/tools/lib/recordings.mjs`:

```js
// Recordings players made in WoW Forever, from saved-variables files put in
// tools/recordings/, baked into Data/Recorded.lua one recorder at a time. The
// addon leaves out the baked copy of the player's own recorder, so a
// player's loot is never counted twice.

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { parseSavedVariables } from './savedvars.mjs';
import { luaString } from './lua.mjs';

const KEPT = ['sources', 'quests', 'merchants', 'crafts', 'items'];

/** Each recorder's recordings in the folder's *.lua files, in file-name order. */
export function readRecordings(dir) {
  if (!existsSync(dir)) return { recordings: [], warnings: [] };
  const byRecorder = new Map();
  const warnings = [];
  for (const file of readdirSync(dir).filter((name) => name.endsWith('.lua')).sort()) {
    let vars;
    try {
      vars = parseSavedVariables(readFileSync(join(dir, file), 'utf8'));
    } catch (error) {
      warnings.push(`${file}: ${error.message}`);
      continue;
    }
    const recorded = vars.BossLootDB?.recorded;
    if (!recorded || typeof recorded.recorder !== 'string') {
      warnings.push(`${file}: no BossLoot recordings`);
      continue;
    }
    const data = {};
    for (const key of KEPT) data[key] = recorded[key] ?? {};
    // A recorder sent twice: the later file, by name, wins.
    byRecorder.set(recorded.recorder, { recorder: recorded.recorder, data, file });
  }
  return { recordings: [...byRecorder.values()], warnings };
}

/** A value as Lua source. */
export function toLua(value, indent = '') {
  if (value === null || value === undefined) return 'nil';
  if (typeof value === 'string') return luaString(value);
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  const keys = Object.keys(value);
  if (!keys.length) return '{}';
  const inner = `${indent}    `;
  const lines = keys.map((key) => {
    let written;
    if (/^-?\d+$/.test(key)) written = `[${key}]`;
    else if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) written = key;
    else written = `[${luaString(key)}]`;
    return `${inner}${written} = ${toLua(value[key], inner)},`;
  });
  return `{\n${lines.join('\n')}\n${indent}}`;
}

/** Data/Recorded.lua: each recorder's recordings handed to ns.AddRecordings. */
export function recordedFile(recordings) {
  const lines = [
    '-- Generated by tools/build-data.mjs from saved variables in tools/recordings. Do not edit.',
    '-- Loot, quest rewards, merchant goods and crafts recorded in WoW Forever, by recorder.',
    'local _, ns = ...',
    '',
  ];
  for (const { recorder, data } of recordings) {
    lines.push(`ns.AddRecordings(${luaString(recorder)}, ${toLua(data)})`, '');
  }
  return lines.join('\n');
}
```

Create `BossLoot/tools/recordings/README.md`:

```markdown
Saved-variables files with BossLoot recordings go here, to be baked into the
next release: `WTF/Account/<name>/SavedVariables/BossLoot.lua`, renamed to
anything ending in `.lua` (one per player). The build reads them all.
```

In `BossLoot/tools/build-data.mjs`:
- add `import { readRecordings, recordedFile } from './lib/recordings.mjs';`
- after the block that writes `Items.lua` and `files.unshift('Items.lua');`, add:

```js
// Recordings players sent in, baked in after the items and before the instances.
const { recordings, warnings: recordingWarnings } = readRecordings(join(here, 'recordings'));
for (const warning of recordingWarnings) console.warn(`warn  ${warning}`);
writeFileSync(join(dataDir, 'Recorded.lua'), recordedFile(recordings));
files.splice(1, 0, 'Recorded.lua');
console.log(`ok    ${recordings.length} recorders' recordings`);
```

In `BossLoot/BossLoot.lua`, after `ns.AddItems`:

```lua
-- Recordings baked into a release, from the generated Data\Recorded.lua:
-- recorder id -> its recordings. See Recordings.lua.
ns.bakedRecordings = {}

function ns.AddRecordings(recorder, data)
    ns.bakedRecordings[recorder] = data
end
```

- [ ] **Step 4: Run the tests and rebuild**

Run: `node --test "tools/test/*.test.mjs"` — Expected: all pass.
Run (repo root): the data rebuild — Expected: `ok    0 recorders' recordings`, `BossLoot/Data/Recorded.lua` exists, and the TOC lists `Data\Items.lua` then `Data\Recorded.lua` first.
Run: `lua tests/runner.lua tests/data_spec.lua` — Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add BossLoot/tools/lib/recordings.mjs BossLoot/tools/recordings/README.md BossLoot/tools/build-data.mjs BossLoot/tools/test/recordings.test.mjs BossLoot/BossLoot.lua BossLoot/tests/data_spec.lua BossLoot/Data/Recorded.lua BossLoot/BossLoot.toc
git commit -F - <<'EOF'
BossLoot: bake recordings from saved-variables files into the release

Files put in tools/recordings/ are read, and each recorder's loot, quest
rewards, merchant goods, crafts and items written to Data/Recorded.lua,
handed to ns.AddRecordings by recorder id.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: Record loot and boss fights

**Files:**
- Create: `BossLoot/Recorder.lua`, `BossLoot/Recordings.lua` (only `Recordings.Changed` for now)
- Modify: `BossLoot/BossLoot.toc`, `BossLoot/tests/helpers.lua`
- Test: `BossLoot/tests/recorder_spec.lua`

**Interfaces:**
- Consumes: `ns.LootRow.ItemInfo(itemID)`, `ns.AddDefaults`, `ns.OnLogin`, `ns.db`.
- Produces: `ns.Recorder.ParseGUID(guid) -> kind ("npc"|"object"), id | nil`; `ns.Recorder.LootOpened()`; `ns.Recorder.EncounterEnded(name, success)`; the saved shape of spec §2 under `ns.db.recorded` (`recorder`, `sources`, `quests`, `merchants`, `crafts`, `items`, `seen`); `ns.Recordings.Changed()` (Task 6 fills it in; here it only rebuilds the index).

- [ ] **Step 1: Write the failing tests**

Create `BossLoot/tests/recorder_spec.lua`:

```lua
local helpers = require("helpers")

local REVELOSH = "Creature-0-3110-70-47-6910-00001A2B3C"
local OTHER = "Creature-0-3110-70-47-7000-00001A2B3D"

-- A loot window: each slot an item (link, name, quality) or money, from its
-- sources (guid, count, guid, count, ...); in Uldaman, with `target` targeted.
local function looting(env, slots, target)
    function env.GetNumLootItems() return #slots end
    function env.GetLootSlotLink(slot) return slots[slot].link end
    function env.GetLootSlotInfo(slot) return 134400, slots[slot].name, 1, nil, slots[slot].quality end
    function env.GetLootSourceInfo(slot) return table.unpack(slots[slot].sources) end
    function env.GetInstanceInfo() return "Uldaman", "party", 1, "Normal", 5, 0, false, 70 end
    function env.GetRealZoneText() return "Uldaman" end
    function env.UnitGUID(unit) return unit == "target" and target and target.guid or nil end
    function env.UnitName(unit) return unit == "target" and target and target.name or nil end
end

local BOOTS = { link = "|cff1eff00|Hitem:9387::::|h[Revelosh's Boots]|h|r", name = "Revelosh's Boots", quality = 2 }
local GLOVES = { link = "|cff1eff00|Hitem:9388::::|h[Revelosh's Gloves]|h|r", name = "Revelosh's Gloves", quality = 2 }

local function withSources(item, ...)
    return { link = item.link, name = item.name, quality = item.quality, sources = { ... } }
end

describe("a GUID", function()
    it("names a creature or an object, and nothing else", function()
        local ns = helpers.loggedIn()
        local kind, id = ns.Recorder.ParseGUID(REVELOSH)
        assertEqual("npc", kind)
        assertEqual(6910, id)
        kind, id = ns.Recorder.ParseGUID("GameObject-0-3110-70-47-5678-0000ABCD")
        assertEqual("object", kind)
        assertEqual(5678, id)
        assertNil(ns.Recorder.ParseGUID("Item-0-0-0-0-1234-0000"))
        assertNil(ns.Recorder.ParseGUID("Player-3110-00ABCDEF"))
        assertNil(ns.Recorder.ParseGUID(nil))
    end)
end)

describe("recording loot", function()
    it("records a boss's loot, with the kill, where it was, and its name", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1), withSources(GLOVES, REVELOSH, 1) },
            { guid = REVELOSH, name = "Revelosh" })
        helpers.fire(env, "LOOT_OPENED")
        local source = ns.db.recorded.sources["npc:6910"]
        assertEqual(1, source.kills)
        assertEqual(1, source.items[9387])
        assertEqual(1, source.items[9388])
        assertEqual("Revelosh", source.name)
        assertEqual(70, source.map)
        assertEqual("party", source.instanceType)
        assertEqual("Uldaman", source.instance)
    end)

    it("counts a corpse once, however often its loot is opened", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1) })
        helpers.fire(env, "LOOT_OPENED")
        helpers.fire(env, "LOOT_OPENED")
        local source = ns.db.recorded.sources["npc:6910"]
        assertEqual(1, source.kills)
        assertEqual(1, source.items[9387])
    end)

    it("counts a kill for a corpse with only money", function()
        local ns, env = helpers.loggedIn()
        looting(env, { { sources = { REVELOSH, 1 } } })
        helpers.fire(env, "LOOT_OPENED")
        local source = ns.db.recorded.sources["npc:6910"]
        assertEqual(1, source.kills)
        assertNil(next(source.items))
    end)

    it("keeps each corpse apart when several are looted at once", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1, OTHER, 1) })
        helpers.fire(env, "LOOT_OPENED")
        assertEqual(1, ns.db.recorded.sources["npc:6910"].kills)
        assertEqual(1, ns.db.recorded.sources["npc:7000"].kills)
        assertEqual(1, ns.db.recorded.sources["npc:7000"].items[9387])
    end)

    it("remembers corpses looted before a reload", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1) })
        helpers.fire(env, "LOOT_OPENED")
        local later, laterEnv = helpers.loadAddon(nil, function(e) e.BossLootDB = env.BossLootDB end)
        helpers.sampleInstances(later)
        helpers.login(later, laterEnv)
        looting(laterEnv, { withSources(BOOTS, REVELOSH, 1) })
        helpers.fire(laterEnv, "LOOT_OPENED")
        assertEqual(1, later.db.recorded.sources["npc:6910"].kills)
    end)

    it("marks the boss the game named when the fight ended, for a minute", function()
        local ns, env = helpers.loggedIn()
        env.__now = 100
        function env.GetTime() return env.__now end
        helpers.fire(env, "ENCOUNTER_END", 1, "Revelosh", 1, 5, 1)
        looting(env, { withSources(BOOTS, REVELOSH, 1) }, { guid = REVELOSH, name = "Revelosh" })
        helpers.fire(env, "LOOT_OPENED")
        assertEqual("Revelosh", ns.db.recorded.sources["npc:6910"].encounter)

        helpers.fire(env, "ENCOUNTER_END", 2, "Ironaya", 1, 5, 1)
        env.__now = 200
        local IRONAYA = "Creature-0-3110-70-47-7228-00001A2B3E"
        looting(env, { withSources(GLOVES, IRONAYA, 1) }, { guid = IRONAYA, name = "Ironaya" })
        helpers.fire(env, "LOOT_OPENED")
        assertNil(ns.db.recorded.sources["npc:7228"].encounter, "too long after")
    end)

    it("saves each item's name and quality from the loot window when the game has no more", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1) })
        helpers.fire(env, "LOOT_OPENED")
        assertEqual("Revelosh's Boots", ns.db.recorded.items[9387][1])
        assertEqual(2, ns.db.recorded.items[9387][2])
    end)

    it("saves the game's full description of an item when it has one", function()
        local ns, env = helpers.loggedIn()
        env.__items[9387] = { name = "Forever Boots", quality = 3, type = "Armor", subType = "Leather", equipLoc = "INVTYPE_FEET" }
        looting(env, { withSources(BOOTS, REVELOSH, 1) })
        helpers.fire(env, "LOOT_OPENED")
        local item = ns.db.recorded.items[9387]
        assertEqual("Forever Boots", item[1])
        assertEqual(3, item[2])
        assertEqual("Leather", item[4])
    end)

    it("does nothing, and does not fail, on a client without the loot calls", function()
        local ns, env = helpers.loggedIn()
        helpers.fire(env, "LOOT_OPENED")
        assertNil(next(ns.db.recorded.sources))
    end)

    it("gets a recorder id at login, and keeps it", function()
        local ns, env = helpers.loggedIn()
        local id = ns.db.recorded.recorder
        assertTrue(type(id) == "string" and #id >= 8)
        local later, laterEnv = helpers.loadAddon(nil, function(e) e.BossLootDB = env.BossLootDB end)
        helpers.login(later, laterEnv)
        assertEqual(id, later.db.recorded.recorder)
    end)
end)
```

In `BossLoot/tests/helpers.lua`, in `M.FILES`, after `"LootRow.lua",` add `"Recordings.lua",` and `"Recorder.lua",`.

- [ ] **Step 2: Run it to see it fail**

Run: `lua tests/runner.lua tests/recorder_spec.lua`
Expected: FAIL (`ns.Recorder` is nil).

- [ ] **Step 3: Implement**

Create `BossLoot/Recordings.lua` (Task 6 grows it):

```lua
local addonName, ns = ...

-- What has been recorded in WoW Forever: the player's own recordings and any
-- baked into the release, merged, and laid onto BossLoot's instances.

local Recordings = {}
ns.Recordings = Recordings

--- Something was recorded: bring the lists up to date.
function Recordings.Changed()
    if ns.Index and ns.Index.Build then
        ns.Index.Build()
    end
end
```

Create `BossLoot/Recorder.lua`:

```lua
local addonName, ns = ...

-- Recording what WoW Forever really has. WoW Forever reworked dungeon loot and
-- item stats, so the vanilla lists BossLoot ships with are only a guide; this
-- records, as the player plays, what each creature and chest drops, which
-- boss the game named when a fight ended, and (see below) quest rewards,
-- merchant goods and crafts. Every client call is checked for first: a client
-- without one records the rest.

local Recorder = {}
ns.Recorder = Recorder

ns.AddDefaults({
    recorded = { sources = {}, quests = {}, merchants = {}, crafts = {}, items = {}, seen = {} },
})

local SEEN_LIMIT = 500        -- corpses remembered, so a reopened one does not count again
local ENCOUNTER_WINDOW = 60   -- seconds after a fight that a looted creature can be its boss
local KINDS = { Creature = "npc", Vehicle = "npc", GameObject = "object" }

local function recorded()
    return ns.db and ns.db.recorded
end

local function now()
    return GetTime and GetTime() or 0
end

--- A GUID's kind and id: "npc", 6910 for a creature; "object", 5678 for a
-- game object; nil for anything else.
function Recorder.ParseGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local kind, id = guid:match("^(%a+)%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-")
    kind = KINDS[kind]
    if not kind then
        return nil
    end
    return kind, tonumber(id)
end

local function itemIDOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- An item's name, quality and kind, as the game describes it; failing that,
-- the name and quality the loot window gave. Never a vanilla built-in copy:
-- those are what WoW Forever changed.
local function remember(itemID, name, quality)
    local items = recorded().items
    local info = ns.LootRow.ItemInfo(itemID)
    if info and not info.builtIn then
        items[itemID] = { info.name, info.quality, info.itemType, info.itemSubType, info.equipLoc }
    elseif not items[itemID] and name then
        items[itemID] = { name, quality }
    end
end

local function whereNow()
    local where = { zone = GetRealZoneText and GetRealZoneText() or nil }
    if GetInstanceInfo then
        local name, instanceType, _, _, _, _, _, mapID = GetInstanceInfo()
        where.instance, where.instanceType, where.map = name, instanceType, mapID
    end
    return where
end

local function sourceFor(kind, id, where)
    local sources = recorded().sources
    local key = kind .. ":" .. id
    local source = sources[key]
    if not source then
        source = { kind = kind, id = id, kills = 0, items = {} }
        sources[key] = source
    end
    source.map, source.instance, source.instanceType, source.zone =
        where.map, where.instance, where.instanceType, where.zone
    return source
end

-- Whether a corpse was looted before; remembers it if not.
local seenSet
local function alreadySeen(guid)
    local list = recorded().seen
    if not seenSet then
        seenSet = {}
        for _, seen in ipairs(list) do
            seenSet[seen] = true
        end
    end
    if seenSet[guid] then
        return true
    end
    seenSet[guid] = true
    table.insert(list, guid)
    if #list > SEEN_LIMIT then
        seenSet[table.remove(list, 1)] = nil
    end
    return false
end

local lastEncounter

--- A boss fight ended (ENCOUNTER_END): a won one's boss, looted within a
-- minute, is marked as that encounter's boss.
function Recorder.EncounterEnded(name, success)
    if success == 1 or success == true then
        lastEncounter = { name = name, at = now() }
    end
end

local function encounterFor(name)
    if lastEncounter and name == lastEncounter.name and now() - lastEncounter.at <= ENCOUNTER_WINDOW then
        return lastEncounter.name
    end
    return nil
end

local function targetName(guid)
    if UnitGUID and UnitName and UnitGUID("target") == guid then
        return UnitName("target")
    end
    return nil
end

--- A loot window opened (LOOT_OPENED): each corpse or chest it holds loot
-- from counts one kill or opening, the first time only, and its items once.
function Recorder.LootOpened()
    if not (recorded() and GetNumLootItems and GetLootSlotLink and GetLootSourceInfo) then
        return
    end
    local where = whereNow()
    local counted, skipped = {}, {}
    local changed = false
    for slot = 1, GetNumLootItems() do
        local itemID = itemIDOf(GetLootSlotLink(slot))
        local from = { GetLootSourceInfo(slot) }
        for k = 1, #from, 2 do
            local guid = from[k]
            local source = counted[guid]
            if not source and not skipped[guid] then
                local kind, id = Recorder.ParseGUID(guid)
                if kind and not alreadySeen(guid) then
                    source = sourceFor(kind, id, where)
                    source.kills = source.kills + 1
                    local name = targetName(guid)
                    if name then
                        source.name = name
                        source.encounter = encounterFor(name) or source.encounter
                    end
                    counted[guid] = source
                    changed = true
                else
                    skipped[guid] = true
                end
            end
            if source and itemID then
                source.items[itemID] = (source.items[itemID] or 0) + 1
                local name, quality
                if GetLootSlotInfo then
                    local _
                    _, name, _, _, quality = GetLootSlotInfo(slot)
                end
                remember(itemID, name, quality)
            end
        end
    end
    if changed then
        ns.Recordings.Changed()
    end
end

ns.OnLogin(function()
    local data = recorded()
    if not data.recorder then
        local stamp = time and time() or 0
        data.recorder = string.format("%08x%04x", math.random(0, 0x7fffffff), stamp % 0x10000)
    end
end)

local handlers = {
    LOOT_OPENED = function() Recorder.LootOpened() end,
    ENCOUNTER_END = function(_, name, _, _, success) Recorder.EncounterEnded(name, success) end,
}

local events = CreateFrame("Frame")
for event in pairs(handlers) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then
        handler(...)
    end
end)

Recorder.handlers = handlers
Recorder.events = events
```

In `BossLoot/BossLoot.toc`, after `LootRow.lua` add the lines `Recordings.lua` and `Recorder.lua`.

- [ ] **Step 4: Run it to see it pass**

Run: `lua tests/runner.lua tests/recorder_spec.lua` — Expected: all pass.
Run: `.\run-tests.ps1 BossLoot` (repo root) — Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add BossLoot/Recorder.lua BossLoot/Recordings.lua BossLoot/BossLoot.toc BossLoot/tests/helpers.lua BossLoot/tests/recorder_spec.lua
git commit -F - <<'EOF'
BossLoot: record what really drops, and which boss the game named

On each loot window, every corpse or chest it holds loot from counts one
kill or opening (once, the last 500 remembered across reloads) and its
items once, with where it was and its name. A boss fight won marks the
boss looted within a minute. Items are saved as the game describes them,
or as the loot window names them.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: Record quest rewards, merchant goods and crafts; `/bl probe` and `/bl recorded`

**Files:**
- Modify: `BossLoot/Recorder.lua`
- Test: `BossLoot/tests/recorder_spec.lua`

**Interfaces:**
- Consumes: Task 4's `recorded()`, `remember(itemID)`, `itemIDOf`, `Recorder.ParseGUID`, `handlers`.
- Produces: `Recorder.QuestShown()`, `Recorder.MerchantShown()`, `Recorder.TradeSkillShown()`, `Recorder.Counts() -> { sources, bosses, items, quests, merchants, professions }`; commands `probe` and `recorded`.

- [ ] **Step 1: Write the failing tests**

Append to `BossLoot/tests/recorder_spec.lua`:

```lua
describe("recording quests, merchants and crafts", function()
    it("records a quest's rewards and choices, with its title and the faction", function()
        local ns, env = helpers.loggedIn()
        function env.GetQuestID() return 2279 end
        function env.GetTitleText() return "Passing Word of a Threat" end
        function env.UnitFactionGroup() return "Alliance" end
        function env.GetNumQuestRewards() return 1 end
        function env.GetNumQuestChoices() return 2 end
        function env.GetQuestItemLink(kind, index)
            if kind == "reward" then return "|Hitem:9587::|h[A]|h" end
            return index == 1 and "|Hitem:9588::|h[B]|h" or "|Hitem:9589::|h[C]|h"
        end
        helpers.fire(env, "QUEST_DETAIL")
        local quest = ns.db.recorded.quests[2279]
        assertEqual("Passing Word of a Threat", quest.title)
        assertEqual("Alliance", quest.faction)
        assertEqual("9587", table.concat(quest.rewards, ","))
        assertEqual("9588,9589", table.concat(quest.choices, ","))
    end)

    it("records what a merchant sells, and for how much", function()
        local ns, env = helpers.loggedIn()
        function env.UnitGUID(unit) return unit == "npc" and "Creature-0-3110-0-47-1234-0000AA" or nil end
        function env.UnitName(unit) return unit == "npc" and "Brave Sword" or nil end
        function env.GetRealZoneText() return "Ironforge" end
        function env.GetMerchantNumItems() return 2 end
        function env.GetMerchantItemLink(i) return i == 1 and "|Hitem:2901::|h[Mining Pick]|h" or nil end
        function env.GetMerchantItemInfo(i) return "Mining Pick", 134400, 81 end
        helpers.fire(env, "MERCHANT_SHOW")
        local merchant = ns.db.recorded.merchants["npc:1234"]
        assertEqual("Brave Sword", merchant.name)
        assertEqual("Ironforge", merchant.zone)
        assertEqual(81, merchant.items[2901].price)
    end)

    it("records what a profession's recipes make, leaving out the headings", function()
        local ns, env = helpers.loggedIn()
        function env.GetTradeSkillLine() return "Blacksmithing", 120, 150 end
        function env.GetNumTradeSkills() return 2 end
        function env.GetTradeSkillInfo(i) return i == 1 and "Armor" or "Copper Chain Belt", i == 1 and "header" or "easy" end
        function env.GetTradeSkillItemLink(i) return i == 2 and "|Hitem:2851::|h[Copper Chain Belt]|h" or nil end
        helpers.fire(env, "TRADE_SKILL_SHOW")
        assertTrue(ns.db.recorded.crafts["Blacksmithing"][2851])
    end)

    it("records nothing, and does not fail, without the quest, merchant or profession calls", function()
        local ns, env = helpers.loggedIn()
        helpers.fire(env, "QUEST_DETAIL")
        helpers.fire(env, "QUEST_COMPLETE")
        helpers.fire(env, "MERCHANT_SHOW")
        helpers.fire(env, "TRADE_SKILL_SHOW")
        assertNil(next(ns.db.recorded.quests))
        assertNil(next(ns.db.recorded.merchants))
        assertNil(next(ns.db.recorded.crafts))
    end)
end)

describe("the recorder's commands", function()
    it("say which calls this client is missing", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "probe")
        assertMatch("GetLootSourceInfo", helpers.printed(env))
        function env.GetNumLootItems() end
        function env.GetLootSlotLink() end
        function env.GetLootSlotInfo() end
        function env.GetLootSourceInfo() end
        function env.GetInstanceInfo() end
        function env.UnitGUID() end
        function env.GetQuestID() end
        function env.GetQuestItemLink() end
        function env.GetMerchantItemLink() end
        function env.GetMerchantItemInfo() end
        function env.GetTradeSkillLine() end
        function env.GetTradeSkillItemLink() end
        function env.GetItemStats() end
        env.__printed = {}
        helpers.command(env, "probe")
        assertMatch("Everything the recorder needs", helpers.printed(env))
    end)

    it("count what has been recorded", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1) }, { guid = REVELOSH, name = "Revelosh" })
        helpers.fire(env, "LOOT_OPENED")
        helpers.command(env, "recorded")
        assertMatch("1 creatures and objects", helpers.printed(env))
        assertMatch("1 items", helpers.printed(env))
    end)
end)
```

- [ ] **Step 2: Run it to see it fail**

Run: `lua tests/runner.lua tests/recorder_spec.lua`
Expected: the new tests fail (no quest, merchant or craft recorded; unknown command `probe`).

- [ ] **Step 3: Implement**

In `BossLoot/Recorder.lua`, before `ns.OnLogin(function()`, add:

```lua
--- A quest window (QUEST_DETAIL, QUEST_COMPLETE): its fixed and choice
-- reward items, its title, and the faction of the one who saw it.
function Recorder.QuestShown()
    if not (recorded() and GetQuestID and GetQuestItemLink) then
        return
    end
    local questID = GetQuestID()
    if not questID or questID == 0 then
        return
    end
    local quests = recorded().quests
    local quest = quests[questID] or {}
    quest.title = GetTitleText and GetTitleText() or quest.title
    quest.faction = UnitFactionGroup and UnitFactionGroup("player") or quest.faction
    local function collect(kind, count)
        local ids = {}
        for index = 1, count do
            local itemID = itemIDOf(GetQuestItemLink(kind, index))
            if itemID then
                table.insert(ids, itemID)
                remember(itemID)
            end
        end
        return ids
    end
    local rewards = collect("reward", GetNumQuestRewards and GetNumQuestRewards() or 0)
    local choices = collect("choice", GetNumQuestChoices and GetNumQuestChoices() or 0)
    if #rewards > 0 then quest.rewards = rewards end
    if #choices > 0 then quest.choices = choices end
    quests[questID] = quest
end

--- A merchant window (MERCHANT_SHOW): what it sells, and for how much.
function Recorder.MerchantShown()
    if not (recorded() and GetMerchantNumItems and GetMerchantItemLink and UnitGUID) then
        return
    end
    local kind, id = Recorder.ParseGUID(UnitGUID("npc"))
    if kind ~= "npc" then
        return
    end
    local merchants = recorded().merchants
    local key = "npc:" .. id
    local merchant = merchants[key] or { items = {} }
    merchant.name = UnitName and UnitName("npc") or merchant.name
    merchant.zone = GetRealZoneText and GetRealZoneText() or merchant.zone
    for index = 1, GetMerchantNumItems() do
        local itemID = itemIDOf(GetMerchantItemLink(index))
        if itemID then
            local price = GetMerchantItemInfo and select(3, GetMerchantItemInfo(index)) or nil
            merchant.items[itemID] = { price = price }
            remember(itemID)
        end
    end
    merchants[key] = merchant
end

--- A profession window (TRADE_SKILL_SHOW, TRADE_SKILL_UPDATE): what each of
-- its recipes makes.
function Recorder.TradeSkillShown()
    if not (recorded() and GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillItemLink) then
        return
    end
    local profession = GetTradeSkillLine()
    if not profession or profession == "UNKNOWN" then
        return
    end
    local crafts = recorded().crafts
    local made = crafts[profession] or {}
    for index = 1, GetNumTradeSkills() do
        local _, skillType = GetTradeSkillInfo(index)
        if skillType ~= "header" then
            local itemID = itemIDOf(GetTradeSkillItemLink(index))
            if itemID then
                made[itemID] = true
                remember(itemID)
            end
        end
    end
    crafts[profession] = made
end

--- How much the player has recorded.
function Recorder.Counts()
    local data = recorded()
    local counts = { sources = 0, bosses = 0, items = 0, quests = 0, merchants = 0, professions = 0 }
    for _, source in pairs(data.sources) do
        counts.sources = counts.sources + 1
        if source.encounter then counts.bosses = counts.bosses + 1 end
    end
    for _ in pairs(data.items) do counts.items = counts.items + 1 end
    for _ in pairs(data.quests) do counts.quests = counts.quests + 1 end
    for _ in pairs(data.merchants) do counts.merchants = counts.merchants + 1 end
    for _ in pairs(data.crafts) do counts.professions = counts.professions + 1 end
    return counts
end

-- The calls the recorder (and the gear finder after it) uses.
local PROBED = {
    "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "GetLootSourceInfo", "GetInstanceInfo",
    "UnitGUID", "GetQuestID", "GetQuestItemLink", "GetMerchantItemLink", "GetMerchantItemInfo",
    "GetTradeSkillLine", "GetTradeSkillItemLink", "GetItemStats",
}

ns.RegisterCommand("probe", "Check this client has what the recorder needs", function()
    local missing = {}
    for _, name in ipairs(PROBED) do
        if not (_G[name] or (C_Item and C_Item[name])) then
            table.insert(missing, name)
        end
    end
    if #missing == 0 then
        ns.Print("Everything the recorder needs is here.")
    else
        ns.Print("This client is missing: " .. table.concat(missing, ", "))
    end
end)

ns.RegisterCommand("recorded", "Show how much you have recorded", function()
    local c = Recorder.Counts()
    ns.Print(string.format(
        "Recorded: %d creatures and objects (%d named bosses), %d items; %d quests, %d merchants, %d professions.",
        c.sources, c.bosses, c.items, c.quests, c.merchants, c.professions))
end)
```

Add the events to `handlers`:

```lua
local handlers = {
    LOOT_OPENED = function() Recorder.LootOpened() end,
    ENCOUNTER_END = function(_, name, _, _, success) Recorder.EncounterEnded(name, success) end,
    QUEST_DETAIL = function() Recorder.QuestShown() end,
    QUEST_COMPLETE = function() Recorder.QuestShown() end,
    MERCHANT_SHOW = function() Recorder.MerchantShown() end,
    TRADE_SKILL_SHOW = function() Recorder.TradeSkillShown() end,
    TRADE_SKILL_UPDATE = function() Recorder.TradeSkillShown() end,
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `lua tests/runner.lua tests/recorder_spec.lua` — Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add BossLoot/Recorder.lua BossLoot/tests/recorder_spec.lua
git commit -F - <<'EOF'
BossLoot: record quest rewards, merchant goods and crafts; /bl probe, /bl recorded

For the gear finder to come. /bl probe says which calls the client lacks,
/bl recorded counts what has been recorded.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: Merge the recordings and lay them onto the instances

**Files:**
- Modify: `BossLoot/Recordings.lua`, `BossLoot/Index.lua` (`add`, `Index.Build`), `BossLoot/ItemData.lua` (`ItemData.Get`, new `ItemData.ClassName`)
- Test: `BossLoot/tests/recordings_spec.lua`

**Interfaces:**
- Consumes: `ns.db.recorded` (Task 4), `ns.bakedRecordings` (Task 3), instance `mapID`, boss `npcs`/`objects` (Task 1), `ns.LootRow.ItemInfo`.
- Produces:
  - `Recordings.Sources() -> { [key] = { kind, id, name, encounter, map, instance, instanceType, zone, kills, items = { [itemID] = count } } }`
  - `Recordings.Item(itemID) -> { name, quality, itemType?, itemSubType?, equipLoc? } | nil`
  - `Recordings.Apply()`
  - `Recordings.Changed()`
  - On bosses: `boss.recorded = { { itemID, count, sources }, ... }` (most seen first) and `boss.recordedKills`.
  - On instances: `instance.recordedNotable = { trash = { { itemID, count, { names } }, ... }, objects = {...} }`.
  - Recorded instances in `ns.instances` and `ns.instanceByKey` with `key = "rec:<map>"`, `recorded = true`, no `levels` and no `map`.
  - `ItemData.ClassName(class) -> string`.

- [ ] **Step 1: Write the failing tests**

Create `BossLoot/tests/recordings_spec.lua`:

```lua
local helpers = require("helpers")

-- The samples, with a map id and creature ids, and recordings: `own` as the
-- player's saved ones, `baked` as recorder id -> data.
local function withRecordings(own, baked)
    local ns, env = helpers.loadAddon(nil, function(e)
        e.BossLootDB = { recorded = own }
    end)
    helpers.sampleInstances(ns)
    local depths = ns.instanceByKey.Depths
    depths.mapID = 230
    depths.bosses[1].npcs = { 101, 102 }
    for recorder, data in pairs(baked or {}) do
        ns.AddRecordings(recorder, data)
    end
    helpers.login(ns, env)
    return ns, env, depths
end

local function source(fields)
    fields.map = fields.map or 230
    fields.instanceType = fields.instanceType or "party"
    fields.instance = fields.instance or "Test Depths"
    return fields
end

describe("recorded loot on the instances", function()
    it("lays a boss's recorded loot on it, most seen first, with its kills", function()
        local ns, env, depths = withRecordings({ recorder = "me", sources = {
            ["npc:101"] = source({ kind = "npc", id = 101, kills = 5, items = { [1001] = 3, [5555] = 4 } }),
        } })
        local boss = depths.bosses[1]
        assertEqual(5, boss.recordedKills)
        assertEqual(5555, boss.recorded[1][1])
        assertEqual(4, boss.recorded[1][2])
        assertEqual(1001, boss.recorded[2][1])
    end)

    it("matches a boss by its name when its creature is not known", function()
        local ns, env, depths = withRecordings({ recorder = "me", sources = {
            ["npc:999"] = source({ kind = "npc", id = 999, name = "Second Boss", kills = 1, items = { [1003] = 1 } }),
        } })
        assertEqual(1003, depths.bosses[2].recorded[1][1])
    end)

    it("counts the most kills of one creature for a boss of several", function()
        local ns, env, depths = withRecordings({ recorder = "me", sources = {
            ["npc:101"] = source({ kind = "npc", id = 101, kills = 5, items = { [1001] = 2 } }),
            ["npc:102"] = source({ kind = "npc", id = 102, kills = 5, items = { [1001] = 1 } }),
        } })
        assertEqual(5, depths.bosses[1].recordedKills)
        assertEqual(3, depths.bosses[1].recorded[1][2])
    end)

    it("puts other creatures under trash and chests under objects, notable items only", function()
        local ns, env, depths = withRecordings({ recorder = "me",
            items = { [7001] = { "Rare Find", 3 }, [7002] = { "Green Find", 2 } },
            sources = {
                ["npc:300"] = source({ kind = "npc", id = 300, name = "Trash Mob", kills = 9, items = { [7001] = 2, [7002] = 5 } }),
                ["object:50"] = source({ kind = "object", id = 50, name = "Old Chest", kills = 1, items = { [7001] = 1 } }),
            } })
        local trash = depths.recordedNotable.trash
        assertEqual(1, #trash)
        assertEqual(7001, trash[1][1])
        assertEqual(2, trash[1][2])
        assertEqual("Trash Mob", trash[1][3][1])
        assertEqual(7001, depths.recordedNotable.objects[1][1])
    end)

    it("sums baked recordings with the player's own, but not the baked copy of the player's own", function()
        local ns, env, depths = withRecordings(
            { recorder = "me", sources = { ["npc:101"] = source({ kind = "npc", id = 101, kills = 1, items = { [1001] = 1 } }) } },
            {
                friend = { sources = { ["npc:101"] = source({ kind = "npc", id = 101, kills = 2, items = { [1001] = 2 } }) } },
                me = { sources = { ["npc:101"] = source({ kind = "npc", id = 101, kills = 100, items = { [1001] = 100 } }) } },
            })
        assertEqual(3, depths.bosses[1].recordedKills)
        assertEqual(3, depths.bosses[1].recorded[1][2])
    end)

    it("lists an instance BossLoot does not know, with the bosses the game named", function()
        local ns = withRecordings({ recorder = "me", sources = {
            ["npc:8000"] = source({ kind = "npc", id = 8000, map = 9999, instance = "Hall of Thanes",
                name = "Thane", encounter = "Thane", kills = 1, items = { [8001] = 1 } }),
            ["npc:8002"] = source({ kind = "npc", id = 8002, map = 9999, instance = "Hall of Thanes",
                name = "Guard", kills = 3, items = { [8003] = 1 } }),
        } })
        local hall = ns.instanceByKey["rec:9999"]
        assertEqual("Hall of Thanes", hall.name)
        assertEqual("dungeon", hall.kind)
        assertTrue(hall.recorded)
        assertEqual(1, #hall.bosses)
        assertEqual("Thane", hall.bosses[1].name)
        assertEqual(8001, hall.bosses[1].recorded[1][1])
        local listed = false
        for _, instance in ipairs(ns.Index.Instances("dungeon")) do
            if instance == hall then listed = true end
        end
        assertTrue(listed)
    end)

    it("leaves open-world loot out of the instances", function()
        local ns = withRecordings({ recorder = "me", sources = {
            ["npc:40"] = source({ kind = "npc", id = 40, map = 0, instanceType = "none", kills = 1, items = { [900] = 1 } }),
        } })
        assertNil(ns.instanceByKey["rec:0"])
    end)

    it("names a recorded item from its recording, over the vanilla built-in copy", function()
        local ns = withRecordings({ recorder = "me", items = { [7001] = { "Forever Robe", 4, "Armor", "Cloth", "INVTYPE_CHEST" } } })
        ns.AddItems({ [7001] = { "Vanilla Robe", 2, 4, 1, 5 } })
        local info = ns.LootRow.ItemInfo(7001)
        assertEqual("Forever Robe", info.name)
        assertEqual(4, info.quality)
    end)

    it("finds recorded items in a search", function()
        local ns = withRecordings({ recorder = "me",
            items = { [5555] = { "Thane's Seal", 3 } },
            sources = { ["npc:101"] = source({ kind = "npc", id = 101, kills = 1, items = { [5555] = 1 } }) } })
        local result = ns.Index.Search("thane", function(id) local info = ns.LootRow.ItemInfo(id) return info and info.name end)
        assertEqual(5555, result.items[1].id)
    end)
end)
```

- [ ] **Step 2: Run it to see it fail**

Run: `lua tests/runner.lua tests/recordings_spec.lua`
Expected: FAIL (`boss.recordedKills` is nil, and so on).

- [ ] **Step 3: Implement**

Replace the body of `BossLoot/Recordings.lua` after `ns.Recordings = Recordings` with:

```lua
local RECORDED_KEY = "rec:"

-- Every recorder's recordings: the player's own, and those baked into the
-- release but the baked copy of the player's own. Remembered until the next
-- change.
local recorders

local function all()
    if not recorders then
        recorders = {}
        local own = ns.db and ns.db.recorded
        if own then
            table.insert(recorders, own)
        end
        for recorder, data in pairs(ns.bakedRecordings or {}) do
            if not (own and recorder == own.recorder) then
                table.insert(recorders, data)
            end
        end
    end
    return recorders
end

--- Every recorder's loot sources, merged by kind and id: kills and item
-- counts summed, names and places from whichever recorder has them.
function Recordings.Sources()
    local merged = {}
    for _, data in ipairs(all()) do
        for key, source in pairs(data.sources or {}) do
            local into = merged[key]
            if not into then
                into = { kind = source.kind, id = source.id, kills = 0, items = {} }
                merged[key] = into
            end
            into.name = into.name or source.name
            into.encounter = into.encounter or source.encounter
            into.map = into.map or source.map
            into.instance = into.instance or source.instance
            into.instanceType = into.instanceType or source.instanceType
            into.zone = into.zone or source.zone
            into.kills = into.kills + (source.kills or 0)
            for itemID, count in pairs(source.items or {}) do
                into.items[itemID] = (into.items[itemID] or 0) + count
            end
        end
    end
    return merged
end

--- A recorded item's name, quality and kind, from any recorder, or nil.
function Recordings.Item(itemID)
    for _, data in ipairs(all()) do
        local item = data.items and data.items[itemID]
        if item then
            return item
        end
    end
    return nil
end

local function contains(list, value)
    for _, each in ipairs(list or {}) do
        if each == value then
            return true
        end
    end
    return false
end

local function bossFor(instance, source)
    for _, boss in ipairs(instance.bosses) do
        if (source.kind == "npc" and contains(boss.npcs, source.id))
            or (source.kind == "object" and contains(boss.objects, source.id))
            or (source.name ~= nil and source.name == boss.name)
            or (source.encounter ~= nil and source.encounter == boss.name) then
            return boss
        end
    end
    return nil
end

-- Notable, as the vanilla trash and chest lists count it: rare or better, a
-- recipe or a key. An item not described yet counts, rather than hiding.
local function notable(itemID)
    local info = ns.LootRow.ItemInfo(itemID)
    if not info then
        return true
    end
    return (info.quality or 0) >= 3
        or info.itemType == ns.ItemData.ClassName(9)
        or info.itemType == ns.ItemData.ClassName(13)
end

local function byCount(a, b)
    if a[2] ~= b[2] then
        return a[2] > b[2]
    end
    return a[1] < b[1]
end

-- Add `count` of an item to a list, once per item, noting where it came from.
local function addTo(list, index, itemID, count, sourceName)
    local entry = index[itemID]
    if not entry then
        entry = { itemID, 0, {} }
        index[itemID] = entry
        table.insert(list, entry)
    end
    entry[2] = entry[2] + count
    if sourceName and not contains(entry[3], sourceName) then
        table.insert(entry[3], sourceName)
    end
end

-- Take away what the last Apply laid on, and the recorded instances.
local function clear()
    for position = #ns.instances, 1, -1 do
        local instance = ns.instances[position]
        if instance.recorded then
            table.remove(ns.instances, position)
            ns.instanceByKey[instance.key] = nil
        else
            instance.recordedNotable = nil
            for _, boss in ipairs(instance.bosses) do
                boss.recorded, boss.recordedKills = nil, nil
            end
        end
    end
end

local function recordedInstance(source)
    return {
        key = RECORDED_KEY .. source.map,
        name = source.instance or ("Instance " .. source.map),
        kind = source.instanceType == "raid" and "raid" or "dungeon",
        recorded = true,
        bosses = {},
        notable = { trash = {}, objects = {} },
    }
end

--- Lay the recordings onto the instances: each boss's loot and kills, the
-- notable trash and chest finds, and instances BossLoot does not know.
function Recordings.Apply()
    clear()
    local byMap = {}
    for _, instance in ipairs(ns.instances) do
        if instance.mapID then
            byMap[instance.mapID] = instance
        end
    end

    local sources = Recordings.Sources()
    local keys = {}
    for key in pairs(sources) do
        table.insert(keys, key)
    end
    table.sort(keys)

    local indexes = {}
    local function list(owner)
        indexes[owner] = indexes[owner] or {}
        return owner, indexes[owner]
    end

    for _, key in ipairs(keys) do
        local source = sources[key]
        local inInstance = source.instanceType == "party" or source.instanceType == "raid"
        if source.map and inInstance then
            local instance = byMap[source.map]
            if not instance then
                instance = recordedInstance(source)
                table.insert(ns.instances, instance)
                ns.instanceByKey[instance.key] = instance
                byMap[source.map] = instance
            end
            local boss = bossFor(instance, source)
            if not boss and instance.recorded and source.encounter then
                boss = { name = source.encounter, loot = {} }
                table.insert(instance.bosses, boss)
            end
            if boss then
                boss.recorded = boss.recorded or {}
                boss.recordedKills = math.max(boss.recordedKills or 0, source.kills)
                local entries, index = list(boss.recorded)
                for itemID, count in pairs(source.items) do
                    addTo(entries, index, itemID, count)
                end
            else
                instance.recordedNotable = instance.recordedNotable or { trash = {}, objects = {} }
                local which = source.kind == "object" and "objects" or "trash"
                local entries, index = list(instance.recordedNotable[which])
                for itemID, count in pairs(source.items) do
                    if notable(itemID) then
                        addTo(entries, index, itemID, count, source.name)
                    end
                end
            end
        end
    end

    for entries in pairs(indexes) do
        table.sort(entries, byCount)
    end
end

--- Something was recorded, or the saved recordings are in: bring the
-- instances, the index and an open window up to date.
function Recordings.Changed()
    recorders = nil
    Recordings.Apply()
    if ns.Index and ns.Index.Build then
        ns.Index.Build()
    end
    local frame = ns.Window and ns.Window.Frame and ns.Window.Frame()
    if frame and frame:IsShown() then
        ns.Window.Refresh()
    end
end

ns.OnLogin(Recordings.Changed)
```

In `BossLoot/Index.lua`, make `add` skip a place already listed for the item, and read the recorded lists. Replace `add` and `Index.Build` with:

```lua
local function add(itemID, instanceKey, boss)
    if not sources[itemID] then
        sources[itemID] = {}
        table.insert(allItems, itemID)
    end
    for _, place in ipairs(sources[itemID]) do
        if place.instance == instanceKey and place.boss == boss then
            return
        end
    end
    table.insert(sources[itemID], { instance = instanceKey, boss = boss })

    local list = itemsByInstance[instanceKey]
    if not list.seen[itemID] then
        list.seen[itemID] = true
        table.insert(list, itemID)
    end
end

function Index.Build()
    sources, allItems, itemsByInstance = {}, {}, {}

    for _, instance in ipairs(ns.instances) do
        itemsByInstance[instance.key] = { seen = {} }

        for bossIndex, boss in ipairs(instance.bosses) do
            for _, entry in ipairs(boss.recorded or {}) do
                add(entry[1], instance.key, bossIndex)
            end
            for _, entry in ipairs(boss.loot) do
                add(entry[1], instance.key, bossIndex)
            end
        end

        local notable = instance.notable or {}
        local recordedNotable = instance.recordedNotable or {}
        for _, which in ipairs({ "trash", "objects" }) do
            for _, entry in ipairs(recordedNotable[which] or {}) do
                add(entry[1], instance.key, which)
            end
            for _, entry in ipairs(notable[which] or {}) do
                add(entry[1], instance.key, which)
            end
        end
    end
end
```

Still in `BossLoot/Index.lua`, `Index.Instances` sorts by level, and a recorded instance has none. Replace its `table.sort` call with:

```lua
    -- Known instances by level; recorded ones, which have no level range,
    -- after them by name.
    table.sort(list, function(a, b)
        if (a.levels == nil) ~= (b.levels == nil) then
            return a.levels ~= nil
        end
        if a.levels and a.levels[1] ~= b.levels[1] then
            return a.levels[1] < b.levels[1]
        end
        return a.name < b.name
    end)
```

In `BossLoot/ItemData.lua`, export the class names and put the recorded layer first in `ItemData.Get`:

```lua
--- The game's name for an item class (9 recipes, 13 keys, ...).
function ItemData.ClassName(class)
    return className(class)
end
```

and at the top of `ItemData.Get`, before `local entry = ns.builtInItems[itemID]`:

```lua
    -- Recorded in WoW Forever: the real item, over a vanilla one of the same id.
    local recorded = ns.Recordings and ns.Recordings.Item(itemID)
    if recorded then
        local name, quality = recorded[1], recorded[2] or 1
        return {
            name = name,
            quality = quality,
            link = "|cff" .. ns.Format.QualityHex(quality) .. "|Hitem:" .. itemID .. "|h[" .. name .. "]|h|r",
            itemType = recorded[3],
            itemSubType = recorded[4],
            equipLoc = recorded[5] or "",
            builtIn = true,
        }
    end
```

- [ ] **Step 4: Run it to see it pass**

Run: `lua tests/runner.lua tests/recordings_spec.lua` — Expected: all pass.
Run: `.\run-tests.ps1 BossLoot` — Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add BossLoot/Recordings.lua BossLoot/Index.lua BossLoot/ItemData.lua BossLoot/tests/recordings_spec.lua
git commit -F - <<'EOF'
BossLoot: merge the recordings and lay them onto the instances

The player's own recordings and the baked ones (less the baked copy of the
player's own) are summed per creature or chest, matched to bosses by id,
name or the encounter the game named, and laid on: each boss's recorded
loot and kills, the notable trash and chest finds, and a recorded instance
for each map BossLoot does not know. Search finds recorded items, and a
recorded item's name wins over a vanilla one of the same id.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 7: The loot list shows recorded loot first, the classic list dimmed; recorded instances in the list

**Files:**
- Modify: `BossLoot/Window.lua` (`instanceEntry`, `placeEntry`, `Window.BossEntries`, `lootSource` users, `Window.LootEntries`, `validSelection`, `Window.Current`, the `Window.LootEntries` call in `Window.Refresh`), `BossLoot/LootRow.lua` (`Render`, `showTooltip`)
- Test: `BossLoot/tests/window_spec.lua`, `BossLoot/tests/lootrow_spec.lua`

**Interfaces:**
- Consumes: `boss.recorded`, `boss.recordedKills`, `instance.recordedNotable`, recorded instances (Task 6).
- Produces: `Window.LootEntries(instance, selection, perLine) -> entries`. Entries are:
  - an item: `{ id, seen = "3/5" | "×2", sources?, selected }`
  - a heading: `{ heading = "Classic loot", note = "Not seen on WoW Forever yet" }`
  - a blank: `{ blank = true }`
  - a classic item: `{ id, chance, sources?, classic = true, selected }`

  `LootRow.Render` draws all four.

- [ ] **Step 1: Write the failing tests, and update the tests the heading moves**

In `BossLoot/tests/window_spec.lua`:

(a) Replace the test `"lists a boss's loot"` with:

```lua
    it("shows the classic list, dimmed, under its heading when nothing is recorded", function()
        local ns = helpers.loggedIn()
        local entries = ns.Window.LootEntries(ns.instanceByKey.Depths, 1)
        assertEqual(4, #entries)
        assertEqual("Classic loot", entries[1].heading)
        assertTrue(entries[2].blank, "the heading on a line of its own")
        assertEqual(1001, entries[3].id)
        assertEqual(20, entries[3].chance)
        assertTrue(entries[3].classic)
    end)
```

(b) In `"lists notable drops with what drops them"`, change `entries[1].sources[1]` to `entries[3].sources[1]`.

(c) In `"draws the three columns from the selection"`, change both `frame.loot.rows[1].entry.id` to `frame.loot.rows[3].entry.id`.

(d) In `"redraws loot rows once their items arrive"` and `"are marked unknown when the answer says so"`, change `loot.rows[1]` to `loot.rows[3]`.

(e) In `"moves under the bosses, and back when the map closes"`, change `frame.mapLoot.rows[1].entry.id` to `frame.mapLoot.rows[2].entry.id` (one column: the heading, then the items), and `frame.loot.rows[1].entry.id` to `frame.loot.rows[3].entry.id`. In `"follows a boss picked on the map"`, change `frame.mapLoot.rows[1]` to `frame.mapLoot.rows[2]`.

(f) Append:

```lua
describe("recorded loot in the lists", function()
    local function recordedSample(sources)
        local ns, env = helpers.loadAddon(nil, function(e)
            e.BossLootDB = { recorded = { recorder = "me", sources = sources } }
        end)
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.mapID = 230
        ns.instanceByKey.Depths.bosses[1].npcs = { 101 }
        helpers.login(ns, env)
        return ns, env
    end
    local function at(fields)
        fields.map, fields.instanceType, fields.instance = fields.map or 230, "party", "Test Depths"
        return fields
    end

    it("come first, with how often they were seen, then the classic list, dimmed, less what was seen", function()
        local ns = recordedSample({ ["npc:101"] = at({ kind = "npc", id = 101, kills = 5, items = { [5555] = 3, [1001] = 1 } }) })
        local entries = ns.Window.LootEntries(ns.instanceByKey.Depths, 1)
        assertEqual(5555, entries[1].id)
        assertEqual("3/5", entries[1].seen)
        assertEqual(1001, entries[2].id)
        assertEqual("1/5", entries[2].seen)
        assertEqual("Classic loot", entries[3].heading)
        assertTrue(entries[4].blank)
        assertEqual(1002, entries[5].id)
        assertTrue(entries[5].classic)
        assertEqual(5, #entries, "1001 once, as recorded")
    end)

    it("line the heading up on a line of its own after an odd number of items", function()
        local ns = recordedSample({ ["npc:101"] = at({ kind = "npc", id = 101, kills = 2, items = { [5555] = 1 } }) })
        local entries = ns.Window.LootEntries(ns.instanceByKey.Depths, 1)
        assertEqual(5555, entries[1].id)
        assertTrue(entries[2].blank)
        assertEqual("Classic loot", entries[3].heading)
        local single = ns.Window.LootEntries(ns.instanceByKey.Depths, 1, 1)
        assertEqual("Classic loot", single[2].heading, "no blanks in one column")
    end)

    it("show notable finds with how many and who dropped them", function()
        local ns = recordedSample({ ["npc:300"] = at({ kind = "npc", id = 300, name = "Trash Mob", kills = 4, items = { [2001] = 2 } }) })
        local entries = ns.Window.LootEntries(ns.instanceByKey.Depths, "trash")
        assertEqual(2001, entries[1].id)
        assertEqual("×2", entries[1].seen)
        assertEqual("Trash Mob", entries[1].sources[1])
    end)

    it("put the notable lists in the boss column when only recordings have them", function()
        local ns = recordedSample({ ["npc:300"] = at({ kind = "npc", id = 300, map = 409, name = "Core Hound", kills = 1, items = {} }) })
        ns.instanceByKey.Core.mapID = 409
        ns.db.recorded.sources["npc:300"].items[4444] = 1
        ns.Recordings.Changed()
        local names = {}
        for _, entry in ipairs(ns.Window.BossEntries(ns.instanceByKey.Core, 1)) do table.insert(names, entry.text) end
        assertMatch("From trash", table.concat(names, "|"))
    end)

    it("list a recorded instance in its tab", function()
        local ns = recordedSample({ ["npc:8000"] = at({ kind = "npc", id = 8000, map = 9999, name = "Thane", encounter = "Thane", kills = 1, items = { [8001] = 1 } }) })
        ns.db.recorded.sources["npc:8000"].instance = "Hall of Thanes"
        ns.Recordings.Changed()
        local texts = {}
        for _, entry in ipairs(ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "")) do table.insert(texts, entry.text) end
        assertMatch("Hall of Thanes", table.concat(texts, "|"))
    end)

    it("open a recorded instance with no named boss on its trash", function()
        local ns = recordedSample({ ["npc:8002"] = at({ kind = "npc", id = 8002, map = 9999, name = "Guard", kills = 3, items = { [8003] = 1 } }) })
        ns.Window.Open()
        ns.Window.SelectInstance("rec:9999")
        local instance, selection = ns.Window.Current()
        assertEqual("rec:9999", instance.key)
        assertEqual("trash", selection)
    end)

    it("show a recorded item's count in search results", function()
        local ns = recordedSample({ ["npc:101"] = at({ kind = "npc", id = 101, kills = 5, items = { [5555] = 3 } }) })
        ns.db.recorded.items = { [5555] = { "Thane's Seal", 3 } }
        ns.Recordings.Changed()
        local entries = ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "thane")
        assertEqual("3/5", entries[3].right)
    end)
end)
```

In `BossLoot/tests/lootrow_spec.lua` append:

```lua
describe("the rows around recorded loot", function()
    it("draws a heading with its note, no icon, and no clicks", function()
        local ns, env = helpers.loadAddon(FILES)
        local r = row(ns, env)
        ns.LootRow.Render(r, { heading = "Classic loot", note = "Not seen on WoW Forever yet" })
        assertMatch("Classic loot", r.name:GetText())
        assertEqual("Not seen on WoW Forever yet", r.detail:GetText())
        assertFalse(r.icon:IsShown())
        assertFalse(r.mouseEnabled)
        ns.LootRow.Render(r, { blank = true })
        assertEqual("", r.name:GetText())
    end)

    it("dims a classic row, and shows a recorded one's count", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__items[1001] = { name = "One", quality = 2 }
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 1001, chance = 20, classic = true })
        assertEqual(0.45, r.alpha)
        ns.LootRow.Render(r, { id = 1001, seen = "3/5" })
        assertEqual(1, r.alpha)
        assertEqual("3/5", r.chance:GetText())
        assertTrue(r.icon:IsShown())
        assertTrue(r.mouseEnabled)
    end)
end)
```

- [ ] **Step 2: Run them to see them fail**

Run: `lua tests/runner.lua tests/window_spec.lua` and `lua tests/runner.lua tests/lootrow_spec.lua`
Expected: the new and updated tests fail (no heading entries; no `seen`).

- [ ] **Step 3: Implement**

In `BossLoot/Window.lua`:

Add near the other constants:

```lua
-- Above the vanilla list, once recordings come first.
local CLASSIC_HEADING = "Classic loot"
local CLASSIC_NOTE = "Not seen on WoW Forever yet"
```

Replace `instanceEntry` with:

```lua
local function instanceEntry(instance, selectedKey)
    local text = instance.name
    if instance.levels then
        text = string.format("%s |cff808080%d-%d|r", instance.name, instance.levels[1], instance.levels[2])
    elseif instance.recorded then
        text = instance.name .. " |cff808080recorded|r"
    end
    return { kind = "instance", value = instance.key, selected = instance.key == selectedKey, text = text }
end
```

After `lootSource`, add:

```lua
-- The recorded loot of a boss or notable list, and for a boss its kills.
local function recordedSource(instance, selection)
    if not instance then
        return nil
    end
    if type(selection) == "number" then
        local boss = instance.bosses[selection]
        return boss and boss.recorded, boss and boss.recordedKills
    end
    return instance.recordedNotable and instance.recordedNotable[selection], nil
end

-- How often a recorded item was seen: of the kills for a boss, a count for
-- a notable list.
local function seenText(entry, kills)
    if kills then
        return entry[2] .. "/" .. kills
    end
    return "×" .. entry[2]
end
```

Because `placeEntry` comes before `lootSource` in the file, move `lootSource`, `recordedSource` and `seenText` up to just above `placeEntry`. Then replace the chance lookup in `placeEntry`:

```lua
    local right
    for _, entry in ipairs(list or {}) do
        if entry[1] == itemID then
            right = ns.Format.Chance(entry[2])
            break
        end
    end
    if not right then
        local recorded, kills = recordedSource(instance, source.boss)
        for _, entry in ipairs(recorded or {}) do
            if entry[1] == itemID then
                right = seenText(entry, kills)
                break
            end
        end
    end
```

and use `right = right or ""` in the returned entry (replacing `right = ns.Format.Chance(chance)`, and removing the old `local chance` loop).

In `Window.BossEntries`, replace the notable part with:

```lua
    local notable = instance.notable or {}
    local recordedNotable = instance.recordedNotable or {}
    local function has(which)
        return #(notable[which] or {}) > 0 or #(recordedNotable[which] or {}) > 0
    end
    if has("trash") or has("objects") then
        table.insert(entries, { kind = "heading", text = "Notable drops" })
        if has("trash") then
            table.insert(entries, {
                kind = "boss", value = "trash", text = NOTABLE_NAMES.trash, selected = selection == "trash",
                icon = ns.Portrait.ICONS.trash,
            })
        end
        if has("objects") then
            table.insert(entries, {
                kind = "boss", value = "objects", text = NOTABLE_NAMES.objects, selected = selection == "objects",
                icon = ns.Portrait.ICONS.objects,
            })
        end
    end
```

Replace `Window.LootEntries` with:

```lua
--- A boss's or notable list's loot: what was recorded, most seen first, with
-- how often; then, under a heading on a line of its own in a grid of
-- `perLine` columns, the vanilla list, dimmed, less what was recorded.
function Window.LootEntries(instance, selection, perLine)
    perLine = perLine or 2
    local entries = {}
    if not instance then
        return entries
    end

    local recorded, kills = recordedSource(instance, selection)
    local seen = {}
    for _, entry in ipairs(recorded or {}) do
        seen[entry[1]] = true
        table.insert(entries, {
            id = entry[1],
            seen = seenText(entry, kills),
            sources = #entry[3] > 0 and entry[3] or nil,
            selected = entry[1] == highlightItem,
        })
    end

    local classic = {}
    for _, entry in ipairs(lootSource(instance, selection) or {}) do
        if not seen[entry[1]] then
            table.insert(classic, {
                id = entry[1], chance = entry[2], sources = entry[3], classic = true,
                selected = entry[1] == highlightItem,
            })
        end
    end
    if #classic > 0 then
        while #entries % perLine ~= 0 do
            table.insert(entries, { blank = true })
        end
        table.insert(entries, { heading = CLASSIC_HEADING, note = CLASSIC_NOTE })
        while #entries % perLine ~= 0 do
            table.insert(entries, { blank = true })
        end
        for _, entry in ipairs(classic) do
            table.insert(entries, entry)
        end
    end
    return entries
end
```

Replace `validSelection`, and repair the selection in `Window.Current` to the first valid one:

```lua
local function validSelection(instance, selection)
    if type(selection) == "number" then
        return instance.bosses[selection] ~= nil
    end
    local list = lootSource(instance, selection)
    local recorded = recordedSource(instance, selection)
    return (list ~= nil and #list > 0) or (recorded ~= nil and #recorded > 0)
end

-- The first thing to show: the first boss, or failing one (a recorded
-- instance with no named boss), a notable list.
local function firstSelection(instance)
    for _, selection in ipairs({ 1, "trash", "objects" }) do
        if validSelection(instance, selection) then
            return selection
        end
    end
    return 1
end
```

and in `Window.Current`, change `view.boss = 1` inside `if instance and not validSelection(instance, view.boss) then` to `view.boss = firstSelection(instance)`. In `Window.SelectInstance`, change `view.boss = 1` to `view.boss = firstSelection(instance)`.

In `Window.Refresh`, change `local loot = Window.LootEntries(instance, selection)` to:

```lua
    local loot = Window.LootEntries(instance, selection, mapOpen and 1 or 2)
```

(`mapOpen` is computed just above; if the call comes first, move `local mapOpen = frame.fullMap:IsShown()` above it.)

In `BossLoot/LootRow.lua`, add `local CLASSIC_ALPHA = 0.45` near the constants, guard the tooltip with `if not (row.entry and row.entry.id and GameTooltip) then return end`, and start `LootRow.Render` with:

```lua
function LootRow.Render(row, entry)
    row.entry = entry
    row:SetAlpha(entry.classic and CLASSIC_ALPHA or 1)
    if entry.heading or entry.blank then
        row.link = nil
        row.icon:Hide()
        row.selectedTexture:Hide()
        row.name:SetText(entry.heading and ("|cffffd100" .. entry.heading .. "|r") or "")
        row.detail:SetText(entry.note or "")
        row.chance:SetText("")
        row:EnableMouse(false)
        return
    end
    row.icon:Show()
    row:EnableMouse(true)
```

and change `row.chance:SetText(ns.Format.Chance(entry.chance))` to:

```lua
    row.chance:SetText(entry.seen or ns.Format.Chance(entry.chance))
```

- [ ] **Step 4: Run them to see them pass**

Run: `lua tests/runner.lua tests/window_spec.lua` and `lua tests/runner.lua tests/lootrow_spec.lua` — Expected: all pass.
Run: `.\run-tests.ps1 BossLoot` — Expected: all pass.

- [ ] **Step 5: Install, update the README, and commit**

In `BossLoot/README.md`, add after the item paragraph:

```markdown
WoW Forever reworked dungeon loot, so BossLoot records what really drops as
you play: each boss's and mob's loot (with how many kills), chests, quest
rewards, merchant goods and what your professions make. A boss's recorded
drops come first, with how often they were seen (`3/5` is three drops in five
kills), and the vanilla list follows, dimmed, under "Classic loot". Instances
BossLoot does not know are listed once recorded, with the bosses the game
named. `/bl probe` checks the client has what the recorder needs; `/bl
recorded` counts what you have recorded. To bake recordings into a release,
put saved-variables files in `tools/recordings/` and rebuild the data.
```

Run (repo root, PowerShell): `.\package.ps1 BossLoot -Install`

```bash
git add BossLoot/Window.lua BossLoot/LootRow.lua BossLoot/README.md BossLoot/tests/window_spec.lua BossLoot/tests/lootrow_spec.lua
git commit -F - <<'EOF'
BossLoot: recorded loot first in the lists, the classic list dimmed below

A boss's recorded drops come first with how often they were seen (3/5),
notable finds with how many and who dropped them (×2); then "Classic loot",
on a line of its own, and the vanilla list less what was recorded, dimmed.
Recorded instances are listed in their tab, and open on their first list.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```
