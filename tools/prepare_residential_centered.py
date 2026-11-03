"""Register the ImageGen residential street kit around the exact tile midpoint.
Only crops, resamples, mirrors and copies generated pixels; does not draw road art.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/source/residential-centered'
OUT=ROOT/'assets/sprites/roads-v5/residential'
SHAPES=['straight','curve','tee','cross']
PORTS=['NS','NE','NEW','NESW']
STATES=['burning','snowy','damaged','very_damaged','extreme_damage','closed','fading','roundabout','signal']

def carriageway(cell,direction):
 a=np.array(cell.convert('RGB'));h,w=a.shape[:2];band=max(4,int(min(h,w)*.06))
 stripe={'N':a[2:band], 'S':a[-band:-2], 'E':a[2:-2,-band:-2].transpose(1,0,2), 'W':a[2:-2,2:band].transpose(1,0,2)}[direction]
 values=np.median(stripe,axis=0).mean(axis=1)
 positions=np.flatnonzero(values<130)
 positions=positions[(positions>2)&(positions<len(values)-3)]
 if not len(positions): raise ValueError(('No asphalt port',direction))
 # Ignore thin paving joints outside the carriageway, bridging the central paint only.
 groups=[]
 for value in positions:
  if not groups or value-groups[-1][-1]>max(4,len(values)*.035):groups.append([value])
  else:groups[-1].append(value)
 body=max(groups,key=len)
 return (float(body[0]+body[-1]+1)/2,float(body[-1]-body[0]+1))

def register(cell,ports,straight=False):
 ns=[carriageway(cell,d) for d in 'NS' if d in ports]
 cx=sum(p[0] for p in ns)/len(ns);sx=48/(sum(p[1] for p in ns)/len(ns))
 if straight:cy=cell.height/2;sy=64/cell.height
 else:
  ew=[carriageway(cell,d) for d in 'EW' if d in ports]
  cy=sum(p[0] for p in ew)/len(ew);sy=48/(sum(p[1] for p in ew)/len(ew))
 frame=cell.convert('RGBA').transform((64,64),Image.Transform.AFFINE,(1/sx,0,cx-32/sx,0,1/sy,cy-32/sy),resample=Image.Resampling.NEAREST)
 return np.array(frame),{'center':[cx,cy],'scale':[sx,sy]}

def seams(frame,vertical,ports):
 horizontal=np.array(Image.fromarray(vertical).transpose(Image.Transpose.ROTATE_90))
 for direction in ports:
  if direction=='N':frame[:6]=vertical[:6]
  elif direction=='S':frame[-6:]=vertical[-6:]
  elif direction=='E':frame[:,-6:]=horizontal[:,-6:]
  else:frame[:,:6]=horizontal[:,:6]
 return frame

def apply_geometry():
 raw=Image.open(SOURCE/'geometry-raw.png').convert('RGBA')
 frames=[];qc=[]
 for index,(shape,ports) in enumerate(zip(SHAPES,PORTS)):
  x=index%2;y=index//2
  cell=raw.crop((round(x*raw.width/2)+2,round(y*raw.height/2)+2,round((x+1)*raw.width/2)-2,round((y+1)*raw.height/2)-2))
  frame,meta=register(cell,ports,shape=='straight')
  frames.append(frame);qc.append({'shape':shape,**meta})
 vertical=frames[0]
 # Keep the stronger centerline half, then reflect that generated half around x=31.5.
 if (vertical[:,31,:3]>210).all(axis=1).sum()>=(vertical[:,32,:3]>210).all(axis=1).sum():vertical[:,32:]=vertical[:,:32][:,::-1]
 else:vertical[:,:32]=vertical[:,32:][:,::-1]
 shoulder=vertical[3,3].copy()
 if shoulder[3]==0:shoulder=np.array(raw.getpixel((10,10)),dtype=np.uint8)
 vertical[vertical[:,:,3]==0]=shoulder
 # Registered corners belong to the sidewalk, and have one shared boundary sample.
 vertical[:6,:6]=shoulder;vertical[:6,-6:]=shoulder
 vertical[-6:]=vertical[:6][::-1]
 OUT.mkdir(parents=True,exist_ok=True)
 for shape,ports,frame in zip(SHAPES,PORTS,frames):
  frame[frame[:,:,3]==0]=shoulder
  Image.fromarray(seams(frame,vertical,ports)).save(OUT/(shape+'.png'))
 assert np.array_equal(vertical,vertical[:,::-1]),'Straight road must be symmetric around the tile midpoint'
 (SOURCE/'registration.json').write_text(json.dumps({'generator':'built-in image_gen','tile_size':64,'road_axis':31.5,'asphalt_width_target':48,'shared_seam_pixels':6,'frames':qc},indent=2))
 apply_conditions(vertical)
 return vertical

def apply_conditions(vertical):
 path=SOURCE/'conditions-raw.png'
 if not path.exists():return
 raw=Image.open(path).convert('RGBA')
 folder=ROOT/'assets/sprites/road-conditions/residential'
 # Register the actual generated grid (its last row is taller than the first two).
 ratio=raw.width/1254.0
 xs=[0,round(420*ratio),round(838*ratio),raw.width]
 ys=[0,round(420*ratio),round(796*ratio),raw.height]
 axes=[239,629,1024]
 widths=[248,280,240]
 for index,state in enumerate(STATES):
  x=index%3;y=index//3
  cell=raw.crop((xs[x]+2,ys[y]+2,xs[x+1]-2,ys[y+1]-2))
  if state=='roundabout':
   scale=.4/ratio
   cx=629*ratio-xs[x]-2;cy=990*ratio-ys[y]-2
   frame=np.array(cell.transform((192,192),Image.Transform.AFFINE,(1/scale,0,cx-96/scale,0,1/scale,cy-96/scale),resample=Image.Resampling.NEAREST))
   frame[frame[:,:,3]==0]=vertical[3,3]
   horizontal=np.array(Image.fromarray(vertical).transpose(Image.Transpose.ROTATE_90))
   frame[:64,64:128]=vertical;frame[-64:,64:128]=vertical
   frame[64:128,:64]=horizontal;frame[64:128,-64:]=horizontal
  else:
   cx=axes[x]*ratio-xs[x]-2;sx=48/(widths[x]*ratio);sy=64/cell.height
   frame=np.array(cell.transform((64,64),Image.Transform.AFFINE,(1/sx,0,cx-32/sx,0,1/sy,0),resample=Image.Resampling.NEAREST))
   frame[frame[:,:,3]==0]=vertical[3,3]
   frame=seams(frame,vertical,'NS')
   if state=='signal':
    # Keep the complete generated signal inside the sidewalk after registering the road.
    signal=raw.crop(tuple(round(v*ratio) for v in (1160,900,1220,1080)))
    pixels=np.array(signal);rgb=pixels[:,:,:3].astype(np.int16)
    mask=(rgb.mean(axis=2)<120)|((rgb.max(axis=2)-rgb.min(axis=2))>35)
    for row in mask:
     selected=np.flatnonzero(row)
     if len(selected)>1:row[selected[0]:selected[-1]+1]=True
    pixels[~mask]=0
    isolated=Image.fromarray(pixels);bounds=isolated.getbbox()
    if bounds:
     isolated=isolated.crop(bounds)
     factor=min(6/isolated.width,28/isolated.height)
     isolated=isolated.resize((max(1,round(isolated.width*factor)),max(1,round(isolated.height*factor))),Image.Resampling.NEAREST)
     frame[:,56:]=vertical[:,56:]
     finished=Image.fromarray(frame)
     finished.alpha_composite(isolated,(57,32-isolated.height//2))
     frame=np.array(finished)
  Image.fromarray(frame).save(folder/(state+'.png'))

def preview():
 out=Image.new('RGB',(768,384),'#172c2c')
 for index,shape in enumerate(SHAPES):
  tile=Image.open(OUT/(shape+'.png')).resize((160,160),Image.Resampling.NEAREST)
  out.paste(tile,(index*192+16,16),tile)
 network={(1,0):('straight',0),(1,1):('tee',0),(0,1):('straight',1),(2,1):('straight',1)}
 for (x,y),(shape,turns) in network.items():
  tile=Image.open(OUT/(shape+'.png')).rotate(-90*turns).resize((64,64),Image.Resampling.NEAREST)
  out.paste(tile,(288+x*64,184+y*64),tile)
 out.save(SOURCE/'preview.png')
 gallery=Image.new('RGB',(480,480),'#172c2c')
 folder=ROOT/'assets/sprites/road-conditions/residential'
 for index,state in enumerate(STATES):
  tile=Image.open(folder/(state+'.png')).resize((144,144),Image.Resampling.NEAREST)
  gallery.paste(tile,((index%3)*160+8,int(index/3)*160+8),tile)
 gallery.save(SOURCE/'conditions-preview.png')

if __name__=='__main__':
 apply_geometry();preview();print('Residential street registered around x=31.5 with matching 6-pixel seams')
