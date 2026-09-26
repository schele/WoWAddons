// Resolving vMaNGOS loot templates into "item, chance" pairs, following the
// emulator's own rules for plain rows, groups and references.

// vMaNGOS numbers its content patches 0 (1.2) to 10 (1.12). BossLoot shows
// the final vanilla patch.
export const TARGET_PATCH = 10;

export function inPatch(row, patch = TARGET_PATCH) {
  return row.patch_min <= patch && patch <= row.patch_max;
}

function keepMax(map, item, chance) {
  if (chance > (map.get(item) ?? 0)) map.set(item, chance);
}

// The chance, in percent, that each row is picked.
//
// A plain row (groupid 0) rolls on its own. In a group at most one row drops:
// rows with an explicit chance keep it, and rows with chance 0 share whatever
// the explicit ones leave, equally.
function rowChances(rows) {
  const chances = new Map();
  const groups = new Map();

  for (const row of rows) {
    if (row.groupid > 0) {
      if (!groups.has(row.groupid)) groups.set(row.groupid, []);
      groups.get(row.groupid).push(row);
    } else {
      chances.set(row, row.ChanceOrQuestChance);
    }
  }

  for (const members of groups.values()) {
    const explicit = members.filter((row) => row.ChanceOrQuestChance > 0);
    const equal = members.filter((row) => row.ChanceOrQuestChance === 0);
    const used = explicit.reduce((sum, row) => sum + row.ChanceOrQuestChance, 0);
    const share = equal.length ? Math.max(0, 100 - used) / equal.length : 0;

    for (const row of explicit) chances.set(row, row.ChanceOrQuestChance);
    for (const row of equal) chances.set(row, share);
  }

  return chances;
}

/**
 * Every item a loot table can produce, with its chance in percent.
 *
 * fetch(table, entry) returns the table's rows for that entry. A reference row
 * (negative mincountOrRef) is followed into reference_loot_template, and its
 * items' chances are scaled by the reference row's own chance. An item
 * reachable more than one way keeps its best chance.
 *
 * Quest-only rows (negative chance) are left out, and so are conditional rows
 * (holiday items, quest-state drops) unless allowCondition(id) says the
 * condition is one every player meets one way or another -- a faction.
 */
export function resolveLoot(fetch, table, entry, options = {}, scale = 100, seen = new Set()) {
  const { skipRef = () => false, allowCondition = () => false } = options;
  const loot = new Map();

  const rows = fetch(table, entry).filter(
    (row) => inPatch(row)
      && (row.condition_id === 0 || allowCondition(row.condition_id))
      && row.ChanceOrQuestChance >= 0,
  );

  for (const [row, percent] of rowChances(rows)) {
    const chance = (scale * percent) / 100;
    if (chance <= 0) continue;

    if (row.mincountOrRef < 0) {
      const ref = -row.mincountOrRef;
      if (skipRef(ref) || seen.has(ref)) continue;

      const nested = resolveLoot(fetch, 'reference_loot_template', ref, options, chance, new Set([...seen, ref]));
      for (const [item, itemChance] of nested) keepMax(loot, item, itemChance);
    } else {
      keepMax(loot, row.item, chance);
    }
  }

  return loot;
}
