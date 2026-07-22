#!/usr/bin/env python3
"""Generate all BabyBand sounds as 16-bit 44.1 kHz mono WAV files.

Writes into ../BabyBand/Sounds/ (next to the Swift sources) so Xcode
picks them up automatically. Requires numpy:  pip3 install numpy

The generated .wav files are committed with the project, so you only
need to run this if you want to tweak the sounds.

Design notes (toddler-friendly, parent-ear-friendly):
  * Every sound gets a 2 ms fade-in and a fade-out to exactly zero,
    plus DC-offset removal, so rapid mashing never clicks or thumps.
  * The 7-piece kit (kick, snare, hihat, tom_hi, tom_floor, cymbal
    crash, ride) peaks at -1.5 dBFS. Hi-hat, crash, and ride are
    band-shaped so energy above 8-12 kHz is rolled off (no fatiguing
    white-noise fizz).
  * Guitar is tuned to OPEN G MAJOR (G2 B2 D3 G3 B3 D4) so any strum
    is a consonant G chord. Karplus-Strong with an allpass
    fractional-delay in the loop plus a measure-and-correct calibration
    pass keeps every string within +/-0.05% of target pitch (integer
    delay lines were up to +0.6% sharp, which beats audibly in chords).
  * The six strings are balanced for equal RMS over their first 300 ms
    (equal peak makes low strings read much louder), then scaled as a
    group so a full six-string strum (30 ms onset stagger) sums to
    -1.5 dBFS peak with no clipping.
"""

import os
import sys
import wave

try:
    import numpy as np
except ImportError:
    sys.exit("numpy is required: run  pip3 install numpy  and try again.")

SR = 44100
OUT_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "BabyBand", "Sounds")
)
PEAK_DBFS = -1.5
STRUM_STAGGER = 0.030  # seconds between string onsets in the clip-check strum

rng = np.random.default_rng(20260722)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def t_axis(duration):
    return np.arange(int(SR * duration)) / SR


def db_to_lin(db):
    return 10.0 ** (db / 20.0)


def normalize(x, peak_db=PEAK_DBFS):
    peak = np.max(np.abs(x))
    if peak == 0:
        return x
    return x * db_to_lin(peak_db) / peak


def clean_edges(x, fade_in=0.002, fade_out=0.010):
    """Apply a 2 ms fade-in and a fade-out to exactly zero, then remove any
    residual DC by subtracting a fade-shaped constant (this keeps both
    endpoints at exactly zero, unlike plain mean subtraction)."""
    x = x - x.mean()
    env = np.ones(len(x))
    n_in = min(len(x), int(SR * fade_in))
    if n_in > 0:
        env[:n_in] = np.linspace(0.0, 1.0, n_in)
    n_out = min(len(x), int(SR * fade_out))
    if n_out > 0:
        env[-n_out:] = np.minimum(env[-n_out:], np.linspace(1.0, 0.0, n_out))
    x = x * env
    x -= (x.sum() / env.sum()) * env  # zero the mean, endpoints stay zero
    return x


def write_wav(name, x, do_normalize=True):
    x = clean_edges(x.astype(np.float64))
    if do_normalize:
        x = normalize(x)
    pcm = np.clip(np.round(x * 32767.0), -32767, 32767).astype("<i2")
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"  {name:16s} {len(x) / SR:5.2f}s  peak {np.max(np.abs(x)):.3f}")


