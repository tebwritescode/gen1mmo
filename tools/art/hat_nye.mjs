// Author + preview the first-100 "NYE" party hat: original pixel art, animated
// (sparkles twinkle + pom bob) -- the "special item" quality. Renders a contact
// sheet (facings x animation frames) plus a preview over a placeholder walker.
//
//   node tools/art/hat_nye.mjs   ->  writes scratchpad/hat_nye_sheet.png

import { image, px, scale, blit, contactSheet, encodePNG, drawText } from "./pngkit.mjs";
import { writeFileSync } from "node:fs";

const OUT = "C:/Users/User/AppData/Local/Temp/claude/C--Users-User/67a83c03-e11c-4e24-80ca-06f2737fbc08/scratchpad";

// festive palette
const PAL = {
  ".": null,
  "K": [20, 26, 36, 255],     // outline
  "R": [226, 62, 54, 255],    // red band
  "G": [240, 208, 74, 255],   // gold band
  "W": [248, 248, 240, 255],  // white pom / trim
  "P": [150, 84, 190, 255],   // purple band
};

// Clean cone: white pom, alternating red/gold bands, dark outline + brim that
// seats on the head (row 8). DOWN faces us.
const HAT_DOWN = [
  "................",
  ".......WW.......",
  ".......KK.......",
  "......KRRK......",
  "......KGGK......",
  ".....KRRRRK.....",
  ".....KGGGGK.....",
  "....KRRRRRRK....",
  "....KKKKKKKK....",
  "................",
  "................",
  "................",
  "................",
  "................",
  "................",
  "................",
];

// UP: the back of the cone (pom just peeks, bands read the same)
const HAT_UP = [
  "................",
  ".......WW.......",
  ".......KK.......",
  "......KGGK......",
  "......KRRK......",
  ".....KGGGGK.....",
  ".....KRRRRK.....",
  "....KGGGGGGK....",
  "....KKKKKKKK....",
  "................",
  "................",
  "................",
  "................",
  "................",
  "................",
  "................",
];

// LEFT: cone leans into the walk direction, pom leads
const HAT_LEFT = [
  "................",
  ".....WW.........",
  ".....KK.........",
  "....KRRK........",
  "....KGGKK.......",
  "...KRRRRK.......",
  "...KGGGGGK......",
  "..KRRRRRRK......",
  "..KKKKKKKK......",
  "................",
  "................",
  "................",
  "................",
  "................",
  "................",
  "................",
];

function fromGrid(grid) {
  const img = image(16, 16);
  grid.forEach((row, y) => [...row].forEach((ch, x) => {
    const c = PAL[ch]; if (c) px(img, x, y, c);
  }));
  return img;
}

// sparkle positions per animation frame (twinkle around the hat), and a pom
// bob offset. 4 frames.
const SPARKLES = [
  [[3, 2], [11, 4]],
  [[12, 1], [2, 5]],
  [[10, 2], [4, 1]],
  [[13, 3], [3, 3]],
];
const SPARKLE_COL = [255, 244, 140, 255];
const SPARKLE_HI = [255, 255, 255, 255];

function frame(baseGrid, f) {
  const img = fromGrid(baseGrid);
  // pom bob: on frames 1 & 2 lift the white pom (top rows) by 1px for a bounce
  const bob = (f === 1 || f === 2) ? 1 : 0;
  if (bob) {
    for (let x = 0; x < 16; x++) {
      for (let y = 1; y <= 2; y++) {
        const i = (y * 16 + x) * 4, d = img.data;
        if (d[i] > 240 && d[i + 1] > 240 && d[i + 2] > 220) { // white pom
          d.copyWithin((( (y - 1) * 16 + x) * 4), i, i + 4);
          d.fill(0, i, i + 4);
        }
      }
    }
  }
  for (const [sx, sy] of SPARKLES[f]) {
    px(img, sx, sy, SPARKLE_COL);
    px(img, sx, sy - 1, SPARKLE_HI); // little vertical glint
  }
  return img;
}

// placeholder walker silhouette (so we see the hat "on a player")
function walker() {
  const img = image(16, 16);
  const body = [20, 26, 36, 255], skin = [240, 216, 184, 255], shirt = [80, 120, 210, 255];
  // head rows 8-11, body 12-15 (hat covers 0-8 above)
  const g = [
    "................", "................", "................", "................",
    "................", "................", "................", "................",
    ".....KKKK.......", "....KssssK......", "....KssssK......", "....KssssK......",
    "...KtttttK......", "...KtttttK......", "....K...K.......", "....K...K.......",
  ];
  const map = { ".": null, K: body, s: skin, t: shirt };
  g.forEach((row, y) => [...row].forEach((ch, x) => { const c = map[ch]; if (c) px(img, x, y, c); }));
  return img;
}

const Z = 12;
const cells = [];
const facings = [["DOWN", HAT_DOWN], ["UP", HAT_UP], ["LEFT", HAT_LEFT]];
for (const [fname, grid] of facings) {
  for (let f = 0; f < 4; f++) {
    cells.push({ img: scale(frame(grid, f), Z), label: `${fname} f${f}` });
  }
}
// on-player previews (down facing, each anim frame composited over the walker)
for (let f = 0; f < 4; f++) {
  const combined = walker();
  blit(combined, frame(HAT_DOWN, f), 0, 0);
  cells.push({ img: scale(combined, Z), label: `ON PLAYER f${f}` });
}

const sheet = contactSheet(cells, { cols: 4, gap: 10, pad: 14 });
drawText(sheet, "FIRST-100 NYE HAT  ORIGINAL ART  ANIMATED", 14, 2, [230, 210, 120, 255]);
writeFileSync(`${OUT}/hat_nye_sheet.png`, encodePNG(sheet));
console.log("wrote hat_nye_sheet.png", sheet.w + "x" + sheet.h);
