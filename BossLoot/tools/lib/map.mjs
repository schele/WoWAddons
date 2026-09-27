// An instance's map, generated: a floor plan of the ground its mobs stand on,
// wander over and patrol, seen from above. The client has no dungeon maps to
// borrow.
//
// Points alone draw rooms as rings of dots. What makes a floor plan is the
// ground between them: each mob's wander radius fills the room it roams, and
// its patrol path, joined point to point, draws the corridor it walks. The
// result is closed up (small gaps bridged, specks dropped, pinholes filled)
// and stored as horizontal runs of floor, which the addon draws as strips.

export const MAX_CELLS = 200;   // cells across the longer side, at most
export const MIN_CELL = 4;      // yards; finer shows every stray step
export const TRIM = 0.01;       // outermost share of points ignored for the bounds
export const MARGIN = 10;       // yards of room around the bounds
export const KEEP_MARGIN = 0.6;  // how far past the edge a boss still widens the map
export const KEEP_RADIUS = 12;  // yards of floor drawn round a boss, whose room may have no spawns
export const MAX_WANDER = 20;   // yards; bigger radii are scripted, not rooms
export const MAX_STEP = 80;     // yards; a longer patrol step is a jump, not a corridor
export const MIN_ISLAND = 12;   // cells; smaller specks are dropped
export const MAX_HOLE = 10;     // cells; smaller holes inside the floor are filled
export const MAX_GAP = 6;       // cells; a wider empty band right across the map is squeezed to this

function quantile(sorted, q) {
  const index = Math.min(sorted.length - 1, Math.max(0, Math.round(q * (sorted.length - 1))));
  return sorted[index];
}

// Cells touching a cell, up down left right.
const NEIGHBOURS = [[1, 0], [-1, 0], [0, 1], [0, -1]];

function morph(grid, cols, rows, grow) {
  const out = new Uint8Array(grid.length);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      let any = false;
      let all = true;
      for (let dr = -1; dr <= 1; dr++) {
        for (let dc = -1; dc <= 1; dc++) {
          const rr = r + dr;
          const cc = c + dc;
          const value = rr >= 0 && cc >= 0 && rr < rows && cc < cols ? grid[rr * cols + cc] : 0;
          any = any || value === 1;
          all = all && value === 1;
        }
      }
      out[r * cols + c] = (grow ? any : all) ? 1 : 0;
    }
  }
  return out;
}

// The connected areas of cells with `value`, each as a list of indices.
function areas(grid, cols, rows, value) {
  const seen = new Uint8Array(grid.length);
  const found = [];
  for (let start = 0; start < grid.length; start++) {
    if (seen[start] || grid[start] !== value) continue;
    const area = [];
    const stack = [start];
    seen[start] = 1;
    while (stack.length) {
      const index = stack.pop();
      area.push(index);
      const r = Math.floor(index / cols);
      const c = index % cols;
      for (const [dr, dc] of NEIGHBOURS) {
        const rr = r + dr;
        const cc = c + dc;
        if (rr < 0 || cc < 0 || rr >= rows || cc >= cols) continue;
        const next = rr * cols + cc;
        if (!seen[next] && grid[next] === value) {
          seen[next] = 1;
          stack.push(next);
        }
      }
    }
    found.push(area);
  }
  return found;
}

/** Clear floor areas smaller than `min` cells, in place. */
export function removeIslands(grid, cols, rows, min = MIN_ISLAND) {
  for (const area of areas(grid, cols, rows, 1)) {
    if (area.length < min) for (const index of area) grid[index] = 0;
  }
}

/** Fill enclosed empty areas of up to `max` cells, in place. */
export function fillHoles(grid, cols, rows, max = MAX_HOLE) {
  for (const area of areas(grid, cols, rows, 0)) {
    if (area.length > max) continue;
    const touchesEdge = area.some((index) => {
      const r = Math.floor(index / cols);
      const c = index % cols;
      return r === 0 || c === 0 || r === rows - 1 || c === cols - 1;
    });
    if (!touchesEdge) for (const index of area) grid[index] = 1;
  }
}

/** Each row's floor as runs, flattened: row, first column, length, ... */
export function toRuns(grid, cols, rows) {
  const runs = [];
  for (let r = 0; r < rows; r++) {
    let start = -1;
    for (let c = 0; c <= cols; c++) {
      const floor = c < cols && grid[r * cols + c] === 1;
      if (floor && start < 0) start = c;
      if (!floor && start >= 0) {
        runs.push(r, start, c - start);
        start = -1;
      }
    }
  }
  return runs;
}

/**
 * One axis of the map with its wide empty bands squeezed: `used` says which
 * lines (rows or columns) hold any floor. Used lines keep their size and
 * order; a band of empty ones wider than `maxGap` shrinks to `maxGap`, and a
 * point inside it keeps its share of the band. Returns the new length and
 * the map from an old position, in cells, to the new one.
 */
