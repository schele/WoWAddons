// Gathers players recorded in WoW Forever, from saved-variables files put in
// tools/recordings/, baked into the release: the game is the authority,
// vMaNGOS only a first guess (BossLoot's lesson).
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { parseSavedVariables } from '../../../BossLoot/tools/lib/savedvars.mjs';

export const REACH = 15;

const round1 = (value) => Math.round(value * 10) / 10;

// The same key as the addon's Spawns.Key: "%d:%d:%.1f:%.1f".
export function spawnKey(continent, entry, x, y) {
  return `${continent}:${entry}:${x.toFixed(1)}:${y.toFixed(1)}`;
}

/** Each file's GatherMapDB, in file-name order. */
export function readRecordings(dir) {
  if (!existsSync(dir)) return { recorders: [], warnings: [] };
  const recorders = [];
  const warnings = [];
  for (const file of readdirSync(dir).filter((name) => name.endsWith('.lua')).sort()) {
    let vars;
    try {
      vars = parseSavedVariables(readFileSync(join(dir, file), 'utf8'));
    } catch (error) {
      warnings.push(`${file}: ${error.message}`);
      continue;
    }
    const db = vars.GatherMapDB;
    if (!db || typeof db !== 'object') {
      warnings.push(`${file}: no GatherMap recordings`);
      continue;
    }
    recorders.push({ file, gathered: db.gathered ?? {}, missing: db.missing ?? {} });
  }
  return { recorders, warnings };
}

/**
 * Fold the recordings into the database's spawns, in place: new points join,
 * spawns marked "not here" by someone and gathered by no one leave. Returns
 * the keys of every spawn someone gathered, sorted.
 */
export function applyRecordings(byContinent, nodes, recorders) {
  const known = new Set(nodes.map((node) => node.entry));
  const gathered = new Set();
  const missing = new Set();
  for (const recorder of recorders) {
    for (const key of Object.keys(recorder.gathered)) gathered.add(key);
    for (const key of Object.keys(recorder.missing)) missing.add(key);
  }

  let dropped = 0;
  for (const [continent, list] of byContinent) {
    const kept = list.filter((s) => {
      const key = spawnKey(continent, s.entry, s.x, s.y);
      return !(missing.has(key) && !gathered.has(key));
    });
    dropped += list.length - kept.length;
    byContinent.set(continent, kept);
  }

  const confirmed = new Set();
  let added = 0;
  for (const recorder of recorders) {
    for (const [key, point] of Object.entries(recorder.gathered)) {
      const list = byContinent.get(point?.continent);
      if (!list || !known.has(point.entry) || typeof point.x !== 'number' || typeof point.y !== 'number') continue;
      const x = round1(point.x);
      const y = round1(point.y);
      const near = list.find((s) => s.entry === point.entry && Math.hypot(s.x - x, s.y - y) <= REACH);
      if (near) {
        confirmed.add(spawnKey(point.continent, near.entry, near.x, near.y));
      } else if (point.new) {
        list.push({ entry: point.entry, x, y });
        confirmed.add(spawnKey(point.continent, point.entry, x, y));
        added++;
      } else {
        confirmed.add(key);
      }
    }
  }

  return { confirmed: [...confirmed].sort(), added, dropped };
}
