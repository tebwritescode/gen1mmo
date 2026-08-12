// Minimal zero-dep PNG encode/decode + pixel-art helpers, for authoring and
// reviewing sprites (contact sheets we can actually look at). Node built-ins
// only (zlib). RGBA8 throughout.

import { deflateSync, inflateSync } from "node:zlib";

const SIG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return (buf) => {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) c = t[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
})();

function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(CRC(td));
  return Buffer.concat([len, td, crc]);
}

/** An RGBA image: { w, h, data:Uint8Array(w*h*4) }. */
export function image(w, h, fill = [0, 0, 0, 0]) {
  const data = new Uint8Array(w * h * 4);
  if (fill[3] !== 0) for (let i = 0; i < w * h; i++) data.set(fill, i * 4);
  return { w, h, data };
}
export function px(img, x, y, rgba) {
  if (x < 0 || y < 0 || x >= img.w || y >= img.h) return;
  img.data.set(rgba, (y * img.w + x) * 4);
}
export function getpx(img, x, y) {
  const i = (y * img.w + x) * 4, d = img.data;
  return [d[i], d[i + 1], d[i + 2], d[i + 3]];
}

export function encodePNG(img) {
  const { w, h, data } = img;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0; // filter: none
    Buffer.from(data.buffer, y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; // 8-bit, RGBA
  return Buffer.concat([SIG, chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

function rawScanlines(img) {
  const { w, h, data } = img;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    Buffer.from(data.buffer, y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  }
  return raw;
}

/** Animated PNG (APNG). frames: array of equal-size images. delayMs per frame. */
export function encodeAPNG(frames, { delayMs = 150, loops = 0 } = {}) {
  const { w, h } = frames[0];
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  const actl = Buffer.alloc(8);
  actl.writeUInt32BE(frames.length, 0); actl.writeUInt32BE(loops, 4);
  const parts = [SIG, chunk("IHDR", ihdr), chunk("acTL", actl)];
  let seq = 0;
  const fcTL = () => {
    const b = Buffer.alloc(26);
    b.writeUInt32BE(seq++, 0); b.writeUInt32BE(w, 4); b.writeUInt32BE(h, 8);
    b.writeUInt32BE(0, 12); b.writeUInt32BE(0, 16);
    b.writeUInt16BE(delayMs, 20); b.writeUInt16BE(1000, 22);
    b[24] = 0; b[25] = 0; // dispose NONE, blend SOURCE
    return b;
  };
  frames.forEach((f, i) => {
    parts.push(chunk("fcTL", fcTL()));
    const comp = deflateSync(rawScanlines(f));
    if (i === 0) parts.push(chunk("IDAT", comp));
    else {
      const fd = Buffer.alloc(4 + comp.length);
      fd.writeUInt32BE(seq++, 0); comp.copy(fd, 4);
      parts.push(chunk("fdAT", fd));
    }
  });
  parts.push(chunk("IEND", Buffer.alloc(0)));
  return Buffer.concat(parts);
}

export function decodePNG(buf) {
  let p = 8; // skip signature
  let w = 0, h = 0, idat = [];
  while (p < buf.length) {
    const len = buf.readUInt32BE(p); const type = buf.toString("ascii", p + 4, p + 8);
    const data = buf.subarray(p + 8, p + 8 + len);
    if (type === "IHDR") { w = data.readUInt32BE(0); h = data.readUInt32BE(4); }
    else if (type === "IDAT") idat.push(data);
    else if (type === "IEND") break;
    p += 12 + len;
  }
  const raw = inflateSync(Buffer.concat(idat));
  const img = image(w, h);
  const stride = w * 4 + 1;
  // supports filter types 0 (none) and 1/2 (sub/up) minimally
  const out = img.data;
  for (let y = 0; y < h; y++) {
    const f = raw[y * stride];
    for (let x = 0; x < w * 4; x++) {
      let v = raw[y * stride + 1 + x];
      const a = x >= 4 ? out[(y * w * 4) + x - 4] : 0;
      const b = y > 0 ? out[((y - 1) * w * 4) + x] : 0;
      if (f === 1) v = (v + a) & 0xff;
      else if (f === 2) v = (v + b) & 0xff;
      else if (f === 3) v = (v + ((a + b) >> 1)) & 0xff;
      out[(y * w * 4) + x] = v;
    }
  }
  return img;
}

/** Nearest-neighbour upscale. */
export function scale(img, s) {
  const o = image(img.w * s, img.h * s);
  for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) {
    const c = getpx(img, x, y);
    for (let dy = 0; dy < s; dy++) for (let dx = 0; dx < s; dx++) px(o, x * s + dx, y * s + dy, c);
  }
  return o;
}

/** Blit src onto dst at (ox,oy) with alpha-over. */
export function blit(dst, src, ox, oy) {
  for (let y = 0; y < src.h; y++) for (let x = 0; x < src.w; x++) {
    const [r, g, b, a] = getpx(src, x, y);
    if (a === 0) continue;
    if (a === 255) { px(dst, ox + x, oy + y, [r, g, b, a]); continue; }
    const [dr, dg, db, da] = getpx(dst, ox + x, oy + y);
    const af = a / 255, ia = 1 - af;
    px(dst, ox + x, oy + y, [Math.round(r * af + dr * ia), Math.round(g * af + dg * ia), Math.round(b * af + db * ia), Math.max(a, da)]);
  }
}

/** Lay images in a grid onto a background, with gaps. Returns the sheet. */
export function contactSheet(cells, { cols, gap = 8, bg = [24, 27, 34, 255], pad = 12 }) {
  const cw = Math.max(...cells.map((c) => c.img.w));
  const ch = Math.max(...cells.map((c) => c.img.h));
  const rows = Math.ceil(cells.length / cols);
  const labelH = cells.some((c) => c.label) ? 14 : 0;
  const W = pad * 2 + cols * cw + (cols - 1) * gap;
  const H = pad * 2 + rows * (ch + labelH) + (rows - 1) * gap;
  const sheet = image(W, H, bg);
  cells.forEach((c, i) => {
    const col = i % cols, row = Math.floor(i / cols);
    const x = pad + col * (cw + gap), y = pad + row * (ch + labelH + gap);
    blit(sheet, c.img, x + Math.floor((cw - c.img.w) / 2), y);
    if (c.label) drawText(sheet, c.label, x, y + ch + 3, [160, 172, 185, 255]);
  });
  return sheet;
}

// tiny 3x5 pixel font for labels (enough for names/coords)
const FONT = {
  " ": [], "0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7], "2": [7, 1, 7, 4, 7], "3": [7, 1, 7, 1, 7],
  "4": [5, 5, 7, 1, 1], "5": [7, 4, 7, 1, 7], "6": [7, 4, 7, 5, 7], "7": [7, 1, 2, 2, 2],
  "8": [7, 5, 7, 5, 7], "9": [7, 5, 7, 1, 7], "/": [1, 1, 2, 4, 4], "#": [5, 7, 5, 7, 5],
  "-": [0, 0, 7, 0, 0], ":": [0, 2, 0, 2, 0], ".": [0, 0, 0, 0, 2],
};
for (let i = 0; i < 26; i++) {
  // uppercase A-Z as blocky 3x5
  const glyphs = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const G = [
    [2,5,7,5,5],[6,5,6,5,6],[3,4,4,4,3],[6,5,5,5,6],[7,4,6,4,7],[7,4,6,4,4],[3,4,5,5,3],[5,5,7,5,5],
    [7,2,2,2,7],[1,1,1,5,2],[5,6,4,6,5],[4,4,4,4,7],[5,7,7,5,5],[5,7,7,7,5],[2,5,5,5,2],[6,5,6,4,4],
    [2,5,5,7,3],[6,5,6,5,5],[3,4,2,1,6],[7,2,2,2,2],[5,5,5,5,7],[5,5,5,2,2],[5,5,7,7,5],[5,5,2,5,5],
    [5,5,2,2,2],[7,1,2,4,7],
  ];
  FONT[glyphs[i]] = G[i];
}
export function drawText(img, text, x, y, color = [220, 220, 220, 255]) {
  let cx = x;
  for (const ch of text.toUpperCase()) {
    const g = FONT[ch] ?? FONT[" "];
    for (let row = 0; row < g.length; row++) for (let bit = 0; bit < 3; bit++) {
      if (g[row] & (4 >> bit)) px(img, cx + bit, y + row, color);
    }
    cx += 4;
  }
}
