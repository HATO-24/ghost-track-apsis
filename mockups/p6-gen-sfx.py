"""P6 SFX generator: all-original terminal / system / alarm sounds (44.1k 16-bit mono)."""
import numpy as np, os, wave, json

SR = 44100
OUT = r"D:\GHOST TRACK_APSIS\game_v15\audio"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(4471)

def t(d): return np.arange(int(SR * d), dtype=np.float64) / SR

def env(x, a=0.004, r=0.06):
    n = len(x)
    na = max(1, int(SR * a)); nr = max(1, int(SR * r))
    e = np.ones(n)
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return x * e

def tone(freq, dur, amp=1.0, decay=8.0, wave_type="sine", phase=0.0):
    tt = t(dur)
    if wave_type == "square":
        y = np.sign(np.sin(2*np.pi*freq*tt + phase))
    elif wave_type == "triangle":
        y = 2*np.abs(2*(tt*freq - np.floor(tt*freq + 0.5))) - 1
    else:
        y = np.sin(2*np.pi*freq*tt + phase)
    return y * np.exp(-decay*tt) * amp

def noise(dur, amp=1.0, lp=0.25, seed=4471):
    n = int(SR * dur)
    x = np.random.default_rng(seed).standard_normal(n)
    # simple one-pole low-pass
    y = np.empty(n); acc = 0.0
    for i in range(n):
        acc += lp * (x[i] - acc); y[i] = acc
    return y / (np.max(np.abs(y)) + 1e-9) * amp

def sweep(f0, f1, dur, amp=1.0, decay=2.0, wave_type="sine"):
    tt = t(dur)
    freq = f0 + (f1 - f0) * (tt / max(dur, 1e-9))
    phase = 2*np.pi*np.cumsum(freq)/SR
    if wave_type == "square": y = np.sign(np.sin(phase))
    else: y = np.sin(phase)
    return y * np.exp(-decay*tt) * amp

def mix(*parts):
    parts = [p for p in parts if hasattr(p, "__len__")]
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out

def norm(x, peak_db=-1.5):
    x = np.nan_to_num(x)
    p = np.max(np.abs(x))
    if p < 1e-9: return x
    target = 10 ** (peak_db / 20.0)
    return x / p * target

def save(name, x, peak_db=-1.5):
    x = norm(x, peak_db)
    data = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    return path

def click(dur=0.04, f=1400, amp=0.9):
    n = noise(dur, 0.5, 0.6, int(rng.integers(1, 9999)))
    return env(mix(tone(f, dur, 0.8, 40), n * 0.35), 0.001, 0.02)

def two_beep(f1, f2, gap=0.05, d=0.10):
    return mix(tone(f1, d, 0.9, 6), np.pad(tone(f2, d, 0.9, 6), (int(SR*(d+gap)), 0), mode="constant"))

def three_beep(freqs, gap=0.06, d=0.10):
    total = len(freqs)*(d+gap)
    out = np.zeros(int(SR*total))
    for i,f in enumerate(freqs):
        b = tone(f, d, 0.9, 6)
        start = int(SR*i*(d+gap))
        out[start:start+len(b)] += b
    return out

