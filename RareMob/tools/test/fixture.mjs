// A tiny in-memory copy of the vMaNGOS tables the build reads, holding only
// the columns it reads, so every rule can be tested without the real dump.
import { DatabaseSync } from 'node:sqlite';

export function fixtureDb() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    create table creature_template (entry int, patch int default 0, name text, level_min int default 1,
      level_max int default 1, rank int default 0);
    create table creature (guid integer primary key, id int, id2 int default 0, id3 int default 0,
      id4 int default 0, id5 int default 0, map int, patch_min int default 0, patch_max int default 10,
      position_x real default 0, position_y real default 0, position_z real default 0);
  `);

  const add = (table, row) => {
    const columns = Object.keys(row);
    db.prepare(`insert into ${table} (${columns.join(', ')}) values (${columns.map(() => '?').join(', ')})`)
      .run(...Object.values(row));
  };

  return { db, add };
}
