// Minimal animated GIF89a encoder (zero deps). Indexed color with 1-bit
// transparency, LZW-compressed, Netscape loop. Built for tiny pixel-art frames
// with few colors -- animates in every viewer, unlike APNG.

import { getpx } from "./pngkit.mjs";

function lzwEncode(indices, minCodeSize) {
  const clear = 1 << minCodeSize;
  const eoi = clear + 1;
  let codeSize = minCodeSize + 1;
  const bytes = [];
  let cur = 0, curBits = 0;
  const emit = (code) => {
    cur |= code << curBits; curBits += codeSize;
    while (curBits >= 8) { bytes.push(cur & 0xff); cur >>= 8; curBits -= 8; }
  };
  let dict = new Map(), next;
  const reset = () => { dict = new Map(); next = eoi + 1; codeSize = minCodeSize + 1; };
  reset();
  emit(clear);
  let w = "";
  for (const k of indices) {
    const c = String.fromCharCode(k);
    const wc = w + c;
    if (dict.has(wc) || (w === "" && false)) { w = wc; continue; }
    // w+c not in dict: output code for w (w is always a single known symbol or dict entry)
    emit(w === "" ? k : dict.get(w));
    if (w !== "") {
      dict.set(wc, next++);
      if (next > (1 << codeSize) && codeSize < 12) codeSize++;
      if (next === 4096) { emit(clear); reset(); }
    }
    w = c;
  }
  if (w !== "") emit(dict.has(w) ? dict.get(w) : w.charCodeAt(0));
  emit(eoi);
  if (curBits > 0) bytes.push(cur & 0xff);
  return bytes;
}

// Simpler, correct LZW: treat single symbols as their own initial codes.
function lzw(indices, minCodeSize) {
  const clear = 1 << minCodeSize, eoi = clear + 1;
  let codeSize = minCodeSize + 1;
  const out = []; let cur = 0, bits = 0;
  const put = (code) => { cur |= code << bits; bits += codeSize; while (bits >= 8) { out.push(cur & 255); cur >>= 8; bits -= 8; } };
  let dict, next;
  const reset = () => { dict = new Map(); for (let i = 0; i < clear; i++) dict.set(String.fromCharCode(i), i); next = eoi + 1; codeSize = minCodeSize + 1; };
  reset(); put(clear);
  let w = String.fromCharCode(indices[0]);
  for (let i = 1; i < indices.length; i++) {
    const c = String.fromCharCode(indices[i]);
    if (dict.has(w + c)) { w += c; continue; }
    put(dict.get(w));
    dict.set(w + c, next++);
    if (next - 1 === (1 << codeSize) && codeSize < 12) codeSize++;
    if (next === 4097) { put(clear); reset(); }
    w = c;
  }
  put(dict.get(w)); put(eoi);
  if (bits > 0) out.push(cur & 255);
  return out;
}

function subBlocks(bytes) {
  const out = [];
  for (let i = 0; i < bytes.length; i += 255) {
    const chunk = bytes.slice(i, i + 255);
    out.push(chunk.length, ...chunk);
  }
  out.push(0);
  return out;
}

/** frames: array of equal-size {w,h,data} RGBA images. delayMs per frame. */
export function encodeGIF(frames, { delayMs = 180 } = {}) {
  const { w, h } = frames[0];
  // build shared palette; index 0 reserved for transparent
  const pal = [[0, 0, 0]]; const key = new Map(); key.set("T", 0);
  const idxOf = (r, g, b, a) => {
    if (a === 0) return 0;
    const k = `${r},${g},${b}`;
    if (key.has(k)) return key.get(k);
    const i = pal.length; pal.push([r, g, b]); key.set(k, i); return i;
  };
  const framesIdx = frames.map((f) => {
    const idx = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const [r, g, b, a] = getpx(f, x, y); idx[y * w + x] = idxOf(r, g, b, a);
    }
    return idx;
  });
  let bits = 1; while ((1 << bits) < pal.length) bits++; // color table size
  const tableLen = 1 << bits;
  const bytes = [];
  const push = (...b) => bytes.push(...b);
  const str = (s) => { for (const ch of s) bytes.push(ch.charCodeAt(0)); };
  str("GIF89a");
  push(w & 255, w >> 8, h & 255, h >> 8);
  push(0x80 | ((bits - 1) & 7), 0, 0); // global table, color res, bg, aspect
  for (let i = 0; i < tableLen; i++) { const c = pal[i] || [0, 0, 0]; push(c[0], c[1], c[2]); }
  // netscape loop forever
  push(0x21, 0xff, 11); str("NETSCAPE2.0"); push(3, 1, 0, 0, 0);
  const minCode = Math.max(2, bits);
  for (const idx of framesIdx) {
    // GCE: transparency on, delay
    const cs = Math.round(delayMs / 10);
    push(0x21, 0xf9, 4, 0x01, cs & 255, cs >> 8, 0, 0);
    // image descriptor
    push(0x2c, 0, 0, 0, 0, w & 255, w >> 8, h & 255, h >> 8, 0);
    push(minCode);
    push(...subBlocks(lzw(Array.from(idx), minCode)));
  }
  push(0x3b);
  return Buffer.from(bytes);
}
void lzwEncode;
