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
// the explicit ones leave, equally. Only item rows join a group: a reference
// row always rolls on its own, and its groupid names which group of the
// referenced table it reads (vMaNGOS LootTemplate::AddEntry).
function rowChances(rows) {
  const chances = new Map();
  const groups = new Map();

  for (const row of rows) {
    if (row.groupid > 0 && row.mincountOrRef > 0) {
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
 * (negative mincountOrRef) is followed into reference_loot_template and rolled
 * maxcount times; each of its items gets the reference row's own chance times
 * its chance of coming up at least once in those rolls. An item reachable more
 * than one way keeps its best chance.
 *
 * skipItem(id) drops items written into the table itself, but not the same
 * item reached through a reference: vMaNGOS copies generic world loot straight
 * into some mobs' tables, while a boss's own pool may carry the same item
 * for real.
 *
 * Quest-only rows (negative chance) are left out, and so are conditional rows
 * (holiday items, quest-state drops) unless allowCondition(id) says the
 * condition is one every player meets one way or another -- a faction.
 */
export function resolveLoot(fetch, table, entry, options = {}, seen = new Set(), onlyGroup = 0) {
  const { skipRef = () => false, allowCondition = () => false, skipItem = () => false } = options;
  const loot = new Map();
  const direct = seen.size === 0;

  const rows = fetch(table, entry).filter(
    (row) => inPatch(row)
      && (row.condition_id === 0 || allowCondition(row.condition_id))
      && row.ChanceOrQuestChance >= 0
      && (!onlyGroup || row.groupid === onlyGroup),
  );

  for (const [row, percent] of rowChances(rows)) {
    if (percent <= 0) continue;

    if (row.mincountOrRef < 0) {
      const ref = -row.mincountOrRef;
      if (skipRef(ref) || seen.has(ref)) continue;

      const rolls = Math.max(1, row.maxcount ?? 1);
      const nested = resolveLoot(fetch, 'reference_loot_template', ref, options, new Set([...seen, ref]), row.groupid);
      for (const [item, itemPercent] of nested) {
        // One roll is kept as a plain product, which stays exact in floating
        // point; more rolls need the chance of at least one hit.
        const chance = rolls === 1
          ? (percent * itemPercent) / 100
          : percent * (1 - (1 - itemPercent / 100) ** rolls);
        keepMax(loot, item, chance);
      }
    } else if (!(direct && skipItem(row.item))) {
      keepMax(loot, row.item, percent);
    }
  }

  return loot;
}
