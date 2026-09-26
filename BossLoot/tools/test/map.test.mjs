import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildMap, pinFor, BANDS } from '../lib/map.mjs';

const p = (x, y, z = 0) => ({ x, y, z });

test('fills a cell where points fall, seen from above with north up and east right', () => {
  // North is +x, east is -y.
  const map = buildMap([p(100, 0), p(0, -100)], { grid: 10, trim: 0 });
  assert.equal(map.cols, 10);
  assert.equal(map.rows, 10);
  assert.deepEqual(map.cells, [0 * BANDS, 99 * BANDS], 'north-west corner, then south-east');
});

test('uses square cells, so a long thin instance gets fewer rows', () => {
  const map = buildMap([p(0, 0), p(50, -100)], { grid: 10, trim: 0 });
  assert.equal(map.cols, 10);
  assert.equal(map.rows, 5);
});

test('ignores a stray point far from the rest', () => {
  const points = [];
  for (let i = 0; i < 200; i++) points.push(p(i % 20, -(i % 13)));
  points.push(p(5000, -5000));
  const map = buildMap(points, { grid: 20 });
  assert.ok(map.bounds.x1 < 100, `bounds reach ${map.bounds.x1}`);
});

test('bands cells by height, higher in higher bands', () => {
  const map = buildMap([p(100, 0, 0), p(0, -100, 100)], { grid: 10, trim: 0 });
  assert.deepEqual(map.cells.map((v) => v % BANDS), [0, BANDS - 1]);
});

test('has no map without points', () => {
  assert.equal(buildMap([]), null);
});

test('places a pin as fractions of the map', () => {
  const map = buildMap([p(100, 0), p(0, -100)], { grid: 10, trim: 0 });
  assert.deepEqual(pinFor(map, p(100, 0)), { x: 0, y: 0 });
  assert.deepEqual(pinFor(map, p(50, -50)), { x: 0.5, y: 0.5 });
});

test('gives no pin to a point well outside the map, rather than one on its edge', () => {
  // Clamped, Kel'Thuzad sat in an empty corner a hundred cells from his room.
  const map = buildMap([p(100, 0), p(0, -100)], { grid: 10, trim: 0 });
  assert.equal(pinFor(map, p(-999, 999)), undefined);
});

test('grows the bounds to take in a boss just past the trimmed edge, room and all', () => {
  // Bosses stand at the far ends of instances, which is just what trimming cuts.
  const points = [];
  for (let i = 0; i < 100; i++) points.push(p(i % 10, 0));
  const room = [p(11, 0), p(11, -1), p(11, 1)];
  const boss = p(11, 0);
  const trimmed = buildMap([...points, ...room], { grid: 20, trim: 0.05 });
  assert.equal(trimmed.bounds.x1, 9, 'the trim cuts the room');
  const kept = buildMap([...points, ...room], { grid: 20, trim: 0.05, keep: [boss] });
  assert.equal(kept.bounds.x1, 11);
  assert.ok(pinFor(kept, boss), 'and the boss has a pin');
});

test('does not stretch the map for a boss far beyond it', () => {
  const points = [];
  for (let i = 0; i < 100; i++) points.push(p(i % 10, 0));
  const map = buildMap(points, { grid: 20, trim: 0.05, keep: [p(1000, 0)] });
  assert.ok(map.bounds.x1 < 20);
});

test('has no pin without a point or a map', () => {
  assert.equal(pinFor(null, p(0, 0)), undefined);
  assert.equal(pinFor(buildMap([p(0, 0), p(1, 1)]), undefined), undefined);
});
