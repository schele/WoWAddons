// One instance's data: its bosses' loot and its notable drops.
import { resolveLoot } from './loot.mjs';
import { isNotable, keepForBoss, sortLoot, NOTABLE_MIN_CHANCE } from './filters.mjs';

const CHEST = 3;
const MAX_SOURCES = 3;

export function keyFor(name) {
  return name
    .replace(/[^A-Za-z0-9 ]/g, '')
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => word[0].toUpperCase() + word.slice(1))
    .join('');
}

// instances.json allows a boss as a bare name, or as an object naming the
// creatures and chests its loot comes from. Wings flatten into bosses that
// remember their wing.
export function bossDefs(def) {
  const normalise = (boss, wing) => (typeof boss === 'string'
    ? { name: boss, wing, creatures: [boss], objects: [], ids: [] }
    : {
      name: boss.name,
      wing,
      creatures: boss.creatures ?? (boss.ids ? [] : [boss.name]),
      objects: boss.objects ?? [],
      ids: boss.ids ?? [],
    });

  if (def.wings) return def.wings.flatMap((wing) => wing.bosses.map((boss) => normalise(boss, wing.name)));
  return (def.bosses ?? []).map((boss) => normalise(boss, undefined));
}

// Prefer the templates spawned on this map: a name can belong to several
// creatures (event versions, look-alikes elsewhere). A boss a script
// summons is never spawned, so fall back to the templates with loot, and
// failing that to every template of the name -- a boss whose loot is all in
// a chest (Majordomo Executus) has none of its own. Only a name the
// database does not have at all comes back empty.
function pick(candidates, spawned, hasLoot) {
  const onMap = candidates.filter((c) => spawned.has(c.entry));
  if (onMap.length) return onMap;
  const withLoot = candidates.filter(hasLoot);
  return withLoot.length ? withLoot : candidates;
}

const NO_WORLD = { refs: new Set(), items: new Set() };

export function buildInstance(db, def, { world = NO_WORLD, cache = new Map() } = {}) {
  const errors = [];
  const warnings = [];
  const skipRef = (ref) => world.refs.has(ref);
  const factions = db.factionConditions();
  const allowCondition = (id) => factions.has(id);
  // World loot copied straight into a table; the same item in a boss's own
  // pool stays (see resolveLoot's skipItem).
  const skipItem = (id) => world.items.has(id);

  const items = new Map();
  const itemOf = (id) => {
    if (!items.has(id)) items.set(id, db.item(id) ?? null);
    return items.get(id);
  };

  // The same loot table is shared by many trash mobs; resolve each once.
  const loot = (table, entry) => {
    const key = `${table}:${entry}`;
    if (!cache.has(key)) cache.set(key, resolveLoot(db.lootRows, table, entry, { skipRef, allowCondition, skipItem }));
    return cache.get(key);
  };

  const spawnedCreatures = db.spawnedCreatures(def.map);
  const spawnedObjects = db.spawnedObjects(def.map);
  const claimedCreatures = new Set();
  const claimedObjects = new Set();

  const bosses = [];
  for (const boss of bossDefs(def)) {
    const found = new Map();
    const take = (table, entry) => {
      for (const [id, chance] of loot(table, entry)) {
        if (chance > (found.get(id) ?? 0)) found.set(id, chance);
      }
    };

    const creatures = boss.ids.map((id) => db.creatureTemplate(id)).filter(Boolean);
    for (const name of boss.creatures) {
      const matches = pick(db.creaturesNamed(name), spawnedCreatures, (c) => c.loot_id > 0);
      if (!matches.length) errors.push(`${def.name}: no creature named "${name}"`);
      creatures.push(...matches);
    }
    for (const creature of creatures) {
      claimedCreatures.add(creature.entry);
      if (creature.loot_id > 0) take('creature_loot_template', creature.loot_id);
    }

    for (const name of boss.objects) {
      const chests = db.objectsNamed(name).filter((o) => o.type === CHEST && o.data1 > 0);
      const matches = pick(chests, spawnedObjects, () => true);
      if (!matches.length) errors.push(`${def.name}: no chest named "${name}"`);
      for (const chest of matches) {
        claimedObjects.add(chest.entry);
        take('gameobject_loot_template', chest.data1);
      }
    }

    const entries = [...found]
      .filter(([id]) => keepForBoss(itemOf(id)))
      .map(([id, chance]) => ({ id, chance }));
    if (!entries.length) warnings.push(`${def.name}: ${boss.name} has no loot`);

    const out = { name: boss.name, loot: sortLoot(entries, itemOf) };
    if (boss.wing) out.wing = boss.wing;
    bosses.push(out);
  }

  const trashSources = [...spawnedCreatures]
    .filter((id) => !claimedCreatures.has(id))
    .map((id) => db.creatureTemplate(id))
    .filter((c) => c && c.loot_id > 0)
    .map((c) => ({ name: c.name, table: 'creature_loot_template', entry: c.loot_id }));

  const objectSources = [...spawnedObjects]
    .filter((id) => !claimedObjects.has(id))
    .map((id) => db.objectTemplate(id))
    .filter((o) => o && o.type === CHEST && o.data1 > 0)
    .map((o) => ({ name: o.name, table: 'gameobject_loot_template', entry: o.data1 }));

  const notable = (sources) => {
    const byItem = new Map();
    for (const source of sources) {
      for (const [id, chance] of loot(source.table, source.entry)) {
        if (chance < NOTABLE_MIN_CHANCE || !isNotable(itemOf(id))) continue;
        if (!byItem.has(id)) byItem.set(id, { id, chance: 0, sources: new Map() });
        const entry = byItem.get(id);
        entry.chance = Math.max(entry.chance, chance);
        entry.sources.set(source.name, Math.max(entry.sources.get(source.name) ?? 0, chance));
      }
    }
    return sortLoot([...byItem.values()].map((entry) => ({
      id: entry.id,
      chance: entry.chance,
      sources: [...entry.sources]
        .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
        .slice(0, MAX_SOURCES)
        .map(([name]) => name),
    })), itemOf);
  };

  return {
    instance: {
      key: def.key ?? keyFor(def.name),
      name: def.name,
      kind: def.kind,
      levels: def.levels,
      bosses,
      notable: { trash: notable(trashSources), objects: notable(objectSources) },
    },
    errors,
    warnings,
  };
}
