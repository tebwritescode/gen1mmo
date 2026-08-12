// Animated preview: the first-100 NYE hat on a walking player, all 4 facings,
// as a looping APNG so we can see how it actually moves. The hat is drawn as an
// overlay whose brim seats on the head and whose cone rises above the sprite.
//
//   node tools/art/hat_nye_anim.mjs  ->  scratchpad/hat_nye_anim.png (APNG)

import { image, px, getpx, scale, blit, encodeAPNG, encodePNG, drawText } from "./pngkit.mjs";
import { encodeGIF } from "./gifkit.mjs";
import { writeFileSync } from "node:fs";
const OUT = "C:/Users/User/AppData/Local/Temp/claude/C--Users-User/67a83c03-e11c-4e24-80ca-06f2737fbc08/scratchpad";

const C = {
  ".": null, K: [20, 26, 36, 255], s: [240, 216, 184, 255], h: [90, 60, 40, 255],
  S: [72, 112, 208, 255], L: [40, 46, 60, 255], P: [150, 96, 60, 255], // pack (brown)
  R: [226, 62, 54, 255], G: [240, 208, 74, 255], W: [248, 248, 240, 255],
};
const grid = (g) => {
  const img = image(16, 16);
  g.forEach((row, y) => [...row].forEach((ch, x) => { const c = C[ch]; if (c) px(img, x, y, c); }));
  return img;
};
const mirror = (img) => {
  const o = image(img.w, img.h);
  for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) px(o, img.w - 1 - x, y, getpx(img, x, y));
  return o;
};

// --- placeholder player, 16x16, head rows 1-6, body 7-12, legs 13-15
const PLAYER = {
  down: {
    stand: ["................", "....KKKK........", "...KssssK.......", "...KsKsKK.......", "...KssssK.......", "...KssssK.......", "....KssK........", "...KSSSSK.......", "..KSSSSSK......", "..KSSSSSK......", "..KSSSSSK......", "...KSSSK.......", "...KS..SK......", "...KL..LK......", "...KL..LK......", "...KK..KK......."],
    step:  ["................", "....KKKK........", "...KssssK.......", "...KsKsKK.......", "...KssssK.......", "...KssssK.......", "....KssK........", "...KSSSSK.......", "..KSSSSSK......", "..KSSSSSK......", "..KSSSSSK......", "...KSSSK.......", "...KS..SK......", "...KL..LK......", "....KL.LK......", ".....KKKK......."],
  },
  up: {
    stand: ["................", "....KKKK........", "...KhhhhK.......", "...KhhhhK.......", "...KhhhhK.......", "...KhhhhK.......", "....KhhK........", "...KSSSSK.......", "..KSPPPSK......", "..KSPPPSK......", "..KSPPPSK......", "...KSSSK.......", "...KS..SK......", "...KL..LK......", "...KL..LK......", "...KK..KK......."],
    step:  ["................", "....KKKK........", "...KhhhhK.......", "...KhhhhK.......", "...KhhhhK.......", "...KhhhhK.......", "....KhhK........", "...KSSSSK.......", "..KSPPPSK......", "..KSPPPSK......", "..KSPPPSK......", "...KSSSK.......", "...KS..SK......", "...KL..LK......", "....KL.LK......", ".....KKKK......."],
  },
  left: {
    stand: ["................", "....KKKK........", "...KhsssK.......", "...KhsssK.......", "...KhssKK.......", "...KsssK........", "....KssK........", "...KSSSK........", "..KSSSSK.......", "..KSSSSK.......", "..KSSSK........", "...KSSK........", "...KSSK........", "...KLLK........", "...KLLK........", "...KKKK........."],
    step:  ["................", "....KKKK........", "...KhsssK.......", "...KhsssK.......", "...KhssKK.......", "...KsssK........", "....KssK........", "...KSSSK........", "..KSSSSK.......", "..KSSSSK.......", "..KSSSK........", "...KSSK........", "...KSSK........", "..KLLK.........", "...KLLK........", "...KKK........."],
  },
};

