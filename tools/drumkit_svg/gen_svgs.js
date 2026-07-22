#!/usr/bin/env node
// Generates the hand-tuned drum-kit sprite SVGs (GarageBand-style acoustic kit).
// Run:  node gen_svgs.js
// Emits: kick.svg snare.svg hihat.svg tom_hi.svg tom_floor.svg crash.svg ride.svg stage_bg.svg
// The emitted SVGs are committed next to this script; render_sprites.js turns
// them into 3x PNGs for the asset catalog.

const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------- helpers

let uid = 0;
const nid = (p) => `${p}${++uid}`;

// Chrome linear gradient (vertical banding like polished steel).
function chromeGrad(id, x1 = 0, y1 = 0, x2 = 0, y2 = 1) {
  return `<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">
    <stop offset="0" stop-color="#f4f6f8"/>
    <stop offset="0.18" stop-color="#c8cdd4"/>
    <stop offset="0.38" stop-color="#7d838c"/>
    <stop offset="0.52" stop-color="#e9edf1"/>
    <stop offset="0.70" stop-color="#5c626b"/>
    <stop offset="0.88" stop-color="#2c3138"/>
    <stop offset="1" stop-color="#484e56"/>
  </linearGradient>`;
}

// Mottled-parchment turbulence filter for drum heads.
function headTextureFilter(id, seed) {
  return `<filter id="${id}" x="-10%" y="-10%" width="120%" height="120%">
    <feTurbulence type="fractalNoise" baseFrequency="0.055 0.055" numOctaves="4" seed="${seed}" result="n"/>
    <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.42  0 0 0 0 0.40  0 0 0 0 0.36  0 0 0 0.5 0"/>
    <feComposite operator="in" in2="SourceGraphic"/>
  </filter>`;
}

// Vertical streak filter for the black-oyster shell wrap.
function wrapTextureFilter(id, seed) {
  return `<filter id="${id}" x="-10%" y="-10%" width="120%" height="120%">
    <feTurbulence type="fractalNoise" baseFrequency="0.05 0.004" numOctaves="3" seed="${seed}" result="n"/>
    <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.75  0 0 0 0 0.78  0 0 0 0 0.84  0 0 0 0.38 0"/>
    <feComposite operator="in" in2="SourceGraphic"/>
  </filter>`;
}

// Drum head: parchment ellipse with sheen, mottling, edge shading.
function drumHead(cx, cy, rx, ry, seed, dim = 0) {
  const g1 = nid('hg'), tf = nid('ht');
  const l = 1 - dim;
  const c = (v) => Math.round(v * l);
  return `
  <defs>
    <radialGradient id="${g1}" cx="0.40" cy="0.32" r="0.85">
      <stop offset="0" stop-color="rgb(${c(248)},${c(245)},${c(236)})"/>
      <stop offset="0.45" stop-color="rgb(${c(230)},${c(226)},${c(213)})"/>
      <stop offset="0.78" stop-color="rgb(${c(196)},${c(191)},${c(176)})"/>
      <stop offset="1" stop-color="rgb(${c(148)},${c(143)},${c(129)})"/>
    </radialGradient>
    ${headTextureFilter(tf, seed)}
    <filter id="${tf}b"><feGaussianBlur stdDeviation="${rx * 0.05}"/></filter>
  </defs>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="url(#${g1})"/>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="#ffffff" filter="url(#${tf})" opacity="0.5"/>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx * 0.97}" ry="${ry * 0.97}" fill="none"
           stroke="rgba(80,74,62,0.35)" stroke-width="${rx * 0.012}"/>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx * 0.90}" ry="${ry * 0.90}" fill="none"
           stroke="rgba(255,255,255,0.28)" stroke-width="${rx * 0.008}"/>
  <g filter="url(#${tf}b)">
    <ellipse cx="${cx - rx * 0.18}" cy="${cy - ry * 0.28}" rx="${rx * 0.52}" ry="${ry * 0.40}"
             fill="rgba(255,255,255,0.13)"/>
    <ellipse cx="${cx + rx * 0.10}" cy="${cy + ry * 0.30}" rx="${rx * 0.38}" ry="${ry * 0.26}"
             fill="rgba(60,55,45,0.06)"/>
  </g>`;
}

