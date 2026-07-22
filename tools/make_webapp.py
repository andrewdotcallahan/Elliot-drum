#!/usr/bin/env python3
"""Build the single-file web version of BabyBand.

Embeds every sound (BabyBand/Sounds/*.wav) and drum sprite
(BabyBand/Assets.xcassets/*.imageset/*.png) as data URIs inside one
self-contained HTML file that mirrors the native app: drum kit + open-G
guitar, parent gate (hold both top corners 2 s), instrument switcher,
Guided-Access-friendly fullscreen behavior.

    python3 tools/make_webapp.py            -> webapp/babyband.html

The layout tables, gesture logic, and animation parameters are ports of
DrumKitView.swift / GuitarView.swift / ParentGate.swift — keep them in
sync if the native app changes.
"""

import base64
import io
import json
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOUNDS_DIR = ROOT / "BabyBand" / "Sounds"
ASSETS_DIR = ROOT / "BabyBand" / "Assets.xcassets"
OUT_DIR = ROOT / "webapp"

SPRITES = [
    "drum_kick", "drum_snare", "drum_tom_hi", "drum_tom_floor",
    "drum_hihat", "drum_crash", "drum_ride", "drum_stage_bg",
]


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def silent_wav_b64(seconds: float = 0.25, rate: int = 8000) -> str:
    """A looping silent <audio> keeps iOS in playback mode so the mute
    switch doesn't silence Web Audio (same intent as the native app's
    .playback audio session)."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack("<h", 0) * int(rate * seconds))
    return base64.b64encode(buf.getvalue()).decode("ascii")


def build() -> None:
    sounds = {p.stem: b64(p) for p in sorted(SOUNDS_DIR.glob("*.wav"))}
    images = {
        name: "data:image/png;base64," + b64(ASSETS_DIR / f"{name}.imageset" / f"{name}.png")
        for name in SPRITES
    }

    assets_js = (
        "const SOUNDS_B64 = " + json.dumps(sounds) + ";\n"
        "const IMAGES = " + json.dumps(images) + ";\n"
        'const SILENT_WAV = "data:audio/wav;base64,' + silent_wav_b64() + '";\n'
    )

    content = TEMPLATE.replace("/*__ASSETS__*/", assets_js)

    OUT_DIR.mkdir(exist_ok=True)
    standalone = (
        "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
        "<meta charset=\"utf-8\">\n" + HEAD + "</head>\n<body>\n"
        + content + "</body>\n</html>\n"
    )
    out = OUT_DIR / "babyband.html"
    out.write_text(standalone)
    print(f"wrote {out} ({out.stat().st_size / 1e6:.1f} MB)")

    # Body-only variant for publishing as a Claude Artifact (the artifact
    # pipeline supplies its own document skeleton).
    artifact = OUT_DIR / "babyband-artifact.html"
    artifact.write_text(HEAD + content)
    print(f"wrote {artifact} ({artifact.stat().st_size / 1e6:.1f} MB)")


HEAD = """\
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="BabyBand">
<title>BabyBand</title>
"""

TEMPLATE = r"""
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body {
    width: 100%; height: 100%;
    overflow: hidden;
    background: #1a1512;
    touch-action: none;
    -webkit-user-select: none; user-select: none;
    -webkit-touch-callout: none;
    -webkit-tap-highlight-color: transparent;
    overscroll-behavior: none;
    position: fixed; inset: 0;
    font-family: -apple-system, "SF Pro Rounded", system-ui, sans-serif;
  }
  .screen { position: absolute; inset: 0; display: none; }
  .screen.active { display: block; }

  /* ---------- drums ---------- */
  #drums {
    background-image: var(--stage-bg);
    background-size: cover;
    background-position: center;
  }
  .piece { position: absolute; }
  .wob, .bnc { width: 100%; height: 100%; will-change: transform; }
  .piece img {
    position: absolute;
    pointer-events: none;
    -webkit-user-drag: none;
  }
  .ring {
    position: absolute;
    border-radius: 50%;
    border: 2px solid rgba(255,255,255,0.9);
    opacity: 0;
    pointer-events: none;
  }

  /* ---------- guitar ---------- */
  #guitar canvas { position: absolute; inset: 0; }

  /* ---------- parent gate + switcher ---------- */
  .gate-zone { position: absolute; top: 0; width: 90px; height: 90px; z-index: 50; }
  #gate-left { left: 0; }
  #gate-right { right: 0; }
  #switcher {
    position: absolute; inset: 0; z-index: 100;
    background: rgba(0,0,0,0.65);
    display: none;
    align-items: center; justify-content: center;
  }
  #switcher.open { display: flex; }
  .sw-panel { display: flex; flex-direction: column; align-items: center; gap: 28px; padding: 32px; }
  .sw-row { display: flex; gap: 24px; }
  .sw-btn {
    width: 160px; height: 160px;
    border: none; border-radius: 24px;
    background: rgba(255,255,255,0.15);
    color: #fff;
    display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px;
    font-family: inherit; font-size: 22px; font-weight: 700;
    cursor: pointer;
  }
  .sw-btn .emoji { font-size: 64px; line-height: 1; }
  .sw-btn.current { background: #0a84ff; }
  .sw-close {
    border: none; background: none; color: rgba(255,255,255,0.85);
    font-size: 44px; line-height: 1; cursor: pointer;
    width: 56px; height: 56px; border-radius: 50%;
  }
  .sw-close:focus-visible, .sw-btn:focus-visible { outline: 3px solid #0a84ff; outline-offset: 3px; }
</style>

<div id="drums" class="screen"></div>
<div id="guitar" class="screen">
  <canvas id="g-bg"></canvas>
  <canvas id="g-strings"></canvas>
</div>

<div id="gate-left" class="gate-zone"></div>
<div id="gate-right" class="gate-zone"></div>

<div id="switcher">
  <div class="sw-panel">
    <div class="sw-row">
      <button class="sw-btn" id="pick-drums"><span class="emoji">🥁</span>Drums</button>
      <button class="sw-btn" id="pick-guitar"><span class="emoji">🎸</span>Guitar</button>
    </div>
    <button class="sw-close" id="sw-close" aria-label="Close">✕</button>
  </div>
</div>

<script>
/*__ASSETS__*/

document.documentElement.style.setProperty("--stage-bg", "url('" + IMAGES.drum_stage_bg + "')");
document.getElementById("drums").style.backgroundImage = "url('" + IMAGES.drum_stage_bg + "')";

const REDUCED_MOTION = matchMedia("(prefers-reduced-motion: reduce)").matches;

/* ================= audio ================= */

let ctx = null;
const buffers = {};
let silentEl = null;

function decodeAll() {
  for (const [name, b64] of Object.entries(SOUNDS_B64)) {
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    ctx.decodeAudioData(bytes.buffer,
      buf => { buffers[name] = buf; },
      err => console.error("decode failed:", name, err));
  }
}

function ensureAudio() {
  if (!ctx) {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    decodeAll();
  }
  if (ctx.state === "suspended") ctx.resume();
  if (!silentEl) {
    // Looping silent <audio> keeps playback alive through the mute switch.
    silentEl = new Audio(SILENT_WAV);
    silentEl.loop = true;
    silentEl.setAttribute("playsinline", "");
    silentEl.play().catch(() => { silentEl = null; });
  }
}

function play(name) {
  ensureAudio();
  const buf = buffers[name];
  if (!buf) return;
  const src = ctx.createBufferSource();
  src.buffer = buf;
  src.connect(ctx.destination);
  src.start();
}

/* Screen-wake (iOS 16.4+; harmless elsewhere). */
let wakeLock = null;
async function requestWake() {
  try { wakeLock = await navigator.wakeLock.request("screen"); } catch (e) {}
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") requestWake();
});

/* ================= drum kit =================
   Direct port of DrumKitView.swift: design canvases 1400x1000 (landscape)
   and 1000x1800 (portrait), sprites aspect-fit and centered. */

const NAT = {
  kick: [470, 500], snare: [360, 330], tomHi: [310, 300], tomFloor: [400, 400],
  hihat: [330, 540], crash: [460, 230], ride: [490, 440],
};
const PAD = {
  kick: [235, 232, 225, 225], snare: [180, 155, 190, 150],
  tomHi: [155, 145, 165, 145], tomFloor: [200, 185, 205, 180],
  hihat: [165, 113, 175, 95], crash: [230, 112, 235, 118], ride: [245, 124, 240, 120],
};
function P(kind, sprite, sound, cymbal, cx, cy, w) {
  return { kind, sprite, sound, cymbal, cx, cy, w,
           nat: NAT[kind], pad: PAD[kind] };
}
const LANDSCAPE = { canvas: [1400, 1000], pieces: [
  P("crash", "drum_crash", "cymbal", true, 195, 225, 440),
  P("ride", "drum_ride", "ride", true, 1215, 364, 480),
  P("hihat", "drum_hihat", "hihat", true, 150, 555, 320),
  P("tomHi", "drum_tom_hi", "tom_hi", false, 530, 365, 295),
  P("tomHi", "drum_tom_hi", "tom_hi", false, 830, 375, 320),
  P("kick", "drum_kick", "kick", false, 680, 640, 460),
  P("snare", "drum_snare", "snare", false, 265, 720, 350),
  P("tomFloor", "drum_tom_floor", "tom_floor", false, 1125, 690, 390),
]};
const PORTRAIT = { canvas: [1000, 1800], pieces: [
  P("crash", "drum_crash", "cymbal", true, 210, 240, 400),
  P("ride", "drum_ride", "ride", true, 790, 349, 430),
  P("hihat", "drum_hihat", "hihat", true, 135, 900, 300),
  P("tomHi", "drum_tom_hi", "tom_hi", false, 365, 555, 285),
  P("tomHi", "drum_tom_hi", "tom_hi", false, 660, 565, 305),
  P("kick", "drum_kick", "kick", false, 500, 985, 430),
  P("snare", "drum_snare", "snare", false, 255, 1420, 350),
  P("tomFloor", "drum_tom_floor", "tom_floor", false, 755, 1430, 380),
]};

const drumsEl = document.getElementById("drums");
let placed = [];       // built by layoutDrums(); hit-tested topmost-first
let wobbleSigns = [];

function layoutDrums() {
  drumsEl.textContent = "";
  placed = [];
  const w = innerWidth, h = innerHeight;
  const layout = w > h ? LANDSCAPE : PORTRAIT;
  const [cw, ch] = layout.canvas;
  const scale = Math.min(w / cw, h / ch);
  const offX = (w - cw * scale) / 2;
  const offY = (h - ch * scale) / 2;

  layout.pieces.forEach((p, i) => {
    const spriteW = p.w * scale;
    const spriteH = spriteW * p.nat[1] / p.nat[0];
    const unit = spriteW / p.nat[0];
    const margin = spriteW * 0.06;
    const frameW = spriteW + margin * 2;
    const frameH = spriteH + margin * 2;
    const padX = margin + p.pad[0] * unit;
    const padY = margin + p.pad[1] * unit;
    const padRX = p.pad[2] * unit;
    const padRY = p.pad[3] * unit;
    const left = offX + p.cx * scale - frameW / 2;
    const top = offY + p.cy * scale - frameH / 2;

    const el = document.createElement("div");
    el.className = "piece";
    el.style.cssText = `left:${left}px;top:${top}px;width:${frameW}px;height:${frameH}px;`;
    const wob = document.createElement("div");
    wob.className = "wob";
    const bnc = document.createElement("div");
    bnc.className = "bnc";
    const origin = `${padX}px ${padY}px`;
    wob.style.transformOrigin = origin;
    bnc.style.transformOrigin = origin;

    const img = document.createElement("img");
    img.src = IMAGES[p.sprite];
    img.alt = "";
    img.style.cssText = `left:${margin}px;top:${margin}px;width:${spriteW}px;height:${spriteH}px;`;
    bnc.appendChild(img);

    let ring = null;
    if (p.cymbal) {
      ring = document.createElement("div");
      ring.className = "ring";
      ring.style.cssText +=
        `left:${padX - padRX}px;top:${padY - padRY}px;` +
        `width:${padRX * 2}px;height:${padRY * 2}px;` +
        `border-width:${Math.max(2, spriteW * 0.015)}px;`;
      bnc.appendChild(ring);
    }

    wob.appendChild(bnc);
    el.appendChild(wob);
    drumsEl.appendChild(el);

    placed.push({
      piece: p, wob, bnc, ring,
      // hit ellipse in page coords (pad inflated for toddler fingers)
      hx: left + padX, hy: top + padY,
      hrx: padRX * 1.12 + margin, hry: padRY * 1.12 + margin,
    });
  });
  wobbleSigns = placed.map(() => 1);
}

function hitDrums(x, y) {
  for (let i = placed.length - 1; i >= 0; i--) {
    const d = placed[i];
    const dx = (x - d.hx) / d.hrx, dy = (y - d.hy) / d.hry;
    if (dx * dx + dy * dy <= 1) return i;
  }
  return -1;
}

function strikeDrum(i) {
  const d = placed[i];
  play(d.piece.sound);
  if (REDUCED_MOTION) return;
  const down = d.piece.cymbal ? 0.97 : 0.94;
  d.bnc.animate(
    [{ transform: "scale(1)" }, { transform: `scale(${down})`, offset: 0.25 },
     { transform: "scale(1.015)", offset: 0.62 }, { transform: "scale(1)" }],
    { duration: 300, easing: "ease-out" });
  if (d.piece.cymbal) {
    d.ring.animate(
      [{ transform: "scale(1)", opacity: 0.85 }, { transform: "scale(1.22)", opacity: 0 }],
      { duration: 400, easing: "ease-out" });
    wobbleSigns[i] = -wobbleSigns[i];
    const a = 4.5 * wobbleSigns[i];
    const rot = deg => `perspective(600px) rotate3d(1, 0.3, 0, ${deg}deg)`;
    d.wob.animate(
      [{ transform: rot(0) }, { transform: rot(a), offset: 0.12 },
       { transform: rot(-a * 0.55), offset: 0.38 }, { transform: rot(a * 0.28), offset: 0.62 },
       { transform: rot(-a * 0.12), offset: 0.82 }, { transform: rot(0) }],
      { duration: 650, easing: "ease-out" });
  }
}

drumsEl.addEventListener("touchstart", e => {
  e.preventDefault();
  ensureAudio(); requestWake();
  for (const t of e.changedTouches) {
    const i = hitDrums(t.clientX, t.clientY);
    if (i >= 0) strikeDrum(i);
  }
}, { passive: false });
drumsEl.addEventListener("mousedown", e => {
  ensureAudio(); requestWake();
  const i = hitDrums(e.clientX, e.clientY);
  if (i >= 0) strikeDrum(i);
});

/* ================= guitar =================
   Port of GuitarView.swift. Strings span 16%..86% of screen height;
   string 0 (lowest pitch, thickest) at the bottom. */

const STRINGS = [
  { sound: "guitar_s1", thickness: 6.0 },
  { sound: "guitar_s2", thickness: 5.3 },
  { sound: "guitar_s3", thickness: 4.6 },
  { sound: "guitar_s4", thickness: 3.9 },
  { sound: "guitar_s5", thickness: 3.2 },
  { sound: "guitar_s6", thickness: 2.5 },
];
const VIB_DURATION = 0.5, MAX_AMP = 6;

const guitarEl = document.getElementById("guitar");
const bgCanvas = document.getElementById("g-bg");
const strCanvas = document.getElementById("g-strings");
const pluckTimes = STRINGS.map(() => -1e9);   // performance.now() ms
const lastPluck = STRINGS.map(() => -1e9);    // debounce
const touchPrevY = new Map();
let rafRunning = false;

function stringY(i, h) {
  const top = h * 0.16, bottom = h * 0.86;
  return bottom - i * (bottom - top) / 5;
}

function sizeCanvas(canvas) {
  const dpr = Math.min(devicePixelRatio || 1, 2);
  canvas.width = innerWidth * dpr;
  canvas.height = innerHeight * dpr;
  canvas.style.width = innerWidth + "px";
  canvas.style.height = innerHeight + "px";
  const c = canvas.getContext("2d");
  c.setTransform(dpr, 0, 0, dpr, 0, 0);
  return c;
}

function drawGuitarBody() {
  const c = sizeCanvas(bgCanvas);
  const w = innerWidth, h = innerHeight;
  const holeX = w * 0.40, holeY = h * 0.51;
  const R = Math.min(w, h) * (w > h ? 0.185 : 0.22);
  const bx = w * 0.80, bw = Math.min(w, h) * 0.075;
  const btop = h * 0.125, bh = h * 0.77;

  // Warm layered wood + horizontal sheen.
  let g = c.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, "#8c5929"); g.addColorStop(0.5, "#ad7338"); g.addColorStop(1, "#7a4a21");
  c.fillStyle = g; c.fillRect(0, 0, w, h);
  g = c.createLinearGradient(0, 0, w, 0);
  g.addColorStop(0, "rgba(255,255,255,0)");
  g.addColorStop(0.35, "rgba(255,255,255,0.07)");
  g.addColorStop(1, "rgba(255,255,255,0)");
  c.fillStyle = g; c.fillRect(0, 0, w, h);

  // Grain streaks.
  const streaks = [[0.05,2,0.12],[0.13,3,0.09],[0.24,2,0.13],[0.35,2.5,0.09],
                   [0.48,2,0.11],[0.63,3,0.09],[0.77,2,0.12],[0.92,2.5,0.10]];
  for (const [fy, sh, op] of streaks) {
    c.fillStyle = `rgba(64,33,13,${op})`;
    c.fillRect(0, fy * h - sh / 2, w, sh);
  }

  const circle = (r, stroke, lw, dash) => {
    c.beginPath(); c.arc(holeX, holeY, r, 0, Math.PI * 2);
    c.strokeStyle = stroke; c.lineWidth = lw;
    c.setLineDash(dash || []); c.stroke(); c.setLineDash([]);
  };
  // Rosette: dark band, dashed gold mosaic, thin gold rings.
  circle(R * 1.18, "#331a0a", R * 0.18);
  circle(R * 1.18, "rgba(217,173,89,0.8)", R * 0.06, [R * 0.07, R * 0.05]);
  circle(R * 1.06, "#d9ae59", 2);
  circle(R * 1.30, "#d9ae59", 2);

  // Soundhole.
  g = c.createRadialGradient(holeX, holeY, 0, holeX, holeY, R);
  g.addColorStop(0, "#1a0f08"); g.addColorStop(1, "#080503");
  c.beginPath(); c.arc(holeX, holeY, R, 0, Math.PI * 2);
  c.fillStyle = g; c.fill();
  circle(R, "rgba(0,0,0,0.6)", 4);

  // Bridge bar, saddle, pins.
  c.save();
  c.shadowColor = "rgba(0,0,0,0.4)"; c.shadowBlur = 5; c.shadowOffsetX = 3; c.shadowOffsetY = 3;
  g = c.createLinearGradient(bx - bw / 2, 0, bx + bw / 2, 0);
  g.addColorStop(0, "#3d1f0d"); g.addColorStop(1, "#241208");
  c.fillStyle = g;
  c.beginPath(); c.roundRect(bx - bw / 2, btop, bw, bh, bw * 0.35); c.fill();
  c.restore();
  c.fillStyle = "#ebebeb";
  c.beginPath();
  c.roundRect(bx - bw * 0.18 - bw * 0.07, btop + bh * 0.06, bw * 0.14, bh * 0.88, bw * 0.07);
  c.fill();
  for (let i = 0; i < 6; i++) {
    c.beginPath(); c.arc(bx + bw * 0.22, stringY(i, h), bw * 0.12, 0, Math.PI * 2);
    c.fillStyle = "#e6e6e6"; c.fill();
    c.strokeStyle = "rgba(0,0,0,0.5)"; c.lineWidth = 1; c.stroke();
  }
}

