import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildMap, pinFor, removeIslands, fillHoles, toRuns, squeezeAxis, cellOf, MAX_GAP,
} from '../lib/map.mjs';

const disc = (x, y, r = 0) => ({ x, y, z: 0, r });
const at = (x, y) => ({ x, y, z: 0 });

// Where a world point falls, and whether that cell is floor.
function cellAt(map, point) {
  const { col, row } = cellOf(map, point);
  return { row: Math.floor(row), col: Math.floor(col) };
}
function isFloor(map, point) {
  const { row, col } = cellAt(map, point);
  for (let i = 0; i < map.runs.length; i += 3) {
    if (map.runs[i] === row && col >= map.runs[i + 1] && col < map.runs[i + 1] + map.runs[i + 2]) return true;
  }
  return false;
}

const bounded = { trim: 0, minCell: 2, maxCells: 100 };

test('fills the ground a mob wanders over', () => {
  const map = buildMap({ discs: [disc(0, 0, 10), disc(100, -100, 10)], paths: [] }, bounded);
  assert.ok(isFloor(map, at(0, 0)));
  assert.ok(isFloor(map, at(7, 0)), 'within its wander radius');
  assert.ok(!isFloor(map, at(50, -50)), 'nothing between the two');
});

test('joins a patrol path into a corridor', () => {
  const paths = [[at(0, 0), at(0, -60)]];
  const map = buildMap({ discs: [disc(100, 0), disc(0, -100)], paths }, bounded);
  assert.ok(isFloor(map, at(0, -30)));
});

test('does not join a jump longer than a patrol step', () => {
  const paths = [[at(0, 0), at(0, -200)]];
  const map = buildMap({ discs: [disc(0, 0, 5), disc(0, -200, 5)], paths }, bounded);
  assert.ok(!isFloor(map, at(0, -100)));
});

test('puts north at the top and east on the right', () => {
  const map = buildMap({ discs: [disc(100, 0, 5), disc(0, -100, 5)], paths: [] }, bounded);
  const north = cellAt(map, at(100, 0));
  const east = cellAt(map, at(0, -100));
  assert.ok(north.row < east.row, 'north above');
  assert.ok(east.col > north.col, 'east to the right');
});

test('uses cells of at least the minimum size, and at most so many across', () => {
  const small = buildMap({ discs: [disc(0, 0), disc(20, -20)], paths: [] }, { trim: 0, minCell: 4, maxCells: 100 });
  assert.ok(small.cell >= 4);
  const large = buildMap({ discs: [disc(0, 0), disc(2000, -2000)], paths: [] }, { trim: 0, minCell: 4, maxCells: 100 });
  assert.ok(large.cols <= 101 && large.rows <= 101);
});

test('has no map without anything on it', () => {
  assert.equal(buildMap({ discs: [], paths: [] }), null);
});

test('drops specks smaller than the minimum island', () => {
  const cols = 10;
  const rows = 3;
  const grid = new Uint8Array(cols * rows);
  grid[0] = 1; // a single-cell speck
  for (let c = 4; c < 10; c++) { grid[c] = 1; grid[cols + c] = 1; } // a 12-cell area
  removeIslands(grid, cols, rows, 5);
  assert.equal(grid[0], 0);
  assert.equal(grid[4], 1);
});

test('fills a small hole inside an area, but not open ground outside it', () => {
  const cols = 5;
  const rows = 5;
  const grid = new Uint8Array(cols * rows);
  for (let r = 1; r <= 3; r++) for (let c = 1; c <= 3; c++) grid[r * cols + c] = 1;
  grid[2 * cols + 2] = 0; // the hole
  fillHoles(grid, cols, rows, 4);
  assert.equal(grid[2 * cols + 2], 1, 'hole filled');
  assert.equal(grid[0], 0, 'outside untouched');
});

test('writes each row as runs of floor: row, first column, length', () => {
  const grid = Uint8Array.from([1, 1, 0, 1, 0, 0, 1, 1]);
  assert.deepEqual(toRuns(grid, 4, 2), [0, 0, 2, 0, 3, 1, 1, 2, 2]);
});

test('places a pin as fractions of the map', () => {
  const map = buildMap({ discs: [disc(100, 0), disc(0, -100)], paths: [] }, { ...bounded, margin: 0 });
  assert.deepEqual(pinFor(map, at(100, 0)), { x: 0, y: 0 });
  const middle = pinFor(map, at(50, -50));
  assert.ok(Math.abs(middle.x - 0.5) < 0.02 && Math.abs(middle.y - 0.5) < 0.02);
});

test('gives no pin to a point well outside the map, rather than one on its edge', () => {
  const map = buildMap({ discs: [disc(100, 0), disc(0, -100)], paths: [] }, bounded);
  assert.equal(pinFor(map, at(-999, 999)), undefined);
});

test('grows the bounds to take in a boss just past the trimmed edge', () => {
  const discs = [];
  for (let i = 0; i < 100; i++) discs.push(disc(i % 10, 0));
  const boss = at(11, 0);
  const options = { trim: 0.05, minCell: 1, maxCells: 100, margin: 0 };
  assert.equal(buildMap({ discs, paths: [] }, options).bounds.x1, 9, 'the trim cuts it');
  const kept = buildMap({ discs, paths: [] }, { ...options, keep: [boss] });
  assert.equal(kept.bounds.x1, 11);
  assert.ok(pinFor(kept, boss));
});

