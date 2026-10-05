// The two queries the build needs, over vMaNGOS's SQLite dump.
import { DatabaseSync } from 'node:sqlite';

// 1.12: the patch WoW Forever's world is closest to, as BossLoot builds it.
export const TARGET_PATCH = 10;
const P = TARGET_PATCH;

// creature_template.rank: 0 normal, 1 elite, 2 rare elite, 3 boss, 4 rare.
const RARE_ELITE = 2;
const RARE = 4;
// The two continents: Eastern Kingdoms and Kalimdor.
export const CONTINENTS = [0, 1];

const round = (value) => Math.round(value * 10) / 10;

export function openDb(source) {
  const db = typeof source === 'string' ? new DatabaseSync(source, { readOnly: true }) : source;

  return {
    // Templates carry one row per patch that changed them. The one in force
    // at the target patch is the newest not after it; only then is its rank
    // asked, so a rare made normal by 1.12 is not a rare.
    rares() {
      return db.prepare(`
        select entry, name, level_min, level_max, rank from creature_template t
        where t.patch = (select max(x.patch) from creature_template x where x.entry = t.entry and x.patch <= ${P})
          and t.rank in (${RARE_ELITE}, ${RARE})
        order by entry
      `).all().map((row) => ({
        entry: row.entry,
        name: row.name,
        minLevel: row.level_min,
        maxLevel: row.level_max,
        elite: row.rank === RARE_ELITE,
      }));
    },

    // Every spawn on the continents of these creatures, in world yards. A
    // spawn point can pick one of up to five creatures; each rare among them
    // counts.
    spawns(ids) {
      const wanted = new Set(ids);
      const out = [];
      const rows = db.prepare(`
        select guid, id, id2, id3, id4, id5, map, position_x, position_y from creature
        where map in (${CONTINENTS.join(', ')}) and patch_min <= ${P} and ${P} <= patch_max
      `).all();
      for (const row of rows) {
        const picks = new Set([row.id, row.id2, row.id3, row.id4, row.id5].filter((id) => wanted.has(id)));
        for (const entry of picks) {
          out.push({ guid: row.guid, entry, map: row.map, x: round(row.position_x), y: round(row.position_y) });
        }
      }
      out.sort((a, b) => a.map - b.map || a.entry - b.entry || a.guid - b.guid);
      return out.map(({ entry, map, x, y }) => ({ entry, map, x, y }));
    },
  };
}
