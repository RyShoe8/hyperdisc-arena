"""Pack the isolated illustrations and animation attachments. Run from repository root."""
from pathlib import Path
import json

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SOURCE = Path('tools/art/crowd-cast')
OUT = Path('assets/art/crowds/live')
ATTACHMENTS = Path('build/crowd-attachments')
W, H = 152, 172
STEPS = 8
GRID = np.indices((H, W), dtype=np.float32)[::-1].transpose(1, 2, 0).copy()


def clean_plates():
    calibration = json.loads(Path('tools/art/venues/calibration.json').read_text())
    for venue, spec in calibration.items():
        original = Image.open(f'assets/art/courts/{venue}_pixel.png').convert('RGB')
        empty = Image.open(SOURCE / f'{venue}.png').convert('RGB').resize(original.size, Image.Resampling.LANCZOS)
        x1, y1, x2, x3, y2, x4 = spec['bounds']
        # Near-row heads and hands can project over the boundary. Use the
        # clean painting for the entire perimeter, even on the floor side.
        polygon = [(x1+8,y1+8),(x2-8,y1+8),(x4-20,y2-39),(x3+20,y2-39)]
        mask = Image.new('L', original.size)
        ImageDraw.Draw(mask).polygon([(x*original.width/512,y*original.height/288) for x,y in polygon], fill=255)
        # Keep the collision-calibrated surface and center divider, with a narrow
        # join on the inside wall. The area occupied by spectators is all empty.
        plate = Image.composite(original, empty, mask.filter(ImageFilter.GaussianBlur(7.0)))
        plate.save(OUT / f'{venue}.webp', lossless=True, method=4)


def split_sheet(file):
    rgba = np.array(Image.open(file).convert('RGBA'))
    _, labels, stats, centers = cv2.connectedComponentsWithStats((rgba[:,:,3]>32).astype('uint8'))
    subjects = sorted(range(1,len(stats)), key=lambda i:stats[i,4], reverse=True)[:12]
    subjects.sort(key=lambda i:centers[i,1])
    result = []
    for row in range(3):
        for i in sorted(subjects[4*row:4*row+4], key=lambda i:centers[i,0]):
            x,y,w,h,area = stats[i]
            if h < rgba.shape[0]*.17 or area < 3000:
                raise ValueError(f'Missing spectator at {file}, row {row}')
            # Preserve the original antialiased boundary without disconnected
            # debris from other cells in the sheet.
            mask = cv2.dilate((labels[y:y+h,x:x+w]==i).astype('uint8'),np.ones((3,3),'uint8'))
            actor = rgba[y:y+h,x:x+w].copy()
            actor[:,:,3] *= mask
            actor = Image.fromarray(actor)
            actor.thumbnail((W-10,H-12), Image.Resampling.LANCZOS)
            img = Image.new('RGBA',(W,H))
            img.paste(actor,((W-actor.width)//2,H-4-actor.height))
            result.append(np.array(img))
    return result


def premultiply(src):
    rgba=src.astype('float32')/255
    rgba[:,:,:3] *= rgba[:,:,3:]
    return rgba


def movement(start,end):
    a,b = premultiply(start),premultiply(end)
    def luminance(img):
        # A neutral backdrop makes both dark sleeves and highlights trackable.
        rgb=img[:,:,:3]+.5*(1-img[:,:,3:])
        return cv2.cvtColor(np.uint8(rgb*255),cv2.COLOR_RGB2GRAY)
    la,lb=luminance(a),luminance(b)
    solver=cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    fwd=solver.calc(la,lb,None)
    rev=solver.calc(lb,la,None)
    frames=[]
    for step in range(1,STEPS):
        t=step/STEPS
        def warp(img, flow, weight):
            coords=GRID-weight*flow
            return cv2.remap(img,coords,None,cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
        # Interpolate color only where the transported drawings agree. At
        # a newly revealed silhouette keep one inked contour, never two ghosts.
        old, new = warp(a,fwd,t), warp(b,rev,1-t)
        agree = np.max(np.abs(old-new),axis=2,keepdims=True)<0.13
        inter = np.where(agree,old*(1-t)+new*t,old if t<0.5 else new)
        inter[:,:,:3] /= np.maximum(inter[:,:,3:],1e-5)
        frames.append(np.uint8(np.clip(inter*255+.5,0,255)))
    return frames+[end]


def pack_view(view):
    idle,opened,contact,cheer=[split_sheet(SOURCE / (view+suffix+'.png')) for suffix in ('','-open','-clap','-cheer')]
    atlas=Image.new('RGBA',(W*25,H*12))
    for i,(rest,ready,closed,win) in enumerate(zip(idle,opened,contact,cheer)):
        frames=[rest]+movement(rest,ready)+movement(ready,closed)+movement(rest,win)
        folder=ATTACHMENTS/view/str(i)
        folder.mkdir(parents=True,exist_ok=True)
        for n,rgba in enumerate(frames):
            frame=Image.fromarray(rgba)
            frame.save(folder/f'{n}.png')
            atlas.paste(frame,(n*W,i*H))
    atlas.save(OUT / f'{view}.webp',lossless=True,method=4)


if __name__ == '__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    clean_plates()
    for direction in ('front','rear','profile'):
        pack_view(direction)
