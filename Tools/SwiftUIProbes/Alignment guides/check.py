import re, math, sys, os
# Reads guide.out (SwiftUI) and tuikit.out (TUI at 45e9a1f7a, before the GUIDE fix) beside this script.
here = os.path.dirname(os.path.abspath(__file__))
pat = re.compile(r'(VStack|HStack)\((\w+)\) G [wh]=(\d+) guide=(-?\d+) \| S [wh]=(\d+) \|\| G\.[xy]=(-?\d+) S\.[xy]=(-?\d+) stack\.[wh]=(\d+)')
def own(al, size):
    return {'leading':0,'top':0,'trailing':size,'bottom':size,'center':size/2}[al]
def swiftui(al, gw, g, sw):
    pos=[g, own(al, sw)]; M=max(pos); off=[M-p for p in pos]
    return off[0], off[1], max(off[0]+gw, off[1]+sw)
def coord(v, size):
    r=max(1,size); return min(max(-r,v),2*r)
def tuikit(al, gw, g, sw):
    sizes=[gw,sw]; pos=[coord(g,gw), coord(own(al,sw),sw)]; M=max(pos)
    ext=max(max(math.ceil(M-p+s) for p,s in zip(pos,sizes)), max(sizes))
    anchor=max(M, coord(own(al,ext),ext))
    off=[min(max(0,math.floor(anchor-p)), max(0,ext-s)) for p,s in zip(pos,sizes)]
    return off[0], off[1], ext
for fn, model in [('guide.out', swiftui), ('tuikit.out', tuikit)]:
    ok=bad=0
    for line in open(os.path.join(here, fn)):
        m=pat.search(line)
        if not m: continue
        _, al, gw, g, sw, gx, sx, w = m.groups()
        got=(int(gx),int(sx),int(w)); want=model(al,int(gw),int(g),int(sw))
        if got==want: ok+=1
        else: bad+=1; print(fn, 'MISMATCH', line.strip(), 'model', want)
    print(fn, model.__name__, 'match', ok, 'mismatch', bad)

# Attribution: which of the two TUI rules makes each divergent row differ.
def tuikit_noclamp(al, gw, g, sw):
    sizes=[gw,sw]; pos=[g, own(al,sw)]; M=max(pos)
    ext=max(max(math.ceil(M-p+s) for p,s in zip(pos,sizes)), max(sizes))
    anchor=max(M, own(al,ext))
    off=[min(max(0,math.floor(anchor-p)), max(0,ext-s)) for p,s in zip(pos,sizes)]
    return off[0], off[1], ext
def tuikit_noanchor(al, gw, g, sw):
    sizes=[gw,sw]; pos=[coord(g,gw), coord(own(al,sw),sw)]; M=max(pos)
    off=[math.floor(M-p) for p in pos]; return off[0], off[1], max(o+s for o,s in zip(off,sizes))
cases=[]
for line in open(os.path.join(here, 'tuikit.out')):
    m=pat.search(line)
    if m: _, al, gw, g, sw, *_ = m.groups(); cases.append((al,int(gw),int(g),int(sw)))
diff=[c for c in cases if tuikit(*c)!=swiftui(*c)]
print('rows', len(cases), 'TUI != SwiftUI', len(diff))
print(' fixed by removing clamp alone:', sum(tuikit_noclamp(*c)==swiftui(*c) for c in diff))
print(' fixed by removing anchor alone:', sum(tuikit_noanchor(*c)==swiftui(*c) for c in diff))
print(' need both removed:', sum(tuikit_noclamp(*c)!=swiftui(*c) and tuikit_noanchor(*c)!=swiftui(*c) for c in diff))
print(' by alignment:', {a: sum(1 for c in diff if c[0]==a) for a in ['leading','trailing','center','top','bottom']})
