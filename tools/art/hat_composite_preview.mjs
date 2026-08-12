// CONCEPT preview of the correct architecture: the hat is composited INTO each
// frame of the walk sheet at a per-frame anchor (so it bobs WITH the body), and
// the item animates by cycling N baked sheet-variants (sparkle states). Draws
// the anchor marker so placement is reviewable.
//
// This mirrors what the real tonegen compositing will do once fed the actual
// ROM-decoded body sheets. Placeholder body here only to confirm the approach.
//
//   node tools/art/hat_composite_preview.mjs -> scratchpad/hat_composite.gif

import { image, px, getpx, scale, blit, encodePNG, drawText } from "./pngkit.mjs";
import { encodeGIF } from "./gifkit.mjs";
import { writeFileSync } from "node:fs";
const OUT = "C:/Users/User/AppData/Local/Temp/claude/C--Users-User/67a83c03-e11c-4e24-80ca-06f2737fbc08/scratchpad";

const C = { ".": null, K: [20, 26, 36, 255], s: [240, 216, 184, 255], h: [92, 60, 40, 255],
  S: [216, 64, 56, 255], L: [40, 46, 60, 255], P: [150, 96, 60, 255],
  R: [226, 62, 54, 255], G: [240, 208, 74, 255], W: [248, 248, 240, 255] };
const grid = (g, w = 16, hgt = 16) => { const im = image(w, hgt); g.forEach((row, y) => [...row].forEach((ch, x) => { const c = C[ch]; if (c) px(im, x, y, c); })); return im; };
const mirror = (im) => { const o = image(im.w, im.h); for (let y = 0; y < im.h; y++) for (let x = 0; x < im.w; x++) px(o, im.w - 1 - x, y, getpx(im, x, y)); return o; };

// A body FRAME (16x16). Walk frames drop the head 1px (a bob) to prove the hat
// tracks it because it is composited per-frame at that frame's anchor.
const HEAD_DOWN = ["....KKKK........", "...KssssK.......", "...KsKsKK.......", "...KssssK.......", "...KssssK.......", "....KssK........"];
const HEAD_UP   = ["....KKKK........", "...KhhhhK.......", "...KhhhhK.......", "...KhhhhK.......", "...KhhhhK.......", "....KhhK........"];
const HEAD_LEFT = ["....KKKK........", "...KhsssK.......", "...KhsssK.......", "...KhssKK.......", "...KsssK........", "....KssK........"];
const BODY_DOWN = ["...KSSSSK.......", "..KSSSSSK......", "..KSSSSSK......", "...KSSSK.......", "...KS.SK.......", "...KL.LK.......", "...KL.LK.......", "...KK.KK......."];
const BODY_UP   = ["...KSSSSK.......", "..KSPPPK.......", "..KSPPPK.......", "...KSSSK.......", "...KS.SK.......", "...KL.LK.......", "...KL.LK.......", "...KK.KK......."];
const BODY_LEFT = ["...KSSSK........", "..KSSSSK.......", "..KSSSK........", "...KSSK........", "...KSSK........", "...KLLK........", "...KLLK........", "...KKK........."];

function bodyFrame(facing, walk) {
  const head = { down: HEAD_DOWN, up: HEAD_UP, left: HEAD_LEFT }[facing];
  const body = { down: BODY_DOWN, up: BODY_UP, left: BODY_LEFT }[facing];
  const im = image(16, 16);
  const bob = walk ? 1 : 0;                    // head+body drop 1px on the walk frame
  head.forEach((row, y) => [...row].forEach((ch, x) => { const c = C[ch]; if (c) px(im, x, y + 1 + bob, c); }));
  body.forEach((row, y) => [...row].forEach((ch, x) => { const c = C[ch]; if (c) px(im, x, y + 7 + bob, c); }));
  return im;
}

