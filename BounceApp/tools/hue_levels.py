"""Draws the 50 Hue levels (Graphite accent and Sky as the second) into docs/hue-levels.png, with the same colour maths as HueLevels.swift."""
from PIL import Image, ImageDraw, ImageFont
def lin(v): return v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4
def lab(c):
    r,g,b=[lin(x) for x in c]
    l=(0.4122214708*r+0.5363325363*g+0.0514459929*b)**(1/3); m=(0.2119034982*r+0.6806995451*g+0.1073969566*b)**(1/3); s=(0.0883024619*r+0.2817188376*g+0.6299787005*b)**(1/3)
    return (0.2104542553*l+0.7936177850*m-0.0040720468*s, 1.9779984951*l-2.4285922050*m+0.4505937099*s, 0.0259040371*l+0.7827717662*m-0.8086757660*s)
def rgb(c):
    L,a,b=c; l=(L+0.3963377774*a+0.2158037573*b)**3; m=(L-0.1055613458*a-0.0638541728*b)**3; s=(L-0.0894841775*a-1.2914855480*b)**3
    def g(v):
        x=max(0,min(1,v)); return 12.92*x if x<=0.0031308 else 1.055*x**(1/2.4)-0.055
    return tuple(int(255*g(v)) for v in (4.0767416621*l-3.3077115913*m+0.2309699292*s, -1.2684380046*l+2.6097574011*m-0.3413193965*s, -0.0041960863*l-0.7034186147*m+1.7076147010*s))
mix=lambda a,b,t: tuple(x+(y-x)*t for x,y in zip(a,b))
hx=lambda h: ((h>>16&255)/255,(h>>8&255)/255,(h&255)/255)
W,K,A,B=lab(hx(0xF4F3EF)),lab(hx(0x1A1A1E)),lab(hx(0xFF6129)),lab(hx(0x6FB6F2))
tok={'light':W,'dark':K,'accent':A,'second':B,'accentSoft':mix(A,W,0.55),'secondDeep':mix(B,K,0.45)}
PAL=[['light', 'accent', 'second', 'dark'], ['accent', 'light', 'dark', 'second'], ['light', 'accent', 'dark', 'accent'], ['accentSoft', 'second', 'accent', 'dark'], ['light', 'second', 'accent', 'dark'], ['accent', 'light', 'accent', 'dark'], ['second', 'accent', 'light', 'second'], ['accent', 'second', 'dark', 'light'], ['light', 'accent', 'accentSoft', 'dark'], ['accent', 'second', 'secondDeep', 'accentSoft']]
def make(n):
    t=(n-1)/49
    fx='border' if n<=4 else 'alternate' if n<=10 else 'cross' if n<=18 else 'anchors' if n<=28 else 'corners'
    sh={1:'8',2:'14',3:'20'}.get(n,'all')
    return (PAL[(n-1)%len(PAL)], 1-0.82*t**0.85, fx, sh)
L=[make(n) for n in range(1,51)]
cols,rows=7,8
def fixed(kind,x,y):
    edge=x in(0,cols-1) or y in(0,rows-1); corner=x in(0,cols-1) and y in(0,rows-1)
    return {'border':edge,'alternate':edge and (x+y)%2==0,'cross':corner or (x==3 and y in(0,7)) or (y==4 and x in(0,6)) or (x==3 and y==4),'anchors':corner or (x in(2,4) and y in(2,5)),'corners':corner}[kind]
c=16; per=10; cw,chh=cols*c+24, rows*c+44
sheet=Image.new('RGB',(per*cw+20, 5*chh+20),(255,255,255)); d=ImageDraw.Draw(sheet); f=ImageFont.load_default(size=13)
for i,(cs,ct,fx,sh) in enumerate(L):
    cc=[tok[t] for t in cs]; mean=tuple(sum(v[k] for v in cc)/4 for k in range(3)); cc=[mix(mean,v,ct) for v in cc]
    ox=20+(i%per)*cw; oy=20+(i//per)*chh
    nfix=sum(fixed(fx,x,y) for y in range(rows) for x in range(cols))
    d.text((ox,oy),f"{i+1} · {nfix} fixed",fill=(30,30,30),font=f)
    for y in range(rows):
        for x in range(cols):
            u,v=x/(cols-1),y/(rows-1); col=rgb(mix(mix(cc[0],cc[1],u),mix(cc[2],cc[3],u),v))
            r=(ox+x*c, oy+20+y*c, ox+x*c+c-2, oy+20+y*c+c-2); d.rectangle(r,fill=col)
            if fixed(fx,x,y):
                lum=0.2126*col[0]/255+0.7152*col[1]/255+0.0722*col[2]/255; mx,my=(r[0]+r[2])/2,(r[1]+r[3])/2
                d.ellipse((mx-2,my-2,mx+2,my+2),fill=(60,60,60) if lum>0.55 else (240,240,240))
sheet.save('docs/hue-levels.png')
