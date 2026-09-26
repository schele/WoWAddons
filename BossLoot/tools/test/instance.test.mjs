import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fixtureDb } from './fixture.mjs';
import { openDb } from '../lib/db.mjs';
import { worldRefs } from '../lib/world.mjs';
import { buildInstance, bossDefs, keyFor } from '../lib/instance.mjs';

const MAP = 230;

// A small instance: one boss, one trash mob, one chest; items of each kind.
function world() {
  const { db, add } = fixtureDb();
  add('creature_template', { entry: 1, name: 'Boss One', loot_id: 1 });
  add('creature_template', { entry: 2, name: 'Trash Mob', loot_id: 2 });
  add('creature', { id: 1, map: MAP });
  add('creature', { id: 2, map: MAP });
  add('gameobject_template', { entry: 50, type: 3, name: 'Old Chest', data1: 50 });
  add('gameobject', { id: 50, map: MAP });

  add('item_template', { entry: 100, name: 'Epic Blade', quality: 4 });
  add('item_template', { entry: 101, name: 'Grey Junk', quality: 0 });
  add('item_template', { entry: 102, name: 'Green Boots', quality: 2 });
  add('item_template', { entry: 103, name: 'Recipe: Thing', quality: 2, class: 9 });
  add('item_template', { entry: 104, name: 'Rare Ring', quality: 3 });
  add('item_template', { entry: 105, name: 'World Epic', quality: 4 });

  add('creature_loot_template', { entry: 1, item: 100, ChanceOrQuestChance: 0.3 });
  add('creature_loot_template', { entry: 1, item: 101, ChanceOrQuestChance: 50 });
  add('creature_loot_template', { entry: 1, item: 102, ChanceOrQuestChance: 20 });
  add('creature_loot_template', { entry: 2, item: 103, ChanceOrQuestChance: 2 });
  add('creature_loot_template', { entry: 2, item: 104, ChanceOrQuestChance: 0.2 });
  add('creature_loot_template', { entry: 2, item: 102, ChanceOrQuestChance: 5 });
  add('gameobject_loot_template', { entry: 50, item: 104, ChanceOrQuestChance: 40 });
  return { db, add };
}

const def = { name: 'Test Depths', map: MAP, kind: 'dungeon', levels: [52, 60], bosses: ['Boss One'] };

test('a boss keeps everything but grey items, however unlikely', () => {
  const { db } = world();
  const { instance, errors } = buildInstance(openDb(db), def);
  assert.deepEqual(errors, []);
  assert.deepEqual(instance.bosses[0].loot, [{ id: 100, chance: 0.3 }, { id: 102, chance: 20 }]);
});

test('trash keeps only notable items at half a percent or better, with who drops them', () => {
  const { db } = world();
  const { instance } = buildInstance(openDb(db), def);
  assert.deepEqual(instance.notable.trash, [{ id: 103, chance: 2, sources: ['Trash Mob'] }]);
});

test('chests on the map are read for notable items', () => {
  const { db } = world();
  const { instance } = buildInstance(openDb(db), def);
  assert.deepEqual(instance.notable.objects, [{ id: 104, chance: 40, sources: ['Old Chest'] }]);
});

test('a boss named for a chest reads the chest, and the chest leaves the notable list', () => {
  const { db } = world();
  const withChest = { ...def, bosses: [{ name: 'Boss One', objects: ['Old Chest'] }] };
  const { instance } = buildInstance(openDb(db), withChest);
  assert.ok(instance.bosses[0].loot.some((e) => e.id === 104));
  assert.deepEqual(instance.notable.objects, []);
});

test('a boss the database does not have is an error naming it', () => {
  const { db } = world();
  const { errors } = buildInstance(openDb(db), { ...def, bosses: ['Boss Onne'] });
  assert.deepEqual(errors, ['Test Depths: no creature named "Boss Onne"']);
});

test('a boss summoned by script, never spawned, is still found by name', () => {
  const { db, add } = world();
  add('creature_template', { entry: 3, name: 'Summoned Boss', loot_id: 3 });
  add('creature_loot_template', { entry: 3, item: 100, ChanceOrQuestChance: 10 });
  const { instance, errors } = buildInstance(openDb(db), { ...def, bosses: ['Summoned Boss'] });
  assert.deepEqual(errors, []);
  assert.equal(instance.bosses[0].loot[0].id, 100);
});

test('a reference shared across four maps is a world drop and is left out', () => {
  const { db, add } = world();
  add('creature_loot_template', { entry: 1, item: 0, ChanceOrQuestChance: 100, mincountOrRef: -900 });
  add('reference_loot_template', { entry: 900, item: 105, ChanceOrQuestChance: 5 });
  // Three more maps whose mobs use the same reference.
  for (const [entry, map] of [[10, 0], [11, 1], [12, 309]]) {
    add('creature_template', { entry, name: `Mob ${entry}`, loot_id: entry });
    add('creature', { id: entry, map });
    add('creature_loot_template', { entry, item: 0, ChanceOrQuestChance: 100, mincountOrRef: -900 });
  }
  const dbx = openDb(db);
  const refs = worldRefs(dbx);
  assert.deepEqual([...refs], [900]);
  const { instance } = buildInstance(dbx, def, { worldRefs: refs });
  assert.ok(!instance.bosses[0].loot.some((e) => e.id === 105));
});

test('spawns and templates outside the target patch are ignored', () => {
  const { db, add } = world();
  add('creature_template', { entry: 4, name: 'Late Mob', loot_id: 4 });
  add('creature', { id: 4, map: MAP, patch_min: 0, patch_max: 5 });
  add('creature_loot_template', { entry: 4, item: 104, ChanceOrQuestChance: 50 });
  const { instance } = buildInstance(openDb(db), def);
  assert.ok(!instance.notable.trash.some((e) => e.id === 104));
});

test('wings flatten into bosses that carry their wing', () => {
  const bosses = bossDefs({ wings: [{ name: 'East', bosses: ['A'] }, { name: 'West', bosses: [{ name: 'B', creatures: ['B1', 'B2'] }] }] });
  assert.deepEqual(bosses.map((b) => [b.name, b.wing, b.creatures]), [['A', 'East', ['A']], ['B', 'West', ['B1', 'B2']]]);
});

test('keys are the name without punctuation', () => {
  assert.equal(keyFor("Ahn'Qiraj Temple"), 'AhnQirajTemple');
  assert.equal(keyFor('Blackrock Depths'), 'BlackrockDepths');
});
