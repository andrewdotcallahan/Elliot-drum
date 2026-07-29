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


# Loudness normalization target, in phone-band RMS units (see
# phone_loud300). Chosen so the peak-limited drums can just reach it;
# everything louder (guitar, xylophone, cymbals) is trimmed down to it.
PHONE_TARGET = 0.065
PEAK_CAP = 0.97


def phone_weight(x):
    """Rough phone-speaker response: 4th-order highpass at 300 Hz."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    X *= 1.0 / np.sqrt(1.0 + (300.0 / np.maximum(f, 1e-9)) ** 8)
    return np.fft.irfft(X, len(x))


def phone_loud300(x):
    """Perceived level of a hit on a phone: RMS of the phone-weighted
    signal over the first 300 ms."""
    return np.sqrt(np.mean(phone_weight(x)[: int(SR * 0.300)] ** 2))


def phone_calibrate(x, target=PHONE_TARGET):
    """Scale so phone_loud300 == target, capped so the file peak stays
    below PEAK_CAP (peak-limited sounds land as close as they can)."""
    g = target / max(phone_loud300(x), 1e-12)
    g = min(g, PEAK_CAP / max(np.max(np.abs(x)), 1e-12))
    return x * g


def write_wav(name, x, do_normalize=True, phone_target=None, loop=False):
    x = x.astype(np.float64)
    if not loop:  # a seamless loop must keep its endpoints untouched
        x = clean_edges(x)
    if do_normalize:
        x = normalize(x)
    if phone_target is not None:
        x = phone_calibrate(x, phone_target)
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
    transient (filtered, not raw white noise), sub rumble high-passed.

    Phone speakers can't reproduce the 46 Hz fundamental, so quieter
    2nd/3rd-harmonic sweeps ride along in the 100-450 Hz range the
    speaker CAN play — the ear reconstructs the missing fundamental
    (residue pitch), so the kick still reads as a deep thump."""
    dur = 0.38
    t = t_axis(dur)
    body = pitch_sweep(150.0, 46.0, dur, 9.5)
    h2 = pitch_sweep(300.0, 92.0, dur, 11.0)
    h3 = pitch_sweep(450.0, 138.0, dur, 12.5)
    n_k = int(SR * 0.006)
    knock = np.zeros_like(body)
    knock[:n_k] = shape_spectrum(rng.uniform(-1, 1, n_k), bp_curve(200, 1800, 2)) \
        * np.linspace(1.0, 0.0, n_k)
    x = body + 0.65 * h2 + 0.35 * h3 + 0.7 * knock
    return shape_spectrum(x, hp_curve(34, 2))


def tom_hi():
    """Rack tom: higher and tighter than the floor tom — 200->105 Hz sweep,
    short 0.3 s decay, warm band-passed knock on the attack."""
    dur = 0.30
    body = pitch_sweep(200.0, 105.0, dur, 11.0)
    h2 = pitch_sweep(400.0, 210.0, dur, 13.0)   # phone-speaker presence
    n_k = int(SR * 0.004)
    knock = np.zeros_like(body)
    knock[:n_k] = shape_spectrum(rng.uniform(-1, 1, n_k), bp_curve(300, 2000, 2)) \
        * np.linspace(1.0, 0.0, n_k)
    return body + 0.25 * h2 + 0.3 * knock


def tom_floor():
    """Floor tom: deeper and boomier — 130->65 Hz sweep over 0.45 s with a
    slower decay and a darker, softer knock. High-passed at 40 Hz so the
    boom stays controlled on small speakers."""
    dur = 0.45
    body = pitch_sweep(130.0, 65.0, dur, 7.5)
    h2 = pitch_sweep(260.0, 130.0, dur, 8.5)    # phone-speaker presence
    h3 = pitch_sweep(390.0, 195.0, dur, 9.5)
    n_k = int(SR * 0.005)
    knock = np.zeros_like(body)
    knock[:n_k] = shape_spectrum(rng.uniform(-1, 1, n_k), bp_curve(200, 1500, 2)) \
        * np.linspace(1.0, 0.0, n_k)
    x = body + 0.55 * h2 + 0.30 * h3 + 0.4 * knock
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


