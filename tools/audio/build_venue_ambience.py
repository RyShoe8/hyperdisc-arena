"""Render seamless, original location ambience. No samples or network dependencies."""
from pathlib import Path
import wave
import numpy as np
RATE, SEC = 22050, 12
out = Path(__file__).resolve().parents[2] / "assets/sfx/venues"
out.mkdir(exist_ok=True)
t = np.arange(RATE*SEC)/RATE
tau = np.pi*2
rng = np.random.default_rng(1986)
def noise(centre, width):
    f=np.fft.rfftfreq(len(t),1/RATE)
    return np.fft.irfft(np.fft.rfft(rng.normal(size=len(t))) * np.exp(-((f-centre)/width)**2))
def pulse(at, decay, freq, drop=0):
    z=np.mod(t-at,SEC)
    return (1-np.exp(-z*140))*np.exp(-z*decay)*np.sin(tau*(freq*z + drop*(1-np.exp(-8*z))/8))
for name in ("beach","lawn","tiled","concrete","clay","stadium"):
    if name=="beach": # two swells run under the planks
        y=noise(800,750)*(.2+.8*np.sin(tau*t/SEC+.3)**4)+.16*noise(150,100)
    elif name=="concrete": # gutter drops ringing in different buckets
        y=noise(440,390)*.20
        for at,f in [(1,490),(1.25,640),(4.8,380),(7.2,580),(10.1,480)]: y+=.17*pulse(at,13,f,260)
    elif name=="lawn": # muffled club kick from behind the rail
        y=noise(240,160)*.12
        for at in np.arange(0,SEC,.5): y+=.27*pulse(at,13,48,34)
    elif name=="clay": # idling delivery truck and distant reversing signal
        y=noise(90,70)*.6+.12*np.sin(tau*48*t)*(1+.3*np.sin(tau*t/3))
        for at in (7.0,8.0,9.0): y+=.05*pulse(at,6,740)
    elif name=="tiled":
        y=noise(370,260)*.1
        for i,at in enumerate((1,1.13,1.26,5.7,5.86,8.9,9.05)): y+=.09*pulse(at,10,[523,659,784,622][i%4])
    else:
        y=noise(300,260)*(.55+.18*np.sin(tau*t/SEC))+.18*noise(75,60)
    y*=.24/max(np.abs(y))
    with wave.open(str(out/(name+".wav")),"wb") as wav:
        wav.setparams((1,2,RATE,0,"NONE","not compressed"))
        wav.writeframes(np.rint(y*32767).astype("<i2").tobytes())