// Metal hoop around a head: two offset ellipse strokes for 3D depth.
function hoop(cx, cy, rx, ry, t) {
  const g = nid('hoopg');
  return `
  <defs>${chromeGrad(g)}</defs>
  <ellipse cx="${cx}" cy="${cy + t * 0.55}" rx="${rx}" ry="${ry}" fill="none"
           stroke="#1a1d21" stroke-width="${t * 1.15}"/>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="none"
           stroke="url(#${g})" stroke-width="${t}"/>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="none"
           stroke="rgba(255,255,255,0.55)" stroke-width="${t * 0.18}"
           stroke-dasharray="${rx * 0.9} ${rx * 2.6}" stroke-dashoffset="${rx * 1.55}"/>`;
}

// Cylinder side of a drum between head ellipse and bottom ellipse, with
// black-oyster wrap, cylindrical shading, lugs + tension rods.
function shell(cx, cy, rx, ry, depth, seed, lugFracs) {
  const g = nid('shg'), tf = nid('sht'), clip = nid('shc'), lg = nid('lug');
  const p = `M ${cx - rx} ${cy} A ${rx} ${ry} 0 0 0 ${cx + rx} ${cy} L ${cx + rx} ${cy + depth} A ${rx} ${ry} 0 0 1 ${cx - rx} ${cy + depth} Z`;
  let lugs = '';
  for (const f of lugFracs) {
    const x = cx + rx * f;
    const yTop = cy + ry * Math.sqrt(Math.max(0, 1 - f * f));
    const lw = rx * 0.075 * (1 - 0.35 * Math.abs(f));
    const lh = depth * 0.52;
    const ly = yTop + depth * 0.16;
    lugs += `
    <rect x="${x - lw * 0.28}" y="${yTop - depth * 0.05}" width="${lw * 0.56}" height="${depth * 0.24}"
          rx="${lw * 0.2}" fill="#9aa1a9" opacity="0.9"/>
    <rect x="${x - lw / 2}" y="${ly}" width="${lw}" height="${lh}" rx="${lw * 0.42}"
          fill="url(#${lg})" stroke="rgba(0,0,0,0.5)" stroke-width="0.8"/>
    <rect x="${x - lw * 0.14}" y="${ly + lh * 0.1}" width="${lw * 0.28}" height="${lh * 0.8}"
          rx="${lw * 0.14}" fill="rgba(255,255,255,0.35)"/>`;
  }
  return `
  <defs>
    <linearGradient id="${g}" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#07080a"/>
      <stop offset="0.22" stop-color="#23262c"/>
      <stop offset="0.40" stop-color="#3a3e46"/>
      <stop offset="0.55" stop-color="#22252b"/>
      <stop offset="0.8" stop-color="#0d0e11"/>
      <stop offset="1" stop-color="#040506"/>
    </linearGradient>
    ${chromeGrad(lg)}
    ${wrapTextureFilter(tf, seed)}
    <clipPath id="${clip}"><path d="${p}"/></clipPath>
  </defs>
  <path d="${p}" fill="url(#${g})"/>
  <g clip-path="url(#${clip})">
    <rect x="${cx - rx}" y="${cy}" width="${rx * 2}" height="${ry + depth + ry}"
          fill="#ffffff" filter="url(#${tf})" opacity="0.55"/>
    <rect x="${cx - rx}" y="${cy + depth * 0.82}" width="${rx * 2}" height="${depth + ry}"
          fill="rgba(0,0,0,0.45)"/>
  </g>
  ${lugs}
  <path d="M ${cx - rx} ${cy + depth} A ${rx} ${ry} 0 0 0 ${cx + rx} ${cy + depth}"
        fill="none" stroke="#61666e" stroke-width="${rx * 0.035}"/>
  <path d="M ${cx - rx * 0.75} ${cy + depth + ry * 0.66} A ${rx} ${ry} 0 0 0 ${cx + rx * 0.75} ${cy + depth + ry * 0.66}"
        fill="none" stroke="rgba(255,255,255,0.20)" stroke-width="${rx * 0.014}"/>`;
}

