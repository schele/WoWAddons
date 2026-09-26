// The handful of queries the build needs, over vMaNGOS's SQLite dump.
import { DatabaseSync } from 'node:sqlite';
import { TARGET_PATCH } from './loot.mjs';

const P = TARGET_PATCH;
const SPAWNED = `patch_min <= ${P} and ${P} <= patch_max`;

export function openDb(source) {
  const db = typeof source === 'string' ? new DatabaseSync(source, { readOnly: true }) : source;
  const statements = new Map();
  const prepare = (sql) => {
    if (!statements.has(sql)) statements.set(sql, db.prepare(sql));
    return statements.get(sql);
  };

  // Templates carry one row per patch that changed them. The one in force at
  // the target patch is the newest not after it.
  const latest = (table, where, ...args) => prepare(`
    select * from ${table} t
    where ${where}
      and t.patch = (select max(x.patch) from ${table} x where x.entry = t.entry and x.patch <= ${P})
  `).all(...args);

  return {
    lootRows: (table, entry) => prepare(`select * from ${table} where entry = ?`).all(entry),
    item: (entry) => latest('item_template', 't.entry = ?', entry)[0],
    creatureTemplate: (entry) => latest('creature_template', 't.entry = ?', entry)[0],
    creaturesNamed: (name) => latest('creature_template', 't.name = ?', name),
    objectTemplate: (entry) => latest('gameobject_template', 't.entry = ?', entry)[0],
    objectsNamed: (name) => latest('gameobject_template', 't.name = ?', name),

    // A spawn point can pick one of up to five creatures; all of them count.
    spawnedCreatures(map) {
      const ids = new Set();
      for (const row of prepare(`select id, id2, id3, id4, id5 from creature where map = ? and ${SPAWNED}`).all(map)) {
        for (const id of [row.id, row.id2, row.id3, row.id4, row.id5]) if (id) ids.add(id);
      }
      return ids;
    },

    spawnedObjects(map) {
      return new Set(prepare(`select distinct id from gameobject where map = ? and ${SPAWNED}`).all(map).map((r) => r.id));
    },

    // Every (reference, map) pair where a creature spawned on the map uses the
    // reference directly in its own loot table.
    refMaps() {
      return prepare(`
        select distinct -l.mincountOrRef as ref, c.map as map
        from creature_loot_template l
        join creature_template ct on ct.loot_id = l.entry
        join creature c on c.id = ct.entry
        where l.mincountOrRef < 0 and c.patch_min <= ${P} and ${P} <= c.patch_max
      `).all();
    },
  };
}