// --- hat overlay, 16x16, hat in the top 9 rows, brim at row 8
const HAT = {
  down: ["................", ".......WW.......", ".......KK.......", "......KRRK......", "......KGGK......", ".....KRRRRK.....", ".....KGGGGK.....", "....KRRRRRRK....", "....KKKKKKKK....", "................", "................", "................", "................", "................", "................", "................"],
  up:   ["................", ".......WW.......", ".......KK.......", "......KGGK......", "......KRRK......", ".....KGGGGK.....", ".....KRRRRK.....", "....KGGGGGGK....", "....KKKKKKKK....", "................", "................", "................", "................", "................", "................", "................"],
  left: ["................", ".....WW.........", ".....KK.........", "....KRRK........", "....KGGKK.......", "...KRRRRK.......", "...KGGGGGK......", "..KRRRRRRK......", "..KKKKKKKK......", "................", "................", "................", "................", "................", "................", "................"],
};
const SPARK = [[[3, 3], [12, 5]], [[13, 2], [2, 6]], [[11, 3], [4, 2]], [[14, 4], [3, 4]]];

function hatFrame(facing, f) {
  const base = facing === "right" ? mirror(grid(HAT.left)) : grid(HAT[facing]);
  // pom bob on f1,f2
  if (f === 1 || f === 2) {
    for (let x = 0; x < 16; x++) for (let y = 1; y <= 2; y++) {
      const i = (y * 16 + x) * 4, d = base.data;
      if (d[i] > 240 && d[i + 1] > 240 && d[i + 2] > 220) { d.copyWithin(((y - 1) * 16 + x) * 4, i, i + 4); d.fill(0, i, i + 4); }
    }
  }
  const sp = facing === "right" ? SPARK[f].map(([x, y]) => [15 - x, y]) : SPARK[f];
  for (const [sx, sy] of sp) { px(base, sx, sy, [255, 244, 140, 255]); px(base, sx, sy - 1, [255, 255, 255, 255]); }
  return base;
}

// compose one facing cell (16 wide x 22 tall): player in bottom 16, hat seated
// with brim on the head (hat drawn 6px higher so the cone rises above)
function cell(facing, animF, walkStep) {
  const cw = 16, chh = 22;
  const c = image(cw, chh);
  const pf = facing === "right" ? "left" : facing;
  let player = grid(PLAYER[pf][walkStep ? "step" : "stand"]);
  if (facing === "right") player = mirror(player);
  blit(c, player, 0, chh - 16);            // player at the bottom
  blit(c, hatFrame(facing, animF), 0, chh - 16 - 4); // hat brim seated on the hair
  return c;
}

const Z = 10, facings = ["down", "up", "left", "right"];
const frames = [];
for (let f = 0; f < 4; f++) {
  const walk = f % 2 === 1;
  const row = image((16 * 4 + 8 * 5) * 1, 22 + 16, [26, 30, 40, 255]);
  facings.forEach((fc, i) => blit(row, cell(fc, f, walk), 8 + i * (16 + 8), 6));
  frames.push(scale(row, Z));
}
writeFileSync(`${OUT}/hat_nye_anim.png`, encodeAPNG(frames, { delayMs: 180, loops: 0 }));
// also a labelled static strip for reference (first frame with labels)
const still = frames[0];
drawText(still, "DOWN", 20, 6, [200, 210, 220, 255]);
drawText(still, "UP", 200, 6, [200, 210, 220, 255]);
drawText(still, "LEFT", 370, 6, [200, 210, 220, 255]);
drawText(still, "RIGHT", 540, 6, [200, 210, 220, 255]);
writeFileSync(`${OUT}/hat_nye_still.png`, encodePNG(still));
console.log("wrote hat_nye_anim.png (APNG) + hat_nye_still.png", still.w + "x" + still.h);
