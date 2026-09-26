// A tiny in-memory copy of the vMaNGOS tables the build reads, holding only
// the columns it reads, so every rule can be tested without the real dump.
import { DatabaseSync } from 'node:sqlite';

const LOOT_COLUMNS = `entry int, item int, ChanceOrQuestChance real, groupid int default 0,
  mincountOrRef int default 1, condition_id int default 0, patch_min int default 0, patch_max int default 10`;

export function fixtureDb() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    create table creature_template (entry int, patch int default 0, name text, loot_id int default 0);
    create table creature (guid integer primary key, id int, id2 int default 0, id3 int default 0,
      id4 int default 0, id5 int default 0, map int, patch_min int default 0, patch_max int default 10);
    create table gameobject_template (entry int, patch int default 0, type int, name text, data1 int default 0);
    create table gameobject (guid integer primary key, id int, map int, patch_min int default 0, patch_max int default 10);
    create table item_template (entry int, patch int default 0, name text, quality int, class int default 0, start_quest int default 0);
    create table creature_loot_template (${LOOT_COLUMNS});
    create table reference_loot_template (${LOOT_COLUMNS});
    create table gameobject_loot_template (${LOOT_COLUMNS});
  `);

  const add = (table, row) => {
    const columns = Object.keys(row);
    db.prepare(`insert into ${table} (${columns.join(', ')}) values (${columns.map(() => '?').join(', ')})`)
      .run(...Object.values(row));
  };

  return { db, add };
}
