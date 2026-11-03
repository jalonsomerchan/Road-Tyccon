"""Crop/clean generated tiles; narrow lanes retain registered ports, multilane tiles fill a cell."""
from pathlib import Path
import importlib.util
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('previous',ROOT/'tools/prepare_road_variants.py')
prep=importlib.util.module_from_spec(spec)
spec.loader.exec_module(prep)
SLUGS=prep.SLUGS+['forest','farm','cobble','residential','avenue','county','ring','superhighway']
LABELS=prep.LABELS+['Camino forestal','Camino agrícola','Camino adoquinado','Calle residencial','Avenida urbana','Carretera comarcal','Circunvalación','Autopista exprés']
LANES=[1,1,1,2,2,2,2,4,6,8,1,2,2,4,6,6,1,1,1,2,4,2,4,8]
OUT=ROOT/'assets/sprites/roads-v4'
SOURCE=ROOT/'assets/source/roads-v4'
OUT.mkdir(parents=True,exist_ok=True)
gallery=Image.new('RGB',(1088,624),'#1b302c')
draw=ImageDraw.Draw(gallery)
try:font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',14)
except OSError:font=ImageFont.load_default()
qc=[]
for index,slug in enumerate(SLUGS):
    raw_path=SOURCE/f'{slug}-raw.png'
    if not raw_path.exists():raw_path=ROOT/'assets/source/roads-v3'/f'{slug}-raw.png'
    raw=Image.open(raw_path).convert('RGBA')
    folder=OUT/slug
    folder.mkdir(parents=True,exist_ok=True)
    sheet=Image.new('RGBA',(128,128))
    for i,shape in enumerate(prep.SHAPES):
        x,y=i%2,i//2
        cell=prep.clean(raw.crop((round(x*raw.width/2),round(y*raw.height/2),round((x+1)*raw.width/2),round((y+1)*raw.height/2))))
        if LANES[index]==1:
            ports={d:prep.port(cell,d) for d in prep.PORTS[i]}
            cx=sum(ports[d][0] for d in 'NS' if d in ports)/sum(d in ports for d in 'NS')
            sx=24/(sum(ports[d][1] for d in 'NS' if d in ports)/sum(d in ports for d in 'NS'))
            if shape=='straight':
                cy=(ports['N'][2]+ports['S'][2])/2
                sy=64/(ports['S'][2]-ports['N'][2]+1)
            else:
                cy=sum(ports[d][0] for d in 'EW' if d in ports)/sum(d in ports for d in 'EW')
                sy=24/(sum(ports[d][1] for d in 'EW' if d in ports)/sum(d in ports for d in 'EW'))
            frame=cell.transform((64,64),Image.Transform.AFFINE,(1/sx,0,cx-32/sx,0,1/sy,cy-32/sy),resample=Image.Resampling.NEAREST)
            # Narrowing keeps the lane width but shortens ports. Extend each existing
            # straight end to the tile edge by repeating its own boundary pixels.
            data=np.array(frame)
            for direction in prep.PORTS[i]:
                if direction in 'NS':
                    candidates=np.flatnonzero((data[:,24:40,3]>128).sum(axis=1)>4)
                    edge=int(candidates.min() if direction=='N' else candidates.max())
                    if direction=='N':data[:edge]=data[edge:edge+1]
                    else:data[edge+1:]=data[edge:edge+1]
                else:
                    candidates=np.flatnonzero((data[24:40,:,3]>128).sum(axis=0)>4)
                    edge=int(candidates.min() if direction=='W' else candidates.max())
                    if direction=='W':data[:,:edge]=data[:,edge:edge+1]
                    else:data[:,edge+1:]=data[:,edge:edge+1]
            frame=Image.fromarray(data)
        else:
            crop=cell.crop(cell.getbbox())
            # The source is an opaque paved square. Remove only its magenta edge fringe.
            for inset in range(0,max(2,int(min(crop.size)*0.08))):
                candidate=crop.crop((inset,inset,crop.width-inset,crop.height-inset))
                frame=candidate.resize((64,64),Image.Resampling.NEAREST)
                if np.array(frame)[:,:,3].min()==255:break
            assert np.array(frame)[:,:,3].min()==255,(slug,shape,'Expected opaque square pavement')
        frame.save(folder/f'{shape}.png')
        sheet.alpha_composite(frame,((i%2)*64,(i//2)*64))
        gx,gy=(index%4)*272,(index//4)*104
        gallery.paste(frame,(gx+8+i*64,gy+28),frame)
        qc.append({'kind':slug,'shape':shape,'lanes':LANES[index],'size':list(frame.size),'alpha_min':int(np.array(frame)[:,:,3].min()),'bbox':frame.getbbox()})
    sheet.save(folder/'sheet.png')
    draw.text((gx+8,gy+6),LABELS[index]+f' · {LANES[index]}c',font=font,fill='#e0ebbc')
    print('prepared',slug,flush=True)
gallery.save(OUT/'gallery.png')
(OUT/'manifest.json').write_text(json.dumps({'count':96,'footprint':1,'lanes':LANES,'slugs':SLUGS,'shapes':prep.SHAPES,'generator':'built-in image_gen'},indent=2))
(SOURCE/'final-qc.json').write_text(json.dumps(qc,indent=2))