// hat art (16 wide, brim near row 8), 4 sparkle variants
const HAT = {
  down: ["................", ".......WW.......", ".......KK.......", "......KRRK......", "......KGGK......", ".....KRRRRK.....", ".....KGGGGK.....", "....KRRRRRRK....", "....KKKKKKKK...."],
  up:   ["................", ".......WW.......", ".......KK.......", "......KGGK......", "......KRRK......", ".....KGGGGK.....", ".....KRRRRK.....", "....KGGGGGGK....", "....KKKKKKKK...."],
  left: ["................", ".....WW.........", ".....KK.........", "....KRRK........", "....KGGKK.......", "...KRRRRK.......", "...KGGGGGK......", "..KRRRRRRK......", "..KKKKKKKK......"],
};
const SPARK = [[[3, 3], [12, 5]], [[13, 2], [2, 6]], [[11, 3], [4, 2]], [[14, 4], [3, 4]]];
function hatSprite(facing, variant) {
  const base = image(16, 16);
  const g = facing === "right" ? HAT.left : HAT[facing];
  g.forEach((row, y) => [...row].forEach((ch, x) => { const c = C[ch]; if (c) px(base, x, y, c); }));
  let out = facing === "right" ? mirror(base) : base;
  if (variant === 1 || variant === 2) { // pom bob
    for (let x = 0; x < 16; x++) for (let y = 1; y <= 2; y++) { const i = (y * 16 + x) * 4, d = out.data; if (d[i] > 240 && d[i + 1] > 240 && d[i + 2] > 220) { d.copyWithin(((y - 1) * 16 + x) * 4, i, i + 4); d.fill(0, i, i + 4); } }
  }
  const sp = facing === "right" ? SPARK[variant].map(([x, y]) => [15 - x, y]) : SPARK[variant];
  for (const [sx, sy] of sp) { px(out, sx, sy, [255, 244, 140, 255]); px(out, sx, sy - 1, [255, 255, 255, 255]); }
  return out;
}

// ANCHOR: where the hat's top-left is placed in a frame so the brim seats on
// the head. This is the "index" -- tied to the body's head, and it FOLLOWS the
// per-frame bob (walk frames add +1). One table works across bodies with the
// same head placement; per-body nudges override.
const ANCHOR = { x: 0, y: -3 }; // hat drawn at (x, headTop + y); +bob applied

// Build a composited frame: body + hat baked in at the anchor (bob-aware)
function composited(facing, walk, variant, mark) {
  const im = image(16, 22);
  const bob = walk ? 1 : 0;
  blit(im, bodyFrame(facing, walk), 0, 6);
  const hy = 6 + ANCHOR.y + bob; // hat baked at the head anchor, follows the bob
  blit(im, hatSprite(facing, variant), ANCHOR.x, hy);
  if (mark) { px(im, 8, 6 + 1 + bob, [80, 255, 120, 255]); px(im, 8, 6 + bob, [80, 255, 120, 255]); } // anchor dot on the head-top
  return im;
}

const facings = ["down", "up", "left", "right"];
const Z = 11;
const gifFrames = [];
for (let step = 0; step < 4; step++) {
  const walk = step % 2 === 1;
  const variant = step; // sparkle variant cycles with the loop
  const row = image(16 * 4 + 8 * 5, 28, [26, 30, 40, 255]);
  facings.forEach((fc, i) => blit(row, composited(fc, walk, variant, true), 8 + i * 24, 3));
  gifFrames.push(scale(row, Z));
}
writeFileSync(`${OUT}/hat_composite.gif`, encodeGIF(gifFrames, { delayMs: 220 }));

// a labelled still with the anchor callout
const still = scale((() => {
  const row = image(16 * 4 + 8 * 5, 28, [26, 30, 40, 255]);
  facings.forEach((fc, i) => blit(row, composited(fc, false, 0, true), 8 + i * 24, 3));
  return row;
})(), Z);
drawText(still, "DOWN", 20, 4, [200, 210, 220, 255]);
drawText(still, "UP", 285, 4, [200, 210, 220, 255]);
drawText(still, "LEFT", 545, 4, [200, 210, 220, 255]);
drawText(still, "RIGHT", 800, 4, [200, 210, 220, 255]);
drawText(still, "GREEN DOT = HEAD ANCHOR (HAT BAKED IN, FOLLOWS THE BOB)", 20, 300, [120, 240, 150, 255]);
writeFileSync(`${OUT}/hat_composite_still.png`, encodePNG(still));
console.log("wrote hat_composite.gif + still", still.w + "x" + still.h);
