import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fixtureDb } from './fixture.mjs';
import { openDb } from '../lib/db.mjs';
import { worldLoot } from '../lib/world.mjs';
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

test('a boss whose loot is all in a chest is not an error, spawned or not', () => {
  // Majordomo Executus: summoned by script, no loot of his own, and his
  // Cache of the Firelord holds it all.
  const { db, add } = world();
  add('creature_template', { entry: 5, name: 'Chest Boss', loot_id: 0 });
  const { instance, errors } = buildInstance(openDb(db), { ...def, bosses: [{ name: 'Chest Boss', objects: ['Old Chest'] }] });
  assert.deepEqual(errors, []);
  assert.equal(instance.bosses[0].loot[0].id, 104);
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
  const found = worldLoot(dbx);
  assert.deepEqual([...found.refs], [900]);
  const { instance } = buildInstance(dbx, def, { world: found });
  assert.ok(!instance.bosses[0].loot.some((e) => e.id === 105));
});

test('an item copied straight into mobs on both continents is a world drop', () => {
  // vMaNGOS writes the generic world loot directly into some rare mobs'
  // tables (Oggleflint's gems and recipes), so no shared table gives it away.
  const { db, add } = world();
  add('creature_loot_template', { entry: 1, item: 105, ChanceOrQuestChance: 1 });
  for (const [entry, map] of [[10, 0], [11, 1]]) {
    add('creature_template', { entry, name: `Mob ${entry}`, loot_id: entry });
    add('creature', { id: entry, map });
    add('creature_loot_template', { entry, item: 105, ChanceOrQuestChance: 1 });
  }
  const dbx = openDb(db);
  const found = worldLoot(dbx);
  assert.ok(found.items.has(105));
  const { instance } = buildInstance(dbx, def, { world: found });
  assert.ok(!instance.bosses[0].loot.some((e) => e.id === 105));
});

test("a boss's own pool keeps an item that is copied into world mobs elsewhere", () => {
  // Goraluk Anvilcrack's Plans: Invulnerable Mail, 14% from his own pool,
  // 0.02% from mobs on nine maps.
  const { db, add } = world();
  add('creature_loot_template', { entry: 1, item: 0, ChanceOrQuestChance: 100, mincountOrRef: -903 });
  add('reference_loot_template', { entry: 903, item: 105, ChanceOrQuestChance: 14 });
  for (const [entry, map] of [[10, 0], [11, 1]]) {
    add('creature_template', { entry, name: `Mob ${entry}`, loot_id: entry });
    add('creature', { id: entry, map });
    add('creature_loot_template', { entry, item: 105, ChanceOrQuestChance: 0.02 });
  }
  const dbx = openDb(db);
  const found = worldLoot(dbx);
  assert.ok(found.items.has(105), 'a world drop by the per-item measure');
  const { instance } = buildInstance(dbx, def, { world: found });
  assert.ok(instance.bosses[0].loot.some((e) => e.id === 105 && e.chance === 14));
});

test('rows gated only on faction are kept; other conditions are not', () => {
  const { db, add } = world();
  add('conditions', { condition_entry: 2, type: 6, value1: 67 });
  add('conditions', { condition_entry: 110, type: 12, value1: 2 });
  add('creature_loot_template', { entry: 1, item: 104, ChanceOrQuestChance: 30, condition_id: 2 });
  add('creature_loot_template', { entry: 1, item: 105, ChanceOrQuestChance: 30, condition_id: 110 });
  const { instance } = buildInstance(openDb(db), def);
  const ids = instance.bosses[0].loot.map((e) => e.id);
  assert.ok(ids.includes(104), 'faction row kept');
  assert.ok(!ids.includes(105), 'holiday row left out');
});

test('a reference used on both continents is a world drop, however few maps', () => {
  // Low-level world recipes and gems: shared by mobs in Eastern Kingdoms,
  // Kalimdor and one instance, which is only three maps.
  const { db, add } = world();
  add('creature_loot_template', { entry: 1, item: 0, ChanceOrQuestChance: 100, mincountOrRef: -901 });
  for (const [entry, map] of [[10, 0], [11, 1]]) {
    add('creature_template', { entry, name: `Mob ${entry}`, loot_id: entry });
    add('creature', { id: entry, map });
    add('creature_loot_template', { entry, item: 0, ChanceOrQuestChance: 100, mincountOrRef: -901 });
  }
  assert.deepEqual([...worldLoot(openDb(db)).refs], [901]);
});

test('a reference shared by an instance and one continent is not a world drop', () => {
  // Ruins of Ahn'Qiraj shares tables with Silithus, in Kalimdor.
  const { db, add } = world();
  add('creature_loot_template', { entry: 1, item: 0, ChanceOrQuestChance: 100, mincountOrRef: -902 });
  add('creature_template', { entry: 11, name: 'Silithus Mob', loot_id: 11 });
  add('creature', { id: 11, map: 1 });
  add('creature_loot_template', { entry: 11, item: 0, ChanceOrQuestChance: 100, mincountOrRef: -902 });
  assert.deepEqual([...worldLoot(openDb(db)).refs], []);
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

test('a boss far outside the drawn map gets no pin, and the build says so', () => {
  const { db, add } = world();
  for (let i = 0; i < 150; i++) add('creature', { id: 2, map: MAP, position_x: i % 15, position_y: 0 });
  db.exec('update creature set position_x = 1000 where id = 1');
  const { instance, warnings } = buildInstance(openDb(db), def);
  assert.equal(instance.bosses[0].pin, undefined);
  assert.ok(warnings.some((w) => w.includes('Boss One') && w.includes('outside the map')), warnings.join('; '));
});
