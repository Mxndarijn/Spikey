"""Spikey sound synth: renders every draft SFX and music stem as 16-bit mono WAV.

Pure Python 3 (standard library only), deterministic (fixed seeds), so anyone can
re-render the exact same files. Music stems loop seamlessly: note tails that run
past the loop end wrap around to the start.

    python -I spikey_synth.py OUT_DIR            # everything
    python -I spikey_synth.py OUT_DIR sfx        # only SFX
    python -I spikey_synth.py OUT_DIR music      # only music stems

Then convert, e.g. `ffmpeg -i flap.wav -c:a libvorbis -q:a 5 flap.ogg`.
"""

import math
import random
import sys
import wave
from array import array
from pathlib import Path

SR = 44100
TAU = 2.0 * math.pi


# ---------------------------------------------------------------- basics


def ns(dur: float) -> int:
    return max(1, int(round(dur * SR)))


def zeros(n: int) -> list:
    return [0.0] * n


def curve(dur, a, b, kind="exp"):
    """Per-sample sweep from a to b (exp for pitch/cutoff, lin otherwise)."""
    n = ns(dur)
    if n == 1:
        return [a]
    if kind == "exp":
        r = math.log(b / a)
        return [a * math.exp(r * i / (n - 1)) for i in range(n)]
    return [a + (b - a) * i / (n - 1) for i in range(n)]


def points(dur, pts, kind="lin"):
    """Piecewise sweep through (time, value) points."""
    n = ns(dur)
    out = zeros(n)
    j = 0
    for i in range(n):
        t = i / SR
        while j < len(pts) - 2 and t > pts[j + 1][0]:
            j += 1
        (t0, v0), (t1, v1) = pts[j], pts[j + 1]
        u = 0.0 if t1 <= t0 else min(1.0, max(0.0, (t - t0) / (t1 - t0)))
        if kind == "exp" and v0 > 0 and v1 > 0:
            out[i] = v0 * (v1 / v0) ** u
        else:
            out[i] = v0 + (v1 - v0) * u
    return out


def _blep(t, dt):
    if t < dt:
        t /= dt
        return t + t - t * t - 1.0
    if t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


def osc(kind, freq, dur, duty=0.5, vib=0.0, vib_hz=0.0, phase=0.0):
    """sine | tri | saw | square (band-limited with polyBLEP)."""
    n = ns(dur)
    fs = freq if isinstance(freq, list) else [freq] * n
    out = zeros(n)
    p = phase
    for i in range(n):
        f = fs[min(i, len(fs) - 1)]
        if vib:
            f *= 1.0 + vib * math.sin(TAU * vib_hz * i / SR)
        dt = f / SR
        if kind == "sine":
            v = math.sin(TAU * p)
        elif kind == "tri":
            v = 4.0 * abs(p - 0.5) - 1.0
        elif kind == "saw":
            v = 2.0 * p - 1.0 - _blep(p, dt)
        else:
            v = (1.0 if p < duty else -1.0) + _blep(p, dt) - _blep((p - duty) % 1.0, dt)
        out[i] = v
        p += dt
        if p >= 1.0:
            p -= 1.0
    return out


def fm(freq, dur, ratio, index_from, index_to):
    """Two-operator FM (bells, glassy chimes). Index sweeps exponentially."""
    n = ns(dur)
    idx = curve(dur, max(index_from, 1e-3), max(index_to, 1e-3))
    out = zeros(n)
    for i in range(n):
        t = i / SR
        out[i] = math.sin(TAU * freq * t + idx[i] * math.sin(TAU * freq * ratio * t))
    return out


def noise(dur, seed, hold=1):
    """White noise; hold>1 gives grainy 'chiptune' noise (sample-and-hold)."""
    rng = random.Random(seed)
    n = ns(dur)
    out = zeros(n)
    v = 0.0
    for i in range(n):
        if i % hold == 0:
            v = rng.uniform(-1.0, 1.0)
        out[i] = v
    return out


def svf(x, cutoff, q=0.707, mode="low"):
    """Simper TPT state-variable filter, cutoff constant or per-sample list."""
    n = len(x)
    cs = cutoff if isinstance(cutoff, list) else None
    k = 1.0 / q
    ic1 = ic2 = 0.0
    out = zeros(n)
    g = math.tan(math.pi * min(cutoff, SR * 0.45) / SR) if cs is None else 0.0
    for i in range(n):
        if cs is not None:
            g = math.tan(math.pi * min(cs[min(i, len(cs) - 1)], SR * 0.45) / SR)
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
        v0 = x[i]
        v3 = v0 - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if mode == "low":
            out[i] = v2
        elif mode == "band":
            out[i] = v1
        else:
            out[i] = v0 - k * v1 - v2
    return out


