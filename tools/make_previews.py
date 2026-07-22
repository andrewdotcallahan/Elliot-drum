#!/usr/bin/env python3
"""Render listening previews of the BabyBand sound set.

Reads the generated WAVs from ../BabyBand/Sounds/ and writes two ~8 s
preview mixes (guitar strums, drum beat) for human review. Not part of
the app bundle. Usage:

    python3 tools/make_previews.py [output_dir] [guitar|drums|all]

Output defaults to the system temp dir; the second argument selects
which previews to render (default: all). If ffmpeg is on PATH, 128 kbps
MP3 versions are written alongside the WAVs.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
SND_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "BabyBand", "Sounds")
)
PEAK_DBFS = -3.0


def read_wav(name):
    with wave.open(os.path.join(SND_DIR, name), "rb") as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 2 and w.getframerate() == SR
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0


def place(mix, sample, t, gain=1.0):
    start = int(t * SR)
    end = min(len(mix), start + len(sample))
    mix[start:end] += sample[: end - start] * gain


def write_preview(path, mix):
    mix = mix * (10.0 ** (PEAK_DBFS / 20.0)) / max(np.max(np.abs(mix)), 1e-9)
    n_out = int(SR * 0.15)
    mix[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    pcm = np.clip(np.round(mix * 32767.0), -32767, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"wrote {path} ({len(mix)/SR:.2f}s, peak {PEAK_DBFS} dBFS)")
    if shutil.which("ffmpeg"):
        mp3 = os.path.splitext(path)[0] + ".mp3"
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-b:a", "128k", mp3],
            check=True,
        )
        print(f"wrote {mp3}")


def guitar_preview():
    strings = [read_wav(f"guitar_s{i}.wav") for i in range(1, 7)]
    mix = np.zeros(int(SR * 8.5))
    # Slow strum up (low to high), 60 ms stagger.
    for i, s in enumerate(strings):
        place(mix, s, 0.2 + 0.060 * i)
    # Faster strum down (high to low), 25 ms stagger.
    for i, s in enumerate(reversed(strings)):
        place(mix, s, 3.0 + 0.025 * i)
    # A few single plucks.
    place(mix, strings[3], 5.4)   # G3
    place(mix, strings[4], 6.1)   # B3
    place(mix, strings[5], 6.8)   # D4
    place(mix, strings[0], 7.4)   # G2
    return mix


def drums_preview():
    """~10 s playful groove at 100 bpm showcasing all 7 kit pieces:
    bar 1  kick/snare backbeat under hi-hat eighths, opening crash
    bar 2  backbeat continues, tom_hi -> tom_floor fill into...
    bar 3  ride section (ride eighths instead of hi-hat), crash accent
    bar 4  big descending fill (tom_hi, tom_floor) and closing crash."""
    kick = read_wav("kick.wav")
    snare = read_wav("snare.wav")
    hihat = read_wav("hihat.wav")
    tom_hi = read_wav("tom_hi.wav")
    tom_floor = read_wav("tom_floor.wav")
    cymbal = read_wav("cymbal.wav")   # crash
    ride = read_wav("ride.wav")

    bpm = 100.0
    beat = 60.0 / bpm            # 0.6 s
    mix = np.zeros(int(SR * 10.5))  # last crash (at 9.6 s) gets room to ring

    def backbeat(t0):
        place(mix, kick, t0 + 0 * beat)
        place(mix, snare, t0 + 1 * beat)
        place(mix, kick, t0 + 2 * beat)
        place(mix, kick, t0 + 2.5 * beat, gain=0.8)
        place(mix, snare, t0 + 3 * beat)

    def eighths(t0, sample, gain):
        for e in range(8):
            place(mix, sample, t0 + e * beat / 2, gain=gain)

    # Bar 1: crash in, hi-hat eighths over the backbeat.
    place(mix, cymbal, 0.0, gain=0.8)
    backbeat(0.0)
    eighths(0.0, hihat, 0.55)

    # Bar 2: same, ending in a tom_hi -> tom_floor pickup fill.
    t1 = 4 * beat
    backbeat(t1)
    eighths(t1, hihat, 0.55)
    place(mix, tom_hi, t1 + 3.25 * beat, gain=0.9)
    place(mix, tom_hi, t1 + 3.5 * beat, gain=0.9)
    place(mix, tom_floor, t1 + 3.75 * beat, gain=0.95)

    # Bar 3: ride section — ride eighths carry the pulse, crash accent on 1.
    t2 = 8 * beat
    place(mix, cymbal, t2, gain=0.7)
    backbeat(t2)
    eighths(t2, ride, 0.6)

    # Bar 4: descending tom fill and a closing kick + crash.
    t3 = 12 * beat
    place(mix, kick, t3)
    place(mix, ride, t3, gain=0.6)
    place(mix, snare, t3 + 1 * beat)
    place(mix, tom_hi, t3 + 2 * beat, gain=0.9)
    place(mix, tom_hi, t3 + 2.5 * beat, gain=0.9)
    place(mix, tom_floor, t3 + 3 * beat, gain=0.95)
    place(mix, tom_floor, t3 + 3.5 * beat, gain=0.95)
    place(mix, kick, t3 + 4 * beat)
    place(mix, cymbal, t3 + 4 * beat, gain=0.9)
    return mix


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else tempfile.gettempdir()
    which = sys.argv[2] if len(sys.argv) > 2 else "all"
    if which not in ("guitar", "drums", "all"):
        sys.exit(f"unknown preview selection {which!r}: use guitar, drums, or all")
    os.makedirs(out_dir, exist_ok=True)
    if which in ("guitar", "all"):
        write_preview(os.path.join(out_dir, "preview_guitar.wav"), guitar_preview())
    if which in ("drums", "all"):
        write_preview(os.path.join(out_dir, "preview_drums.wav"), drums_preview())


if __name__ == "__main__":
    main()
