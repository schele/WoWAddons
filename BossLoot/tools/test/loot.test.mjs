import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveLoot, inPatch } from '../lib/loot.mjs';

// A loot row with the defaults vMaNGOS uses for an ordinary drop.
const row = (item, chance, extra = {}) => ({
  item, ChanceOrQuestChance: chance, groupid: 0, mincountOrRef: 1, maxcount: 1,
  condition_id: 0, patch_min: 0, patch_max: 10, ...extra,
});

// fetch() over a plain object: { 'table:entry': [rows] }.
const fetcher = (tables) => (table, entry) => tables[`${table}:${entry}`] ?? [];

test('a plain row drops with its own chance', () => {
  const fetch = fetcher({ 'creature_loot_template:1': [row(100, 25)] });
  assert.deepEqual([...resolveLoot(fetch, 'creature_loot_template', 1)], [[100, 25]]);
});

test('grouped rows with chance 0 share what the explicit ones leave', () => {
  // Emperor Thaurissan's first group: Ironfoe at 1%, five more sharing 99%.
  const fetch = fetcher({
    'creature_loot_template:1': [
      row(11684, 1, { groupid: 1 }),
      ...[11815, 11930, 11931, 11933, 22204].map((id) => row(id, 0, { groupid: 1 })),
    ],
  });
  const loot = resolveLoot(fetch, 'creature_loot_template', 1);
  assert.equal(loot.get(11684), 1);
  assert.equal(loot.get(11815), 19.8);
});

test('a reference multiplies its items by its own chance', () => {
  const fetch = fetcher({
    'creature_loot_template:1': [row(0, 50, { mincountOrRef: -500 })],
    'reference_loot_template:500': [row(200, 10), row(201, 0, { groupid: 1 }), row(202, 0, { groupid: 1 })],
  });
  const loot = resolveLoot(fetch, 'creature_loot_template', 1);
  assert.equal(loot.get(200), 5);
  assert.equal(loot.get(201), 25);
  assert.equal(loot.get(202), 25);
});

test('a skipped reference contributes nothing', () => {
  const fetch = fetcher({
    'creature_loot_template:1': [row(0, 100, { mincountOrRef: -500 }), row(300, 10)],
    'reference_loot_template:500': [row(200, 10)],
  });
  const loot = resolveLoot(fetch, 'creature_loot_template', 1, { skipRef: (ref) => ref === 500 });
  assert.deepEqual([...loot.keys()], [300]);
});

test('quest-only and conditional rows are left out', () => {
  const fetch = fetcher({
    'creature_loot_template:1': [row(100, -80), row(101, 100, { condition_id: 110 }), row(102, 5)],
  });
  assert.deepEqual([...resolveLoot(fetch, 'creature_loot_template', 1).keys()], [102]);
});

test('a conditional row is kept when the caller allows its condition', () => {
  // Onyxia's tier 2 helms: one row per faction, each gated on the faction.
  const fetch = fetcher({
    'creature_loot_template:1': [row(100, 50, { condition_id: 2 }), row(101, 50, { condition_id: 110 })],
  });
  const loot = resolveLoot(fetch, 'creature_loot_template', 1, { allowCondition: (id) => id === 2 });
  assert.deepEqual([...loot.keys()], [100]);
});

test('rows outside the target patch are left out', () => {
  const fetch = fetcher({
    'creature_loot_template:1': [row(100, 5, { patch_max: 7 }), row(101, 5, { patch_min: 8 })],
  });
  assert.deepEqual([...resolveLoot(fetch, 'creature_loot_template', 1).keys()], [101]);
});

test('an item reachable twice keeps its best chance', () => {
  const fetch = fetcher({
    'creature_loot_template:1': [row(100, 5), row(0, 100, { mincountOrRef: -500 })],
    'reference_loot_template:500': [row(100, 30)],
  });
  assert.equal(resolveLoot(fetch, 'creature_loot_template', 1).get(100), 30);
});

test('a reference that loops back on itself is followed once', () => {
  const fetch = fetcher({
    'creature_loot_template:1': [row(0, 100, { mincountOrRef: -500 })],
    'reference_loot_template:500': [row(0, 100, { mincountOrRef: -500 }), row(100, 10)],
  });
  assert.equal(resolveLoot(fetch, 'creature_loot_template', 1).get(100), 10);
});

test('inPatch is inclusive at both ends', () => {
  assert.equal(inPatch({ patch_min: 10, patch_max: 10 }), true);
  assert.equal(inPatch({ patch_min: 0, patch_max: 9 }), false);
});

test('a reference row in a group rolls on its own, and reads only that group of the reference', () => {
  // Knot Thimblejack's Cache: ref 12006 sits in group 1 at 100% beside
  // patterns at 2% and at 0. vMaNGOS groups only item rows; the reference's
  // group number picks which group of the referenced table to roll.
  const fetch = fetcher({
    'gameobject_loot_template:1': [
      row(0, 100, { groupid: 1, mincountOrRef: -500 }),
      row(101, 2, { groupid: 1 }), row(102, 0, { groupid: 1 }), row(103, 0, { groupid: 1 }),
    ],
    'reference_loot_template:500': [
      row(200, 0, { groupid: 1 }), row(201, 0, { groupid: 1 }), row(300, 0, { groupid: 2 }),
    ],
  });
  const loot = resolveLoot(fetch, 'gameobject_loot_template', 1);
  assert.equal(loot.get(101), 2);
  assert.equal(loot.get(102), 49);
  assert.equal(loot.get(103), 49);
  assert.equal(loot.get(200), 50);
  assert.equal(loot.get(201), 50);
  assert.equal(loot.has(300), false);
});

test('a reference rolled maxcount times gives each item its chance of coming up at least once', () => {
  // Ragnaros's tier 2 legs: one pool of eight, rolled twice.
  const fetch = fetcher({
    'creature_loot_template:1': [row(0, 100, { mincountOrRef: -500, maxcount: 2 })],
    'reference_loot_template:500': [1, 2, 3, 4, 5, 6, 7, 8].map((id) => row(id, 0, { groupid: 1 })),
  });
  const loot = resolveLoot(fetch, 'creature_loot_template', 1);
  assert.ok(Math.abs(loot.get(1) - 23.4375) < 1e-9, `got ${loot.get(1)}`);
});

test('items written into a table directly can be skipped without touching the same item through a reference', () => {
  // Plans: Invulnerable Mail is in Goraluk's own pool, and also copied at
  // 0.02% into mobs all over the world.
  const fetch = fetcher({
    'creature_loot_template:1': [row(100, 0.02), row(101, 5), row(0, 100, { mincountOrRef: -500 })],
    'reference_loot_template:500': [row(100, 14.29)],
  });
  const loot = resolveLoot(fetch, 'creature_loot_template', 1, { skipItem: (id) => id === 100 || id === 101 });
  assert.equal(loot.get(100), 14.29, 'kept: it is in the reference');
  assert.equal(loot.has(101), false, 'skipped: only ever written in directly');
});
