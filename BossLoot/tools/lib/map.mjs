// An instance's map, generated: the places its mobs stand and walk, seen from
// above on a grid of square cells. The client has no dungeon maps to borrow.

export const GRID = 96;
export const TRIM = 0.01;
export const BANDS = 4;

function quantile(sorted, q) {
  const index = Math.min(sorted.length - 1, Math.max(0, Math.round(q * (sorted.length - 1))));
  return sorted[index];
}

/**
 * Points ({x, y, z} in world yards) to filled cells. North is up and east is
 * right: screen right is world -y, screen down is world -x. The bounds skip
 * the outermost `trim` of points on each axis, since one stray spawn would
 * otherwise squash the whole instance into a corner.
 */
export function buildMap(points, { grid = GRID, trim = TRIM } = {}) {
  if (!points.length) return null;

  const sorted = (axis) => points.map((point) => point[axis]).sort((a, b) => a - b);
  const xs = sorted('x');
  const ys = sorted('y');
  const zs = sorted('z');
  const bounds = {
    x0: quantile(xs, trim), x1: quantile(xs, 1 - trim),
    y0: quantile(ys, trim), y1: quantile(ys, 1 - trim),
    z0: quantile(zs, trim), z1: quantile(zs, 1 - trim),
  };

  const width = bounds.y1 - bounds.y0;
  const height = bounds.x1 - bounds.x0;
  const cell = Math.max(width, height, 1) / grid;
  const cols = Math.max(1, Math.ceil(width / cell - 1e-9));
  const rows = Math.max(1, Math.ceil(height / cell - 1e-9));

  const heights = new Map();
  for (const point of points) {
    if (point.x < bounds.x0 || point.x > bounds.x1 || point.y < bounds.y0 || point.y > bounds.y1) continue;
    const col = Math.min(cols - 1, Math.floor((bounds.y1 - point.y) / cell));
    const row = Math.min(rows - 1, Math.floor((bounds.x1 - point.x) / cell));
    const index = row * cols + col;
    const sum = heights.get(index) ?? { z: 0, n: 0 };
    sum.z += point.z;
    sum.n += 1;
    heights.set(index, sum);
  }

  const range = bounds.z1 - bounds.z0;
  const band = (z) => {
    if (range <= 0) return 0;
    return Math.min(BANDS - 1, Math.max(0, Math.floor(((z - bounds.z0) / range) * BANDS)));
  };

  const cells = [...heights]
    .sort((a, b) => a[0] - b[0])
    .map(([index, sum]) => index * BANDS + band(sum.z / sum.n));

  return { cols, rows, cells, bounds, cell };
}

/** Where a world point falls on the map, as fractions 0 to 1, clamped. */
export function pinFor(map, point) {
  if (!map || !point) return undefined;
  const clamp = (value) => Math.min(1, Math.max(0, value));
  const round = (value) => Math.round(value * 1000) / 1000;
  return {
    x: round(clamp((map.bounds.y1 - point.y) / (map.cols * map.cell))),
    y: round(clamp((map.bounds.x1 - point.x) / (map.rows * map.cell))),
  };
}
