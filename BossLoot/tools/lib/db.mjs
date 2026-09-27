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

    // The raw material for spotting world drops (see world.mjs): where every
    // creature is spawned, which loot table each uses, and what every loot
    // and reference table holds, in force at the target patch.
    spawns: () => prepare(`select id, id2, id3, id4, id5, map from creature where ${SPAWNED}`).all(),
    creatureLootIds: () => latest('creature_template', 't.loot_id > 0'),
    lootLinks: (table) => prepare(`select entry, item, mincountOrRef from ${table} where ${SPAWNED}`).all(),

    // What marks out an instance's floor: every spawn with how far it wanders
    // (discs), and every patrol in order (paths) -- per spawn, per creature
    // template, and scripted escorts.
    mapShapes(map) {
      const discs = [
        ...prepare(`select position_x as x, position_y as y, position_z as z, wander_distance as r from creature where map = ? and ${SPAWNED}`).all(map),
        ...prepare(`select position_x as x, position_y as y, position_z as z, 0 as r from gameobject where map = ? and ${SPAWNED}`).all(map),
      ];

      // A dump without one of the patrol tables still has the others.
      const rows = (sql) => {
        try {
          return prepare(sql).all(map);
        } catch {
          return [];
        }
      };
      const onMap = `(select id from creature where map = ? and ${SPAWNED})`;
      const paths = [];
      const group = (points) => {
        let current;
        let key;
        for (const point of points) {
          if (!current || point.path !== key) {
            current = [];
            paths.push(current);
            key = point.path;
          }
          current.push({ x: point.x, y: point.y, z: point.z });
        }
      };
      group(rows(`
        select m.id as path, m.position_x as x, m.position_y as y, m.position_z as z
        from creature_movement m join creature c on c.guid = m.id
        where c.map = ? and c.patch_min <= ${P} and ${P} <= c.patch_max
        order by m.id, m.point`));
      group(rows(`
        select t.entry as path, t.position_x as x, t.position_y as y, t.position_z as z
        from creature_movement_template t where t.entry in ${onMap}
        order by t.entry, t.point`));
      group(rows(`
        select s.entry as path, s.location_x as x, s.location_y as y, s.location_z as z
        from script_waypoint s where s.entry in ${onMap}
        order by s.entry, s.pointid`));

      return { discs, paths };
    },
    // Where anything by this name -- creature or object -- is spawned on a
    // map: the anchors a summoned boss is pinned beside.
    namedSpawns(name, map) {
      return [
        ...prepare(`select c.position_x as x, c.position_y as y, c.position_z as z
          from creature c join creature_template t on t.entry = c.id
          where t.name = ? and c.map = ? and c.patch_min <= ${P} and ${P} <= c.patch_max`).all(name, map),
        ...prepare(`select g.position_x as x, g.position_y as y, g.position_z as z
          from gameobject g join gameobject_template t on t.entry = g.id
          where t.name = ? and g.map = ? and g.patch_min <= ${P} and ${P} <= g.patch_max`).all(name, map),
      ];
    },

    // Where a script summons one of these creatures (command 10 in any of
    // the *_scripts tables), for bosses that are never spawned.
    summonPoint(entries) {
      if (!this.scriptTables) {
        this.scriptTables = db.prepare("select name from sqlite_master where type = 'table' and name like '%scripts'")
          .all().map((row) => row.name)
          .filter((table) => {
            const columns = db.prepare(`pragma table_info(${table})`).all().map((c) => c.name);
            return ['command', 'datalong', 'x', 'y'].every((c) => columns.includes(c));
          });
      }
      for (const table of this.scriptTables) {
        for (const entry of entries) {
          const point = prepare(`select x, y, z from ${table} where command = 10 and datalong = ? limit 1`).get(entry);
          if (point) return point;
        }
      }
      return undefined;
    },

    // Where the game drops a player entering the instance.
    entrance(map) {
      try {
        return prepare(`select target_position_x as x, target_position_y as y, target_position_z as z
          from areatrigger_teleport where target_map = ? and patch <= ${P}
          order by (name like '%Entrance%') desc, id limit 1`).get(map);
      } catch {
        return undefined;
      }
    },

    creatureSpawn: (entry, map) => prepare(`select position_x as x, position_y as y, position_z as z from creature where id = ? and map = ? and ${SPAWNED} order by guid limit 1`).get(entry, map),
    objectSpawn: (entry, map) => prepare(`select position_x as x, position_y as y, position_z as z from gameobject where id = ? and map = ? and ${SPAWNED} order by guid limit 1`).get(entry, map),

    // Conditions that only ask which faction the looter is on. Every player
    // is on one, and the rows gated on them lead to the same items (Onyxia's
    // tier 2 helms come as a Horde row and an Alliance row).
    factionConditions() {
      try {
        return new Set(prepare('select condition_entry from conditions where type = 6').all().map((r) => r.condition_entry));
      } catch {
        return new Set();
      }
    },
  };
}
