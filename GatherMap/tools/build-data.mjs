// Regenerates GatherMap/Data/ from vMaNGOS's world database and
// tools/nodes.json.
//
//   node GatherMap/tools/build-data.mjs <path to mangos.sqlite>
//
// The database comes from the db_latest release on github.com/vmangos/core
// (db-sqlite-<commit>.zip). Neither it nor this script ships in the addon.
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { catalog, spawns } from './lib/nodes.mjs';
import { nodesFile, spawnFiles, confirmedFile } from './lib/lua.mjs';
import { readRecordings, applyRecordings } from './lib/recordings.mjs';
import { updateToc } from '../../BossLoot/tools/lib/lua.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const addon = join(here, '..');

const dbPath = process.argv[2];
if (!dbPath) {
  console.error('usage: node GatherMap/tools/build-data.mjs <path to mangos.sqlite>');
  process.exit(2);
}

const lists = JSON.parse(readFileSync(join(here, 'nodes.json'), 'utf8'));
const db = new DatabaseSync(dbPath, { readOnly: true });

const { nodes: all, errors } = catalog(db, lists);
for (const error of errors) console.error(`error ${error}`);
// Stop before Data/ or the .toc is touched: a failed build changes nothing.
if (errors.length) {
  console.error(`${errors.length} error(s): fix tools/nodes.json and run again.`);
  process.exit(1);
}

const byContinent = spawns(db, all);

// What players recorded in WoW Forever outranks vMaNGOS.
const { recorders, warnings: recordingWarnings } = readRecordings(join(here, 'recordings'));
for (const warning of recordingWarnings) console.warn(`warn  ${warning}`);
const { confirmed, added, dropped } = applyRecordings(byContinent, all, recorders);
console.log(`ok    ${recorders.length} recordings: ${confirmed.length} confirmed, ${added} new, ${dropped} not there`);

const spawned = new Set([...byContinent.values()].flat().map((s) => s.entry));
const nodes = all.filter((node) => spawned.has(node.entry));

// A name in nodes.json that matched nothing is most likely misspelt.
const names = new Set(nodes.map((node) => node.name));
for (const name of [...Object.keys(lists.herb), ...Object.keys(lists.ore), ...lists.chest]) {
  if (!names.has(name)) console.warn(`warn  "${name}" in nodes.json has no spawns`);
}

const dataDir = join(addon, 'Data');
rmSync(dataDir, { recursive: true, force: true });
mkdirSync(dataDir);

writeFileSync(join(dataDir, 'Nodes.lua'), nodesFile(nodes));
const files = ['Nodes.lua'];
for (const { file, text } of spawnFiles(byContinent)) {
  writeFileSync(join(dataDir, file), text);
  files.push(file);
}
writeFileSync(join(dataDir, 'Confirmed.lua'), confirmedFile(confirmed));
files.push('Confirmed.lua');

const tocPath = join(addon, 'GatherMap.toc');
writeFileSync(tocPath, updateToc(readFileSync(tocPath, 'utf8'), files));

for (const kind of ['herb', 'ore', 'pool', 'chest']) {
  console.log(`ok    ${nodes.filter((n) => n.kind === kind).length} ${kind} nodes`);
}
for (const [continent, list] of byContinent) console.log(`ok    continent ${continent}: ${list.length} spawns`);
