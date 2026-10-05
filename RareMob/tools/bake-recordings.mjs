// Bakes players' sightings into RareMob/Data/Recorded.lua.
//
//   node RareMob/tools/bake-recordings.mjs [RareMob.lua saved variables...]
//
// With no files named, every .lua in tools/recordings/ is read. Keep the
// files there: a bake writes Recorded.lua afresh from what it is given.
import { readdirSync, existsSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readRecordings, recordedFile } from './lib/recordings.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const folder = join(here, 'recordings');

let files = process.argv.slice(2);
if (!files.length && existsSync(folder)) {
  files = readdirSync(folder).filter((name) => name.endsWith('.lua')).sort().map((name) => join(folder, name));
}

const { recordings, warnings } = readRecordings(files);
for (const warning of warnings) console.warn(`warn  ${warning}`);
writeFileSync(join(here, '..', 'Data', 'Recorded.lua'), recordedFile(recordings));

const rares = recordings.reduce((sum, { sightings }) => sum + Object.keys(sightings).length, 0);
console.log(`ok    ${recordings.length} recorders, ${rares} rares seen, written to Data/Recorded.lua.`);
