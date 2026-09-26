// World drops: the BoE items any mob of the right level can drop, anywhere.
// vMaNGOS keeps them in reference tables shared by mobs all over the world.
// Tables made for one instance are shared too, but within it -- and at most
// a couple of maps over (Ruins of Ahn'Qiraj shares with Silithus) -- so the
// line is drawn at four maps. Measured on the 2026-09-06 snapshot: instance
// tables span 1 to 3 maps, world-drop tables 4 to 16.
export const WORLD_MAP_THRESHOLD = 4;

export function worldRefs(db, threshold = WORLD_MAP_THRESHOLD) {
  const maps = new Map();
  for (const { ref, map } of db.refMaps()) {
    if (!maps.has(ref)) maps.set(ref, new Set());
    maps.get(ref).add(map);
  }
  return new Set([...maps].filter(([, set]) => set.size >= threshold).map(([ref]) => ref));
}