export function squeezeAxis(used, maxGap = MAX_GAP) {
  const pieces = []; // old start, old end, new start, new end
  let length = 0;
  for (let start = 0; start < used.length;) {
    let end = start;
    while (end < used.length && Boolean(used[end]) === Boolean(used[start])) end++;
    const size = used[start] ? end - start : Math.min(end - start, maxGap);
    pieces.push([start, end, length, length + size]);
    length += size;
    start = end;
  }

  const map = (old) => {
    if (old <= 0) return old;
    for (const [start, end, newStart, newEnd] of pieces) {
      if (old <= end) return newStart + ((old - start) * (newEnd - newStart)) / (end - start);
    }
    return length + (old - used.length);
  };
  return { length, map };
}

/**
 * A floor plan from `discs` ({x, y, r}: where a mob stands and how far it
 * wanders) and `paths` (patrols, as lists of {x, y}). North is up and east is
 * right: screen right is world -y, screen down is world -x. The bounds skip
 * the outermost `trim` of points on each axis -- one stray spawn would squash
 * the rest into a corner -- but widen for any `keep` point (a boss) standing
 * a little past that edge, since bosses stand at the far ends of instances.
 */
export function buildMap({ discs = [], paths = [] }, options = {}) {
  const {
    trim = TRIM, keep = [], maxCells = MAX_CELLS, minCell = MIN_CELL, margin = MARGIN,
  } = options;

  const centres = [...discs, ...paths.flat()];
  if (!centres.length) return null;

  const sorted = (axis) => centres.map((point) => point[axis]).sort((a, b) => a - b);
  const xs = sorted('x');
  const ys = sorted('y');
  const bounds = {
    x0: quantile(xs, trim), x1: quantile(xs, 1 - trim),
    y0: quantile(ys, trim), y1: quantile(ys, 1 - trim),
  };

  const reach = Math.max(bounds.x1 - bounds.x0, bounds.y1 - bounds.y0, 1) * KEEP_MARGIN;
  const kept = [];
  for (const point of keep) {
    const near = point.x >= bounds.x0 - reach && point.x <= bounds.x1 + reach
      && point.y >= bounds.y0 - reach && point.y <= bounds.y1 + reach;
    if (near) {
      kept.push({ x: point.x, y: point.y, r: KEEP_RADIUS });
      bounds.x0 = Math.min(bounds.x0, point.x);
      bounds.x1 = Math.max(bounds.x1, point.x);
      bounds.y0 = Math.min(bounds.y0, point.y);
      bounds.y1 = Math.max(bounds.y1, point.y);
    }
  }
  bounds.x0 -= margin;
  bounds.x1 += margin;
  bounds.y0 -= margin;
  bounds.y1 += margin;

  const width = bounds.y1 - bounds.y0;
  const height = bounds.x1 - bounds.x0;
  const cell = Math.max(minCell, Math.max(width, height, 1) / maxCells);
  const cols = Math.max(1, Math.ceil(width / cell - 1e-9));
  const rows = Math.max(1, Math.ceil(height / cell - 1e-9));

  let grid = new Uint8Array(cols * rows);
  const mark = (x, y) => {
    const col = Math.floor((bounds.y1 - y) / cell);
    const row = Math.floor((bounds.x1 - x) / cell);
    if (col >= 0 && row >= 0 && col < cols && row < rows) grid[row * cols + col] = 1;
  };

  const step = cell / 2;
  // A boss's room shows even when nothing is spawned in it (a lair whose
  // guards are summoned): a patch of floor goes round every boss taken in.
  for (const { x, y, r } of [...discs, ...kept]) {
    const radius = Math.max(Math.min(r ?? 0, MAX_WANDER), step);
    for (let dx = -radius; dx <= radius; dx += step) {
      for (let dy = -radius; dy <= radius; dy += step) {
        if (dx * dx + dy * dy <= radius * radius) mark(x + dx, y + dy);
      }
    }
  }

  for (const path of paths) {
    for (let i = 1; i < path.length; i++) {
      const a = path[i - 1];
      const b = path[i];
      const length = Math.hypot(b.x - a.x, b.y - a.y);
      if (length > MAX_STEP) continue;
      const steps = Math.max(1, Math.ceil(length / step));
      for (let s = 0; s <= steps; s++) mark(a.x + ((b.x - a.x) * s) / steps, a.y + ((b.y - a.y) * s) / steps);
    }
  }

  // Close up: grow twice to bridge gaps a cell or two wide, shrink once back.
  grid = morph(grid, cols, rows, true);
  grid = morph(grid, cols, rows, true);
  grid = morph(grid, cols, rows, false);
  removeIslands(grid, cols, rows);
  fillHoles(grid, cols, rows);

  const layout = pack(grid, cols, rows);
  const packed = new Uint8Array(layout.cols * layout.rows);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      if (!grid[r * cols + c]) continue;
      const [col, row] = layout.place(c, r);
      packed[row * layout.cols + col] = 1;
    }
  }

  return {
    cols: layout.cols, rows: layout.rows, cell, bounds, runs: toRuns(packed, layout.cols, layout.rows),
    gridCols: cols, gridRows: rows, place: layout.place,
  };
}

