"""Original, synthesized beach-to-tension score. No licensed song recordings."""
import json, subprocess, wave
from pathlib import Path
import numpy as np
import imageio_ffmpeg
ROOT=Path(__file__).resolve().parents[3]
data=json.loads((ROOT/'data/story_rigby.json').read_text(encoding='utf-8'))
rate=24000
duration=data['duration']+1
count=int(duration*rate)
audio=np.zeros(count,dtype=np.float32)
rng=np.random.default_rng(1986)
def add(start, signal):
    first=max(0,int(start*rate));n=min(len(signal),len(audio)-first)
    if n>0: audio[first:first+n]+=signal[:n]
impact=data['beats'][36]['start'];charge=data['beats'][32]['start']
chords=[(45,52,57,60),(41,48,53,57),(48,55,60,64),(43,50,55,59)]
for bar in range(int(impact/4)+1):
    start=bar*4;x=np.arange(rate*4)/rate
    env=np.minimum(x/.7,1)*np.minimum((4-x)/1.1,1)
    for midi in chords[bar%4]:
        f=440*2**((midi-69)/12)
        add(start,.018*env*(np.sin(2*np.pi*f*x)+.22*np.sin(2*np.pi*f*2.003*x)))
    for beat in range(8):
        x=np.arange(int(rate*.5))/rate
        midi=chords[bar%4][beat%4]+12;f=440*2**((midi-69)/12)
        add(start+beat*.5,.022*np.sin(2*np.pi*f*x)*np.exp(-x*9)*(1-np.exp(-x*120)))
        if beat%2==0:
            add(start+beat*.5,.016*np.sin(2*np.pi*(52*x+12*(1-np.exp(-x*25))))*np.exp(-x*18))
seconds=np.arange(count)/rate
audio*=np.minimum(seconds/3,1)*np.clip((impact-seconds)/.08,0,1)
x=np.arange(int((impact-charge)*rate))/rate
add(charge,.032*np.sin(2*np.pi*(78*x+2.1*x*x))*np.minimum(x/4,1))
x=np.arange(int(rate*1.2))/rate
clang=sum(np.sin(2*np.pi*f*x)*np.exp(-x*d) for f,d in [(196,7),(533,10),(1191,13)])
add(impact,.13*clang+.04*rng.normal(size=len(x))*np.exp(-x*27))
# Mick's ludicrous credentials get a completely sincere action-hero flourish.
# The joke is the disproportionate dignity, never a comic sound effect.
for beat in [12,14]:
    start=data['beats'][beat]['start']+.4
    for j,midi in enumerate([57,64,69,68,64,71,69]):
        x=np.arange(int(rate*.58))/rate; f=440*2**((midi-69)/12)
        env=np.minimum(x/.06,1)*np.minimum((.58-x)/.17,1)
        brass=sum(np.sin(2*np.pi*f*k*x)/k for k in [1,2,3,4])
        add(start+j*.52,.024*brass*env)
resolve=data['beats'][49]['start']
for start in np.arange(resolve,duration,5):
    x=np.arange(rate*5)/rate
    for midi in [33,40,48]:
        f=440*2**((midi-69)/12)
        add(start,.024*np.sin(2*np.pi*f*x)*np.minimum(x/1.2,1)*np.minimum((5-x)/1.5,1))
audio*=np.clip((duration-seconds)/3,0,1)
out=ROOT/'build/prologue-review/score.wav'
with wave.open(str(out),'wb') as w:
    w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate)
    w.writeframes((np.clip(audio,-.9,.9)*32767).astype('<i2').tobytes())
target=ROOT/'assets/audio/story/prologue.ogg';target.parent.mkdir(parents=True,exist_ok=True)
subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(),'-hide_banner','-loglevel','error','-y','-i',str(out),'-c:a','libvorbis','-q:a','5',str(target)],check=True)
print('Original prologue score:',target)
