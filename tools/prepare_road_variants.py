"""Register ImageGen road sprites without generating artwork.
Chroma key, split fixed cells, align ports, resize and export.
Run with Pillow and NumPy installed (authoring only).
"""
from pathlib import Path
import json
import sys
from concurrent.futures import ThreadPoolExecutor
import subprocess
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/source/roads-v3'
OUTPUT = ROOT / 'assets/sprites/roads-v3'
SLUGS = ['dirt','gravel','concrete','local','secondary','main','express','dual','motorway','premium','wood_bridge','stone_bridge','concrete_bridge','steel_bridge','cable_bridge','suspension_bridge']
LABELS = ['Camino de tierra','Camino de grava','Camino de cemento','Carretera local','Carretera secundaria','Carretera principal','Carretera rápida','Autovía','Autopista','Autopista de alta capacidad','Puente de madera','Puente de piedra','Puente de hormigón','Puente de acero','Puente atirantado','Puente colgante']
SHAPES = ['straight','curve','tee','cross']
PORTS = ['NS','NE','NEW','NESW']


def official_baseline(slug):
    skill = Path('/Users/jorgealonso/.codex/skills/generate2dsprite/scripts/generate2dsprite.py')
    args = [sys.executable, str(skill), 'process', '--input', str(SOURCE / f'{slug}-raw.png'), '--target', 'asset', '--mode', 'sheet', '--rows', '2', '--cols', '2', '--cell-size', '64', '--fit-scale', '1.0', '--align', 'center', '--shared-scale', '--component-mode', 'largest', '--trim-border', '0', '--edge-clean-depth', '0', '--label-prefix', 'variant', '--output-dir', str(SOURCE / f'{slug}-processor')]
    r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode: raise RuntimeError(r.stdout)
    return slug


def clean(cell):
    a = np.array(cell.convert('RGBA'))
    rgb = a[:,:,:3].astype(np.int16)
    magenta = (rgb[:,:,0] > rgb[:,:,1] + 40) & (rgb[:,:,2] > rgb[:,:,1] + 40)
    a[magenta] = 0
    # Remove neighboring-cell slivers before measuring ports, retaining the road component.
    ys,xs = np.nonzero(a[:,:,3])
    nearest = np.argmin((xs-a.shape[1]/2)**2 + (ys-a.shape[0]/2)**2)
    mask = Image.fromarray(np.where(a[:,:,3]>0,255,0).astype(np.uint8)).copy()
    ImageDraw.floodfill(mask,(int(xs[nearest]),int(ys[nearest])),128)
    a[np.array(mask)!=128] = 0
    return Image.fromarray(a)


def port(cell, direction):
    a = np.array(cell)[:,:,3] > 128
    ys = np.flatnonzero(a.sum(axis=1) >= max(4, a.shape[1] * 0.08))
    xs = np.flatnonzero(a.sum(axis=0) >= max(4, a.shape[0] * 0.08))
    if direction in 'NS':
        y = int(ys.min() + 3 if direction == 'N' else ys.max() - 3)
        if not a[y].any(): y = int(ys.min() if direction == 'N' else ys.max())
        selected = np.flatnonzero(a[y])
        return (float((selected.min() + selected.max()) / 2), float(selected.max() - selected.min() + 1), y)
    x = int(xs.min() + 3 if direction == 'W' else xs.max() - 3)
    if not a[:,x].any(): x = int(xs.min() if direction == 'W' else xs.max())
    selected = np.flatnonzero(a[:,x])
    return (float((selected.min() + selected.max()) / 2), float(selected.max() - selected.min() + 1), x)


def prepare(slug):
    raw = Image.open(SOURCE / f'{slug}-raw.png').convert('RGBA')
    dest = OUTPUT / slug
    dest.mkdir(parents=True, exist_ok=True)
    sheet = Image.new('RGBA', (128,128))
    report = []
    for i, shape in enumerate(SHAPES):
        col, row = i % 2, i // 2
        cell = clean(raw.crop((round(col*raw.width/2),round(row*raw.height/2),round((col+1)*raw.width/2),round((row+1)*raw.height/2))))
        info = {d:port(cell,d) for d in PORTS[i]}
        # Align equal-width road ports in the conceptual tile, not each silhouette's bbox.
        cx = sum(info[d][0] for d in 'NS' if d in info) / sum(d in info for d in 'NS')
        sx = 36 / (sum(info[d][1] for d in 'NS' if d in info) / sum(d in info for d in 'NS'))
        if shape == 'straight':
            cy = (info['N'][2] + info['S'][2]) / 2
            sy = 64 / (info['S'][2] - info['N'][2] + 1)
        else:
            cy = sum(info[d][0] for d in 'EW' if d in info) / sum(d in info for d in 'EW')
            sy = 36 / (sum(info[d][1] for d in 'EW' if d in info) / sum(d in info for d in 'EW'))
        frame = cell.transform((64,64), Image.Transform.AFFINE, (1/sx,0,cx-32/sx,0,1/sy,cy-32/sy), resample=Image.Resampling.NEAREST)
        frame.save(dest / f'{shape}.png')
        sheet.alpha_composite(frame, ((i%2)*64,(i//2)*64))
        report.append({'shape':shape,'ports':PORTS[i],'source_ports':info,'scale':[sx,sy],'output_bbox':frame.getbbox()})
    sheet.save(dest/'sheet.png')
    (SOURCE/f'{slug}-registration.json').write_text(json.dumps(report,indent=2))
    return sheet

if __name__ == '__main__':
    if '--baseline' in sys.argv:
        with ThreadPoolExecutor(max_workers=4) as pool:
            for slug in pool.map(official_baseline,SLUGS): print('processed',slug,flush=True)
    gallery = Image.new('RGB',(1088,416),'#1b302c')
    draw = ImageDraw.Draw(gallery)
    try: font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',14)
    except OSError: font=ImageFont.load_default()
    for i,slug in enumerate(SLUGS):
        sheet=prepare(slug)
        x,y=(i%4)*272,(i//4)*104
        draw.text((x+8,y+6),LABELS[i],font=font,fill='#e0ebbc')
        for j in range(4):
            tile=Image.open(OUTPUT/slug/f'{SHAPES[j]}.png')
            gallery.paste(tile,(x+8+j*64,y+28),tile)
        print('registered',slug,flush=True)
    gallery.save(OUTPUT/'gallery.png')
    manifest={'size':64,'shapes':SHAPES,'canonical_ports':PORTS,'kinds':dict(enumerate(SLUGS)),'count':64,'generator':'built-in image_gen','registration':'fixed grid; magenta removal; affine port alignment; nearest neighbor scaling'}
    (OUTPUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
