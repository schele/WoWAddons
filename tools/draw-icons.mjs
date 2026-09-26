// Draws the 64x64 icons for BossLoot, FishScale and BankBags, and their minimap icons, in the style of
// the others: a dark rounded tile with a soft glow in the addon's colour, a
// thin ring, and a light, glossy symbol with a darker outline and details.
// A minimap icon is the symbol alone, filling the frame: the minimap button
// supplies its own dark disc and gold ring.
// Usage, from the repo root: node tools/draw-icons.mjs .
import fs from 'node:fs';
import path from 'node:path';

const N = 64;
const S = 4; // supersampling per axis

const len = (x, y) => Math.hypot(x, y);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

// Signed distances, negative inside.
const circle = (cx, cy, r) => (x, y) => len(x - cx, y - cy) - r;
const roundBox = (cx, cy, hw, hh, r) => (x, y) => {
  const qx = Math.abs(x - cx) - hw + r;
  const qy = Math.abs(y - cy) - hh + r;
  return len(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
};
const ellipse = (cx, cy, rx, ry) => (x, y) => (len((x - cx) / rx, (y - cy) / ry) - 1) * Math.min(rx, ry);
function triangle(ax, ay, bx, by, cx, cy) {
  const pts = [[ax, ay], [bx, by], [cx, cy]];
  return (x, y) => {
    let d = Infinity;
    let sign = 0;
    for (let i = 0; i < 3; i++) {
      const [x0, y0] = pts[i];
      const [x1, y1] = pts[(i + 1) % 3];
      const ex = x1 - x0, ey = y1 - y0;
      const wx = x - x0, wy = y - y0;
      const t = clamp((wx * ex + wy * ey) / (ex * ex + ey * ey), 0, 1);
      d = Math.min(d, len(wx - ex * t, wy - ey * t));
      sign += ex * wy - ey * wx > 0 ? 1 : -1;
    }
    return Math.abs(sign) === 3 ? -d : d;
  };
}
const union = (...fs) => (x, y) => Math.min(...fs.map((f) => f(x, y)));
const minus = (a, b) => (x, y) => Math.max(a(x, y), -b(x, y));

function tileColour(theme, x, y) {
  const r = len(x - 32, y - 32) / 32;
  const glow = clamp(1 - r * 0.92, 0, 1) ** 1.1;
  return mix(theme.dark, theme.glow, glow);
}

// An icon: the tile, ring and symbol; or with `tile` false, the symbol alone,
// grown by `zoom` about the middle.
function draw(theme, symbol, details, highlight, { tile: withTile = true, zoom = 1 } = {}) {
  const tile = roundBox(32, 32, 32, 32, 7);
  const ring = (x, y) => Math.abs(len(x - 32, y - 32) - 27) - 1.1;
  const out = new Uint8Array(N * N * 4);
  for (let py = 0; py < N; py++) {
    for (let px = 0; px < N; px++) {
      let acc = [0, 0, 0, 0]; // premultiplied
      for (let sy = 0; sy < S; sy++) {
        for (let sx = 0; sx < S; sx++) {
          const x = px + (sx + 0.5) / S;
          const y = py + (sy + 0.5) / S;
          const ux = (x - 32) / zoom + 32;
          const uy = (y - 32) / zoom + 32;
          let colour = [0, 0, 0];
          let alpha = 0;
          const over = (c, a) => { colour = mix(colour, c, a); alpha = alpha + a * (1 - alpha); };
          if (withTile) {
            const dt = tile(x, y);
            if (dt < 0) {
              let c = tileColour(theme, x, y);
              if (dt > -1.5) c = mix(c, [0, 0, 0], 0.55); // the tile's dark edge
              over(c, 1);
            }
            if (ring(x, y) < 0) over(theme.ring, 0.95);
          }
          const ds = symbol(ux, uy) * zoom;
          if (ds < 0) {
            const t = clamp((uy - 14) / 38, 0, 1); // lighter at the top
            let c = mix(theme.light, theme.mid, t);
            if (highlight && highlight(ux, uy) < 0) c = mix(c, [255, 255, 255], 0.28);
            if (details && details(ux, uy) < 0) c = theme.detail;
            if (ds > -1.3) c = theme.outline; // outline
            over(c, 1);
          }
          acc = [acc[0] + colour[0] * alpha, acc[1] + colour[1] * alpha, acc[2] + colour[2] * alpha, acc[3] + alpha];
        }
      }
      const n = S * S;
      const a = acc[3] / n;
      const i = (py * N + px) * 4;
      out[i] = a > 0 ? Math.round(acc[0] / n / a) : 0;
      out[i + 1] = a > 0 ? Math.round(acc[1] / n / a) : 0;
      out[i + 2] = a > 0 ? Math.round(acc[2] / n / a) : 0;
      out[i + 3] = Math.round(a * 255);
    }
  }
  return out;
}

function writeTga(file, px) {
  const header = Buffer.alloc(18);
  header[2] = 2; // uncompressed true colour
  header.writeUInt16LE(N, 12);
  header.writeUInt16LE(N, 14);
  header[16] = 32;
  header[17] = 0x28; // top-left origin, 8 alpha bits
  const body = Buffer.alloc(N * N * 4);
  for (let i = 0; i < N * N; i++) {
    body[i * 4] = px[i * 4 + 2];
    body[i * 4 + 1] = px[i * 4 + 1];
    body[i * 4 + 2] = px[i * 4];
    body[i * 4 + 3] = px[i * 4 + 3];
  }
  fs.writeFileSync(file, Buffer.concat([header, body]));
}

// BossLoot: a treasure chest, in crimson.
const crimson = {
  dark: [18, 7, 7], glow: [104, 32, 28], ring: [206, 80, 66],
  light: [255, 184, 168], mid: [228, 104, 88], outline: [74, 18, 14], detail: [104, 28, 22],
};
const chest = union(roundBox(32, 25, 17, 7.5, 6.5), roundBox(32, 39, 17, 9, 2));
const chestDetails = union(
  roundBox(32, 31, 17, 1, 0.5), // the seam between lid and body
  roundBox(32, 33, 3.6, 4.6, 1.2), // the lock plate
  roundBox(20.5, 32, 1, 14, 0.4), // the two straps
  roundBox(43.5, 32, 1, 14, 0.4),
);
const chestShine = roundBox(28, 22, 9, 1.7, 1.7);

// FishScale: a fish, in orange.
const orange = {
  dark: [20, 11, 4], glow: [110, 62, 20], ring: [232, 148, 58],
  light: [255, 214, 146], mid: [240, 150, 64], outline: [84, 42, 10], detail: [110, 56, 16],
};
const fish = union(
  ellipse(26.5, 32, 17, 11),
  minus(triangle(38, 32, 54, 19, 54, 45), triangle(50, 32, 55, 27, 55, 37)),
  triangle(21, 22.5, 33, 22.5, 28.5, 16),
);
const fishDetails = union(
  circle(17.5, 30, 2.3), // the eye
  (x, y) => Math.abs(len(x - 35, y - 32) - 8) - 0.9 + (x < 31.5 ? 20 : 0), // the gill line
);
const fishShine = ellipse(24, 26.5, 8, 1.7);

// BankBags: a money sack, in teal.
const teal = {
  dark: [4, 18, 17], glow: [20, 92, 86], ring: [64, 196, 182],
  light: [168, 250, 238], mid: [56, 184, 168], outline: [8, 58, 52], detail: [16, 84, 76],
};
const segment = (ax, ay, bx, by, r) => (x, y) => {
  const ex = bx - ax, ey = by - ay;
  const t = clamp(((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey), 0, 1);
  return len(x - ax - ex * t, y - ay - ey * t) - r;
};
const sack = union(
  ellipse(32, 40.5, 16.5, 12.5), // the body, squat and full
  roundBox(32, 28, 7.5, 4, 2), // the neck
  circle(25.5, 21.5, 4.6), // the gathered top, puffed out
  circle(32, 19.5, 5.2),
  circle(38.5, 21.5, 4.6),
);
const sackDetails = union(
  roundBox(32, 27.5, 9, 1.5, 0.7), // the tie
  segment(29, 32, 24.5, 39, 0.8), // two creases in the cloth
  segment(35, 32, 39.5, 39, 0.8),
);
const sackShine = ellipse(26, 35.5, 4.5, 2);

const root = process.argv[2];
writeTga(path.join(root, 'BossLoot', 'icon.tga'), draw(crimson, chest, chestDetails, chestShine));
writeTga(path.join(root, 'BossLoot', 'minimap.tga'), draw(crimson, chest, chestDetails, chestShine, { tile: false, zoom: 1.4 }));
writeTga(path.join(root, 'FishScale', 'icon.tga'), draw(orange, fish, fishDetails, fishShine));
writeTga(path.join(root, 'FishScale', 'minimap.tga'), draw(orange, fish, fishDetails, fishShine, { tile: false, zoom: 1.3 }));
writeTga(path.join(root, 'BankBags', 'icon.tga'), draw(teal, sack, sackDetails, sackShine));
writeTga(path.join(root, 'BankBags', 'minimap.tga'), draw(teal, sack, sackDetails, sackShine, { tile: false, zoom: 1.4 }));
console.log('written');
