import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isNotable, keepForBoss, round, sortLoot, NOTABLE_MIN_CHANCE } from '../lib/filters.mjs';

const item = (fields) => ({ entry: 1, name: 'x', quality: 1, class: 0, start_quest: 0, ...fields });

test('rare, epic and legendary items are notable', () => {
  assert.equal(isNotable(item({ quality: 3 })), true);
  assert.equal(isNotable(item({ quality: 4 })), true);
  assert.equal(isNotable(item({ quality: 5 })), true);
  assert.equal(isNotable(item({ quality: 2 })), false);
});

test('recipes, keys and quest starters are notable whatever their quality', () => {
  assert.equal(isNotable(item({ class: 9 })), true);
  assert.equal(isNotable(item({ class: 13 })), true);
  assert.equal(isNotable(item({ start_quest: 4241 })), true);
});

test('an unknown item is never notable and never kept', () => {
  assert.equal(isNotable(undefined), false);
  assert.equal(keepForBoss(undefined), false);
});

test('boss loot keeps everything but grey items', () => {
  assert.equal(keepForBoss(item({ quality: 0 })), false);
  assert.equal(keepForBoss(item({ quality: 1 })), true);
});

test('the notable threshold is half a percent', () => {
  assert.equal(NOTABLE_MIN_CHANCE, 0.5);
});

test('chances round to two decimals', () => {
  assert.equal(round(19.799999999), 19.8);
  assert.equal(round(0.004), 0);
});

test('loot sorts by quality, then chance, then id', () => {
  const qualities = { 1: 3, 2: 4, 3: 3, 4: 3 };
  const itemOf = (id) => item({ entry: id, quality: qualities[id] });
  const sorted = sortLoot(
    [{ id: 1, chance: 5 }, { id: 2, chance: 1 }, { id: 3, chance: 20 }, { id: 4, chance: 5 }],
    itemOf,
  );
  assert.deepEqual(sorted.map((e) => e.id), [2, 3, 1, 4]);
});

test('an entry that rounds to nothing is dropped', () => {
  const itemOf = (id) => item({ entry: id });
  assert.deepEqual(sortLoot([{ id: 1, chance: 0.004 }, { id: 2, chance: 3 }], itemOf).map((e) => e.id), [2]);
});
