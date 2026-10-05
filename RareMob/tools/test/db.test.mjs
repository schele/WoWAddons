import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fixtureDb } from './fixture.mjs';
import { openDb } from '../lib/db.mjs';

function sample() {
  const { db, add } = fixtureDb();
  add('creature_template', { entry: 462, name: 'Vultros', level_min: 26, level_max: 26, rank: 4 });
  add('creature_template', { entry: 1, name: 'Elite Rare', level_min: 40, level_max: 42, rank: 2 });
  add('creature_template', { entry: 2, name: 'Normal Mob', rank: 0 });
  add('creature_template', { entry: 3, name: 'Elite Mob', rank: 1 });
  add('creature_template', { entry: 4, name: 'A Boss', rank: 3 });
  // A rare only from a later patch than 1.12: not yet.
  add('creature_template', { entry: 5, patch: 11, name: 'Later Rare', rank: 4 });
  // Rare at first, made normal by patch 5: the row in force at 1.12 wins.
  add('creature_template', { entry: 6, patch: 0, name: 'Demoted', rank: 4 });
  add('creature_template', { entry: 6, patch: 5, name: 'Demoted', rank: 0 });
  // Normal at first, rare from patch 3.
  add('creature_template', { entry: 7, patch: 0, name: 'Promoted Old', rank: 0 });
  add('creature_template', { entry: 7, patch: 3, name: 'Promoted', level_min: 30, level_max: 30, rank: 4 });
  return { db: openDb(db), add };
}

test('keeps rares and rare elites, as of 1.12', () => {
  const { db } = sample();
  assert.deepEqual(db.rares(), [
    { entry: 1, name: 'Elite Rare', minLevel: 40, maxLevel: 42, elite: true },
    { entry: 7, name: 'Promoted', minLevel: 30, maxLevel: 30, elite: false },
    { entry: 462, name: 'Vultros', minLevel: 26, maxLevel: 26, elite: false },
  ]);
});

test('spawns: the rares on the two continents, in patch, rounded to a tenth of a yard', () => {
  const { db, add } = sample();
  add('creature', { guid: 10, id: 462, map: 0, position_x: -10603.84, position_y: 1154.06 });
  add('creature', { guid: 11, id: 462, map: 1, position_x: 100.04, position_y: -200.06 });
  add('creature', { guid: 12, id: 462, map: 36, position_x: 5, position_y: 5 }); // a dungeon
  add('creature', { guid: 13, id: 462, map: 0, patch_min: 0, patch_max: 4 }); // gone by 1.12
  add('creature', { guid: 14, id: 2, map: 0 }); // not a rare
  add('creature', { guid: 15, id: 2, id2: 1, map: 0, position_x: 1, position_y: 2 }); // a rare as the spawn's second pick
  add('creature', { guid: 9, id: 1, map: 0, position_x: 3, position_y: 4 });
  const ids = db.rares().map((rare) => rare.entry);
  assert.deepEqual(db.spawns(ids), [
    { entry: 1, map: 0, x: 3, y: 4 },
    { entry: 1, map: 0, x: 1, y: 2 },
    { entry: 462, map: 0, x: -10603.8, y: 1154.1 },
    { entry: 462, map: 1, x: 100, y: -200.1 },
  ]);
});