def env(dur, attack, decay_tau, hold=0.0):
    """Linear attack, optional hold, exponential decay (tau seconds)."""
    n = ns(dur)
    a, h = ns(attack), ns(hold)
    out = zeros(n)
    for i in range(n):
        if i < a:
            out[i] = i / a
        elif i < a + h:
            out[i] = 1.0
        else:
            out[i] = math.exp(-((i - a - h) / SR) / decay_tau)
    return out


def adsr(dur, a, d, s, r):
    """Gate length dur, then release r (output is dur + r long)."""
    n, nr = ns(dur), ns(r)
    out = zeros(n + nr)
    na, nd = ns(a), ns(d)
    for i in range(n):
        if i < na:
            v = i / na
        elif i < na + nd:
            v = 1.0 - (1.0 - s) * (i - na) / nd
        else:
            v = s
        out[i] = v
    last = out[n - 1]
    for i in range(nr):
        out[n + i] = last * (1.0 - i / nr)
    return out


def mul(a, b):
    n = min(len(a), len(b))
    return [a[i] * b[i] for i in range(n)]


def gain(a, g):
    return [v * g for v in a]


def mix(*parts):
    """mix((buf, start_seconds, gain), ...) into one buffer."""
    end = max(ns(s) + len(b) for b, s, _ in parts)
    out = zeros(end)
    for b, s, g in parts:
        o = ns(s) if s else 0
        for i, v in enumerate(b):
            out[o + i] += v * g
    return out


def echo(x, delay, fb, wet, tail=0.0):
    d = ns(delay)
    out = x + zeros(ns(tail))
    buf = out[:]
    for i in range(d, len(buf)):
        buf[i] += buf[i - d] * fb
    return [out[i] + (buf[i] - out[i]) * wet for i in range(len(out))]


