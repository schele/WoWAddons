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