// Soft baked contact shadow.
function shadow(cx, cy, rx, ry, op = 0.55) {
  const f = nid('shdf'), g = nid('shdg');
  return `
  <defs>
    <radialGradient id="${g}"><stop offset="0" stop-color="rgba(0,0,0,${op})"/>
    <stop offset="0.7" stop-color="rgba(0,0,0,${op * 0.5})"/><stop offset="1" stop-color="rgba(0,0,0,0)"/></radialGradient>
    <filter id="${f}"><feGaussianBlur stdDeviation="${ry * 0.25}"/></filter>
  </defs>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="url(#${g})" filter="url(#${f})"/>`;
}

// Gold cymbal: lathing grooves, bell, radial highlights, wing nut.
function cymbal(cx, cy, rx, ry, opts = {}) {
  const { rot = 0, bell = 0.17, brightness = 1, grooves = 26 } = opts;
  const g = nid('cyg'), bg = nid('cyb'), clip = nid('cyc'), hf = nid('cyh');
  const b = brightness;
  const col = (r, gg, bb) => `rgb(${Math.round(r * b)},${Math.round(gg * b)},${Math.round(bb * b)})`;
  let rings = '';
  for (let i = 0; i < grooves; i++) {
    const t = i / (grooves - 1);
    const f = bell + 0.06 + (0.985 - bell - 0.06) * Math.pow(t, 0.82);
    const dark = i % 2 === 0;
    const op = 0.06 + 0.14 * t; // grooves get more visible toward the edge
    rings += `<ellipse cx="${cx}" cy="${cy}" rx="${rx * f}" ry="${ry * f}" fill="none"
      stroke="${dark ? `rgba(80,52,10,${op})` : `rgba(255,242,200,${op * 0.8})`}" stroke-width="${rx * 0.0052}"/>`;
  }
  // Radial light streaks (bright wedges sweeping from the bell) and shading.
  const wedge = (a0, a1, o, color = '255,248,215') => {
    const px = (a, r) => `${cx + Math.cos(a) * rx * r} ${cy + Math.sin(a) * ry * r}`;
    return `<path d="M ${cx} ${cy} L ${px(a0, 1.02)} A ${rx * 1.02} ${ry * 1.02} 0 0 1 ${px(a1, 1.02)} Z"
      fill="rgba(${color},${o})" filter="url(#${hf})"/>`;
  };
  const nutW = rx * 0.042;
  return `
  <g transform="rotate(${rot} ${cx} ${cy})">
  <defs>
    <radialGradient id="${g}" cx="0.42" cy="0.36" r="0.80">
      <stop offset="0" stop-color="${col(246, 216, 130)}"/>
      <stop offset="0.35" stop-color="${col(228, 185, 92)}"/>
      <stop offset="0.68" stop-color="${col(196, 148, 58)}"/>
      <stop offset="0.9" stop-color="${col(142, 101, 34)}"/>
      <stop offset="1" stop-color="${col(96, 66, 20)}"/>
    </radialGradient>
    <radialGradient id="${bg}" cx="0.40" cy="0.30" r="0.9">
      <stop offset="0" stop-color="${col(255, 238, 178)}"/>
      <stop offset="0.6" stop-color="${col(216, 168, 76)}"/>
      <stop offset="1" stop-color="${col(150, 106, 36)}"/>
    </radialGradient>
    <clipPath id="${clip}"><ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}"/></clipPath>
    <filter id="${hf}"><feGaussianBlur stdDeviation="${rx * 0.03}"/></filter>
  </defs>
  <ellipse cx="${cx}" cy="${cy + ry * 0.09}" rx="${rx * 1.005}" ry="${ry * 1.005}" fill="rgba(30,18,3,0.9)"/>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="url(#${g})"/>
  <g clip-path="url(#${clip})">
    ${rings}
    ${wedge(-2.65, -2.05, 0.34)}
    ${wedge(-1.5, -1.05, 0.26)}
    ${wedge(-0.55, -0.25, 0.14)}
    ${wedge(0.75, 1.35, 0.20, '30,18,2')}
    ${wedge(2.2, 2.7, 0.14, '30,18,2')}
    <ellipse cx="${cx - rx * 0.30}" cy="${cy - ry * 0.34}" rx="${rx * 0.34}" ry="${ry * 0.30}"
             fill="rgba(255,250,225,0.28)" filter="url(#${hf})"/>
  </g>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="none"
           stroke="rgba(60,38,6,0.7)" stroke-width="${rx * 0.006}"/>
  <path d="M ${cx - rx * 0.985} ${cy + ry * 0.17} A ${rx} ${ry} 0 0 0 ${cx + rx * 0.985} ${cy + ry * 0.17}"
        fill="none" stroke="rgba(255,236,180,0.35)" stroke-width="${rx * 0.007}"/>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx * bell}" ry="${ry * bell}" fill="url(#${bg})"/>
  <ellipse cx="${cx - rx * bell * 0.2}" cy="${cy - ry * bell * 0.3}" rx="${rx * bell * 0.5}" ry="${ry * bell * 0.45}"
           fill="rgba(255,252,230,0.55)"/>
  <ellipse cx="${cx}" cy="${cy}" rx="${nutW * 1.5}" ry="${nutW * 1.05}" fill="#43474d" stroke="#8a9098" stroke-width="1"/>
  <ellipse cx="${cx}" cy="${cy - nutW * 0.35}" rx="${nutW * 0.9}" ry="${nutW * 0.6}" fill="#6a7077"/>
  </g>`;
}