def finish(x, peak_db):
    """DC-block, short fades, normalize peak to peak_db dBFS."""
    x = svf(x, 25.0, 0.7, "high")
    fi, fo = min(ns(0.002), len(x) // 4), min(ns(0.006), len(x) // 4)
    for i in range(fi):
        x[i] *= i / fi
    for i in range(fo):
        x[len(x) - 1 - i] *= i / fo
    pk = max(abs(v) for v in x) or 1.0
    return gain(x, 10 ** (peak_db / 20.0) / pk)


def hz(name: str) -> float:
    return 440.0 * 2 ** ((midi(name) - 69) / 12.0)


def midi(name: str) -> int:
    pcs = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    pc = pcs[name[0]]
    rest = name[1:]
    if rest.startswith("#"):
        pc += 1
        rest = rest[1:]
    elif rest.startswith("b"):
        pc -= 1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + pc


def mhz(m: int) -> float:
    return 440.0 * 2 ** ((m - 69) / 12.0)


def write_wav(path: Path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    a = array("h", (max(-32767, min(32767, int(round(v * 32767)))) for v in x))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(a.tobytes())


# ---------------------------------------------------------------- SFX


def sfx_flap():
    # Soft feathery "fwip": band-passed noise sweeping up, two wing strokes.
    def stroke(seed):
        d = 0.13
        body = svf(noise(d, seed), curve(d, 450, 1500), 1.3, "band")
        chirp = osc("sine", curve(d, 280, 480), d)
        e = env(d, 0.006, 0.032)
        return mix((mul(body, e), 0, 1.0), (mul(chirp, env(d, 0.004, 0.022)), 0, 0.22))

    return finish(mix((stroke(1), 0, 1.0), (stroke(2), 0.042, 0.35)), -6)


def sfx_bounce():
    # Rounded "boop" with a tiny dip-then-rise in pitch (like the example Hit).
    d = 0.12
    f = points(d, [(0, 700), (0.018, 560), (0.12, 760)], "exp")
    tone = mix((osc("sine", f, d), 0, 1.0), (osc("tri", f, d), 0, 0.35))
    click = mul(svf(noise(0.004, 3), 3000, 0.7, "high"), env(0.004, 0.0005, 0.0015))
    return finish(mix((mul(tone, env(d, 0.002, 0.045)), 0, 1.0), (click, 0, 0.25)), -5)


def sfx_bounce_ladder():
    # Demo only: the game plays sfx_bounce with pitch_scale stepping a major pentatonic.
    base = sfx_bounce()
    steps = [0, 2, 4, 7, 9, 12, 14, 16]
    parts = []
    for k, s in enumerate(steps):
        r = 2 ** (s / 12.0)
        sh = [base[int(i * r)] for i in range(int(len(base) / r) - 1)]
        parts.append((sh, k * 0.28, 1.0))
    return finish(mix(*parts), -5)


def _coin_note(f, d, tau):
    sq = svf(osc("square", f, d, 0.25), 6000, 0.7)
    return mul(mix((sq, 0, 0.6), (osc("sine", f * 2, d), 0, 0.25)), env(d, 0.001, tau))


def sfx_coin():
    # Classic bright two-note "bling": B5 then E6.
    return finish(
        mix((_coin_note(hz("B5"), 0.06, 0.05), 0, 1.0), (_coin_note(hz("E6"), 0.2, 0.07), 0.055, 1.0)),
        -6,
    )


def sfx_coin_counter():
    # Tiny glassy tick when a coin lands on the HUD counter (pitch climbs per coin).
    d = 0.06
    t = mix((osc("sine", hz("D7"), d), 0, 1.0), (osc("sine", hz("D7") * 2, d), 0, 0.2))
    tick = mul(svf(noise(0.003, 4), 5000, 0.7, "high"), env(0.003, 0.0003, 0.001))
    return finish(mix((mul(t, env(d, 0.001, 0.015)), 0, 1.0), (tick, 0, 0.3)), -12)


def sfx_death_spike():
    # Cartoon "pop-thud": click, falling sub thump, crunch, little descending squeak.
    d = 0.45
    click = mul(noise(0.006, 5), env(0.006, 0.0003, 0.002))
    thump = mul(osc("sine", curve(d, 180, 45), d), env(d, 0.002, 0.11))
    crunch = mul(svf(noise(0.15, 6), 2500, 0.8), env(0.15, 0.001, 0.04))
    squeak = mul(
        svf(osc("square", curve(0.14, 900, 300), 0.14), 2500, 0.7), env(0.14, 0.004, 0.05)
    )
    return finish(mix((click, 0, 0.8), (thump, 0, 1.0), (crunch, 0, 0.5), (squeak, 0.01, 0.28)), -3)


def sfx_death_wall():
    # Ceiling/floor: woody "bonk" then a sad slide-whistle drop.
    bonk_d = 0.12
    bonk = mix(
        (mul(osc("sine", 320, bonk_d), env(bonk_d, 0.001, 0.05)), 0, 1.0),
        (mul(osc("sine", 320 * 3.3, bonk_d), env(bonk_d, 0.001, 0.02)), 0, 0.4),
    )
    sd = 0.55
    slide = mul(osc("sine", curve(sd, 700, 160), sd, vib=0.03, vib_hz=6), points(sd, [(0, 0), (0.03, 1), (0.35, 0.7), (0.55, 0)]))
    return finish(mix((bonk, 0, 1.0), (slide, 0.08, 0.6)), -4)


def sfx_portal_open():
    # Magical swell: rising band-passed hiss + C-E-G-C sparkle arpeggio with echo.
    d = 1.0
    hiss = mul(svf(noise(d, 7), curve(d, 600, 4000), 3.0, "band"), points(d, [(0, 0), (0.5, 1), (1.0, 0)]))
    parts = [(hiss, 0, 0.8)]
    for k, n in enumerate(["C6", "E6", "G6", "C7"]):
        f = hz(n)
        nd = 0.4
        tone = mix((osc("sine", f, nd), 0, 1.0), (osc("sine", f * 4, nd), 0, 0.15))
        parts.append((mul(tone, env(nd, 0.002, 0.12)), 0.25 + k * 0.09, 0.45))
    return finish(echo(mix(*parts), 0.09, 0.35, 0.4, 0.3), -6)


def sfx_portal_pass():
    # Warp whoosh: crossing sine sweeps (the example Teleport's X shape) + humming ring.
    d = 0.85
    up = osc("sine", curve(0.45, 300, 1400), 0.45, vib=0.03, vib_hz=9)
    dn = osc("sine", curve(0.45, 1400, 300), 0.45, vib=0.03, vib_hz=9)
    sweep_env = points(0.45, [(0, 0), (0.15, 1), (0.45, 0)])
    whoosh = svf(noise(d, 8), points(d, [(0, 400), (0.3, 2500), (0.85, 600)], "exp"), 1.2, "band")
    whoosh = mul(whoosh, points(d, [(0, 0), (0.3, 1), (0.85, 0)]))
    rd = 0.5
    ring = mul(osc("sine", 880, rd), [math.exp(-i / SR / 0.2) * (0.6 + 0.4 * math.sin(TAU * 12 * i / SR)) for i in range(ns(rd))])
    return finish(
        mix((mul(up, sweep_env), 0, 0.3), (mul(dn, sweep_env), 0, 0.3), (whoosh, 0, 1.0), (ring, 0.35, 0.35)),
        -5,
    )


def _bell(note, d=0.9, tau=0.35):
    f = hz(note)
    return mul(fm(f, d, 3.5, 3.0, 0.2), env(d, 0.002, tau))


def sfx_fork_appear():
    # "Choose!" two bells: a low calm one and a high wild one.
    return finish(echo(mix((_bell("C5"), 0, 0.8), (_bell("G5"), 0.16, 0.8)), 0.12, 0.3, 0.35, 0.3), -6)


def _pad_chord(notes, d, cutoff, bend_to=1.0):
    parts = []
    for n in notes:
        f = hz(n)
        fs = curve(d, f, f * bend_to)
        parts += [(osc("tri", fs, d), 0, 0.5), (osc("saw", [v * 1.004 for v in fs], d), 0, 0.2)]
    return svf(mix(*parts), cutoff, 0.9)


def sfx_fork_calm():
    # Calm exit: slow-motion feel, a soft F chord whose filter and pitch sink (example Slowmo).
    d = 1.3
    pad = _pad_chord(["F4", "A4", "C5"], d, curve(d, 5000, 350), 2 ** (-1 / 12))
    pad = mul(pad, points(d, [(0, 0), (0.06, 1), (0.8, 0.6), (1.3, 0)]))
    swish = mul(svf(noise(d, 9), curve(d, 3000, 300), 1.0, "band"), points(d, [(0, 0), (0.1, 1), (1.3, 0)]))
    return finish(mix((pad, 0, 1.0), (swish, 0, 0.4)), -7)


def sfx_fork_wild():
    # Wild exit: power-up riser, rumbling bass climbing an octave, ending in a bright stab.
    d = 0.85
    bass = svf(osc("saw", curve(d, 55, 110), d), curve(d, 200, 3000), 1.5)
    bass = mul(bass, points(d, [(0, 0), (0.1, 1), (0.85, 1)]))
    hiss = mul(svf(noise(d, 10), curve(d, 1500, 9000), 0.8, "high"), points(d, [(0, 0), (0.85, 1)]))
    sd = 0.35
    stab = mix(*[(svf(osc("square", hz(n), sd, 0.5), 4000, 0.7), 0, 0.3) for n in ["A4", "C#5", "E5"]])
    stab = mul(stab, env(sd, 0.002, 0.09))
    return finish(mix((bass, 0, 0.8), (hiss, 0, 0.3), (stab, d - 0.02, 1.0)), -5)


def sfx_new_room():
    # Arrival: quick strummed C-major pluck after a short air puff.
    d = 0.5
    puff = mul(svf(noise(0.12, 11), 1200, 0.8, "band"), points(0.12, [(0, 0), (0.05, 1), (0.12, 0)]))
    parts = [(puff, 0, 0.5)]
    for k, n in enumerate(["C5", "E5", "G5", "C6"]):
        p = mul(osc("tri", hz(n), d), env(d, 0.002, 0.16))
        parts.append((p, 0.06 + k * 0.018, 0.4))
    return finish(mix(*parts), -8)


def sfx_milestone():
    # Sparkle swell for every 10 points / combo (like the example AchievementSound).
    d = 0.65
    shimmer = mul(svf(noise(d, 12), 7000, 2.0, "band"), points(d, [(0, 0), (0.35, 1), (0.65, 0)]))
    rng = random.Random(13)
    penta = ["C7", "D7", "E7", "G7", "A7", "C8"]
    parts = [(shimmer, 0, 0.6)]
    for k in range(12):
        n = penta[min(len(penta) - 1, k // 2 + rng.randrange(2))]
        p = mul(osc("sine", hz(n), 0.12), env(0.12, 0.001, 0.05))
        parts.append((p, 0.05 + k * 0.03, 0.35 + 0.03 * k))
    root = mul(osc("sine", curve(0.6, hz("C5"), hz("C6")), 0.6), points(0.6, [(0, 0), (0.35, 1), (0.6, 0)]))
    parts.append((root, 0, 0.3))
    return finish(mix(*parts), -6)


def _ui_pop(f0, f1, d=0.08):
    t = mul(osc("sine", curve(d, f0, f1), d), env(d, 0.001, 0.02))
    c = mul(svf(noise(0.003, 14), 4000, 0.7, "high"), env(0.003, 0.0003, 0.001))
    return mix((t, 0, 1.0), (c, 0, 0.2))


def sfx_ui_tap():
    return finish(_ui_pop(880, 1100), -10)


def sfx_ui_back():
    return finish(_ui_pop(900, 600, 0.09), -10)


def sfx_ui_confirm():
    a = mul(osc("tri", hz("E5"), 0.07), env(0.07, 0.002, 0.03))
    b = mul(osc("tri", hz("B5"), 0.14), env(0.14, 0.002, 0.05))
    return finish(mix((a, 0, 1.0), (b, 0.055, 1.0)), -8)


def sfx_ui_locked():
    # "Nuh-uh": two low muted buzzes for a locked item / not enough coins.
    def buzz():
        return mul(svf(osc("square", 196, 0.08, 0.5), 900, 0.8), env(0.08, 0.003, 0.03))

    return finish(mix((buzz(), 0, 1.0), (buzz(), 0.1, 0.8)), -9)


def sfx_purchase():
    # Coin cascade then a happy G-major pluck chord with sparkle.
    rng = random.Random(15)
    parts = []
    for k in range(6):
        n = rng.choice(["E6", "G6", "A6", "B6", "D7"])
        parts.append((_coin_note(hz(n), 0.08, 0.035), k * 0.04, 0.5))
    for k, n in enumerate(["G4", "B4", "D5", "G5"]):
        parts.append((mul(osc("tri", hz(n), 0.6), env(0.6, 0.002, 0.22)), 0.26 + k * 0.012, 0.35))
    parts.append((mul(svf(noise(0.5, 16), 8000, 2.0, "band"), env(0.5, 0.05, 0.12)), 0.26, 0.4))
    return finish(mix(*parts), -5)


def sfx_revive():
    # Rewarded-ad revive: rising shimmering gliss, then a bright bell pop as the flyer returns.
    d = 0.9
    gl = mul(osc("sine", curve(d, 300, 1200), d, vib=0.015, vib_hz=7), points(d, [(0, 0), (0.7, 1), (0.9, 0.2)]))
    sh = mul(svf(noise(d, 17), curve(d, 1500, 8000), 2.0, "band"), points(d, [(0, 0), (0.85, 1), (0.9, 0)]))
    bells = mix((_bell("C6", 0.6, 0.2), 0, 0.6), (_bell("E6", 0.6, 0.2), 0.03, 0.5), (_bell("G6", 0.6, 0.2), 0.06, 0.5))
    return finish(mix((gl, 0, 0.6), (sh, 0, 0.4), (bells, 0.85, 1.0)), -5)


SFX = {
    "flap": sfx_flap,
    "bounce": sfx_bounce,
    "bounce_ladder_demo": sfx_bounce_ladder,
    "coin": sfx_coin,
    "coin_counter": sfx_coin_counter,
    "death_spike": sfx_death_spike,
    "death_wall": sfx_death_wall,
    "portal_open": sfx_portal_open,
    "portal_pass": sfx_portal_pass,
    "fork_appear": sfx_fork_appear,
    "fork_calm": sfx_fork_calm,
    "fork_wild": sfx_fork_wild,
    "new_room": sfx_new_room,
    "milestone": sfx_milestone,
    "ui_tap": sfx_ui_tap,
    "ui_back": sfx_ui_back,
    "ui_confirm": sfx_ui_confirm,
    "ui_locked": sfx_ui_locked,
    "purchase": sfx_purchase,
    "revive": sfx_revive,
}


# ---------------------------------------------------------------- music instruments
# Each returns a mono buffer for one note: (midi note, gate seconds, velocity).


def i_pluck_sq(m, g, v):
    d = g + 0.25
    x = svf(osc("square", mhz(m), d, 0.25), curve(d, 4500, 900), 0.8)
    return gain(mul(x, env(d, 0.003, 0.14)), v)


def i_marimba(m, g, v):
    f = mhz(m)
    d = 0.7
    x = mix(
        (mul(osc("sine", f, d), env(d, 0.002, 0.25)), 0, 1.0),
        (mul(osc("sine", f * 4, d), env(d, 0.001, 0.04)), 0, 0.25),
        (mul(osc("sine", f * 10, d), env(d, 0.0005, 0.01)), 0, 0.1),
    )
    return gain(x, v)


def i_kalimba(m, g, v):
    f = mhz(m)
    d = 0.9
    x = mix(
        (mul(osc("sine", f, d), env(d, 0.002, 0.35)), 0, 1.0),
        (mul(osc("sine", f * 5.4, d), env(d, 0.001, 0.03)), 0, 0.3),
        (mul(osc("sine", f * 2, d), env(d, 0.002, 0.12)), 0, 0.15),
    )
    return gain(x, v)


def i_saw_lead(m, g, v):
    f = mhz(m)
    x = mix((osc("saw", f, g), 0, 0.5), (osc("square", f * 1.003, g, 0.5), 0, 0.35))
    x = svf(x, 3200, 1.0)
    e = adsr(g, 0.005, 0.08, 0.6, 0.08)
    return gain(mul(x + zeros(len(e) - len(x)), e), v)


def i_pulse(m, g, v, duty=0.25):
    f = mhz(m)
    e = adsr(g, 0.002, 0.05, 0.7, 0.03)
    x = osc("square", f, len(e) / SR, duty, vib=0.004, vib_hz=5.5)
    return gain(mul(x, e), v)


def i_pulse_arp(m, g, v):
    return i_pulse(m, g * 0.8, v, 0.125)


def i_tri_bass(m, g, v):
    e = adsr(g, 0.004, 0.06, 0.8, 0.03)
    return gain(mul(osc("tri", mhz(m), len(e) / SR), e), v)


def i_sine_bass(m, g, v):
    e = adsr(g, 0.01, 0.1, 0.7, 0.08)
    x = mix((osc("sine", mhz(m), len(e) / SR), 0, 1.0), (osc("tri", mhz(m), len(e) / SR), 0, 0.2))
    return gain(mul(x, e), v)


def i_saw_bass(m, g, v):
    e = adsr(g, 0.003, 0.08, 0.5, 0.03)
    d = len(e) / SR
    x = svf(osc("saw", mhz(m), d), points(d, [(0, 2200), (0.08, 600), (d, 500)], "exp"), 1.4)
    return gain(mul(x, e), v)


def i_pad(m, g, v, bright=1400):
    e = adsr(g, 0.25, 0.3, 0.8, 0.5)
    d = len(e) / SR
    f = mhz(m)
    x = mix((osc("saw", f * 0.996, d), 0, 0.3), (osc("saw", f * 1.004, d), 0, 0.3), (osc("tri", f, d), 0, 0.5))
    return gain(mul(svf(x, bright, 0.7), e), v)


def i_pad_soft(m, g, v):
    e = adsr(g, 0.4, 0.4, 0.8, 0.8)
    d = len(e) / SR
    f = mhz(m)
    x = mix((osc("sine", f, d, vib=0.003, vib_hz=4.5), 0, 0.7), (osc("tri", f * 1.003, d), 0, 0.3))
    return gain(mul(svf(x, 1800, 0.7), e), v)


def i_pad_dark(m, g, v):
    return i_pad(m, g, v, 900)


# drums: (velocity) -> buffer
def d_kick(v):
    d = 0.3
    x = mul(osc("sine", points(d, [(0, 150), (0.04, 55), (0.3, 42)], "exp"), d), env(d, 0.001, 0.12))
    c = mul(noise(0.004, 21), env(0.004, 0.0003, 0.001))
    return gain(mix((x, 0, 1.0), (c, 0, 0.3)), v)


def d_snare(v):
    d = 0.2
    n = mul(svf(noise(d, 22), 1800, 0.8, "band"), env(d, 0.001, 0.06))
    t = mul(osc("sine", 190, d), env(d, 0.001, 0.04))
    return gain(mix((n, 0, 1.0), (t, 0, 0.5)), v)


def d_clap(v):
    parts = []
    for k in range(3):
        parts.append((mul(svf(noise(0.012, 23 + k), 1200, 1.0, "band"), env(0.012, 0.001, 0.004)), k * 0.01, 1.0))
    parts.append((mul(svf(noise(0.25, 26), 1200, 1.0, "band"), env(0.25, 0.001, 0.07)), 0.02, 0.9))
    return gain(mix(*parts), v)


def d_hat(v, tau=0.022, seed=27):
    d = tau * 6
    return gain(mul(svf(noise(d, seed), 7500, 0.7, "high"), env(d, 0.0005, tau)), v)


def d_ohat(v):
    return d_hat(v, 0.11, 28)


def d_shaker(v):
    d = 0.1
    return gain(mul(svf(noise(d, 29), 6000, 1.5, "band"), env(d, 0.012, 0.025)), v)


def d_rim(v):
    d = 0.06
    x = mix((mul(osc("sine", 1700, d), env(d, 0.0005, 0.008)), 0, 1.0), (mul(svf(noise(d, 30), 3000, 2, "band"), env(d, 0.0005, 0.01)), 0, 0.6))
    return gain(x, v)


def d_logdrum(v, f=220):
    d = 0.35
    x = mix(
        (mul(osc("sine", curve(d, f * 1.15, f), d), env(d, 0.001, 0.09)), 0, 1.0),
        (mul(osc("sine", f * 2.7, d), env(d, 0.001, 0.03)), 0, 0.3),
    )
    return gain(x, v)


def d_logdrum_lo(v):
    return d_logdrum(v, 147)


def d_chip_kick(v):
    d = 0.12
    return gain(mul(osc("square", curve(d, 160, 40), d, 0.5), env(d, 0.001, 0.04)), v)


def d_chip_snare(v):
    d = 0.14
    return gain(mul(noise(d, 31, hold=3), env(d, 0.001, 0.045)), v)


def d_chip_hat(v):
    d = 0.04
    return gain(mul(svf(noise(d, 32, hold=1), 6000, 0.7, "high"), env(d, 0.0005, 0.012)), v)


DRUMS = {
    "k": d_kick, "s": d_snare, "c": d_clap, "h": d_hat, "o": d_ohat, "z": d_shaker,
    "r": d_rim, "l": d_logdrum, "L": d_logdrum_lo, "K": d_chip_kick, "S": d_chip_snare,
    "H": d_chip_hat,
}


# ---------------------------------------------------------------- tracks


TRACKS = {
    "candy_hop": {
        "title": "Candy Hop", "bpm": 120, "swing": 0.0,
        "chords": [["C4", "E4", "G4"], ["B3", "D4", "G4"], ["C4", "E4", "A4"], ["C4", "F4", "A4"]],
        "roots": ["C2", "G2", "A2", "F2"],
        "pad": (i_pad_soft, 0.24),
        "bass": (i_tri_bass, 0.55, "R.O.R.O.R.O.R.FO"),
        "lead": (i_pluck_sq, 0.5, [
            "E5 . G5 . C6 . G5 . E5 . G5 . A5 . G5 .",
            "D5 . G5 . B5 . G5 . D6 . B5 . G5 . . .",
            "C6 . B5 . A5 . E5 . A5 . . . C6 . B5 .",
            "A5 . F5 . C5 . F5 . A5 . G5 . F5 . E5 .",
            "A5 . C6 . F5 . A5 . G5 - - - . . . .",
        ]),
        "drums": {"k": "x.......x.......", "c": "....x.......x...", "h": "x.x.x.x.x.x.x.x.", "o": "..............x."},
        "levels": {"k": 0.9, "c": 0.45, "h": 0.18, "o": 0.15},
        "echo": (3, 0.25, 0.2),
    },
    "bubble_drift": {
        "title": "Bubble Drift", "bpm": 92, "swing": 0.0,
        "chords": [["F3", "A3", "C4", "E4"], ["G3", "B3", "D4", "E4"], ["E3", "G3", "B3", "D4"], ["A3", "C4", "E4", "G4"]],
        "roots": ["F2", "G2", "E2", "A2"],
        "pad": (i_pad_soft, 0.18),
        "bass": (i_sine_bass, 0.45, "R.........F....."),
        "lead": (i_marimba, 0.65, [
            "A5 . . . C6 . . . E6 . . . C6 . . .",
            "B5 . . . D6 . . . G5 . . . . . . .",
            "G5 . . . B5 . . . E6 . D6 . B5 . . .",
            "C6 . . . A5 . . . E5 . . . . . . .",
            "C6 . . . E6 . . . A5 - - - - - - -",
        ]),
        "drums": {"k": "x.........x.....", "z": "x.x.x.x.x.x.x.x.", "r": "........x.......", "h": ".....x.......x.."},
        "levels": {"k": 0.6, "z": 0.22, "r": 0.25, "h": 0.08},
        "echo": (3, 0.4, 0.35),
    },
    "jungle_bounce": {
        "title": "Jungle Bounce", "bpm": 104, "swing": 0.12,
        "chords": [["D4", "F4", "A4", "C5"], ["B3", "D4", "F4", "G4"], ["D4", "F4", "A4", "C5"], ["C4", "E4", "G4", "A4"]],
        "roots": ["D2", "G2", "D2", "A2"],
        "pad": (i_pad, 0.28),
        "bass": (i_tri_bass, 0.6, "R..R..F...R..O.."),
        "lead": (i_kalimba, 0.45, [
            "D5 . F5 . A5 . . F5 . . C6 . A5 . . .",
            "B5 . D6 . . B5 . . G5 . . A5 . B5 . .",
            "A5 . . F5 . . D5 . E5 . F5 . A5 . . .",
            "G5 . E5 . . C5 . . E5 . . G5 . A5 . .",
            "C6 . A5 . . G5 . . E5 . D5 . . . . .",
        ]),
        "drums": {"k": "x.....x...x.....", "c": "....x.......x...", "z": "xxxxxxxxxxxxxxxx", "l": "...x......x...x.", "L": ".......x.....x.."},
        "levels": {"k": 0.85, "c": 0.35, "z": 0.12, "l": 0.4, "L": 0.45},
        "echo": (3, 0.3, 0.25),
    },
    "lava_rush": {
        "title": "Lava Rush", "bpm": 140, "swing": 0.0,
        "chords": [["A3", "C4", "E4"], ["A3", "C4", "F4"], ["G3", "C4", "E4"], ["G3", "B3", "D4"]],
        "roots": ["A1", "F1", "C2", "G1"],
        "pad": (i_pad_dark, 0.22),
        "bass": (i_saw_bass, 0.42, "R.RORRROR.RORRRO"),
        "lead": (i_saw_lead, 0.9, [
            "A5 . C6 . E6 . C6 . A5 . E6 . D6 . C6 .",
            "A5 . C6 . F6 . C6 . A5 . F6 . E6 . C6 .",
            "G5 . C6 . E6 . G6 . E6 . C6 . D6 . E6 .",
            "D6 . B5 . G5 . B5 . D6 - - - B5 . . .",
            "D6 . E6 . G6 - - - E6 . D6 . B5 . . .",
        ]),
        "drums": {"k": "x...x...x...x...", "s": "....x.......x...", "h": "xxxxxxxxxxxxxxxx", "o": "..x...x...x...x."},
        "levels": {"k": 0.8, "s": 0.45, "h": 0.1, "o": 0.14},
        "echo": (3, 0.2, 0.15),
    },
    "star_arcade": {
        "title": "Star Arcade", "bpm": 128, "swing": 0.0,
        "chords": [["E4", "G4", "B4"], ["E4", "G4", "C5"], ["D4", "G4", "B4"], ["D4", "F#4", "A4"]],
        "roots": ["E2", "C2", "G2", "D2"],
        "pad": (i_pulse_arp, 0.26, "arp"),
        "bass": (i_tri_bass, 0.45, "R...R.O.R...R.O."),
        "lead": (i_pulse, 0.36, [
            "E5 . G5 . B5 . E6 . B5 . G5 . B5 . G5 .",
            "E5 . G5 . C6 . E6 . C6 . G5 . C6 . E6 .",
            "D5 . G5 . B5 . D6 . B5 . G5 . D6 . G6 .",
            "F#5 . A5 . D6 . A5 . F#6 - - - E6 . D6 .",
            "F#5 . A5 . D6 - - - C#6 - - - A5 . . .",
        ]),
        "drums": {"K": "x.........x.....", "S": "....x.......x...", "H": "x.x.x.x.x.x.x.x."},
        "levels": {"K": 0.7, "S": 0.4, "H": 0.2},
        "echo": (3, 0.25, 0.2),
    },
}

STEMS = ["pad", "bass", "drums", "lead"]
BARS = 8


def _place(stem, buf, pos):
    L = len(stem)
    for i, v in enumerate(buf):
        stem[(pos + i) % L] += v


def _circular_echo(x, d, fb, wet):
    L = len(x)
    wetbuf = zeros(L)
    cur = x[:]
    for _ in range(6):  # settle the feedback around the loop
        nxt = zeros(L)
        for i in range(L):
            nxt[(i + d) % L] += cur[i] * fb
        for i in range(L):
            wetbuf[i] += nxt[i]
        cur = nxt
    return [x[i] + wetbuf[i] * wet / fb for i in range(L)]


def render_track(key):
    t = TRACKS[key]
    step = 60.0 / t["bpm"] / 4.0
    L = int(round(BARS * 16 * step * SR))
    stems = {s: zeros(L) for s in STEMS}

    def at(bar, st):
        # Swing pushes odd 16ths later.
        sw = t["swing"] * step if st % 2 else 0.0
        return int(round(((bar * 16 + st) * step + sw) * SR))

    for bar in range(BARS):
        ci = bar % 4
        chord = t["chords"][ci]
        # pad
        fn, lv = t["pad"][0], t["pad"][1]
        if len(t["pad"]) > 2:  # chip arpeggio: chord tones every 16th
            for st in range(16):
                m = midi(chord[st % len(chord)]) + (12 if st % 8 >= 4 else 0)
                _place(stems["pad"], fn(m, step, lv), at(bar, st))
        else:
            for n in chord:
                _place(stems["pad"], fn(midi(n), 16 * step - 0.05, lv), at(bar, 0))
        # bass
        bfn, blv, pat = t["bass"]
        root = midi(t["roots"][ci])
        hits = [i for i, ch in enumerate(pat) if ch != "."]
        for j, st in enumerate(hits):
            nxt = hits[j + 1] if j + 1 < len(hits) else 16
            m = root + {"R": 0, "O": 12, "F": 7}[pat[st]]
            _place(stems["bass"], bfn(m, (nxt - st) * step * 0.85, blv), at(bar, st))
        # drums
        for inst, p in t["drums"].items():
            for st, ch in enumerate(p):
                if ch == "x":
                    accent = 1.0 if st % 4 == 0 else 0.8
                    _place(stems["drums"], DRUMS[inst](t["levels"][inst] * accent), at(bar, st))
        # lead (bars 0-3 phrase A, 4-6 repeat, bar 7 uses the alternate ending)
        lfn, llv, mel = t["lead"]
        line = mel[4] if bar == 7 else mel[bar % 4]
        toks = line.split()
        assert len(toks) == 16, (key, line)
        for st, tok in enumerate(toks):
            if tok in (".", "-"):
                continue
            ln = 1
            while st + ln < 16 and toks[st + ln] == "-":
                ln += 1
            _place(stems["lead"], lfn(midi(tok), ln * step * 0.9, llv), at(bar, st))

    steps_d, fb, wet = t["echo"]
    stems["lead"] = _circular_echo(stems["lead"], int(round(steps_d * step * SR)), fb, wet)
    # One shared gain for all stems, so the full mix peaks at -3 dBFS and stems keep balance.
    full = [sum(stems[s][i] for s in STEMS) for i in range(L)]
    g = 10 ** (-3 / 20.0) / (max(abs(v) for v in full) or 1.0)
    out = {s: gain(stems[s], g) for s in STEMS}
    out["full"] = gain(full, g)
    return out, L


def main():
    out = Path(sys.argv[1])
    what = sys.argv[2] if len(sys.argv) > 2 else "all"
    if what in ("all", "sfx"):
        for name, fn in SFX.items():
            x = fn()
            write_wav(out / "sfx" / f"{name}.wav", x)
            print(f"sfx {name}: {len(x) / SR:.3f}s", flush=True)
    if what in ("all", "music"):
        keys = sys.argv[3:] or list(TRACKS)
        for key in keys:
            stems, L = render_track(key)
            for s, x in stems.items():
                write_wav(out / "music" / key / f"{key}_{s}.wav", x)
            print(f"music {key}: {L} samples = {L / SR:.3f}s loop", flush=True)


if __name__ == "__main__":
    main()
