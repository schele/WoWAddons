// What counts as worth listing, and in what order.

// Below this, a drop off trash or out of a chest is a fluke, not a plan.
// Boss loot has no threshold: a 0.3% epic off a boss is worth knowing about.
export const NOTABLE_MIN_CHANCE = 0.5;

const RARE = 3;
const RECIPE_CLASS = 9;
const KEY_CLASS = 13;

// Rare and better gear, recipes, keys and quest starters.
export function isNotable(item) {
  if (!item) return false;
  return item.quality >= RARE
    || item.class === RECIPE_CLASS
    || item.class === KEY_CLASS
    || item.start_quest > 0;
}

// Everything a boss drops except grey vendor trash.
export function keepForBoss(item) {
  return Boolean(item) && item.quality > 0;
}

export function round(chance) {
  return Math.round(chance * 100) / 100;
}

// Best quality first, then likeliest, then by id so the output is stable
// from one build to the next. Anything that rounds to 0% is dropped: it
// cannot be told apart from never.
export function sortLoot(entries, itemOf) {
  const quality = (id) => itemOf(id)?.quality ?? 0;
  return entries
    .map((entry) => ({ ...entry, chance: round(entry.chance) }))
    .filter((entry) => entry.chance > 0)
    .sort((a, b) => quality(b.id) - quality(a.id) || b.chance - a.chance || a.id - b.id);
}
