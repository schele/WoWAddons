import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildMap, pinFor, removeIslands, fillHoles, toRuns } from '../lib/map.mjs';

const disc = (x, y, r = 0) => ({ x, y, z: 0, r });
const at = (x, y) => ({ x, y, z: 0 });

// Where a world point falls, and whether that cell is floor.
function cellAt(map, point) {
  return {
    row: Math.floor((map.bounds.x1 - point.x) / map.cell),
    col: Math.floor((map.bounds.y1 - point.y) / map.cell),
  };
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
