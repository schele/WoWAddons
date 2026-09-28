// Gathers players recorded in WoW Forever, from saved-variables files put in
// tools/recordings/, baked into the release: the game is the authority,
// vMaNGOS only a first guess (BossLoot's lesson).
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { parseSavedVariables } from '../../../BossLoot/tools/lib/savedvars.mjs';

export const REACH = 15;
export const POOL_REACH = 30;
// A spawn is left out only when this many recorders marked it "not here":
// one mark often only means someone else had just gathered it.
export const MIN_MISSING = 2;

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
 * spawns marked "not here" by at least MIN_MISSING recorders and gathered by
 * no one leave. Returns the keys of every spawn someone gathered, sorted.
 */
export function applyRecordings(byContinent, nodes, recorders) {
  const known = new Set(nodes.map((node) => node.entry));
  const kindOf = new Map(nodes.map((node) => [node.entry, node.kind]));
  const gathered = new Set();
  // Per key, how many recorders marked it.
  const marks = new Map();
  for (const recorder of recorders) {
    for (const key of Object.keys(recorder.gathered)) gathered.add(key);
    for (const key of Object.keys(recorder.missing)) marks.set(key, (marks.get(key) ?? 0) + 1);
  }

  let dropped = 0;
  const byKey = new Map();
  for (const [continent, list] of byContinent) {
    const kept = list.filter((s) => {
      const key = spawnKey(continent, s.entry, s.x, s.y);
      return !((marks.get(key) ?? 0) >= MIN_MISSING && !gathered.has(key));
    });
    dropped += list.length - kept.length;
    byContinent.set(continent, kept);
    for (const s of kept) byKey.set(spawnKey(continent, s.entry, s.x, s.y), s);
  }

  const confirmed = new Set();
  let added = 0;
  for (const recorder of recorders) {
    for (const [key, point] of Object.entries(recorder.gathered)) {
      const list = byContinent.get(point?.continent);
      if (!list || !known.has(point.entry) || typeof point.x !== 'number' || typeof point.y !== 'number') continue;
      // The recorder matched this spawn itself: take its word.
      if (byKey.has(key)) {
        confirmed.add(key);
        continue;
      }
      const x = round1(point.x);
      const y = round1(point.y);
      const kind = kindOf.get(point.entry);
      const reach = kind === 'pool' ? POOL_REACH : REACH;
      let near;
      let nearest = Infinity;
      for (const s of list) {
        if (s.entry !== point.entry) continue;
        const distance = Math.hypot(s.x - x, s.y - y);
        if (distance <= reach && distance < nearest) {
          near = s;
          nearest = distance;
        }
      }
      if (near) {
        confirmed.add(spawnKey(point.continent, near.entry, near.x, near.y));
      } else if (point.new && kind !== 'pool') {
        const spawn = { entry: point.entry, x, y };
        const newKey = spawnKey(point.continent, point.entry, x, y);
        list.push(spawn);
        byKey.set(newKey, spawn);
        confirmed.add(newKey);
        added++;
      } else if (kind !== 'pool') {
        confirmed.add(key);
      }
    }
  }

  return { confirmed: [...confirmed].sort(), added, dropped };
}