function layoutGuitar() {
  drawGuitarBody();
  sizeCanvas(strCanvas);
  drawStrings();
}

function drawStrings() {
  const c = strCanvas.getContext("2d");
  const w = innerWidth, h = innerHeight;
  c.clearRect(0, 0, w, h);
  const now = performance.now();
  let anyVibrating = false;

  STRINGS.forEach((s, i) => {
    const y = stringY(i, h);
    const elapsed = (now - pluckTimes[i]) / 1000;
    const progress = elapsed / VIB_DURATION;
    const vibrating = !REDUCED_MOTION && progress >= 0 && progress < 1;
    if (vibrating) anyVibrating = true;
    const amp = vibrating ? MAX_AMP * (1 - progress) : 0;

    c.save();
    const glow = vibrating ? 1 - progress : 0;
    if (glow > 0.02) {
      c.shadowColor = `rgba(255,230,128,${glow * 0.8})`;
      c.shadowBlur = 10;
    } else {
      c.shadowColor = "rgba(0,0,0,0.35)";
      c.shadowBlur = 2; c.shadowOffsetY = 2;
    }

    c.beginPath();
    c.moveTo(0, y);
    if (amp > 0.1) {
      const phase = elapsed * 55;
      for (let x = 0; x <= w; x += 6) {
        const f = x / w;
        const envelope = Math.sin(f * Math.PI);
        const wave = Math.sin(f * 3 * 2 * Math.PI + phase);
        c.lineTo(x, y + amp * envelope * wave);
      }
      c.lineTo(w, y);
    } else {
      c.lineTo(w, y);
    }
    const g = c.createLinearGradient(0, y - s.thickness, 0, y + s.thickness);
    g.addColorStop(0, "#999999"); g.addColorStop(0.5, "#fafafa"); g.addColorStop(1, "#858585");
    c.strokeStyle = g;
    c.lineWidth = s.thickness;
    c.lineCap = "round";
    c.stroke();
    c.restore();
  });

  if (anyVibrating) requestAnimationFrame(drawStrings);
  else rafRunning = false;
}

