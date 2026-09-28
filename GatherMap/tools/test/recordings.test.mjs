import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { readRecordings, applyRecordings, spawnKey, MIN_MISSING } from '../lib/recordings.mjs';
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

test('a spawn two recorders marked not here is dropped, unless someone gathered it', () => {
  assert.equal(MIN_MISSING, 2);
  const byContinent = world();
  const { dropped } = applyRecordings(byContinent, NODES, [
    { gathered: {}, missing: { '0:1731:-10008.9:878.7': 1, '0:1731:-10133.8:793.8': 1 } },
    {
      gathered: { '0:1731:-10133.8:793.8': { continent: 0, entry: 1731, x: -10133.8, y: 793.8, count: 1 } },
      missing: { '0:1731:-10008.9:878.7': 1 },
    },
  ]);
  assert.equal(dropped, 1);
  assert.deepEqual(byContinent.get(0).map((s) => s.x), [-10133.8]);
});

test('one recorder\'s mark alone keeps the spawn: someone else may just have gathered it', () => {
  const byContinent = world();
  const { dropped } = applyRecordings(byContinent, NODES, [
    { gathered: {}, missing: { '0:1731:-10008.9:878.7': 1 } },
    { gathered: {}, missing: {} },
  ]);
  assert.equal(dropped, 0);
  assert.equal(byContinent.get(0).length, 2);
});

test('a gathered key that is a spawn\'s own confirms that spawn, not an earlier one close by', () => {
  const byContinent = new Map([
    [0, [{ entry: 1731, x: -10100, y: 800 }, { entry: 1731, x: -10105, y: 800 }]],
    [1, []],
  ]);
  const { confirmed } = applyRecordings(byContinent, NODES, [
    { gathered: { '0:1731:-10105.0:800.0': { continent: 0, entry: 1731, x: -10105, y: 800, count: 1 } }, missing: {} },
  ]);
  assert.deepEqual(confirmed, ['0:1731:-10105.0:800.0']);
});

test('a gathered point off every spawn\'s key confirms the nearest within reach', () => {
  const byContinent = new Map([
    [0, [{ entry: 1731, x: -10100, y: 800 }, { entry: 1731, x: -10110, y: 800 }]],
    [1, []],
  ]);
  const { confirmed } = applyRecordings(byContinent, NODES, [
    { gathered: { '0:1731:-10108.0:800.0': { continent: 0, entry: 1731, x: -10108, y: 800, count: 1 } }, missing: {} },
  ]);
  assert.deepEqual(confirmed, ['0:1731:-10110.0:800.0']);
});

test('the confirmed file hands the keys to ns.AddConfirmed', () => {
  const text = confirmedFile(['0:1731:-10133.8:793.8']);
  assert.match(text, /ns\.AddConfirmed\(\{\n    "0:1731:-10133\.8:793\.8",\n\}\)/);
  assert.match(confirmedFile([]), /ns\.AddConfirmed\(\{\n\}\)/);
});

test('a pool point 25 yards from a known pool spawn confirms that spawn\'s key', () => {
  const byContinent = new Map([
    [0, [{ entry: 180582, x: -10620, y: 1170 }]],
    [1, []],
  ]);
  const { confirmed } = applyRecordings(byContinent, NODES, [
    { gathered: { '0:180582:-10600.0:1150.0': { continent: 0, entry: 180582, x: -10600, y: 1150, count: 1 } }, missing: {} },
  ]);
  assert.deepEqual(confirmed, ['0:180582:-10620.0:1170.0']);
});

test('a pool point with new: true 40 yards from any pool adds nothing and confirms nothing', () => {
  const byContinent = new Map([
    [0, [{ entry: 180582, x: -10620, y: 1170 }]],
    [1, []],
  ]);
  const { confirmed, added } = applyRecordings(byContinent, NODES, [
    { gathered: { '0:180582:-10550.0:1100.0': { continent: 0, entry: 180582, x: -10550, y: 1100, count: 1, new: true } }, missing: {} },
  ]);
  assert.equal(added, 0);
  assert.deepEqual(confirmed, []);
  assert.equal(byContinent.get(0).length, 1);
});
