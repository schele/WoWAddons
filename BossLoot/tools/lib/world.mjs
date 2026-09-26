// World drops: the BoE items any mob of the right level can drop, anywhere.
//
// vMaNGOS keeps them two ways: in reference tables shared by mobs all over
// the world, and copied straight into some rare mobs' own tables (Oggleflint
// in Ragefire Chasm carries the low-level world recipes and gems directly).
// So both references and items are judged by the same measure: where the
// mobs that carry them are spawned.
//
// World loot is carried on four or more maps, or on both continents.
// Measured on the 2026-09-06 snapshot: loot made for one instance spans 1 to
// 3 maps and at most one continent (Ruins of Ahn'Qiraj shares with Silithus,
// in Kalimdor), while world loot spans 4 to 16 maps -- except the low-level
// world loot, which Ragefire Chasm shares with Eastern Kingdoms and Kalimdor
// alone: three maps, but both continents.
export const WORLD_MAP_THRESHOLD = 4;

const EASTERN_KINGDOMS = 0;
const KALIMDOR = 1;

function addAll(map, key, values) {
  if (!map.has(key)) map.set(key, new Set());
  const set = map.get(key);
  for (const value of values) set.add(value);
}

export function worldLoot(db, threshold = WORLD_MAP_THRESHOLD) {
  // creature -> the maps it is spawned on
  const creatureMaps = new Map();
  for (const row of db.spawns()) {
    for (const id of [row.id, row.id2, row.id3, row.id4, row.id5]) {
      if (id) addAll(creatureMaps, id, [row.map]);
    }
  }

  // loot table -> the maps its creatures are spawned on
  const lootMaps = new Map();
  for (const creature of db.creatureLootIds()) {
    addAll(lootMaps, creature.loot_id, creatureMaps.get(creature.entry) ?? []);
  }

  const refMaps = new Map();
  const itemMaps = new Map();
  const carry = (links, mapsOf) => {
    for (const link of links) {
      const maps = mapsOf(link.entry);
      if (!maps || !maps.size) continue;
      if (link.mincountOrRef < 0) addAll(refMaps, -link.mincountOrRef, maps);
      else addAll(itemMaps, link.item, maps);
    }
  };

  carry(db.lootLinks('creature_loot_template'), (entry) => lootMaps.get(entry));

  // A reference's items, and any references nested in it, are carried
  // wherever the reference is. Twice covers the nesting vMaNGOS actually has.
  const referenceLinks = db.lootLinks('reference_loot_template');
  carry(referenceLinks, (entry) => refMaps.get(entry));
  carry(referenceLinks, (entry) => refMaps.get(entry));

  const isWorld = (set) => set.size >= threshold || (set.has(EASTERN_KINGDOMS) && set.has(KALIMDOR));
  const pick = (map) => new Set([...map].filter(([, set]) => isWorld(set)).map(([key]) => key));
  return { refs: pick(refMaps), items: pick(itemMaps) };
}
