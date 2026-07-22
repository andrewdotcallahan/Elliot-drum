# BabyBand 🥁🎸

A toddler-proof music app for iPhone and iPad. Two instruments — a big
colorful drum kit and a strummable six-string guitar — with nothing on
screen a little one can mess up. Instrument switching is hidden behind
an adult-only gesture, and the app is designed to be locked on with
iOS Guided Access.

Everything is included: source code, sounds, app icon, and the Xcode
project. There are no third-party dependencies.

## 1. What you need

- A Mac with **Xcode 16 or newer** (free from the Mac App Store).
- An **Apple ID** (a free one is enough — no paid developer account needed).
- An iPhone or iPad running **iOS 16 or newer**, plus its charging cable.

## 2. Build and install it on your device

1. Unzip this folder and double-click **`BabyBand.xcodeproj`**. Xcode opens.
2. Sign in with your Apple ID (once): Xcode menu → **Settings… → Accounts →
   "+" → Apple ID**.
3. Set the signing team: click the blue **BabyBand** project icon at the top
   of the left sidebar → select the **BabyBand** target → **Signing &
   Capabilities** tab → check **Automatically manage signing** and pick your
   name under **Team**. If Xcode complains the bundle identifier is taken,
   change `com.family.babyband` to something unique like
   `com.yourlastname.babyband`.
4. Plug in the iPhone/iPad with the cable. On the device, tap **Trust** when
   asked. In Xcode's toolbar, click the device selector (top middle) and
   choose your device.
5. Enable **Developer Mode** on the device (iOS 16+ requires this once):
   **Settings → Privacy & Security → Developer Mode** → turn on → the device
   restarts → confirm. If you don't see the option, connect the device to
   Xcode once first, then look again.
6. Press the **▶ Run** button (or Cmd-R). The first build takes a minute.
   If the app installs but won't open, go to the device's **Settings →
   General → VPN & Device Management** and tap **Trust** for your developer
   certificate.

## 3. How long the install lasts

- **Free Apple ID:** the app expires after **7 days**. Just plug in and
  press Run again to re-install (your settings survive). You can have at
  most 3 sideloaded apps at a time.
- **Paid Apple Developer Program ($99/year):** installs last **1 year**,
  and you unlock **TestFlight**, the nicest option for family devices:
  1. In Xcode: **Product → Archive**, then in the Organizer window click
     **Distribute App → TestFlight & App Store → Upload**.
  2. On [App Store Connect](https://appstoreconnect.apple.com), create the
     app record if prompted, open **TestFlight**, and add yourself (and any
     family member's Apple ID) as an **internal tester**.
  3. Install the **TestFlight** app on the iPhone/iPad, accept the invite,
     and install BabyBand. Builds last 90 days and update over the air —
     no cable needed.

### No Mac? TestFlight via GitHub Actions

If the project lives in a GitHub repo, you don't need a Mac at all: a
ready-made CI pipeline (`.github/workflows/testflight.yml`) builds, signs,
and uploads the app to TestFlight on every push to `main`, and the app
updates over the air on your devices. One-time setup (Apple Developer
Program + a few clicks) is walked through step by step in
**[SETUP-TESTFLIGHT.md](SETUP-TESTFLIGHT.md)**.

## 4. Lock it on with Guided Access (recommended!)

Guided Access keeps the toddler inside the app — no Home swipe, no
Control Center, no notifications.

1. **Settings → Accessibility → Guided Access** → turn it **on**.
2. Set a **Passcode** (or enable Face ID/Touch ID ending) under
   *Passcode Settings*.
3. Open BabyBand, then **triple-click the side (or Home) button** to start
   Guided Access.
4. Optional, tap **Options** (bottom-left) before starting: you can leave
   everything at its defaults — the app has no keyboard and doesn't use
   motion. Just make sure **Touch** stays ON. Turning off the volume
   buttons is up to you.
5. To end: triple-click again and enter your passcode.

## 5. Switching instruments (the parent gate)

The screens are intentionally free of buttons. To switch between drums
and guitar:

**Press and hold BOTH top corners of the screen at the same time for
2 seconds.** A switcher appears with two big buttons — 🥁 Drums and 🎸
Guitar — plus an X to close. It goes away by itself after 8 seconds if
you don't touch it. The app remembers the last instrument you picked.

## 6. Plan B: if Xcode won't open the project file

The project file was written for Xcode 16's format. If your Xcode
refuses to open it, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
using the included `project.yml`:

```
brew install xcodegen
cd BabyBand        # the folder containing project.yml
xcodegen generate
```

Then open the freshly generated `BabyBand.xcodeproj` and continue from
step 2 above.

## Extras

- `tools/make_sounds.py` regenerates all the drum and guitar sounds
  (synthesized — the guitar uses Karplus-Strong plucked-string synthesis).
  Requires Python 3 with numpy: `pip3 install numpy && python3 tools/make_sounds.py`.
  You only need this if you want to tweak the sounds; the .wav files are
  already included.