def save_all():
    files = {}
    files["ui_hover"] = save("ui_hover", click(0.045, 2100, 0.55))
    files["ui_select"] = save("ui_select", env(mix(tone(1250,0.06,0.8,14), click(0.02,1800,0.4)),0.001,0.02))
    files["ui_confirm"] = save("ui_confirm", two_beep(760, 1140))
    files["ui_back"] = save("ui_back", env(mix(tone(620,0.10,0.8,12), np.pad(tone(420,0.08,0.7,14),(int(SR*0.06),0))),0.001,0.04))
    files["ui_error"] = save("ui_error", env(mix(tone(180,0.26,0.9,4), tone(240,0.26,0.6,5), noise(0.26,0.08,0.12)),0.002,0.08))
    files["ui_toggle_on"] = save("ui_toggle_on", sweep(420, 880, 0.14, 0.8, 5))
    files["ui_toggle_off"] = save("ui_toggle_off", sweep(880, 420, 0.14, 0.8, 5))
    files["ui_open"] = save("ui_open", mix(noise(0.22,0.35,0.10), tone(520,0.22,0.6,6), np.pad(tone(780,0.12,0.5,10),(int(SR*0.10),0)),0.001))
    files["ui_close"] = save("ui_close", mix(noise(0.18,0.30,0.10), np.pad(tone(680,0.08,0.5,10),(int(SR*0.02),0)), tone(380,0.16,0.5,6)))
    files["ui_slider"] = save("ui_slider", mix(tone(2200,0.025,0.5,30), click(0.02,2600,0.5)))
    files["ui_tab"] = save("ui_tab", two_beep(980, 980, 0.02, 0.04))

    files["sys_boot"] = save("sys_boot", mix(sweep(180, 880, 1.6, 0.8, 1.2), np.pad(tone(440,0.6,0.3,2),(int(SR*0.7),0)), np.pad(tone(880,0.5,0.2,3),(int(SR*1.1),0)),0.002))
    files["sys_sensor_on"] = save("sys_sensor_on", two_beep(520, 780, 0.04, 0.12))
    files["sys_sensor_off"] = save("sys_sensor_off", two_beep(780, 520, 0.04, 0.11))
    files["sys_radar_ping"] = save("sys_radar_ping", mix(tone(1320,0.5,0.8,5), np.pad(tone(1320,0.35,0.25,8),(int(SR*0.18),0)), np.pad(tone(1320,0.2,0.1,10),(int(SR*0.36),0)),0.001))
    files["sys_elint"] = save("sys_elint", mix(noise(0.45,0.45,0.18), sweep(1800,2400,0.35,0.25,2), tone(520,0.35,0.3,4),0.002))
    files["sys_comms_rx"] = save("sys_comms_rx", mix(noise(0.09,0.35,0.25), tone(900,0.16,0.55,8), np.pad(tone(1200,0.06,0.35,12),(int(SR*0.08),0)),0.001))
    files["sys_cmd_queued"] = save("sys_cmd_queued", two_beep(520, 650, 0.03, 0.07))
    files["sys_cmd_tx"] = save("sys_cmd_tx", sweep(560, 880, 0.22, 0.7, 4))
    files["sys_cmd_exec"] = save("sys_cmd_exec", mix(tone(330,0.25,0.7,5), tone(660,0.25,0.5,6), np.pad(tone(990,0.12,0.2,10),(int(SR*0.10),0)),0.001))
    files["sys_evidence_start"] = save("sys_evidence_start", two_beep(440, 660, 0.05, 0.09))
    files["sys_evidence_done"] = save("sys_evidence_done", three_beep([440, 660, 880]))
    files["sys_evac_start"] = save("sys_evac_start", two_beep(300, 420, 0.05, 0.12))
    files["sys_evac_done"] = save("sys_evac_done", mix(tone(400,0.4,0.5,3), np.pad(tone(600,0.3,0.4,4),(int(SR*0.12),0)), np.pad(tone(800,0.25,0.35,5),(int(SR*0.24),0)),0.001))
    files["sys_clock_tick"] = save("sys_clock_tick", click(0.025, 3000, 0.25))

    files["alarm_decision"] = save("alarm_decision", mix(
        np.concatenate([tone(784,0.14,0.7,4), np.zeros(int(SR*0.06)), tone(588,0.14,0.7,4), np.zeros(int(SR*0.06))] * 4),
        np.pad(tone(196,0.9,0.22,1.2),(0,int(SR*0.3)), mode="constant")[:int(SR*1.2)],
        0.001))
    files["alarm_lock"] = save("alarm_lock", mix(two_beep(1180, 880, 0.05, 0.12), np.pad(tone(220,0.7,0.2,2),(int(SR*0.3),0)),0.002))
    files["alarm_fire"] = save("alarm_fire", mix(noise(0.75,0.7,0.10), tone(90,0.8,0.9,5), tone(180,0.5,0.4,6),0.001))
    files["alarm_damage"] = save("alarm_damage", mix(noise(0.55,0.6,0.06), tone(60,0.6,0.9,4), np.pad(tone(120,0.4,0.4,6),(int(SR*0.12),0)),0.001))
    files["alarm"] = files["alarm_decision"]
    files["fire"] = files["alarm_fire"]
    files["hard_cut"] = save("hard_cut", mix(noise(0.10,0.8,0.35), tone(80,0.10,0.6,10),0.001))
    files["boot"] = save("boot", mix(sweep(220, 880, 1.8, 0.7, 0.8), np.pad(tone(440,0.5,0.25,2),(int(SR*0.8),0)), np.pad(tone(660,0.35,0.2,3),(int(SR*1.3),0)),0.001))
    stats = {}
    for k,p in files.items():
        with wave.open(p, "rb") as w:
            stats[k] = {"dur": round(w.getnframes()/SR, 3), "bytes": os.path.getsize(p)}
    return files, stats

if __name__ == "__main__":
    files, stats = save_all()
    with open(r"D:\GHOST TRACK_APSIS\mockups\p6-sfx-stats.json", "w", encoding="utf-8") as f:
        json.dump(stats, f, ensure_ascii=False, indent=2)
    print("generated", len(files), "files")
    for k,v in sorted(stats.items()): print(k, v["dur"], "s", v["bytes"], "bytes")
