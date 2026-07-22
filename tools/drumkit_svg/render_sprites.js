#!/usr/bin/env node
// Renders the sprite SVGs to 3x transparent PNGs and composes full-screen
// mockups at the exact unit coordinates DrumKitView.swift uses.
// Run:  NODE_PATH=$(npm root -g) PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers node render_sprites.js <outDir>

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const OUT = process.argv[2] || path.join(__dirname, 'out');

// Sprite name -> natural unit size (must match the SVG viewBox).
const SPRITES = {
  drum_kick: ['kick.svg', 470, 500],
  drum_snare: ['snare.svg', 360, 330],
  drum_tom_hi: ['tom_hi.svg', 310, 300],
  drum_tom_floor: ['tom_floor.svg', 400, 400],
  drum_hihat: ['hihat.svg', 330, 540],
  drum_crash: ['crash.svg', 460, 230],
  drum_ride: ['ride.svg', 490, 440],
  drum_stage_bg: ['stage_bg.svg', 1400, 1000],
};

// ---- Coordinate tables. MUST MATCH DrumKitView.swift exactly. ----
// [sprite, centerX, centerY, width] in unit coordinates; height follows
// from the sprite's natural aspect. Array order = draw order.
const LANDSCAPE = { w: 1400, h: 1000, pieces: [
  ['drum_crash',     195, 225, 440],
  ['drum_ride',     1215, 364, 480],
  ['drum_hihat',     150, 555, 320],
  ['drum_tom_hi',    530, 365, 295],
  ['drum_tom_hi',    830, 375, 320],
  ['drum_kick',      680, 640, 460],
  ['drum_snare',     265, 720, 350],
  ['drum_tom_floor',1125, 690, 390],
]};

const PORTRAIT = { w: 1000, h: 1800, pieces: [
  ['drum_crash',     210, 240, 400],
  ['drum_ride',      790, 349, 430],
  ['drum_hihat',     135, 900, 300],
  ['drum_tom_hi',    365, 555, 285],
  ['drum_tom_hi',    660, 565, 305],
  ['drum_kick',      500, 985, 430],
  ['drum_snare',     255, 1420, 350],
  ['drum_tom_floor', 755, 1430, 380],
]};

function mockupHTML(table, dir) {
  const scaleFit = `
    const K = { w: ${table.w}, h: ${table.h} };
    const s = Math.min(innerWidth / K.w, innerHeight / K.h);
    const ox = (innerWidth - K.w * s) / 2, oy = (innerHeight - K.h * s) / 2;`;
  let imgs = '';
  for (const [name, cx, cy, w] of table.pieces) {
    const [, nw, nh] = SPRITES[name];
    const h = (w * nh) / nw;
    imgs += `place('${name}', ${cx}, ${cy}, ${w}, ${h});\n`;
  }
  return `<!doctype html><html><head><style>
  html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#0a0b10}
  #bg{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
  .sp{position:absolute}
  </style></head><body>
  <img id="bg" src="file://${dir}/drum_stage_bg.png">
  <div id="kit"></div>
  <script>
  ${scaleFit}
  function place(name, cx, cy, w, h) {
    const img = document.createElement('img');
    img.className = 'sp';
    img.src = 'file://${dir}/' + name + '.png';
    img.style.left = (ox + (cx - w/2) * s) + 'px';
    img.style.top = (oy + (cy - h/2) * s) + 'px';
    img.style.width = (w * s) + 'px';
    img.style.height = (h * s) + 'px';
    document.getElementById('kit').appendChild(img);
  }
  ${imgs}
  </script></body></html>`;
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();

  // 1) Render each sprite SVG to a transparent PNG at 3x.
  // (COMPOSE_ONLY=1 skips this and just recomposes mockups from OUT.)
  for (const [outName, [svgFile, w, h]] of process.env.COMPOSE_ONLY ? [] : Object.entries(SPRITES)) {
    const isBG = outName === 'drum_stage_bg';
    const scale = isBG ? 1 : 3;
    const page = await browser.newPage({
      viewport: { width: w, height: h },
      deviceScaleFactor: scale,
    });
    const svg = fs.readFileSync(path.join(__dirname, svgFile), 'utf8');
    await page.setContent(
      `<!doctype html><style>html,body{margin:0;padding:0}svg{display:block}</style>${svg}`
    );
    await page.screenshot({ path: path.join(OUT, `${outName}.png`), omitBackground: !isBG });
    await page.close();
    console.log('rendered', outName);
  }

  // 2) Compose mockups.
  const shots = [
    ['mockup_drums_v2_ipad.png', 1194, 834, LANDSCAPE],
    ['mockup_drums_v2_iphone.png', 393, 852, PORTRAIT],
  ];
  for (const [file, w, h, table] of shots) {
    const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2 });
    const htmlPath = path.join(OUT, file.replace('.png', '.html'));
    fs.writeFileSync(htmlPath, mockupHTML(table, OUT));
    await page.goto('file://' + htmlPath);
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(OUT, file) });
    await page.close();
    console.log('composed', file);
  }

  await browser.close();
})();
