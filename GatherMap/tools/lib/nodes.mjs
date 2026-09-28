// Picking the gatherable objects out of vMaNGOS, and where each is spawned.

// vMaNGOS numbers its content patches 0 (1.2) to 10 (1.12), as BossLoot does.
export const TARGET_PATCH = 10;
export const CONTINENTS = [0, 1];

const P = TARGET_PATCH;
const CHEST = 3; // GAMEOBJECT_TYPE_CHEST: herbs, veins and chests alike
const FISHING_HOLE = 25;

const has = (object, key) => Object.prototype.hasOwnProperty.call(object, key);

// Every herb, vein, chest and pool, by entry, sorted by entry. A vein or
// deposit nodes.json has no skill for is an error, so a new ore can never
// ship unfiltered. Herbs have no such tell-tale name, and a missing one only
// goes unlisted.
export function catalog(db, lists) {
  const templates = db.prepare(`
    select entry, type, name, data1 from gameobject_template t
    where t.type in (${CHEST}, ${FISHING_HOLE})
      and t.patch = (select max(x.patch) from gameobject_template x where x.entry = t.entry and x.patch <= ${P})
    order by entry`).all();
  const mainItem = db.prepare(`
    select item from gameobject_loot_template
    where entry = ? and mincountOrRef > 0 and patch_min <= ${P} and ${P} <= patch_max
    order by ChanceOrQuestChance desc, item limit 1`);
  const chests = new Set(lists.chest);

  const nodes = [];
  const errors = [];
  for (const t of templates) {
    let node;
    if (t.type === FISHING_HOLE) node = { entry: t.entry, kind: 'pool', name: t.name };
    else if (has(lists.herb, t.name)) node = { entry: t.entry, kind: 'herb', name: t.name, skill: lists.herb[t.name] };
    else if (has(lists.ore, t.name)) node = { entry: t.entry, kind: 'ore', name: t.name, skill: lists.ore[t.name] };
    else if (chests.has(t.name)) node = { entry: t.entry, kind: 'chest', name: t.name };
    else {
      if (/ (Vein|Deposit)$/.test(t.name)) errors.push(`"${t.name}" (${t.entry}) looks like ore but nodes.json has no skill for it`);
      continue;
    }
    if (node.skill !== undefined && t.data1) {
      const row = mainItem.get(t.data1);
      if (row) node.item = row.item;
    }
    nodes.push(node);
  }
  return { nodes, errors };
}

const round1 = (value) => Math.round(value * 10) / 10;

// Every spawn of the catalog's objects on the two continents, in guid order.
export function spawns(db, nodes) {
  const wanted = new Set(nodes.map((node) => node.entry));
  const byContinent = new Map(CONTINENTS.map((continent) => [continent, []]));
  const rows = db.prepare(`
    select id, map, position_x as x, position_y as y from gameobject
    where map in (${CONTINENTS.join(', ')}) and patch_min <= ${P} and ${P} <= patch_max
    order by guid`).all();
  for (const row of rows) {
    if (wanted.has(row.id)) byContinent.get(row.map).push({ entry: row.id, x: round1(row.x), y: round1(row.y) });
  }
  return byContinent;
}
