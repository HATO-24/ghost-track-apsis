import os
import wave
import json
import numpy as np

SR = 44100
OUT = r'D:\GHOST TRACK_APSIS\game_v15\audio'
STATS = r'D:\GHOST TRACK_APSIS\mockups\_audio_stats.json'
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(20871103)
stats = {}


def save(name, x, target_peak=0.84):
    x = np.asarray(x, dtype=np.float64)
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    if peak > 0:
        x = x / peak * target_peak
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype('<i2')
    p = os.path.join(OUT, name + '.wav')
    with wave.open(p, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    peak_db = 20 * np.log10(max(1e-12, float(np.max(np.abs(x)))))
    rms_db = 20 * np.log10(max(1e-12, float(np.sqrt(np.mean(x * x)))))
    stats[name] = {
        'seconds': round(len(x) / SR, 3),
        'peak_dbfs': round(peak_db, 2),
        'rms_dbfs': round(rms_db, 2),
        'bytes': os.path.getsize(p),
    }


def periodic_noise(L, alpha=1.8):
    spec = np.fft.rfft(rng.normal(0, 1, L))
    f = np.arange(spec.size, dtype=np.float64)
    f[0] = 1.0
    spec = spec / (f ** alpha)
    x = np.fft.irfft(spec, n=L)
    return x / (np.max(np.abs(x)) + 1e-12)


def periodic_noise_band(L, lo_hz, hi_hz):
    spec = np.fft.rfft(rng.normal(0, 1, L))
    freqs = np.fft.rfftfreq(L, 1 / SR)
    mask = ((freqs >= lo_hz) & (freqs <= hi_hz)).astype(np.float64)
    spec = spec * mask
    x = np.fft.irfft(spec, n=L)
    return x / (np.max(np.abs(x)) + 1e-12)


def loop_tone(L, hz, amp, phase=0.0):
    k = max(1, int(round(hz * L / SR)))
    f = k * SR / L
    t = np.arange(L) / SR
    return amp * np.sin(2 * np.pi * f * t + phase)


def fade_edges(x, ms=4.0):
    x = np.array(x, dtype=np.float64)
    n = int(SR * ms / 1000.0)
    if n * 2 >= len(x):
        n = max(1, len(x) // 4)
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x


def menu_ambient(seconds=30.0):
    L = int(SR * seconds)
    t = np.arange(L) / SR
    x = np.zeros(L)
    base = [55.0, 82.5, 110.0, 130.81, 164.81]
    for i, hz in enumerate(base):
        x += loop_tone(L, hz, 0.20 / (i + 1), phase=i * 0.7)
        x += loop_tone(L, hz * 1.003, 0.10 / (i + 1), phase=1.3 + i)
    pulse = 0.5 + 0.5 * np.cos(2 * np.pi * 6.0 * t)
    x *= (0.72 + 0.28 * pulse)
    n = periodic_noise(L, alpha=2.0) * 0.10
    lfo = 0.5 + 0.5 * np.cos(2 * np.pi * 3.0 * t + 0.4)
    x = x * (0.85 + 0.15 * lfo) + n * (0.5 + 0.5 * lfo)
    return fade_edges(x, ms=8.0)


def game_ambient(seconds=32.0):
    L = int(SR * seconds)
    t = np.arange(L) / SR
    x = np.zeros(L)
    for i, hz in enumerate([41.20, 61.74, 82.41, 98.0]):
        x += loop_tone(L, hz, 0.16 / (i + 1), phase=i * 1.1)
        x += loop_tone(L, hz * 1.004, 0.06 / (i + 1), phase=0.5 + i)
    x *= 0.60 + 0.25 * np.cos(2 * np.pi * 4.0 * t)
    n = periodic_noise_band(L, 20.0, 260.0) * 0.14
    x = x + n
    tick_len = int(SR * 0.06)
    tt = np.arange(tick_len) / SR
    tick_wave = np.sin(2 * np.pi * 1560.0 * tt) * np.exp(-tt / 0.012) * 0.16
    for k in range(8):
        pos = int(k * SR * 4.0)
        seg = min(tick_len, L - pos)
        if seg > 0:
            x[pos:pos + seg] += tick_wave[:seg]
    return fade_edges(x, ms=8.0)


def sfx_ui_hover():
    L = int(SR * 0.07)
    t = np.arange(L) / SR
    return fade_edges(np.sin(2 * np.pi * 1400 * t) * np.exp(-t / 0.018) * 0.30, 3.0)


def sfx_ui_confirm():
    L = int(SR * 0.20)
    t = np.arange(L) / SR
    a = np.sin(2 * np.pi * 760 * t) * np.exp(-t / 0.045) * 0.32
    local = np.maximum(0, t - 0.085)
    b = np.sin(2 * np.pi * 1140 * local) * np.exp(-local / 0.045) * 0.30
    return fade_edges(a + b, 3.0)


def sfx_ui_back():
    L = int(SR * 0.16)
    t = np.arange(L) / SR
    a = np.sin(2 * np.pi * 620 * t) * np.exp(-t / 0.05) * 0.30
    local = np.maximum(0, t - 0.07)
    b = np.sin(2 * np.pi * 420 * local) * np.exp(-local / 0.05) * 0.26
    return fade_edges(a + b, 3.0)


def sfx_ui_error():
    L = int(SR * 0.28)
    t = np.arange(L) / SR
    a = np.sin(2 * np.pi * 180 * t) * 0.28
    b = np.sign(np.sin(2 * np.pi * 240 * t)) * 0.06
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * 28 * t)
    return fade_edges((a + b) * trem * np.exp(-t / 0.20), 4.0)


def sfx_alarm():
    L = int(SR * 1.20)
    t = np.arange(L) / SR
    out = np.zeros(L)
    seg = 0.15
    for k in range(8):
        s = k * seg
        local = t - s
        m = (local >= 0) & (local < seg)
        f = 880.0 if k % 2 == 0 else 660.0
        env = np.sin(np.pi * np.clip(local[m] / seg, 0, 1)) ** 1.5
        out[m] += np.sin(2 * np.pi * f * local[m]) * env * 0.42
    return fade_edges(out, 4.0)


def sfx_fire():
    L = int(SR * 0.90)
    t = np.arange(L) / SR
    f = 90 * np.exp(-t / 0.35) + 38
    phase = 2 * np.pi * np.cumsum(f) / SR
    boom = np.sin(phase) * np.exp(-t / 0.30) * 0.55
    n = rng.normal(0, 1, L) * np.exp(-t / 0.10) * 0.25
    lp = np.copy(n)
    for _ in range(3):
        lp = np.convolve(lp, np.ones(12) / 12.0, mode='same')
    body = np.tanh((boom + lp * 1.4) * 1.8) * 0.55
    return fade_edges(body, 4.0)


def sfx_hard_cut():
    L = int(SR * 0.10)
    t = np.arange(L) / SR
    n = rng.normal(0, 1, L)
    n = np.diff(np.concatenate([[0.0], n]))
    n = n / (np.max(np.abs(n)) + 1e-12)
    env = np.exp(-t / 0.018)
    click = np.sin(2 * np.pi * 2400 * t) * np.exp(-t / 0.006) * 0.35
    return fade_edges(n * env * 0.62 + click, 1.0)


def sfx_boot():
    L = int(SR * 2.20)
    t = np.arange(L) / SR
    f = 220 + 660 * np.clip(t / 1.6, 0, 1) ** 1.4
    phase = 2 * np.pi * np.cumsum(f) / SR
    sweep = np.sin(phase) * 0.30 * np.exp(-t / 1.5)
    chime = np.zeros(L)
    for i, hz in enumerate([440.0, 554.37, 659.25]):
        local = np.maximum(0, t - 1.1)
        chime += np.sin(2 * np.pi * hz * local) * np.exp(-local / 0.45) * 0.16 / (i + 1)
    return fade_edges(sweep + chime, 5.0)


files = {
    'menu_ambient': menu_ambient(),
    'game_ambient': game_ambient(),
    'ui_hover': sfx_ui_hover(),
    'ui_confirm': sfx_ui_confirm(),
    'ui_back': sfx_ui_back(),
    'ui_error': sfx_ui_error(),
    'alarm': sfx_alarm(),
    'fire': sfx_fire(),
    'hard_cut': sfx_hard_cut(),
    'boot': sfx_boot(),
}
for name, x in files.items():
    save(name, x)
    if name.endswith('ambient'):
        y = x / (np.max(np.abs(x)) + 1e-12)
        stats[name]['seam_abs_diff'] = round(abs(float(y[0] - y[-1])), 4)

max_peak = max(v['peak_dbfs'] for v in stats.values())
print('AUDIO GENERATED', len(stats), 'files; max peak dBFS =', max_peak)
for k, v in stats.items():
    extra = ''
    if 'seam_abs_diff' in v:
        extra = ' seam ' + str(v['seam_abs_diff'])
    print('{:16s} {:>6.2f}s peak {:>6.2f} dBFS rms {:>6.2f} bytes {}{}'.format(
        k, v['seconds'], v['peak_dbfs'], v['rms_dbfs'], v['bytes'], extra))
with open(STATS, 'w', encoding='utf-8') as fh:
    json.dump(stats, fh, ensure_ascii=False, indent=2)
print('stats written', STATS)