const svgOpen = (w, h) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">`;

// ---------------------------------------------------------------- sprites

function makeKick() {
  const W = 470, H = 500;
  const cx = 235, cy = 232, r = 196;
  const hg = nid('kh'), tf = nid('kt'), hoopG = nid('khp'), legG = nid('kleg');
  // Claw hooks + T-rods around the wooden hoop.
  let claws = '';
  const n = 10;
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2 + Math.PI / n;
    const px = cx + Math.cos(a) * (r + 9), py = cy + Math.sin(a) * (r + 9);
    const ox = cx + Math.cos(a) * (r + 24), oy = cy + Math.sin(a) * (r + 24);
    const deg = (a * 180) / Math.PI + 90;
    claws += `
    <g transform="rotate(${deg} ${px} ${py})">
      <rect x="${px - 7}" y="${py - 11}" width="14" height="22" rx="4"
            fill="url(#${legG})" stroke="rgba(0,0,0,0.55)" stroke-width="0.8"/>
    </g>
    <line x1="${px}" y1="${py}" x2="${ox}" y2="${oy}" stroke="#8b9199" stroke-width="4.5" stroke-linecap="round"/>
    <circle cx="${ox}" cy="${oy}" r="4.6" fill="#b9bfc7" stroke="#2b2e33" stroke-width="0.8"/>`;
  }
  return `${svgOpen(W, H)}
  <defs>
    <radialGradient id="${hg}" cx="0.42" cy="0.34" r="0.85">
      <stop offset="0" stop-color="#f5f2e9"/>
      <stop offset="0.4" stop-color="#e6e2d5"/>
      <stop offset="0.75" stop-color="#c9c4b3"/>
      <stop offset="0.94" stop-color="#9d9786"/>
      <stop offset="1" stop-color="#7e7869"/>
    </radialGradient>
    ${headTextureFilter(tf, 7)}
    <filter id="${tf}b"><feGaussianBlur stdDeviation="${r * 0.06}"/></filter>
    <linearGradient id="${hoopG}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2e3138"/>
      <stop offset="0.5" stop-color="#101216"/>
      <stop offset="1" stop-color="#05060a"/>
    </linearGradient>
    ${chromeGrad(legG)}
  </defs>
  ${shadow(cx, 462, 215, 26, 0.62)}
  <!-- spurs -->
  <g stroke="url(#${legG})" stroke-width="9" stroke-linecap="round">
    <line x1="${cx - r * 0.86}" y1="${cy + r * 0.42}" x2="${cx - r * 1.06}" y2="452"/>
    <line x1="${cx + r * 0.86}" y1="${cy + r * 0.42}" x2="${cx + r * 1.06}" y2="452"/>
  </g>
  <circle cx="${cx - r * 1.06}" cy="452" r="7" fill="#111318"/>
  <circle cx="${cx + r * 1.06}" cy="452" r="7" fill="#111318"/>
  <!-- shell rim behind hoop -->
  <circle cx="${cx}" cy="${cy}" r="${r + 26}" fill="#0b0d11"/>
  <circle cx="${cx}" cy="${cy}" r="${r + 26}" fill="none" stroke="rgba(120,126,134,0.35)" stroke-width="2"/>
  <!-- black wood hoop -->
  <circle cx="${cx}" cy="${cy}" r="${r + 12}" fill="none" stroke="url(#${hoopG})" stroke-width="26"/>
  <circle cx="${cx}" cy="${cy}" r="${r + 23}" fill="none" stroke="rgba(255,255,255,0.16)" stroke-width="1.6"/>
  <!-- resonant head -->
  <circle cx="${cx}" cy="${cy}" r="${r}" fill="url(#${hg})"/>
  <circle cx="${cx}" cy="${cy}" r="${r}" fill="#ffffff" filter="url(#${tf})" opacity="0.5"/>
  <circle cx="${cx}" cy="${cy}" r="${r * 0.965}" fill="none" stroke="rgba(80,74,62,0.35)" stroke-width="2.4"/>
  <g filter="url(#${tf}b)">
    <ellipse cx="${cx - r * 0.22}" cy="${cy - r * 0.30}" rx="${r * 0.5}" ry="${r * 0.36}" fill="rgba(255,255,255,0.13)"/>
    <ellipse cx="${cx + r * 0.12}" cy="${cy + r * 0.34}" rx="${r * 0.4}" ry="${r * 0.28}" fill="rgba(60,55,45,0.05)"/>
    <circle cx="${cx}" cy="${cy}" r="${r * 0.16}" fill="rgba(90,84,70,0.07)"/>
  </g>
  ${claws}
  <!-- pedal -->
  <g>
    <rect x="${cx - 7}" y="${cy + r + 4}" width="14" height="46" rx="5" fill="#22252b" stroke="#565b63" stroke-width="1.2"/>
    <path d="M ${cx - 34} 486 L ${cx + 34} 486 L ${cx + 20} 440 L ${cx - 20} 440 Z" fill="#1a1d22" stroke="#4c5158" stroke-width="1.4"/>
    <circle cx="${cx}" cy="${cy + r - 6}" r="15" fill="#d8d4c8" stroke="#6e6a5e" stroke-width="2"/>
  </g>
</svg>`;
}

