// The items the addon knows without asking the server: every item any
// instance lists. Most servers will not say what an item is when asked --
// WoW Forever refused thousands -- so the name, quality and kind of each
// ship with the addon, and the client supplies only the icon.

/** Every item the instances list, boss loot and notable drops, once each, in id order. */
export function itemIdsOf(instances) {
  const ids = new Set();
  for (const instance of instances) {
    for (const boss of instance.bosses) for (const entry of boss.loot) ids.add(entry.id);
    for (const which of ['trash', 'objects']) for (const entry of instance.notable[which]) ids.add(entry.id);
  }
  return [...ids].sort((a, b) => a - b);
}
