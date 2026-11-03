"""Deterministic slicing, magenta key, shared tile alignment and nearest-neighbor scaling."""
from pathlib import Path
import json, importlib.util
from concurrent.futures import ThreadPoolExecutor
import subprocess,sys
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/sprites/road-conditions'
SOURCE=ROOT/'assets/source/road-conditions'
SLUGS=json.loads((ROOT/'assets/sprites/roads-v4/manifest.json').read_text())['slugs']
LANES=json.loads((ROOT/'assets/sprites/roads-v4/manifest.json').read_text())['lanes']
STATES=['burning','snowy','damaged','very_damaged','extreme_damage','closed','fading','roundabout','signal']
LABELS=['Fuego','Nieve','Dañada 5%','Muy dañada 15%','Extrema 30%','Cortada','Desapareciendo','Rotonda 3×3','Semáforo']
OUT.mkdir(parents=True,exist_ok=True)

def baseline(slug):
    tool=Path('/Users/jorgealonso/.codex/skills/generate2dsprite/scripts/generate2dsprite.py')
    args=[sys.executable,str(tool),'process','--input',str(SOURCE/f'{slug}-raw.png'),'--target','asset','--mode','sheet','--rows','3','--cols','3','--cell-size','64','--fit-scale','1.0','--align','center','--shared-scale','--component-mode','all','--trim-border','0','--edge-clean-depth','0','--label-prefix','state','--output-dir',str(SOURCE/f'{slug}-processor')]
    r=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    if r.returncode:raise RuntimeError(r.stdout)
    return slug

def key(cell):
    data=np.array(cell.convert('RGBA'))
    rgb=data[:,:,:3].astype(np.int16)
    data[(rgb[:,:,0]>rgb[:,:,1]+40)&(rgb[:,:,2]>rgb[:,:,1]+40)]=0
    return Image.fromarray(data)

def main():
    if '--baseline' in sys.argv:
        with ThreadPoolExecutor(max_workers=4) as pool:
            for slug in pool.map(baseline,SLUGS): print('QC',slug,flush=True)
    gallery=Image.new('RGB',(9*72+152,24*86+30),'#1b302c')
    draw=ImageDraw.Draw(gallery)
    try:font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',12)
    except OSError:font=ImageFont.load_default()
    for i,title in enumerate(LABELS):draw.text((152+i*72,8),title,font=font,fill='#dfedb6')
    report=[]
    for index,slug in enumerate(SLUGS):
        raw=Image.open(SOURCE/f'{slug}-raw.png').convert('RGBA')
        # The unadorned damaged tile supplies the shared road-body width. Fire,
        # snow and fixtures may extend beyond it without shrinking the road itself.
        reference=key(raw.crop((round(2*raw.width/3),0,raw.width,round(raw.height/3))))
        margin=max(1,int(min(reference.size)*.025))
        reference=reference.crop((margin,margin,reference.width-margin,reference.height-margin))
        ref_bbox=reference.getbbox()
        ref_cx=(ref_bbox[0]+ref_bbox[2])/2
        ref_width=ref_bbox[2]-ref_bbox[0]
        folder=OUT/slug;folder.mkdir(parents=True,exist_ok=True)
        draw.text((8,30+index*86+23),slug,font=font,fill='#dfedb6')
        for i,state in enumerate(STATES):
            x,y=i%3,i//3
            cell=key(raw.crop((round(x*raw.width/3),round(y*raw.height/3),round((x+1)*raw.width/3),round((y+1)*raw.height/3))))
            # Ignore atlas gutters and any tiny fragments spilling from a neighboring cell.
            inset=max(1,int(min(cell.size)*.025))
            cell=cell.crop((inset,inset,cell.width-inset,cell.height-inset))
            crop=cell.crop(cell.getbbox())
            size=192 if state=='roundabout' else 64
            frame=Image.new('RGBA',(size,size))
            if LANES[index]==1 and state!='roundabout':
                bbox=cell.getbbox()
                sx=24/ref_width
                sy=64/max(1,bbox[3]-bbox[1]-2)
                cy=(bbox[1]+bbox[3])/2
                frame=cell.transform((64,64),Image.Transform.AFFINE,(1/sx,0,ref_cx-32/sx,0,1/sy,cy-32/sy),resample=Image.Resampling.NEAREST)
            else:
                frame=crop.resize((size,size),Image.Resampling.NEAREST)
            frame.save(folder/f'{state}.png')
            thumb=frame.resize((64,64),Image.Resampling.NEAREST)
            gallery.paste(thumb,(152+i*72,30+index*86),thumb)
            report.append({'kind':slug,'state':state,'size':size,'bbox':frame.getbbox()})
        print('prepared',slug,flush=True)
    gallery.save(OUT/'gallery.png')
    (OUT/'manifest.json').write_text(json.dumps({'count':216,'slugs':SLUGS,'states':STATES,'size':64,'roundabout_size':192,'generator':'built-in image_gen'},indent=2))
    (SOURCE/'qc.json').write_text(json.dumps(report,indent=2))
    envout=ROOT/'assets/sprites/environment'
    for name in ['fire','snow']:
        raw=Image.open(ROOT/'assets/source/environment'/f'{name}-raw.png')
        folder=envout/name;folder.mkdir(parents=True,exist_ok=True)
        sheet=Image.new('RGBA',(128,128))
        for i in range(4):
            x,y=i%2,i//2
            cell=key(raw.crop((round(x*raw.width/2),round(y*raw.height/2),round((x+1)*raw.width/2),round((y+1)*raw.height/2))))
            art=cell.crop(cell.getbbox())
            art.thumbnail((60,60),Image.Resampling.NEAREST)
            frame=Image.new('RGBA',(64,64));frame.alpha_composite(art,((64-art.width)//2,(64-art.height)//2))
            frame.save(folder/f'frame-{i+1}.png');sheet.alpha_composite(frame,((i%2)*64,(i//2)*64))
        sheet.save(folder/'sheet.png')
if __name__=='__main__':main()
