// A tiny in-memory copy of the vMaNGOS tables the build reads, holding only
// the columns it reads.
import { DatabaseSync } from 'node:sqlite';

export function fixtureDb() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    create table gameobject_template (entry int, patch int default 0, type int, name text, data1 int default 0);
    create table gameobject (guid integer primary key, id int, map int, patch_min int default 0, patch_max int default 10,
      position_x real default 0, position_y real default 0);
    create table gameobject_loot_template (entry int, item int, ChanceOrQuestChance real, mincountOrRef int default 1,
      patch_min int default 0, patch_max int default 10);
  `);
  const add = (table, row) => {
    const columns = Object.keys(row);
    db.prepare(`insert into ${table} (${columns.join(', ')}) values (${columns.map(() => '?').join(', ')})`)
      .run(...Object.values(row));
  };
  return { db, add };
}

export const LISTS = {
  herb: { Silverleaf: 1, Peacebloom: 1 },
  ore: { 'Copper Vein': 1, 'Tin Vein': 65 },
  chest: ['Battered Chest'],
};