// Generic mounted tom / snare / floor tom sprite.
function makeTom({ W, H, rx, ry, depth, seed, lugFracs, snare = false, legs = false, dim = 0, bakeShadow = false }) {
  const cx = W / 2, cy = ry + 14;
  let extra = '';
  const legG = nid('tleg');
  if (legs) {
    const y0 = cy + depth + ry * 0.55;
    extra += `<defs>${chromeGrad(legG)}</defs>
    <g stroke="url(#${legG})" stroke-width="10" stroke-linecap="round">
      <line x1="${cx - rx * 0.80}" y1="${y0 - 14}" x2="${cx - rx * 0.92}" y2="${H - 18}"/>
      <line x1="${cx + rx * 0.80}" y1="${y0 - 14}" x2="${cx + rx * 0.92}" y2="${H - 18}"/>
    </g>
    <circle cx="${cx - rx * 0.92}" cy="${H - 16}" r="7" fill="#111318"/>
    <circle cx="${cx + rx * 0.92}" cy="${H - 16}" r="7" fill="#111318"/>`;
  }
  let snareBody = '';
  if (snare) {
    // Chrome snare shell instead of dark wrap: overlay a steel gradient band.
    const sg = nid('sng'), clip = nid('snc');
    const p = `M ${cx - rx} ${cy} A ${rx} ${ry} 0 0 0 ${cx + rx} ${cy} L ${cx + rx} ${cy + depth} A ${rx} ${ry} 0 0 1 ${cx - rx} ${cy + depth} Z`;
    snareBody = `
    <defs>
      <linearGradient id="${sg}" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stop-color="#1c1f24"/>
        <stop offset="0.16" stop-color="#8f969e"/>
        <stop offset="0.34" stop-color="#e8ecf0"/>
        <stop offset="0.5" stop-color="#aab0b8"/>
        <stop offset="0.68" stop-color="#5a6068"/>
        <stop offset="0.86" stop-color="#23262b"/>
        <stop offset="1" stop-color="#0c0e11"/>
      </linearGradient>
      <clipPath id="${clip}"><path d="${p}"/></clipPath>
    </defs>
    <path d="${p}" fill="url(#${sg})"/>
    <g clip-path="url(#${clip})">
      <rect x="${cx - rx}" y="${cy + depth * 0.84}" width="${rx * 2}" height="${depth + ry}" fill="rgba(0,0,0,0.4)"/>
    </g>`;
  }
  const shadowPart = bakeShadow ? shadow(cx, H - 14, rx * 1.05, ry * 0.24, 0.55) : '';
  return `${svgOpen(W, H)}
  ${shadowPart}
  ${extra}
  ${snare ? snareBody : shell(cx, cy, rx, ry, depth, seed, lugFracs)}
  ${snare ? lugStrip(cx, cy, rx, ry, depth, lugFracs) : ''}
  ${drumHead(cx, cy, rx, ry, seed + 3, dim)}
  ${hoop(cx, cy, rx, ry, rx * 0.055)}
</svg>`;
}