def small_speaker_exciter(x, amount):
    """Psychoacoustic bass for phone speakers: soft-saturate the signal to
    generate upper harmonics of the (inaudible-on-phone) low fundamental,
    keep only the 300 Hz - 3 kHz band, and mix it back in. Harmonics stay
    exactly harmonic, so the pitch is unchanged — the ear reconstructs the
    fundamental from the series. amount=0 is a no-op."""
    if amount <= 0:
        return x
    peak = max(np.max(np.abs(x)), 1e-9)
    harm = np.tanh(4.0 * x / peak)
    harm = shape_spectrum(harm, bp_curve(300, 3000, 2))
    harm *= peak / max(np.max(np.abs(harm)), 1e-9)
    y = x + amount * harm
    # Energy-preserving: trade (phone-inaudible) fundamental level for the
    # audible harmonics instead of just getting louder, so the balance
    # across strings survives the later group scaling.
    return y * np.sqrt(np.mean(x ** 2) / max(np.mean(y ** 2), 1e-12))


# --------------------------------------------------------------------------
# Xylophone (toy 8-bar C major, C5..C6)
# --------------------------------------------------------------------------

def xylo_bar(freq):
    """Wooden xylophone bar: quint-tuned partials (f, 3f, ~6.7f) with a soft
    mallet thock on the attack. Lower bars ring a little longer; everything
    decays fast enough that glissando mashing stays clean."""
    rel = freq / 523.25                     # 1.0 at C5
    dur = 0.85 / rel ** 0.35
    t = t_axis(dur)
    decay = 6.5 * rel ** 0.5
    x = np.zeros(len(t))
    for mult, amp, dmul in ((1.0, 1.00, 1.0), (3.0, 0.30, 2.2), (6.7, 0.10, 3.5)):
        x += amp * np.sin(2 * np.pi * freq * mult * t + float(rng.uniform(0, 6.28))) \
            * np.exp(-t * decay * dmul)
    n_m = int(SR * 0.003)
    mallet = shape_spectrum(rng.uniform(-1, 1, n_m), bp_curve(800, 4500, 2))
    mallet /= max(np.max(np.abs(mallet)), 1e-9)
    x[:n_m] += 0.18 * mallet * np.linspace(1.0, 0.0, n_m)
    return shape_spectrum(x, lp_curve(9000, 3))


# --------------------------------------------------------------------------
# Piano (toy grand: 8 keys, C4..C5)
# --------------------------------------------------------------------------

def piano_note(freq):
    """Struck-string tone: slightly stretched partials (real piano strings
    are stiff), per-partial decays, a faintly detuned unison string for
    warmth, and a soft hammer thump on the attack."""
    rel = freq / 261.63                      # 1.0 at C4
    dur = 1.5 / rel ** 0.3
    t = t_axis(dur)
    x = np.zeros(len(t))
    stretch = 0.00015
    for k in range(1, 14):
        fk = k * freq * np.sqrt(1.0 + stretch * k * k)
        if fk > 8500:
            break
        amp = 1.0 / k ** 1.25
        decay = 3.0 * rel ** 0.4 + 1.1 * k
        x += amp * np.sin(2 * np.pi * fk * t + float(rng.uniform(0, 6.28))) \
            * np.exp(-t * decay)
    x += 0.4 * np.sin(2 * np.pi * freq * 1.0015 * t) * np.exp(-t * 3.0 * rel ** 0.4)
    n_h = int(SR * 0.004)
    thump = shape_spectrum(rng.uniform(-1, 1, n_h), bp_curve(150, 2500, 2))
    thump /= max(np.max(np.abs(thump)), 1e-9)
    x[:n_h] += 0.25 * thump * np.linspace(1.0, 0.0, n_h)
    return shape_spectrum(x, lp_curve(9000, 3))


# Filenames are a fixed contract with the UIs: key index 1..8, low to high.
PIANO_NOTES = {
    "piano_1.wav": 261.63,   # C4
    "piano_2.wav": 293.66,   # D4
    "piano_3.wav": 329.63,   # E4
    "piano_4.wav": 349.23,   # F4
    "piano_5.wav": 392.00,   # G4
    "piano_6.wav": 440.00,   # A4
    "piano_7.wav": 493.88,   # B4
    "piano_8.wav": 523.25,   # C5
}


# --------------------------------------------------------------------------
# Hand drums (congas + bongo)
# --------------------------------------------------------------------------

