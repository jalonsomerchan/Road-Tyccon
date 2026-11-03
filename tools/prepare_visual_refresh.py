"""Postprocess ImageGen assets: chroma key, register ports, extract, align and QC.
No artwork is drawn by this processor. Run with Pillow and NumPy installed.
"""
from pathlib import Path
import json, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/source/visual-refresh'
OUT=ROOT/'assets/sprites/roads-v5'
SLUGS=['dirt','gravel','concrete','local','secondary','main','express','dual','motorway','premium','wood_bridge','stone_bridge','concrete_bridge','steel_bridge','cable_bridge','suspension_bridge','forest','farm','cobble','residential','avenue','county','ring','superhighway']
LANES=[1,1,1,2,2,2,2,4,6,8,1,2,2,4,6,6,1,1,1,2,4,2,4,8]
SHAPES=['straight','curve','tee','cross']
PORTS=['NS','NE','NEW','NESW']
GRIDS={'a':([0,256,512,768,1024],[0,256,512,768,1024,1280,1536]),'b':([0,256,512,768,1024],[0,240,480,730,999,1249,1536]),'c':([0,256,512,768,1024],[0,257,514,769,1025,1280,1536]),'d':([0,243,488,752,1024],[0,251,499,747,1002,1247,1536])}

def clean(im):
 a=np.array(im.convert('RGBA'));rgb=a[:,:,:3].astype(np.int16)
 a[(rgb[:,:,0]>rgb[:,:,1]+45)&(rgb[:,:,2]>rgb[:,:,1]+45)]=0
 return Image.fromarray(a)

def port(im,direction,prototype,narrow):
 a=np.array(im);h,w=a.shape[:2];band=max(2,round(min(h,w)*.025))
 if direction=='N': stripe=a[:band]
 elif direction=='S': stripe=a[-band:]
 elif direction=='E': stripe=a[:,-band:].transpose(1,0,2)
 else: stripe=a[:,:band].transpose(1,0,2)
 alpha_port = float((stripe[:,:,3]>128).mean())
 use_alpha = narrow or alpha_port<.9
 if use_alpha: good=stripe[:,:,3]>128
 else:
  dist=np.linalg.norm(stripe[:,:,:3].astype(float)-prototype,axis=2)
  good=(stripe[:,:,3]>128)&(dist<35)
 scores=good.mean(axis=0);sel=np.flatnonzero(scores>(.22 if narrow else .65))
 # Ignore isolated grid/rail pixels and prefer the continuous road body.
 groups=[]
 for v in sel:
  if not groups or v-groups[-1][-1]>max(4,len(scores)*.09):groups.append([v])
  else:groups[-1].append(v)
 if not groups: raise ValueError(('No port',direction,prototype))
 groups=[g for g in groups if len(g)>=max(3,len(scores)*.04)] or groups
 group=[v for g in groups for v in g]
 return (group[0]+group[-1]+1)/2,group[-1]-group[0]+1,(24 if narrow else (64 if use_alpha else 48))

def extend_narrow(a,ports):
 for d in ports:
  if d in 'NS':
   rows=np.flatnonzero((a[:,24:40,3]>128).sum(axis=1)>4)
   edge=int(rows.min() if d=='N' else rows.max())
   if d=='N':a[:edge]=a[edge:edge+1]
   else:a[edge+1:]=a[edge:edge+1]
  else:
   cols=np.flatnonzero((a[24:40,:,3]>128).sum(axis=0)>4)
   edge=int(cols.min() if d=='W' else cols.max())
   if d=='W':a[:,:edge]=a[:,edge:edge+1]
   else:a[:,edge+1:]=a[:,edge:edge+1]
 return a

def retain_road(a,ports):
 if 'N' not in ports:a[:6]=0
 if 'S' not in ports:a[-6:]=0
 if 'E' not in ports:a[:,-6:]=0
 if 'W' not in ports:a[:,:6]=0
 mask=Image.fromarray(np.where(a[:,:,3]>128,255,0).astype(np.uint8)).copy()
 ImageDraw.floodfill(mask,(32,32),128)
 a[np.array(mask)!=128]=0
 return a