// Lugs drawn on top of the chrome snare shell.
function lugStrip(cx, cy, rx, ry, depth, lugFracs) {
  const lg = nid('lgs');
  let out = `<defs>${chromeGrad(lg)}</defs>`;
  for (const f of lugFracs) {
    const x = cx + rx * f;
    const yTop = cy + ry * Math.sqrt(Math.max(0, 1 - f * f));
    const lw = rx * 0.075 * (1 - 0.35 * Math.abs(f));
    const lh = depth * 0.5;
    const ly = yTop + depth * 0.18;
    out += `<rect x="${x - lw / 2}" y="${ly}" width="${lw}" height="${lh}" rx="${lw * 0.42}"
      fill="url(#${lg})" stroke="rgba(0,0,0,0.55)" stroke-width="0.9"/>
    <rect x="${x - lw * 0.14}" y="${ly + lh * 0.1}" width="${lw * 0.28}" height="${lh * 0.8}"
      rx="${lw * 0.14}" fill="rgba(255,255,255,0.35)"/>`;
  }
  return out;
}

function makeHiHat() {
  const W = 330, H = 540;
  const cx = 165, topY = 100, botY = 126;
  const rx = 152, ry = 46;
  const rodG = nid('hhr');
  return `${svgOpen(W, H)}
  <defs>${chromeGrad(rodG, 0, 0, 1, 0)}</defs>
  ${shadow(cx, H - 16, 120, 18, 0.5)}
  <!-- tripod -->
  <g stroke="url(#${rodG})" stroke-width="8" stroke-linecap="round">
    <line x1="${cx}" y1="${H - 120}" x2="${cx - 78}" y2="${H - 22}"/>
    <line x1="${cx}" y1="${H - 120}" x2="${cx + 78}" y2="${H - 22}"/>
    <line x1="${cx}" y1="${H - 120}" x2="${cx}" y2="${H - 18}"/>
  </g>
  <!-- main rod -->
  <rect x="${cx - 5}" y="${botY}" width="10" height="${H - 130 - botY}" fill="url(#${rodG})" rx="4"/>
  <rect x="${cx - 3.4}" y="${topY - 62}" width="6.8" height="${botY - topY + 70}" fill="url(#${rodG})" rx="3"/>
  <rect x="${cx - 9}" y="${H - 138}" width="18" height="26" rx="5" fill="#7d838b" stroke="#23262b" stroke-width="1"/>
  <!-- clutch above top cymbal -->
  <rect x="${cx - 11}" y="${topY - 58}" width="22" height="20" rx="6" fill="#8d939b" stroke="#23262b" stroke-width="1.2"/>
  <rect x="${cx - 8}" y="${topY - 34}" width="16" height="14" rx="4" fill="#5d636b"/>
  <!-- bottom cymbal -->
  ${cymbal(cx, botY, rx, ry, { rot: 0, bell: 0.15, brightness: 0.86, grooves: 20 })}
  <!-- top cymbal -->
  ${cymbal(cx, topY, rx, ry, { rot: 0, bell: 0.17, brightness: 1.02, grooves: 20 })}
</svg>`;
}