// Runs of used lines, split where an empty band between them is wider than
// `maxGap`: [first, afterLast] each.
function strips(used, maxGap) {
  const found = [];
  let first = -1;
  let last = -1;
  for (let i = 0; i < used.length; i++) {
    if (!used[i]) continue;
    if (first < 0) first = i;
    else if (i - last - 1 > maxGap) {
      found.push([first, last + 1]);
      first = i;
    }
    last = i;
  }
  if (first >= 0) found.push([first, last + 1]);
  return found;
}

// Wide empty column bands squeezed, then the gaps inside each strip of
// columns between them squeezed on its own. Each strip's top stays where
// squeezing the whole map puts it, so a part south of another stays south of
// it. `place` takes a position on the grid, in cells, to the packed map.
function packColumns(grid, cols, rows, maxGap) {
  const usedCols = new Uint8Array(cols);
  const usedRows = new Uint8Array(rows);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) if (grid[r * cols + c]) usedCols[c] = usedRows[r] = 1;
  }
  const allRows = squeezeAxis(usedRows, maxGap);
  const bands = strips(usedCols, maxGap).map(([first, afterLast]) => {
    const used = new Uint8Array(rows);
    for (let r = 0; r < rows; r++) {
      for (let c = first; c < afterLast; c++) if (grid[r * cols + c]) used[r] = 1;
    }
    const own = squeezeAxis(used, maxGap);
    const top = used.indexOf(1);
    const shift = allRows.map(top) - own.map(top);
    return { first, afterLast, length: own.length + shift, rows: { map: (row) => own.map(row) + shift } };
  });
  if (!bands.length) return { cols, rows, place: (c, r) => [c, r] };

  // A point between two strips goes with the nearer.
  const bandAt = (col) => {
    for (let i = 0; i < bands.length; i++) {
      if (col < bands[i].afterLast) {
        if (i > 0 && col < bands[i].first && bands[i].first - col > col - bands[i - 1].afterLast) return bands[i - 1];
        return bands[i];
      }
    }
    return bands[bands.length - 1];
  };
  const colAxis = squeezeAxis(usedCols, maxGap);
  return {
    cols: colAxis.length,
    rows: Math.max(...bands.map((band) => band.length)),
    place: (col, row) => [colAxis.map(col), bandAt(col).rows.map(row)],
  };
}

/**
 * The floor packed tight. Some instances are several parts in one map, far
 * apart -- Scarlet Monastery's four wings. Drawn as they lie, each is a speck
 * in a sea of nothing. So the parts are packed: columns of parts closed up,
 * then each column closed up on its own -- or rows, then each row, if that
 * comes out smaller. Parts keep their order across and within each column
 * (or row); a map in one piece comes out as it went in.
 */
export function pack(grid, cols, rows, maxGap = MAX_GAP) {
  const byColumns = packColumns(grid, cols, rows, maxGap);

  const turned = new Uint8Array(cols * rows);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) turned[c * rows + r] = grid[r * cols + c];
  }
  const t = packColumns(turned, rows, cols, maxGap);
  const byRows = {
    cols: t.rows,
    rows: t.cols,
    place: (col, row) => {
      const [turnedCol, turnedRow] = t.place(row, col);
      return [turnedRow, turnedCol];
    },
  };

  return byRows.cols * byRows.rows < byColumns.cols * byColumns.rows ? byRows : byColumns;
}

// Where a world point falls on the grid as first laid out, in cells.
function gridPosition(map, point) {
  return { col: (map.bounds.y1 - point.y) / map.cell, row: (map.bounds.x1 - point.x) / map.cell };
}

/** Where a world point falls on the finished map, in cells from its top left. */
export function cellOf(map, point) {
  const grid = gridPosition(map, point);
  const [col, row] = map.place(grid.col, grid.row);
  return { col, row };
}

/**
 * Where a world point falls on the map, as fractions 0 to 1. A point outside
 * the map (by more than half a cell) has no place on it: a pin clamped to the
 * edge would sit beside a room that is not drawn.
 */
export function pinFor(map, point) {
  if (!map || !point) return undefined;
  const grid = gridPosition(map, point);
  const slack = 0.5;
  if (grid.col < -slack || grid.col > map.gridCols + slack || grid.row < -slack || grid.row > map.gridRows + slack) {
    return undefined;
  }

  const { col, row } = cellOf(map, point);
  const clamp = (value) => Math.min(1, Math.max(0, value));
  const round = (value) => Math.round(value * 1000) / 1000;
  return { x: round(clamp(col / map.cols)), y: round(clamp(row / map.rows)) };
}