def shape_spectrum(x, gain_fn):
    """Zero-phase spectral shaping: multiply the magnitude spectrum by a
    smooth gain curve. Ideal for shaping one-shot noise-based sounds."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    X *= gain_fn(f)
    return np.fft.irfft(X, n)


def lp_curve(fc, order=2):
    return lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp_curve(fc, order=2):
    return lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-9)) ** (2 * order))


def bp_curve(lo, hi, order=2):
    l, h = hp_curve(lo, order), lp_curve(hi, order)
    return lambda f: l(f) * h(f)


def pitch_sweep(f_start, f_end, duration, decay):
    """Exponential pitch sweep sine with exponential amplitude decay."""
    t = t_axis(duration)
    freq = f_start * (f_end / f_start) ** (t / duration)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t * decay)


def measure_pitch(x, fmin=60.0, fmax=500.0):
    """Autocorrelation pitch estimate with parabolic peak interpolation."""
    seg = x[int(0.05 * SR):int(0.55 * SR)].astype(np.float64)
    seg = seg - seg.mean()
    n = len(seg)
    spec = np.fft.rfft(seg, 2 * n)
    ac = np.fft.irfft(spec * np.conj(spec))[:n]
    ac /= ac[0] + 1e-12
    lo, hi = int(SR / fmax), int(SR / fmin)
    k = int(np.argmax(ac[lo:hi])) + lo
    a, b, c = ac[k - 1], ac[k], ac[k + 1]
    denom = a - 2.0 * b + c
    delta = 0.5 * (a - c) / denom if abs(denom) > 1e-12 else 0.0
    return SR / (k + delta)


# --------------------------------------------------------------------------
# Drums
# --------------------------------------------------------------------------

def kick():
    """Punchy, not boomy: fast 150->46 Hz sweep, tight decay, soft knock
    transient (filtered, not raw white noise), sub rumble high-passed."""
    dur = 0.38
    t = t_axis(dur)
    body = pitch_sweep(150.0, 46.0, dur, 9.5)
    n_k = int(SR * 0.006)
    knock = np.zeros_like(body)
    knock[:n_k] = shape_spectrum(rng.uniform(-1, 1, n_k), bp_curve(150, 1200, 2)) \
        * np.linspace(1.0, 0.0, n_k)
    x = body + 0.5 * knock
    return shape_spectrum(x, hp_curve(34, 2))


def tom_hi():
    """Rack tom: higher and tighter than the floor tom — 200->105 Hz sweep,
    short 0.3 s decay, warm band-passed knock on the attack."""
    dur = 0.30
    body = pitch_sweep(200.0, 105.0, dur, 11.0)
    n_k = int(SR * 0.004)
    knock = np.zeros_like(body)
    knock[:n_k] = shape_spectrum(rng.uniform(-1, 1, n_k), bp_curve(300, 2000, 2)) \
        * np.linspace(1.0, 0.0, n_k)
    return body + 0.3 * knock


def tom_floor():
    """Floor tom: deeper and boomier — 130->65 Hz sweep over 0.45 s with a
    slower decay and a darker, softer knock. High-passed at 40 Hz so the
    boom stays controlled on small speakers."""
    dur = 0.45
    body = pitch_sweep(130.0, 65.0, dur, 7.5)
    n_k = int(SR * 0.005)
    knock = np.zeros_like(body)
    knock[:n_k] = shape_spectrum(rng.uniform(-1, 1, n_k), bp_curve(200, 1200, 2)) \
        * np.linspace(1.0, 0.0, n_k)
    x = body + 0.22 * knock
    return shape_spectrum(x, hp_curve(40, 2))


def snare():
    """Crisp but soft: band-shaped noise (700 Hz - 6.5 kHz, extra roll-off
    above 8 kHz) over two quick drum-head tones."""
    dur = 0.22
    t = t_axis(dur)
    noise = rng.uniform(-1, 1, len(t))
    band = shape_spectrum(noise, bp_curve(700, 6500, 2))
    band = shape_spectrum(band, lp_curve(8000, 3))
    band /= max(np.max(np.abs(band)), 1e-9)
    tones = 0.8 * np.sin(2 * np.pi * 185.0 * t) * np.exp(-t * 28.0) \
        + 0.4 * np.sin(2 * np.pi * 330.0 * t) * np.exp(-t * 32.0)
    return band * np.exp(-t * 20.0) * 0.75 + tones


def hihat():
    """Short and soft-ish: 6-11 kHz band with an extra roll-off above 12 kHz
    instead of full-bandwidth differentiated noise."""
    dur = 0.09
    t = t_axis(dur)
    noise = rng.uniform(-1, 1, len(t))
    band = shape_spectrum(noise, bp_curve(6000, 11000, 3))
    band = shape_spectrum(band, lp_curve(12000, 4))
    return band * np.exp(-t * 45.0)


def cymbal():
    """Non-fatiguing: shimmer band-passed 4-9 kHz (not white noise to 22 k),
    a softer 0.9-4 kHz body layer, slight inharmonic pitch content, and a
    smooth ~1.4 s exponential decay."""
    dur = 1.4
    t = t_axis(dur)
    shimmer = shape_spectrum(rng.uniform(-1, 1, len(t)), bp_curve(4000, 9000, 3))
    shimmer /= max(np.max(np.abs(shimmer)), 1e-9)
    body = shape_spectrum(rng.uniform(-1, 1, len(t)), bp_curve(900, 4000, 2))
    body /= max(np.max(np.abs(body)), 1e-9)
    x = shimmer * np.exp(-t * 3.5) + 0.35 * body * np.exp(-t * 5.0)
    for f, a in ((820.0, 0.06), (1230.0, 0.05), (2050.0, 0.045), (3170.0, 0.04)):
        x += a * np.sin(2 * np.pi * f * t + float(rng.uniform(0, 6.28))) * np.exp(-t * 2.5)
    return x


def ride():
    """Ride cymbal, deliberately distinct from the crash: a clear stick
    "ping" — a short bright transient plus a strong ~1.9 kHz tonal ping with
    a couple of inharmonic partners — over a smoother, quieter sustained
    shimmer. The shimmer sits lower (2.5-6.5 kHz) and decays gently over
    ~2.2 s, so the tail is less washy and less loud than the crash. Energy
    above 8 kHz is kept well under 35% so toddler mashing stays pleasant."""
    dur = 2.2
    t = t_axis(dur)

    # Stick transient: 8 ms bright band-passed click.
    n_k = int(SR * 0.008)
    stick = np.zeros(len(t))
    click = shape_spectrum(rng.uniform(-1, 1, n_k), bp_curve(1500, 6000, 2))
    click /= max(np.max(np.abs(click)), 1e-9)
    stick[:n_k] = click * np.linspace(1.0, 0.0, n_k)

    # Tonal ping: strong ~1.9 kHz fundamental plus inharmonic partials,
    # each with its own decay so the ping "blooms" then settles.
    ping = np.zeros(len(t))
    for f, a, d in ((1900.0, 1.00, 4.0), (2470.0, 0.45, 5.0),
                    (3330.0, 0.30, 6.0), (1130.0, 0.25, 3.2)):
        ping += a * np.sin(2 * np.pi * f * t + float(rng.uniform(0, 6.28))) \
            * np.exp(-t * d)

    # Sustained shimmer: band-shaped 2.5-6.5 kHz, extra roll-off above
    # 8 kHz, quiet and slow (~2.2 s gentle decay).
    shimmer = shape_spectrum(rng.uniform(-1, 1, len(t)), bp_curve(2500, 6500, 3))
    shimmer = shape_spectrum(shimmer, lp_curve(8000, 4))
    shimmer /= max(np.max(np.abs(shimmer)), 1e-9)

    return 0.55 * stick + 0.80 * ping + 0.28 * shimmer * np.exp(-t * 2.0)


# --------------------------------------------------------------------------
# Guitar (open G major, tuned Karplus-Strong)
# --------------------------------------------------------------------------

def ks_string(period, duration, damp):
    """Karplus-Strong with a fractional-delay allpass in the loop.

    Loop delay budget: N samples (delay line) + 0.5 (two-point average
    lowpass) + d (first-order allpass), so period = N + 0.5 + d exactly.
    The excitation noise is pre-lowpassed for a warm, nylon-ish tone and
    a short band-passed pick transient is layered on the attack.
    """
    N = int(np.floor(period - 0.5))
    d = period - N - 0.5
    if d < 0.1:  # keep the allpass coefficient well-conditioned
        N -= 1
        d += 1.0
    C = (1.0 - d) / (1.0 + d)

    exc = rng.uniform(-1, 1, N)
    exc -= exc.mean()
    for _ in range(3):  # warm up the excitation (darker attack)
        exc = 0.5 * (exc + np.roll(exc, 1))

    n = int(SR * duration)
    dl = exc.copy()
    out = np.empty(n)
    ap_x1 = 0.0
    ap_y1 = 0.0
    idx = 0
    for i in range(n):
        cur = dl[idx]
        out[i] = cur
        nxt = dl[(idx + 1) % N]
        lp = damp * 0.5 * (cur + nxt)     # gentle loop lowpass, 0.5-sample delay
        y = C * lp + ap_x1 - C * ap_y1    # fractional delay allpass
        ap_x1 = lp
        ap_y1 = y
        dl[idx] = y
        idx = (idx + 1) % N

    t = np.arange(n) / SR
    out *= np.exp(-t * 1.5)

    n_pick = int(SR * 0.004)
    pick = shape_spectrum(rng.uniform(-1, 1, n_pick), bp_curve(1000, 4000, 2))
    pick /= max(np.max(np.abs(pick)), 1e-9)
    out[:n_pick] += pick * np.linspace(1.0, 0.0, n_pick) * 0.20 * np.max(np.abs(out))
    return out


def pluck(freq, duration=2.0):
    """Tuned pluck: synthesize, measure the pitch by autocorrelation, and
    correct the loop period until within +/-0.03% of the target."""
    damp = 0.9975
    period = SR / freq
    x = ks_string(period, duration, damp)
    for _ in range(4):
        f0 = measure_pitch(x)
        ratio = f0 / freq
        if abs(ratio - 1.0) < 0.0003:
            break
        period *= ratio
        x = ks_string(period, duration, damp)
    return x


# Open G major tuning: G2 B2 D3 G3 B3 D4. Filenames are a fixed contract
# with the UI (StrumView maps string index 1..6 to guitar_sN.wav).
GUITAR_STRINGS = {
    "guitar_s1.wav": 98.00,    # G2
    "guitar_s2.wav": 123.47,   # B2
    "guitar_s3.wav": 146.83,   # D3
    "guitar_s4.wav": 196.00,   # G3
    "guitar_s5.wav": 246.94,   # B3
    "guitar_s6.wav": 293.66,   # D4
}

STALE_FILES = [
    # Pre-open-G guitar names.
    "guitar_e2.wav", "guitar_a2.wav", "guitar_d3.wav",
    "guitar_g3.wav", "guitar_b3.wav", "guitar_e4.wav",
    # Pre-7-piece-kit drum names.
    "tom.wav", "clap.wav",
]


def balance_and_scale_guitar(plucks):
    """Equal RMS over the first 300 ms across strings, then scale the whole
    set so a six-string strum (30 ms stagger) peaks at PEAK_DBFS."""
    n300 = int(SR * 0.300)
    rms = {k: np.sqrt(np.mean(v[:n300] ** 2)) for k, v in plucks.items()}
    target = float(np.mean(list(rms.values())))
    plucks = {k: v * (target / rms[k]) for k, v in plucks.items()}

    stag = int(SR * STRUM_STAGGER)
    names = sorted(plucks)
    length = stag * (len(names) - 1) + max(len(v) for v in plucks.values())
    mix = np.zeros(length)
    for i, k in enumerate(names):
        v = plucks[k]
        mix[i * stag:i * stag + len(v)] += v
    scale = db_to_lin(PEAK_DBFS) / np.max(np.abs(mix))
    return {k: v * scale for k, v in plucks.items()}


# --------------------------------------------------------------------------

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Writing WAVs to {OUT_DIR}")
    for old in STALE_FILES:
        p = os.path.join(OUT_DIR, old)
        if os.path.exists(p):
            os.remove(p)
            print(f"  removed stale {old}")

    write_wav("kick.wav", kick())
    write_wav("snare.wav", snare())
    write_wav("hihat.wav", hihat())
    write_wav("tom_hi.wav", tom_hi())
    write_wav("tom_floor.wav", tom_floor())
    write_wav("cymbal.wav", cymbal())
    write_wav("ride.wav", ride())

    plucks = {}
    for name, freq in GUITAR_STRINGS.items():
        plucks[name] = pluck(freq)
        f0 = measure_pitch(plucks[name])
        print(f"  {name}: tuned to {f0:.3f} Hz (target {freq:.2f}, "
              f"{(f0 / freq - 1) * 100:+.3f}%)")
    plucks = balance_and_scale_guitar(plucks)
    for name, x in plucks.items():
        write_wav(name, x, do_normalize=False)
    print("Done.")


if __name__ == "__main__":
    main()