test('does not stretch the map for a boss far beyond it', () => {
  const discs = [];
  for (let i = 0; i < 100; i++) discs.push(disc(i % 10, 0));
  const map = buildMap({ discs, paths: [] }, { trim: 0.05, minCell: 1, keep: [at(1000, 0)] });
  assert.ok(map.bounds.x1 < 50);
});

test('has no pin without a point or a map', () => {
  assert.equal(pinFor(null, at(0, 0)), undefined);
  assert.equal(pinFor(buildMap({ discs: [disc(0, 0), disc(1, 1)], paths: [] }), undefined), undefined);
});

test('draws a patch of floor where a boss stands, though nothing else is there', () => {
  // Nefarian's lair: its drakonids are summoned, so no spawn marks the room.
  const discs = [];
  for (let i = 0; i < 100; i++) discs.push(disc(i % 10, 0, 2));
  const boss = at(14, 0);
  const map = buildMap({ discs, paths: [] }, { trim: 0.05, minCell: 1, maxCells: 100, keep: [boss] });
  assert.ok(isFloor(map, boss));
});

test('squeezes an empty band on one axis to a few cells, keeping what is used in place', () => {
  const used = [1, ...new Array(10).fill(0), 1];
  const axis = squeezeAxis(used, 3);
  assert.equal(axis.length, 5);
  assert.equal(axis.map(0), 0);
  assert.equal(axis.map(11), 4, 'the far side moves up to the squeezed gap');
  assert.equal(axis.map(6), 2.5, 'a point in the gap keeps its share of it');
});

test('leaves an empty band no wider than the limit as it is', () => {
  const axis = squeezeAxis([1, 0, 0, 1], 3);
  assert.equal(axis.length, 4);
  assert.equal(axis.map(3), 3);
});

// Scarlet Monastery: four wings in one map, far apart, with nothing between.
function emptyColumnsBetween(map, left, right) {
  const from = Math.floor(cellOf(map, left).col);
  const to = Math.floor(cellOf(map, right).col);
  let empty = 0;
  for (let col = from + 1; col < to; col++) {
    let floor = false;
    for (let i = 0; i < map.runs.length; i += 3) {
      if (col >= map.runs[i + 1] && col < map.runs[i + 1] + map.runs[i + 2]) floor = true;
    }
    if (!floor) empty++;
  }
  return empty;
}

test('draws separate parts of an instance close together, not across a sea of nothing', () => {
  const west = at(0, 0);
  const east = at(0, -400);
  const map = buildMap({ discs: [disc(0, 0, 10), disc(0, -400, 10)], paths: [] }, bounded);
  assert.equal(emptyColumnsBetween(map, west, east), MAX_GAP);
  assert.ok(isFloor(map, west) && isFloor(map, east), 'both parts still drawn');
  assert.ok(pinFor(map, east).x > 0.8, "the east part's pin is where the east part now is");
});

test('leaves an instance in one piece its full size', () => {
  const paths = [[at(0, 0), at(0, -60), at(0, -120), at(0, -180)]];
  const map = buildMap({ discs: [disc(0, 0, 5), disc(0, -180, 5)], paths }, bounded);
  assert.equal(map.cols, Math.ceil((map.bounds.y1 - map.bounds.y0) / map.cell - 1e-9));
});

// Cells that are not floor on the straight line between two points.
function gapAlong(map, from, to) {
  const a = cellAt(map, from);
  const b = cellAt(map, to);
  const floor = (row, col) => {
    for (let i = 0; i < map.runs.length; i += 3) {
      if (map.runs[i] === row && col >= map.runs[i + 1] && col < map.runs[i + 1] + map.runs[i + 2]) return true;
    }
    return false;
  };
  let gap = 0;
  if (Math.abs(b.row - a.row) > Math.abs(b.col - a.col)) {
    for (let row = Math.min(a.row, b.row) + 1; row < Math.max(a.row, b.row); row++) if (!floor(row, a.col)) gap++;
  } else {
    for (let col = Math.min(a.col, b.col) + 1; col < Math.max(a.col, b.col); col++) if (!floor(a.row, col)) gap++;
  }
  return gap;
}

test('packs each column of parts on its own, so a part in one does not hold the other apart', () => {
  // Scarlet Monastery: Graveyard over Cathedral in the west, Armory over
  // Library in the east, the Library far lower than the Cathedral.
  const armory = at(0, -400);
  const library = at(-400, -400);
  const discs = [disc(0, 0, 10), disc(-200, 0, 10), disc(0, -400, 10), disc(-400, -400, 10)];
  const map = buildMap({ discs, paths: [] }, bounded);
  assert.equal(gapAlong(map, armory, library), MAX_GAP);
  assert.ok(isFloor(map, armory) && isFloor(map, library));
});

test('or each row of parts, when that packs tighter', () => {
  const west = at(-400, 0);
  const east = at(-400, -400);
  const discs = [disc(0, 0, 10), disc(0, -200, 10), disc(-400, 0, 10), disc(-400, -400, 10)];
  const map = buildMap({ discs, paths: [] }, bounded);
  assert.equal(gapAlong(map, west, east), MAX_GAP);
  assert.ok(isFloor(map, west) && isFloor(map, east));
});
