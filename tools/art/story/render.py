"""Encode deterministic Godot frames with the original score, directly to MP4."""
import argparse, json, socket, struct, subprocess, wave
from pathlib import Path
import imageio_ffmpeg

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'build/prologue-review'
p=argparse.ArgumentParser()
p.add_argument('--reel',action='store_true')
p.add_argument('--tower',action='store_true',help='Tiffany introduction, full stair descent, and Vanessa contact')
p.add_argument('--godot',default=r'D:\Godot\Godot_v4.7.2-stable_win64.exe')
p.add_argument('--height',type=int,choices=[720,1080],default=1080)
args=p.parse_args()
data=json.loads((ROOT/'data/story_rigby.json').read_text(encoding='utf-8'))
audio=OUT/'score.wav'
quiet_at=data['beats'][36]['start']
if args.reel or args.tower:
    spans=[(data['beats'][5]['start'],data['beats'][7]['start']),(data['beats'][15]['start'],data['beats'][15]['start']+4)] if args.tower else [(1.2,8.)]+[(data['beats'][b]['start'],data['beats'][b]['start']+length) for b,length in [(3,6.5),(6,8),(15,4),(25,4),(32,4),(35,5),(37,8),(44,7),(49,4.5)]]
    with wave.open(str(audio),'rb') as r:
        params=r.getparams(); raw=r.readframes(r.getnframes())
    stride=params.nchannels*params.sampwidth;rate=params.framerate
    audio=OUT/'acting-reel-score.wav'
    with wave.open(str(audio),'wb') as w:
        w.setparams(params)
        for a,b in spans:w.writeframes(raw[round(a*rate)*stride:round(b*rate)*stride])
    quiet_at=0
    for a,b in spans:
        if a<=data['beats'][36]['start']<b:
            quiet_at+=data['beats'][36]['start']-a
            break
        quiet_at+=b-a
name='tower-interaction' if args.tower else 'acting-reel' if args.reel else 'story-prologue'
result=OUT/(name+'.mp4')
with socket.socket() as server, (OUT/(name+'-render.log')).open('w') as log:
    server.bind(('127.0.0.1',0));server.listen(1);server.settimeout(90)
    port=server.getsockname()[1]
    width=args.height*16//9
    cmd=[args.godot,'--path',str(ROOT),'--script','tools/render_story_stream.gd','--resolution',f'{width}x{args.height}','--',str(port),'tower' if args.tower else 'reel' if args.reel else 'full',str(width),str(args.height)]
    game=subprocess.Popen(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    encoder=None
    try:
        conn,_=server.accept()
        with conn:
            conn.settimeout(60)
            def receive(n):
                parts=[]
                while n:
                    part=conn.recv(min(n,1024*1024))
                    if not part:raise RuntimeError('Godot ended before completing capture')
                    parts.append(part);n-=len(part)
                return b''.join(parts)
            width,height,frames=struct.unpack('<III',receive(12))
            ambient=ROOT/'assets/sfx/venues/beach.wav'
            mix=f"[2:a]volume='if(lt(t,{quiet_at}),0.13,0.014)':eval=frame[sea];[1:a][sea]amix=inputs=2:duration=first:normalize=0[mix]"
            encoder=subprocess.Popen([imageio_ffmpeg.get_ffmpeg_exe(),'-hide_banner','-loglevel','error','-y','-f','rawvideo','-pixel_format','rgb24','-video_size',f'{width}x{height}','-framerate','30','-i','pipe:0','-i',str(audio),'-stream_loop','-1','-i',str(ambient),'-filter_complex',mix,'-map','0:v','-map','[mix]','-c:v','libx264','-preset','fast','-crf','17','-pix_fmt','yuv420p','-c:a','aac','-b:a','160k','-shortest','-movflags','+faststart',str(result)],stdin=subprocess.PIPE)
            for i in range(frames):
                encoder.stdin.write(receive(width*height*3))
                if i%300==0:print(f'{name}: {i}/{frames} frames',flush=True)
            encoder.stdin.close()
            if encoder.wait(timeout=60):raise RuntimeError('Video encode failed')
            if game.wait(timeout=30):raise RuntimeError('Godot capture failed')
    finally:
        if game.poll() is None:game.terminate()
        if encoder and encoder.poll() is None:encoder.terminate()
print(result,flush=True)