function kickStringLoop() {
  if (!rafRunning) { rafRunning = true; requestAnimationFrame(drawStrings); }
}

function pluck(i) {
  const now = performance.now();
  if (now - lastPluck[i] < 80) return;   // per-string debounce
  lastPluck[i] = now;
  pluckTimes[i] = now;
  play(STRINGS[i].sound);
  kickStringLoop();
}

function guitarTouch(id, y, isFirst) {
  const h = innerHeight;
  const step = (h * 0.70) / 5;
  const prev = touchPrevY.get(id);
  for (let i = 0; i < 6; i++) {
    const sy = stringY(i, h);
    let hit;
    if (!isFirst && prev !== undefined) {
      hit = (prev < sy && y >= sy) || (prev > sy && y <= sy);
    } else {
      hit = Math.abs(y - sy) < step * 0.45;
    }
    if (hit) pluck(i);
  }
  touchPrevY.set(id, y);
}

guitarEl.addEventListener("touchstart", e => {
  e.preventDefault();
  ensureAudio(); requestWake();
  for (const t of e.changedTouches) guitarTouch(t.identifier, t.clientY, true);
}, { passive: false });
guitarEl.addEventListener("touchmove", e => {
  e.preventDefault();
  for (const t of e.changedTouches) guitarTouch(t.identifier, t.clientY, false);
}, { passive: false });
const guitarTouchEnd = e => {
  for (const t of e.changedTouches) touchPrevY.delete(t.identifier);
};
guitarEl.addEventListener("touchend", guitarTouchEnd);
guitarEl.addEventListener("touchcancel", guitarTouchEnd);
guitarEl.addEventListener("mousedown", e => {
  ensureAudio(); requestWake();
  guitarTouch("mouse", e.clientY, true);
  const move = ev => guitarTouch("mouse", ev.clientY, false);
  const up = () => {
    touchPrevY.delete("mouse");
    removeEventListener("mousemove", move); removeEventListener("mouseup", up);
  };
  addEventListener("mousemove", move); addEventListener("mouseup", up);
});

