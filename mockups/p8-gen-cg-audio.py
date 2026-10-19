"""P8b: softer hard-cut + cinematic terminal ambience for startup CG."""
import numpy as np, wave, os, json
SR=44100
OUT=r"D:\GHOST TRACK_APSIS\game_v15\audio"
rng=np.random.default_rng(4711)

def t(d): return np.arange(int(SR*d),dtype=np.float64)/SR

def env(x,a=0.01,r=0.1):
    n=len(x); na=max(1,int(SR*a)); nr=max(1,int(SR*r)); e=np.ones(n)
    e[:na]=np.linspace(0,1,na); e[-nr:]*=np.linspace(1,0,nr); return x*e

def lowpass(x,a=0.08):
    y=np.empty(len(x)); acc=0.0
    for i in range(len(x)):
        acc+=a*(x[i]-acc); y[i]=acc
    return y

def save(name,x,peak_db=-8.0):
    x=np.nan_to_num(x); p=np.max(np.abs(x)); target=10**(peak_db/20.0)
    x=x/(p+1e-9)*target
    data=np.clip(np.round(x*32767),-32768,32767).astype("<i2")
    path=os.path.join(OUT,name+".wav")
    with wave.open(path,"wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())
    return path

def soft_hard_cut():
    d=0.16; tt=t(d)
    # 低频 thump + 低通噪声，去掉 2–4 kHz 的“铅笔敲桌”感。
    thump=np.sin(2*np.pi*58*tt)*np.exp(-18*tt)*0.85
    thump+=np.sin(2*np.pi*116*tt)*np.exp(-24*tt)*0.35
    n=lowpass(np.random.default_rng(812).standard_normal(len(tt)),0.035)
    n=n/(np.max(np.abs(n))+1e-9)*0.35
    x=env(thump+n,0.002,0.10)
    return save("hard_cut",x,-7.0)

def cg_ambience():
    d=18.0; n=int(SR*d); tt=np.arange(n)/SR
    # 1) 机柜低频 / 电源嗡鸣
    base=np.sin(2*np.pi*50*tt)*0.10+np.sin(2*np.pi*100*tt)*0.055+np.sin(2*np.pi*150*tt)*0.025
    base*=0.8
    # 2) 磁带/风机底噪（低通，避免嘶声）
    nz=np.random.default_rng(9123).standard_normal(n)
    nz=lowpass(nz,0.06); nz=nz/(np.max(np.abs(nz))+1e-9)
    base+=nz*0.055
    # 3) CRT 行频，极低音量；不是刺耳的高频尖啸
    base+=np.sin(2*np.pi*7860*tt)*0.004*(0.7+0.3*np.sin(2*np.pi*0.13*tt))
    # 4) 继电器 / 手动开关点击
    def click(dur=0.03,f=220,amp=0.4):
        x=t(dur); nse=np.random.default_rng(int(f*10)).standard_normal(len(x))
        nse=lowpass(nse,0.18); nse=nse/(np.max(np.abs(nse))+1e-9)
        return env((np.sin(2*np.pi*f*x)*0.45+nse*0.4)*np.exp(-30*x)*amp,0.001,0.012)
    for ct in [0.7,2.8,5.3,8.1,10.9,13.6,16.2]:
        i=int(ct*SR); c=click(0.025,160,0.30); e=min(n,i+len(c)); base[i:e]+=c[:e-i]
    # 5) 遥测/数据脉冲，高于底噪但不抢戏
    for ct,f in [(1.8,880),(3.9,660),(6.6,990),(9.4,760),(12.2,880),(15.0,660)]:
        i=int(ct*SR); c=env(np.sin(2*np.pi*f*t(0.045))*0.12,0.003,0.02); e=min(n,i+len(c)); base[i:e]+=c[:e-i]
    # 6) 拨号/数据突发的小段，音量很低
    for ct in [4.8,11.6]:
        i=int(ct*SR); cur=0
        for j,fd in enumerate([(1200,0.07),(2400,0.05),(600,0.08)]):
            f,dd=fd; c=env(np.sin(2*np.pi*f*t(dd))*0.035,0.004,0.02)
            a=i+int(cur*SR); b=min(n,a+len(c)); base[a:b]+=c[:b-a]; cur+=dd+0.03
    # 7) 首尾淡入淡出，避免开始/结束爆音
    base=env(base,0.25,0.6)
    return save("cg_ambience",base,-11.0)

if __name__=="__main__":
    files=[soft_hard_cut(),cg_ambience()]
    stats={}
    for p in files:
        with wave.open(p,"rb") as w:
            stats[os.path.basename(p)]={"dur":round(w.getnframes()/SR,3),"bytes":os.path.getsize(p)}
    print(json.dumps(stats,ensure_ascii=False,indent=2))
