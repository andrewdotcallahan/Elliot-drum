# HANDOFF — BabyBand

*Written 2026-07-22 by a Claude session working with Andrew. This zip is the complete, current state of the project. You (the next Claude) are picking up where that session left off — read this whole file before doing anything.*

## What this is

**BabyBand**: an iPhone/iPad app for Andrew's 1.5-year-old, with exactly two screens — a drum kit and a strummable guitar. Toddler-proofing is the core requirement:

- Nothing on screen is interactive except the instruments. Status bar and home indicator hidden.
- **Parent gate**: press and hold BOTH top corners simultaneously for 2 seconds to open the instrument switcher (Drums/Guitar). Auto-dismisses after 8s. A toddler can't trigger it.
- Designed to run locked-on under iOS **Guided Access** (Settings → Accessibility → Guided Access; triple-click side button).
- Screen stays awake (idle timer disabled). Audio uses the `.playback` session so it plays even with the mute switch on.

## Repo layout (this folder = intended git repo root)

- `BabyBand.xcodeproj` — hand-written Xcode 16 project, objectVersion 77 with a `PBXFileSystemSynchronizedRootGroup`, so any file added under `BabyBand/` is auto-included; the pbxproj rarely needs editing. Shared scheme committed at `xcshareddata/xcschemes/BabyBand.xcscheme` (CI needs it).
- `BabyBand/` — 6 Swift files (App, ContentView, ParentGate, AudioEngine, DrumKitView, GuitarView), `Assets.xcassets` (app icon + 8 pre-rendered drum sprite imagesets), `Sounds/` (13 synthesized WAVs).
- `tools/make_sounds.py` — regenerates all 13 WAVs (numpy). `tools/make_previews.py` — renders listening previews. `tools/drumkit_svg/` — parametric SVG generator + Playwright renderer for the drum sprites.
- `.github/workflows/testflight.yml` — the TestFlight CI pipeline. `SETUP-TESTFLIGHT.md` — step-by-step account setup for Andrew. `project.yml` — XcodeGen fallback if Xcode ever rejects the pbxproj.

## Key decisions (don't relitigate without asking Andrew)

- SwiftUI, **iOS 16 deployment target** (no iOS 17-only APIs: no `@Observable`, one-param `onChange` only), iPhone+iPad, all orientations, `UIRequiresFullScreen`, no third-party dependencies.
- **Guitar is tuned to open G major** — strings `guitar_s1..s6` = G2/B2/D3/G3/B3/D4 (98.00/123.47/146.83/196.00/246.94/293.66 Hz) so any strum in any direction is a consonant major chord. Tuning verified to ±0.003%. Andrew approved the guitar's look and feel.
- **Drum kit is GarageBand-styled** (Andrew explicitly asked for this after rejecting a flat-circles version): 7 pieces (kick, snare, hi-hat, two rack toms sharing the `tom_hi` sound, floor tom, crash=`cymbal.wav`, ride) drawn as pre-rendered PNG sprites sourced from SVGs. The clap pad was removed.
- All sounds are synthesized (no licensed samples): drums shaped for non-fatiguing spectra, everything has 2ms fade-in, exact-zero endings, no DC, −1.5 dBFS peaks.
- Sound triggers on touch DOWN; per-piece gestures keep full multitouch.
- Bundle ID: `com.andrewhq.babyband` (change in pbxproj AND project.yml if taken).

## CI / TestFlight (the whole point: no Mac in the loop)

`testflight.yml`: push to main → macos-15 runner → `xcodebuild archive` with cloud-managed signing via an App Store Connect API key → export+upload to TestFlight. Build number = GitHub run number. Four repo secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8_BASE64`. Exact-clicks instructions for all of it are in `SETUP-TESTFLIGHT.md`.

## What is verified vs. NOT

Verified programmatically in the previous session: WAV quality/tuning/clipping, strum-mix consonance, pbxproj structure (braces/UUIDs/settings), scheme XML, workflow YAML, cross-file sound-name consistency, sprite/asset-catalog integrity, and screen mockups rendered from the real sprites at the real layout coordinates (Andrew saw and liked the guitar; the v2 drum mockups were delivered in chat).

**NOT verified: compilation.** The previous session was a Linux container with no Xcode. Every Swift file got two careful review passes for iOS 16 API correctness, but the first real build (CI or Xcode) is the actual test. If the workflow goes red, read the compile error and fix — most likely spots are the `Canvas`/`TimelineView` string animation in GuitarView and the sprite/gesture code in DrumKitView.

## State at handoff & your next steps

1. Andrew was enrolling in the Apple Developer Program ($99, up to 48h) — may still be pending.
2. The previous session could NOT push: its GitHub credential was org-scoped and couldn't reach Andrew's personal repo **github.com/andrewdotcallahan/Elliot-drum**. That's why you exist. First task: get this tree into that repo — `git init`, commit everything in this folder as the repo root, push to main (that will fire CI, which will fail until secrets are set — that's fine, or hold the push until step 3).
3. Walk Andrew through `SETUP-TESTFLIGHT.md` (register bundle ID, create the app record, API key, add the 4 secrets).
4. Drive the first CI run green (fix compile errors if any), confirm the build reaches TestFlight, help him add himself as an internal tester and install on the iPad.
5. Remaining nice-to-haves Andrew hasn't asked for — don't build unsolicited.

## Regenerating things

- Sounds: `python3 tools/make_sounds.py` (writes into `BabyBand/Sounds/`, purges stale files). Previews: `python3 tools/make_previews.py <outdir> [guitar|drums|all]`.
- Drum sprites: `node tools/drumkit_svg/gen_svgs.js` then `node tools/drumkit_svg/render_sprites.js` (needs Playwright chromium), then re-quantize with pngquant.
