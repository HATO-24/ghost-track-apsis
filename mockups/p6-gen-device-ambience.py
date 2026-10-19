"""P8 game-only device ambience: floppy stepper, tape hiss/wow, modem handshake, relay clicks."""
import numpy as np, wave, os, json
SR = 44100
OUT = r"D:\GHOST TRACK_APSIS\game_v15\audio\game_device_ambience.wav"
rng = np.random.default_rng(8801)

def t(d): return np.arange(int(SR*d), dtype=np.float64)/SR

def env(x,a=0.002,r=0.05):
    n=len(x); na=max(1,int(SR*a)); nr=max(1,int(SR*r)); e=np.ones(n)
    e[:na]=np.linspace(0,1,na); e[-nr:]*=np.linspace(1,0,nr)
    return x*e

def lowpass(x, alpha=0.08):
    y=np.empty(len(x)); acc=0.0
    for i in range(len(x)):
        acc += alpha*(x[i]-acc); y[i]=acc
    return y

def highpass(x, alpha=0.08):
    lp=lowpass(x,alpha); return x-lp

def click(dur=0.018, f=180, amp=0.8):
    tt=t(dur)
    n=np.random.default_rng(int(dur*100000+f)).standard_normal(len(tt))
    return env((np.sin(2*np.pi*f*tt)*0.55 + highpass(n,0.25)*0.45)*np.exp(-40*tt)*amp,0.0005,0.006)

# 32 s base
duration=32.0
n=int(SR*duration)
tt=np.arange(n)/SR
base=np.zeros(n)

# 1) electrical / tape transport hum: 50/100/150 Hz + slow wobble
for f,a in [(50,0.10),(100,0.05),(150,0.025),(37,0.06)]:
    base += a*np.sin(2*np.pi*f*tt + 0.4*np.sin(2*np.pi*0.07*tt))
base *= 0.75

# 2) tape hiss: filtered noise, periodic so loop seam matches
h=np.random.default_rng(9901).standard_normal(n)
hiss=highpass(h,0.16) - highpass(h,0.02)
hiss=hiss/ (np.max(np.abs(hiss))+1e-9)
base += 0.055*hiss

# 3) tape wow / transport: slow amplitude modulation
base *= (0.85 + 0.15*np.sin(2*np.pi*0.18*tt + 1.1))

# 4) floppy stepper click trains
click_times=[1.2, 4.8, 8.3, 12.4, 15.1, 19.6, 23.0, 27.4, 30.2]
for ct in click_times:
    for k in range(5):
        st=ct + 0.09*k
        idx=int(st*SR)
        c=click(0.012, 170 + 18*((k*7)%4), 0.55)
        e=idx+len(c)
        if e<=n: base[idx:e]+=c*(0.8 if k==0 else 0.55)

# 5) tape reel / capstan low whir bursts
for st in [3.0, 11.0, 21.0, 29.0]:
    idx=int(st*SR); dur=1.6; x=t(dur)
    whir=np.sin(2*np.pi*(38+2*np.sin(2*np.pi*0.7*x))*x)*env(np.ones(len(x)),0.25,0.35)*0.025
    e=idx+len(whir)
    if e<=n: base[idx:e]+=whir

# 6) modem handshake: quiet, mechanical, every 16 s
for st in [6.0, 22.0]:
    idx=int(st*SR)
    seq=(0.35, 0.22, 0.26, 0.18, 0.42)
    cur=0.0
    for j,d in enumerate(seq):
        f=[1200,2400,600,1800,900][j]
        x=t(d)
        tone=np.sin(2*np.pi*f*x)*np.sin(np.pi*x/d)*0.06
        a=idx+int(cur*SR); b=a+len(tone)
        if b<=n: base[a:b]+=tone
        cur += d+0.06

# 7) relay / panel clicks
for st in [2.2, 7.4, 10.2, 14.8, 18.0, 24.5, 26.7, 30.8]:
    idx=int(st*SR)
    c=click(0.026, 95, 0.35)
    e=idx+len(c)
    if e<=n: base[idx:e]+=c

# 8) seamless loop: crossfade first/last 0.5 s, then apply soft clip
fade=int(SR*0.5)
base[:fade] = base[:fade]*(np.linspace(0,1,fade)) + base[-fade:]*(np.linspace(1,0,fade))
base = base[:-fade]

# normalize; gentle soft clip for a "device room" feel
peak=np.max(np.abs(base))
base=base/(peak+1e-9)*0.88
base=np.tanh(base*1.15)
base=base/(np.max(np.abs(base))+1e-9)*0.84
data=np.clip(np.round(base*32767),-32768,32767).astype("<i2")
with wave.open(OUT,"wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())
print("saved",OUT,"duration",len(data)/SR,"bytes",os.path.getsize(OUT))