function makeCrash() {
  const W = 460, H = 230;
  return `${svgOpen(W, H)}
  ${cymbal(230, 112, 218, 84, { rot: -7, bell: 0.16, brightness: 1.04, grooves: 30 })}
</svg>`;
}

function makeRide() {
  const W = 490, H = 440;
  const rodG = nid('rrod'), fade = nid('rfade'), rmask = nid('rmask');
  return `${svgOpen(W, H)}
  <defs>
    ${chromeGrad(rodG, 0, 0, 1, 0)}
    <linearGradient id="${fade}" x1="0" y1="0.3" x2="0" y2="1">
      <stop offset="0" stop-color="#fff"/><stop offset="0.55" stop-color="#fff"/>
      <stop offset="1" stop-color="#000"/>
    </linearGradient>
    <mask id="${rmask}"><rect x="0" y="0" width="${W}" height="${H}" fill="url(#${fade})"/></mask>
  </defs>
  <g transform="rotate(3 245 124)" mask="url(#${rmask})">
    <rect x="239.5" y="124" width="11" height="${H - 130}" rx="4.5" fill="url(#${rodG})"/>
  </g>
  ${cymbal(245, 124, 234, 106, { rot: 5, bell: 0.17, brightness: 0.98, grooves: 34 })}
</svg>`;
}

function makeStageBackground() {
  const W = 1400, H = 1000;
  return `${svgOpen(W, H)}
  <defs>
    <linearGradient id="bgv" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#23242e"/>
      <stop offset="0.35" stop-color="#191a22"/>
      <stop offset="0.62" stop-color="#101117"/>
      <stop offset="1" stop-color="#060709"/>
    </linearGradient>
    <radialGradient id="bgspot" cx="0.5" cy="0.18" r="0.85">
      <stop offset="0" stop-color="rgba(120,126,150,0.20)"/>
      <stop offset="0.5" stop-color="rgba(90,94,116,0.07)"/>
      <stop offset="1" stop-color="rgba(0,0,0,0)"/>
    </radialGradient>
    <radialGradient id="bgvig" cx="0.5" cy="0.5" r="0.75">
      <stop offset="0" stop-color="rgba(0,0,0,0)"/>
      <stop offset="0.7" stop-color="rgba(0,0,0,0.05)"/>
      <stop offset="1" stop-color="rgba(0,0,0,0.55)"/>
    </radialGradient>
    <linearGradient id="bgfloor" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="rgba(78,80,100,0.42)"/>
      <stop offset="0.25" stop-color="rgba(44,45,58,0.24)"/>
      <stop offset="1" stop-color="rgba(0,0,0,0)"/>
    </linearGradient>
    <filter id="bgblur"><feGaussianBlur stdDeviation="18"/></filter>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#bgv)"/>
  <rect width="${W}" height="${H}" fill="url(#bgspot)"/>
  <rect x="-60" y="560" width="${W + 120}" height="${H - 540}" fill="url(#bgfloor)" filter="url(#bgblur)"/>
  <rect width="${W}" height="${H}" fill="url(#bgvig)"/>
</svg>`;
}

// ---------------------------------------------------------------- emit

const out = {
  'kick.svg': makeKick(),
  'snare.svg': makeTom({
    W: 360, H: 330, rx: 164, ry: 100, depth: 96, seed: 11,
    lugFracs: [-0.82, -0.45, 0, 0.45, 0.82], snare: true, bakeShadow: true,
  }),
  'tom_hi.svg': makeTom({
    W: 310, H: 300, rx: 142, ry: 96, depth: 92, seed: 21,
    lugFracs: [-0.75, -0.28, 0.28, 0.75],
  }),
  'tom_floor.svg': makeTom({
    W: 400, H: 400, rx: 184, ry: 116, depth: 128, seed: 31,
    lugFracs: [-0.8, -0.42, 0, 0.42, 0.8], legs: true, dim: 0.06, bakeShadow: true,
  }),
  'hihat.svg': makeHiHat(),
  'crash.svg': makeCrash(),
  'ride.svg': makeRide(),
  'stage_bg.svg': makeStageBackground(),
};

for (const [name, svg] of Object.entries(out)) {
  fs.writeFileSync(path.join(__dirname, name), svg);
  console.log('wrote', name);
}