def roads():
 reports=[]
 for batch,(xs,ys) in GRIDS.items():
  raw=Image.open(SOURCE/f'roads-{batch}-raw.png')
  for row in range(6):
   kind=(ord(batch)-97)*6+row;slug=SLUGS[kind];narrow=LANES[kind]==1
   cells=[clean(raw.crop((xs[col]+2,ys[row]+2,xs[col+1]-2,ys[row+1]-2))) for col in range(4)]
   ref=np.array(cells[0]);h,w=ref.shape[:2]
   samples=ref[3:max(5,h//10),int(w*.33):int(w*.46),:3]
   prototype=np.median(samples.reshape(-1,3),axis=0)
   frames=[]
   for shape,ports,cell in zip(SHAPES,PORTS,cells):
    ns=[port(cell,d,prototype,narrow) for d in 'NS' if d in ports]
    cx=sum(p[0] for p in ns)/len(ns);sx=sum(p[2] for p in ns)/sum(p[1] for p in ns)
    if shape=='straight':cy=cell.height/2;sy=64/cell.height
    else:
     ew=[port(cell,d,prototype,narrow) for d in 'EW' if d in ports]
     cy=sum(p[0] for p in ew)/len(ew);sy=sum(p[2] for p in ew)/sum(p[1] for p in ew)
    frame=cell.transform((64,64),Image.Transform.AFFINE,(1/sx,0,cx-32/sx,0,1/sy,cy-32/sy),resample=Image.Resampling.NEAREST)
    a=np.array(frame)
    if narrow:a=extend_narrow(a,ports)
    else:
     # Composite onto a shoulder sample from this generated material, keeping the full-cell footprint.
     raw_pixels=np.array(cells[0]);left=raw_pixels[:,:max(3,raw_pixels.shape[1]//5)]
     valid=left[(left[:,:,3]>128)&(left[:,:,:3].max(axis=2)>65)]
     if not len(valid):valid=raw_pixels[(raw_pixels[:,:,3]>128)&(raw_pixels[:,:,:3].max(axis=2)>65)]
     if not len(valid):raise ValueError(('No generated shoulder sample',slug))
     sample=np.median(valid[:,:3],axis=0).astype(np.uint8)
     a[a[:,:,3]==0]=[*sample,255]
    frames.append(a)
    reports.append({'kind':slug,'shape':shape,'source_port_center':[cx,cy],'source_scale':[sx,sy]})
   straight=frames[0]
   # Opposite edges share the same registered seam. Corners contain shoulder, never a curb across a port.
   if not narrow:
    shoulder=straight[1,5,:3].copy()
    straight[:6,:6]=[*shoulder,255];straight[:6,-6:]=[*shoulder,255]
   straight[-6:]=straight[:6][::-1]
   if narrow: straight=retain_road(straight,"NS")
   horizontal=np.array(Image.fromarray(straight).transpose(Image.Transpose.ROTATE_90))
   for index,(shape,ports) in enumerate(zip(SHAPES,PORTS)):
    a=frames[index]
    if narrow:a=retain_road(a,ports)
    for d in ports:
     if d=='N':a[:6]=straight[:6]
     elif d=='S':a[-6:]=straight[-6:]
     elif d=='E':a[:,-6:]=horizontal[:,-6:]
     else:a[:,:6]=horizontal[:,:6]
    folder=OUT/slug;folder.mkdir(parents=True,exist_ok=True)
    Image.fromarray(a).save(folder/f'{shape}.png')
   print('registered',slug,flush=True)
 # Keep the dedicated centered residential kit when rebuilding the rest of the atlas.
 if (ROOT/'assets/source/residential-centered/geometry-raw.png').exists():
  import importlib.util
  spec=importlib.util.spec_from_file_location('residential_centered',ROOT/'tools/prepare_residential_centered.py')
  centered=importlib.util.module_from_spec(spec);spec.loader.exec_module(centered)
  centered.apply_geometry()
 (SOURCE/'road-registration.json').write_text(json.dumps(reports,indent=2))
 (OUT/'manifest.json').write_text(json.dumps({'generator':'built-in image_gen','count':96,'slugs':SLUGS,'shapes':SHAPES,'ports':PORTS,'size':64,'registration':'shared straight-edge six-pixel seams; affine carriageway and port registration; nearest-neighbor; opaque multilane footprints','overrides':{'residential':'assets/source/residential-centered/registration.json'} if (ROOT/'assets/source/residential-centered/geometry-raw.png').exists() else {}},indent=2))

BUILDINGS=['villa','slate_house','timber_house','apartment','brick_block','warehouse','civic','park']
def props():
 skill=Path('/Users/jorgealonso/.codex/skills/generate2dsprite/scripts/generate2dsprite.py')
 for key in ['cars']+BUILDINGS:
  dest=SOURCE/(key+'-processed')
  args=[sys.executable,str(skill),'process','--input',str(SOURCE/(key+'-raw.png')),'--target','asset','--mode','sheet','--rows','2' if key=='cars' else '1','--cols','4' if key=='cars' else '1','--cell-size','64','--fit-scale','0.92','--align','center','--component-mode','all','--min-component-area','12','--label-prefix','frame','--reject-edge-touch','--output-dir',str(dest)]
  subprocess.run(args,check=True,stdout=subprocess.DEVNULL)
  if key=='cars':
   for i in range(8):Image.open(dest/f'frame-{i+1}.png').save(ROOT/f'assets/sprites/vehicles-v2/car-{i+1}.png')
  else:Image.open(dest/'frame-1.png').save(ROOT/f'assets/sprites/city-v2/{key}.png')
  print('processed',key,flush=True)

def previews():
 gallery=Image.new('RGB',(768,24*102),'#172c2c');draw=ImageDraw.Draw(gallery)
 for i,slug in enumerate(SLUGS):
  draw.text((8,i*102+8),slug,fill='#d3e69b')
  for j,shape in enumerate(SHAPES):
   tile=Image.open(OUT/slug/(shape+'.png'));gallery.paste(tile,(140+j*72,i*102+25),tile)
  for (x,y),(shape,turns) in {(1,1):('tee',0),(1,0):('straight',0),(0,1):('straight',1),(2,1):('straight',1)}.items():
   tile=Image.open(OUT/slug/(shape+'.png')).rotate(-90*turns).resize((32,32),Image.Resampling.NEAREST)
   gallery.paste(tile,(500+x*32,i*102+y*32),tile)
 gallery.save(SOURCE/'road-gallery.png')
 gallery=Image.new('RGB',(768,192),'#172c2c')
 for i,name in enumerate(BUILDINGS):
  tile=Image.open(ROOT/f'assets/sprites/city-v2/{name}.png').resize((80,80),Image.Resampling.NEAREST)
  gallery.paste(tile,(i*96+8,8),tile)
 for i in range(8):
  tile=Image.open(ROOT/f'assets/sprites/vehicles-v2/car-{i+1}.png').resize((80,80),Image.Resampling.NEAREST)
  gallery.paste(tile,(i*96+8,104),tile)
 gallery.save(SOURCE/'props-gallery.png')

if __name__=='__main__':
 if '--roads-only' not in sys.argv: props()
 roads()
 previews()