/* ================= parent gate + switcher ================= */

let current = "drums";
try { current = localStorage.getItem("babyband.instrument") || "drums"; } catch (e) {}

function show(instrument) {
  current = instrument;
  try { localStorage.setItem("babyband.instrument", instrument); } catch (e) {}
  document.getElementById("drums").classList.toggle("active", instrument === "drums");
  document.getElementById("guitar").classList.toggle("active", instrument === "guitar");
  document.getElementById("pick-drums").classList.toggle("current", instrument === "drums");
  document.getElementById("pick-guitar").classList.toggle("current", instrument === "guitar");
  if (instrument === "guitar") layoutGuitar();
  else layoutDrums();
}

const gate = { left: false, right: false, timer: null };
function gateUpdate() {
  clearTimeout(gate.timer);
  gate.timer = null;
  if (gate.left && gate.right) {
    gate.timer = setTimeout(() => {
      if (gate.left && gate.right) {
        gate.left = gate.right = false;
        openSwitcher();
      }
    }, 2000);
  }
}
function bindGate(el, side) {
  const down = e => { e.preventDefault(); if (!gate[side]) { gate[side] = true; gateUpdate(); } };
  const up = () => { gate[side] = false; gateUpdate(); };
  el.addEventListener("touchstart", down, { passive: false });
  el.addEventListener("touchend", up);
  el.addEventListener("touchcancel", up);
  el.addEventListener("mousedown", down);
  el.addEventListener("mouseup", up);
  el.addEventListener("mouseleave", up);
}
bindGate(document.getElementById("gate-left"), "left");
bindGate(document.getElementById("gate-right"), "right");

const switcherEl = document.getElementById("switcher");
let autoDismiss = null;
function openSwitcher() {
  switcherEl.classList.add("open");
  clearTimeout(autoDismiss);
  autoDismiss = setTimeout(closeSwitcher, 8000);
}
function closeSwitcher() {
  switcherEl.classList.remove("open");
  clearTimeout(autoDismiss);
}
switcherEl.addEventListener("click", e => { if (e.target === switcherEl) closeSwitcher(); });
document.getElementById("sw-close").addEventListener("click", closeSwitcher);
document.getElementById("pick-drums").addEventListener("click", () => { show("drums"); closeSwitcher(); });
document.getElementById("pick-guitar").addEventListener("click", () => { show("guitar"); closeSwitcher(); });

/* ================= boot ================= */

function relayout() {
  if (document.getElementById("drums").classList.contains("active")) layoutDrums();
  else layoutGuitar();
}
addEventListener("resize", relayout);
addEventListener("orientationchange", () => setTimeout(relayout, 250));

document.addEventListener("gesturestart", e => e.preventDefault());
document.addEventListener("contextmenu", e => e.preventDefault());
document.addEventListener("dblclick", e => e.preventDefault());

show(current);
</script>
"""

if __name__ == "__main__":
    build()