def hand_drum(f0, slap):
    """Conga/bongo hit: a membrane tone that starts ~10% sharp and settles
    (the classic head bend), one inharmonic overtone, and a short palm-slap
    noise burst. Higher drums decay faster."""
    dur = 0.40 if f0 < 220 else 0.30
    t = t_axis(dur)
    bend = 1.0 + 0.10 * np.exp(-t * 45.0)
    phase = 2.0 * np.pi * np.cumsum(f0 * bend) / SR
    x = np.sin(phase) * np.exp(-t * (11.0 if f0 < 220 else 15.0))
    x += 0.3 * np.sin(2.3 * phase + 0.5) * np.exp(-t * 28.0)
    if f0 < 220:  # phone-speaker presence for the low conga (cf. kick)
        x += 0.45 * np.sin(2.0 * phase + 0.3) * np.exp(-t * 16.0)
    n_s = int(SR * 0.005)
    sl = shape_spectrum(rng.uniform(-1, 1, n_s), bp_curve(900, 5000, 2))
    sl /= max(np.max(np.abs(sl)), 1e-9)
    x[:n_s] += slap * sl * np.linspace(1.0, 0.0, n_s)
    return x


HAND_DRUMS = {
    "conga_lo.wav": (185.0, 0.50),
    "conga_mid.wav": (247.0, 0.55),
    "bongo_hi.wav": (340.0, 0.70),
}


# --------------------------------------------------------------------------
# Steel tongue drum (8 tongues, C major pentatonic C4..E5)
# --------------------------------------------------------------------------

def tongue_note(freq):
    """Soft metallic tongue: a slightly detuned fundamental pair (gentle
    shimmer), a strong near-octave partial and a quiet third partial, all
    with long singing decays, plus a soft thumb-pad attack. Lower tongues
    ring longer."""
    rel = freq / 261.63                      # 1.0 at C4
    dur = 2.6 / rel ** 0.4
    t = t_axis(dur)
    base_decay = 1.3 * rel ** 0.5
    x = np.sin(2 * np.pi * freq * t) * np.exp(-t * base_decay)
    x += 0.6 * np.sin(2 * np.pi * freq * 1.004 * t + float(rng.uniform(0, 6.28))) \
        * np.exp(-t * base_decay * 1.2)
    x += 0.35 * np.sin(2 * np.pi * freq * 1.98 * t + float(rng.uniform(0, 6.28))) \
        * np.exp(-t * base_decay * 2.1)
    x += 0.12 * np.sin(2 * np.pi * freq * 3.01 * t + float(rng.uniform(0, 6.28))) \
        * np.exp(-t * base_decay * 3.2)
    n_a = int(SR * 0.004)
    thumb = shape_spectrum(rng.uniform(-1, 1, n_a), bp_curve(200, 1500, 2))
    thumb /= max(np.max(np.abs(thumb)), 1e-9)
    x[:n_a] += 0.12 * thumb * np.linspace(1.0, 0.0, n_a)
    return shape_spectrum(x, lp_curve(6000, 3))


# Filenames are a fixed contract with the UIs: tongue index 1..8, low to
# high, C major pentatonic so any flurry of taps is consonant.
TONGUE_NOTES = {
    "tongue_1.wav": 261.63,   # C4
    "tongue_2.wav": 293.66,   # D4
    "tongue_3.wav": 329.63,   # E4
    "tongue_4.wav": 392.00,   # G4
    "tongue_5.wav": 440.00,   # A4
    "tongue_6.wav": 523.25,   # C5
    "tongue_7.wav": 587.33,   # D5
    "tongue_8.wav": 659.26,   # E5
}


# --------------------------------------------------------------------------
# Trombone (seamless sustain loop; the UI pitch-bends it for the slide)
# --------------------------------------------------------------------------

def trombone_loop():
    """~1 s brass sustain at Bb3 built from an exact integer number of
    periods, so looping it is seamless. All-harmonic spectrum with a
    ~650 Hz formant bump and a smooth top-end rolloff reads as a warm,
    slightly honky toy trombone. The player glides pitch by varying
    playback rate, so only one reference pitch is needed."""
    f_target = 233.08  # Bb3
    periods = 233
    n = 2 * round(periods * SR / f_target / 2)   # even length, whole periods
    f0 = periods * SR / n                        # exact loop frequency
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(1, 25):
        fk = k * f0
        if fk > 8000:
            break
        amp = 1.0 / k ** 0.7
        amp *= 1.0 + 1.6 * np.exp(-(((fk - 650.0) / 400.0) ** 2))
        amp *= 1.0 / (1.0 + (fk / 3500.0) ** 3)
        x += amp * np.sin(2.0 * np.pi * fk * t + float(rng.uniform(0, 6.28)))
    return x - x.mean()


