// Regenerates RareMob/Data/Rares.lua and Data/Spawns*.lua from vMaNGOS's
// world database.
//
//   node RareMob/tools/build-data.mjs <path to mangos.sqlite>
//
// The database comes from the db_latest release on github.com/vmangos/core
// (db-sqlite-<commit>.zip). Neither it nor this script ships in the addon.
// Data/Recorded.lua is the bake's (tools/bake-recordings.mjs), left alone.
import { writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDb } from './lib/db.mjs';
import { raresFile, spawnsFile } from './lib/lua.mjs';
import { recordedFile } from './lib/recordings.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = join(here, '..', 'Data');

const FILES = { 0: 'SpawnsEasternKingdoms.lua', 1: 'SpawnsKalimdor.lua' };

const dbPath = process.argv[2];
if (!dbPath) {
  console.error('usage: node RareMob/tools/build-data.mjs <path to mangos.sqlite>');
  process.exit(2);
}

const db = openDb(dbPath);
const rares = db.rares();
const spawns = db.spawns(rares.map((rare) => rare.entry));

// An empty result means the schema moved, not that the world has no rares.
if (!rares.length || !spawns.length) {
  console.error(`error: ${rares.length} rares and ${spawns.length} spawns found; the database is not what this script expects.`);
  process.exit(1);
}

mkdirSync(dataDir, { recursive: true });
writeFileSync(join(dataDir, 'Rares.lua'), raresFile(rares));
for (const [continent, file] of Object.entries(FILES)) {
  const mine = spawns.filter((spawn) => spawn.map === Number(continent));
  if (!mine.length) {
    console.error(`error: no spawns on continent ${continent}.`);
    process.exit(1);
  }
  writeFileSync(join(dataDir, file), spawnsFile(continent, mine));
  console.log(`ok    ${file}: ${mine.length} spawns`);
}
if (!existsSync(join(dataDir, 'Recorded.lua'))) {
  writeFileSync(join(dataDir, 'Recorded.lua'), recordedFile([]));
}

const spawned = new Set(spawns.map((spawn) => spawn.entry)).size;
console.log(`ok    ${rares.length} rares (${rares.filter((rare) => rare.elite).length} elite), ${spawned} of them spawned on the continents.`);
