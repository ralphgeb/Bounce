"""Draws all 20 Maze levels with the same generator as Maze.swift (same random numbers), into docs/.

Run from anywhere:  python3 BounceApp/tools/maze_levels.py
"""
from collections import deque
from PIL import Image, ImageDraw, ImageFont
M=(1<<64)-1
class R:
    def __init__(s,seed): s.st=(seed+0x9E3779B97F4A7C15)&M
    def next(s):
        s.st=(s.st+0x9E3779B97F4A7C15)&M; z=s.st
        z=((z^(z>>30))*0xBF58476D1CE4E5B9)&M; z=((z^(z>>27))*0x94D049BB133111EB)&M
        return z^(z>>31)
def size(level):
    cw=4+level+int(max(0,level-4)*0.9)
    return cw,int(cw*1.4)
def gen1(level, attempt):
    rng=R((level*7919+104729+attempt*1_000_003)&M); roll=lambda n: rng.next()%n
    cw,ch=size(level); W,H=cw*2+1,ch*2+1
    wall=[True]*(W*H)
    def op(x,y): wall[y*W+x]=False
    isw=lambda x,y: x<0 or y<0 or x>=W or y>=H or wall[y*W+x]
    branchy=min(0.1,(level-1)*0.1/19)
    sx,sy=cw//2,ch-1; vis=[False]*(cw*ch); act=[(sx,sy)]; vis[sy*cw+sx]=True; op(sx*2+1,sy*2+1)
    while act:
        br=roll(1000)/1000<branchy
        pick=roll(len(act)) if br else len(act)-1
        cx,cy=act[pick]
        opts=[(dx,dy) for dx,dy in((1,0),(-1,0),(0,1),(0,-1)) if 0<=cx+dx<cw and 0<=cy+dy<ch and not vis[(cy+dy)*cw+cx+dx]]
        if not opts: act.pop(pick); continue
        dx,dy=opts[roll(len(opts))]; nx,ny=cx+dx,cy+dy; vis[ny*cw+nx]=True; op(cx*2+1+dx,cy*2+1+dy); op(nx*2+1,ny*2+1); act.append((nx,ny))
    extra=int(cw*ch*(0.03+0.001*level)); made=tries=0
    while made<extra and tries<extra*40:
        tries+=1; x=1+roll(W-2); y=1+roll(H-2)
        if not isw(x,y) or (x+y)%2!=1: continue
        a=not isw(x-1,y) and not isw(x+1,y) and isw(x,y-1) and isw(x,y+1)
        d=not isw(x,y-1) and not isw(x,y+1) and isw(x-1,y) and isw(x+1,y)
        if a or d: op(x,y); made+=1
    for cy in range(ch):
        for cx in range(cw):
            x,y=cx*2+1,cy*2+1
            walls=[(dx,dy) for dx,dy in((1,0),(-1,0),(0,1),(0,-1)) if isw(x+dx,y+dy)]
            if len(walls)!=3 or not roll(100)<max(30,90-3*level): continue
            inside=[d for d in walls if 0<x+d[0]*2<W-1 and 0<y+d[1]*2<H-1]
            if not inside: continue
            d=inside[roll(len(inside))]; op(x+d[0],y+d[1])
    start=(sx*2+1,sy*2+1)
    dist={start:0}; prev={}; q=deque([start]); best=start
    while q:
        p=q.popleft()
        if dist[p]>dist[best]: best=p
        for dx,dy in((1,0),(-1,0),(0,1),(0,-1)):
            n=(p[0]+dx,p[1]+dy)
            if not isw(*n) and n not in dist: dist[n]=dist[p]+1; prev[n]=p; q.append(n)
    path=[best]
    while path[-1]!=start: path.append(prev[path[-1]])
    dead=sum(1 for y in range(H) for x in range(W) if not isw(x,y) and sum(isw(x+a,y+b) for a,b in((1,0),(-1,0),(0,1),(0,-1)))==3)
    return isw,W,H,start,best,path,dist[best],dead
def gen(level):
    cw,ch=size(level)
    target=int(2*cw*ch*(0.22+0.012*level))
    best=None
    for a in range(12):
        g=gen1(level,a)
        if best is None or abs(g[6]-target)<abs(best[6]-target): best=g
    return best
ink=(18,18,20); bg=(249,249,247); acc=(255,97,41)
def draw(level, box):
    isw,W,H,start,goal,path,L,dead=gen(level)
    t=max(1,min(box[0]//W, box[1]//H))
    im=Image.new('RGB',(W*t,H*t),bg); d=ImageDraw.Draw(im)
    for y in range(H):
        for x in range(W):
            if isw(x,y): d.rectangle((x*t,y*t,x*t+t-1,y*t+t-1),fill=ink)
    for (x,y) in path: d.rectangle((x*t+t//3,y*t+t//3,x*t+t-1-t//3,y*t+t-1-t//3),fill=(255,190,160))
    sx,sy=start; d.rectangle((sx*t,sy*t,sx*t+t-1,sy*t+t-1),fill=acc)
    gx,gy=goal; d.ellipse((gx*t-t//2,gy*t-t//2,gx*t+t+t//2,gy*t+t+t//2),fill=acc)
    return im,(W,H,L,dead)
import os
out=os.path.join(os.path.dirname(__file__), '..', '..', 'docs', 'maze-levels')
os.makedirs(out, exist_ok=True)
font=ImageFont.load_default(size=22); small=ImageFont.load_default(size=16)
cellw,cellh=420,600; sheet=Image.new('RGB',(cellw*5,cellh*4+70),(255,255,255)); sd=ImageDraw.Draw(sheet)
sd.text((20,20),"MAZE  ·  20 levels  ·  accent square = start, circle = way out, light path = shortest route",fill=ink,font=font)
for lv in range(1,21):
    im,(W,H,L,dead)=draw(lv,(cellw-30,cellh-80))
    im.save(f'{out}/level-{lv:02d}.png')
    i=lv-1; cx,cy=(i%5)*cellw,(i//5)*cellh+70
    sheet.paste(im,(cx+(cellw-im.width)//2,cy+50+(cellh-80-im.height)//2))
    sd.text((cx+20,cy+12),f"Level {lv}",fill=ink,font=font)
    sd.text((cx+130,cy+16),f"{W}x{H} tiles · {L} steps · {dead} dead ends",fill=(120,120,120),font=small)
    print(lv,W,H,L,dead)
sheet.save(f'{out}/../maze-levels.png')
big,_=draw(20,(1400,2000)); big.save(f'{out}/../maze-level-20.png')