# Filenames are a fixed contract with the UIs: bar index 1..8, low to high.
XYLO_NOTES = {
    "xylo_1.wav": 523.25,   # C5
    "xylo_2.wav": 587.33,   # D5
    "xylo_3.wav": 659.26,   # E5
    "xylo_4.wav": 698.46,   # F5
    "xylo_5.wav": 783.99,   # G5
    "xylo_6.wav": 880.00,   # A5
    "xylo_7.wav": 987.77,   # B5
    "xylo_8.wav": 1046.50,  # C6
}


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


def balance_guitar(plucks):
    """Equal RMS over the first 300 ms across strings."""
    n300 = int(SR * 0.300)
    rms = {k: np.sqrt(np.mean(v[:n300] ** 2)) for k, v in plucks.items()}
    target = float(np.mean(list(rms.values())))
    return {k: v * (target / rms[k]) for k, v in plucks.items()}


def scale_guitar_for_strum(plucks):
    """Scale the whole set so a six-string strum (30 ms stagger) peaks at
    PEAK_DBFS."""
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

    # Every one-shot is leveled to the same perceived loudness through a
    # phone speaker (phone_loud300 == PHONE_TARGET, peak-capped).
    write_wav("kick.wav", kick(), phone_target=PHONE_TARGET)
    write_wav("snare.wav", snare(), phone_target=PHONE_TARGET)
    write_wav("hihat.wav", hihat(), phone_target=PHONE_TARGET)
    write_wav("tom_hi.wav", tom_hi(), phone_target=PHONE_TARGET)
    write_wav("tom_floor.wav", tom_floor(), phone_target=PHONE_TARGET)
    write_wav("cymbal.wav", cymbal(), phone_target=PHONE_TARGET)
    write_wav("ride.wav", ride(), phone_target=PHONE_TARGET)

    plucks = {}
    for name, freq in GUITAR_STRINGS.items():
        plucks[name] = pluck(freq)
        f0 = measure_pitch(plucks[name])
        print(f"  {name}: tuned to {f0:.3f} Hz (target {freq:.2f}, "
              f"{(f0 / freq - 1) * 100:+.3f}%)")
    plucks = balance_guitar(plucks)
    # Exciter AFTER RMS balancing (so the balancer doesn't reabsorb the
    # added harmonics) and before the strum-peak scaling (so a full strum
    # still can't clip). More exciter the lower the string: G2 gets a
    # strong lift, D4 barely any.
    for name, freq in GUITAR_STRINGS.items():
        amount = 0.9 * min(1.0, max(0.0, (300.0 - freq) / 200.0))
        plucks[name] = small_speaker_exciter(plucks[name], amount)
    plucks = scale_guitar_for_strum(plucks)
    # Level the guitar as it is actually played — a six-string strum is
    # one "hit" and should match a single drum hit, so the whole string
    # set shares one calibration gain.
    stag = int(SR * STRUM_STAGGER)
    names = sorted(plucks)
    length = stag * (len(names) - 1) + max(len(v) for v in plucks.values())
    strum = np.zeros(length)
    for i, k in enumerate(names):
        strum[i * stag:i * stag + len(plucks[k])] += plucks[k]
    strum_gain = PHONE_TARGET / max(phone_loud300(strum), 1e-12)
    for name, x in plucks.items():
        write_wav(name, x * strum_gain, do_normalize=False)

    for name, freq in XYLO_NOTES.items():
        write_wav(name, xylo_bar(freq), phone_target=PHONE_TARGET)

    for name, freq in PIANO_NOTES.items():
        write_wav(name, piano_note(freq), phone_target=PHONE_TARGET)

    for name, (freq, slap) in HAND_DRUMS.items():
        write_wav(name, hand_drum(freq, slap), phone_target=PHONE_TARGET)

    for name, freq in TONGUE_NOTES.items():
        write_wav(name, tongue_note(freq), phone_target=PHONE_TARGET)

    # Trombone: a held tone reads louder than a transient at equal RMS,
    # so it targets a few dB under the one-shots.
    write_wav("trombone.wav", trombone_loop(), do_normalize=False,
              phone_target=PHONE_TARGET * 0.55, loop=True)
    print("Done.")


if __name__ == "__main__":
    main()
