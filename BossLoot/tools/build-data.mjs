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
import { worldRefs } from './lib/world.mjs';
import { buildInstance } from './lib/instance.mjs';
import { instanceFile, updateToc } from './lib/lua.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const addon = join(here, '..');

const dbPath = process.argv[2];
if (!dbPath) {
  console.error('usage: node BossLoot/tools/build-data.mjs <path to mangos.sqlite>');
  process.exit(2);
}

const config = JSON.parse(readFileSync(join(here, 'instances.json'), 'utf8'));
const db = openDb(dbPath);
const world = worldRefs(db);
const cache = new Map();

const dataDir = join(addon, 'Data');
rmSync(dataDir, { recursive: true, force: true });
mkdirSync(dataDir);

const files = [];
let errorCount = 0;

for (const def of config.instances) {
  if (def.available === false) {
    console.log(`skip  ${def.name} (not in WoW Forever)`);
    continue;
  }

  const { instance, errors, warnings } = buildInstance(db, def, { worldRefs: world, cache });
  for (const warning of warnings) console.warn(`warn  ${warning}`);
  for (const error of errors) console.error(`error ${error}`);
  errorCount += errors.length;

  const file = `${instance.key}.lua`;
  writeFileSync(join(dataDir, file), instanceFile(instance));
  files.push(file);

  const bossItems = instance.bosses.reduce((sum, boss) => sum + boss.loot.length, 0);
  const notable = instance.notable.trash.length + instance.notable.objects.length;
  console.log(`ok    ${instance.name}: ${instance.bosses.length} bosses, ${bossItems} boss items, ${notable} notable`);
}

const tocPath = join(addon, 'BossLoot.toc');
writeFileSync(tocPath, updateToc(readFileSync(tocPath, 'utf8'), files));

if (errorCount) {
  console.error(`${errorCount} error(s): fix tools/instances.json and run again.`);
  process.exit(1);
}
console.log(`${files.length} instances written to Data/.`);
