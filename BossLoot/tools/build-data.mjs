// Regenerates BossLoot/Data/ from vMaNGOS's world database and
// tools/instances.json.
//
//   node BossLoot/tools/build-data.mjs <path to mangos.sqlite>
//
// The database comes from the db_latest release on github.com/vmangos/core
// (db-sqlite-<commit>.zip). Neither it nor this script ships in the addon.
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDb } from './lib/db.mjs';
import { worldLoot } from './lib/world.mjs';
import { buildInstance } from './lib/instance.mjs';
import { instanceFile, itemsFile, updateToc } from './lib/lua.mjs';
import { itemIdsOf } from './lib/items.mjs';
import { readRecordings, recordedFile } from './lib/recordings.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const addon = join(here, '..');

const dbPath = process.argv[2];
if (!dbPath) {
  console.error('usage: node BossLoot/tools/build-data.mjs <path to mangos.sqlite>');
  process.exit(2);
}

const config = JSON.parse(readFileSync(join(here, 'instances.json'), 'utf8'));
const db = openDb(dbPath);
const world = worldLoot(db);
const cache = new Map();

const dataDir = join(addon, 'Data');
rmSync(dataDir, { recursive: true, force: true });
mkdirSync(dataDir);

const files = [];
const built = [];
let errorCount = 0;

for (const def of config.instances) {
  if (def.available === false) {
    console.log(`skip  ${def.name} (not in WoW Forever)`);
    continue;
  }

  const { instance, errors, warnings } = buildInstance(db, def, { world, cache });
  for (const warning of warnings) console.warn(`warn  ${warning}`);
  for (const error of errors) console.error(`error ${error}`);
  errorCount += errors.length;

  const file = `${instance.key}.lua`;
  writeFileSync(join(dataDir, file), instanceFile(instance));
  files.push(file);
  built.push(instance);

  const bossItems = instance.bosses.reduce((sum, boss) => sum + boss.loot.length, 0);
  const notable = instance.notable.trash.length + instance.notable.objects.length;
  console.log(`ok    ${instance.name}: ${instance.bosses.length} bosses, ${bossItems} boss items, ${notable} notable`);
}

// Every item's name, quality and kind, loaded before the instances.
const items = itemIdsOf(built).map((id) => db.item(id)).filter(Boolean);
writeFileSync(join(dataDir, 'Items.lua'), itemsFile(items));
files.unshift('Items.lua');
console.log(`ok    ${items.length} items`);

// Recordings players sent in, baked in after the items and before the instances.
const { recordings, warnings: recordingWarnings } = readRecordings(join(here, 'recordings'));
for (const warning of recordingWarnings) console.warn(`warn  ${warning}`);
writeFileSync(join(dataDir, 'Recorded.lua'), recordedFile(recordings));
files.splice(1, 0, 'Recorded.lua');
console.log(`ok    ${recordings.length} recorders' recordings`);

const tocPath = join(addon, 'BossLoot.toc');
writeFileSync(tocPath, updateToc(readFileSync(tocPath, 'utf8'), files));

if (errorCount) {
  console.error(`${errorCount} error(s): fix tools/instances.json and run again.`);
  process.exit(1);
}
console.log(`${built.length} instances written to Data/.`);
