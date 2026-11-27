#!/usr/bin/env python3
"""Differential arithmetic / quota / UTF-8 audit against external LuauProof 3.20."""
import argparse, hashlib, json, random, struct, subprocess, sys, tempfile, time
from fractions import Fraction
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--luauproof',type=Path,required=True);p.add_argument('--source',type=Path,default=Path('RemoteGuardRoblox.lua'));p.add_argument('--seed',type=int,default=32071);p.add_argument('--out',type=Path,required=True);p.add_argument('--boundary',type=int,default=24000);a=p.parse_args()
started=time.monotonic();root=a.luauproof.resolve();sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
pins={'numeric_fuzz320.py':'5d4cf91db579d2097cac2d13b9a77bef0bbad54878a47ad493a5d502d6f3e4b0','binary64_320.py':'8995a1949fcc910986bcfe38a9b9c406410db3c25929c45233f1a250a6fe8253','runtime/linux/luau':'7741b96bd8fadb340965b7468dc4a2be8fe41247b8219bd8d4a7e80f16b40625','vm_binary64_320.py':'ba264eb5b102209ab0dbacc7c189a8fcd1536f08ed0805d1f88b4647be370af6'}
for path,h in pins.items():assert sha(root/path)==h,path
sys.path.insert(0,str(root))
from numeric_fuzz320 import generate,expr,eval_ast
from vm_binary64_320 import pairs
from binary64_320 import parts,encode,INF,SIGN
rng=random.Random(a.seed);pool=pairs(a.seed,20000);selected=rng.sample(pool,128);trees=generate(a.seed,128)
def val(b):
 s,k,x=parts(b);return (-x if s else x) if k in ('finite','zero') else None
def bits(b):return f'{b&0xffffffff},{b>>32}'
def bl(x):return str(bool(x)).lower()
def lit(s):return '"'+''.join('\\%03d'%b for b in s)+'"'
def fb(v):return struct.unpack('<Q',struct.pack('<d',v))[0]
body=[r'''
local counts,bad={},{}
local function check(group,ok,label)
 counts[group]=(counts[group] or 0)+1
 if not ok then bad[group]=(bad[group] or 0)+1;if bad[group]<=12 then print("DIFF",group,label) end end
end
local function frombits(lo,hi) return (string.unpack("<d",string.pack("<I4I4",lo,hi))) end
local function matches(v,e)
 if e~=e then return v~=v end
 if e==0 then return v==0 end
 return string.pack("<d",v)==string.pack("<d",e)
end
local now=0
local function new(rule)
 return RemoteGuard.new({Global={Limit=2,Window=1},Clock=function() return now end,MaxSubjects=1,Actions={A={Quota={Limit=2,Window=1},Args={rule}}}})
end
local num=new({Type="number",Min=-1000000,Max=1000000})
local int=new({Type="number",Integer=true,Min=-1000000,Max=1000000})
local str=new({Type="string",MaxBytes=64})
local funcs={}
''']
for i,t in enumerate(trees):body.append(f'funcs[{i+1}]=function(a,b) return {expr(t)} end')
body.append(r'''
local function numeric(i,f,al,ah,bl,bh,el,eh,valid,isint)
 local v=funcs[f](frombits(al,ah),frombits(bl,bh));local e=frombits(el,eh)
 check("oracle",matches(v,e),i)
 now+=1;check("numeric_acceptance",num:Check(1,"A",v)==valid,i)
 check("integer_acceptance",int:Check(1,"A",v)==isint,i)
end
local function direct(i,lo,hi,valid,isint)
 local v=frombits(lo,hi);now+=1;check("direct_number",num:Check(1,"A",v)==valid,i)
 check("direct_integer",int:Check(1,"A",v)==isint,i)
end
local function text(i,v,valid)
 now+=1;check("utf8",str:Check(1,"A",v)==valid,i)
end
local function boundary(i,al,ah,bl,bh,wl,wh,due,mode)
 local start,finish,w=frombits(al,ah),frombits(bl,bh),frombits(wl,wh)
 local clock=start
 local c={Global={Limit=2,Window=w},Actions={A={Quota={Limit=2,Window=w},Args={}}},MaxSubjects=2,Clock=function()return clock end}
 if mode==1 then c.Global.Limit=1 elseif mode==2 then c.Actions.A.Quota.Limit=1 else c.Server={Limit=1,Window=w} end
 local g=RemoteGuard.new(c);check("first_admission",g:Check(1,"A"),i)
 clock=finish
 local ok,code,wait=g:Check(if mode==3 then 2 else 1,"A")
 check("boundary_admission",ok==due,i)
 check("boundary_reason",code==(if due then nil elseif mode==1 then "GLOBAL_LIMIT" elseif mode==2 then "ACTION_LIMIT" else "SERVER_LIMIT"),i)
 if not due then check("boundary_positive_wait",type(wait)=="number" and wait>0 and wait<=w,i) end
 g:Destroy()
end
local function sweep(i,al,ah,bl,bh,wl,wh,due)
 local start,finish,w=frombits(al,ah),frombits(bl,bh),frombits(wl,wh)
 local clock=start
 local g=RemoteGuard.new({Global={Limit=1,Window=w},Actions={A={Quota={Limit=1,Window=w},Args={}}},MaxSubjects=1,Clock=function()return clock end})
 g:Check(1,"A");clock=finish;check("sweep_boundary",g:Sweep()==(if due then 1 else 0),i)
end
''')
for i,t in enumerate(trees):
 for j,(x,y) in enumerate(selected):
  b=eval_ast(t,x,y);v=val(b);valid=v is not None and -1000000<=v<=1000000
  body.append(f'numeric({i*128+j},{i+1},{bits(x)},{bits(y)},{bits(b)},{bl(valid)},{bl(valid and v.denominator==1)})')
for i,(x,y) in enumerate(pool[:8000]):
 v=val(x);valid=v is not None and -1000000<=v<=1000000
 body.append(f'direct({i},{bits(x)},{bl(valid)},{bl(valid and v.denominator==1)})')
for i in range(5000):
 s=bytes(rng.randrange(256) for _ in range(rng.randrange(0,90))) if i%3 else (chr(rng.choice([rng.randrange(0xd800),rng.randrange(0xe000,0x110000)]))*rng.randrange(0,40)).encode()
 if i%100==0:s=bytes.fromhex('eda080')
 try:s.decode('utf-8');valid=len(s)<=64
 except UnicodeDecodeError:valid=False
 body.append(f'text({i},{lit(s)},{bl(valid)})')
# Target all relevant scales, near rounded deadline and at representable neighbors.
starts=[fb(0),fb(2**32),fb(2**-60),1,2,fb(1),fb(1e-300)]
starts.extend(x&~SIGN for x,_ in pool if val(x&~SIGN) is not None and val(x&~SIGN)<=2**32)
windows=[fb(.001),fb(.01),fb(.1),fb(1),fb(10),fb(3600)]
windows.extend(x&~SIGN for x,_ in pool if val(x&~SIGN) is not None and val(fb(.001))<=val(x&~SIGN)<=3600)
maxclock=fb(2**32);n=0;early=0
while n<a.boundary:
 w=rng.choice(windows) if n%4 else fb(rng.uniform(.001,3600))
 start=rng.choice(starts) if n%3 else fb(rng.uniform(0,2**32))
 exact=val(start)+val(w);nearest=encode(exact)
 finish=min(maxclock,max(start,nearest+rng.choice([-3,-2,-1,0,0,0,1,2,3])))
 due=val(finish)-val(start)>=val(w)
 rounded=encode(val(finish)-val(start))
 if not due and rounded>=w:early+=1
 body.append(f'boundary({n},{bits(start)},{bits(finish)},{bits(w)},{bl(due)},{n%3+1})')
 if n%3==0:body.append(f'sweep({n},{bits(start)},{bits(finish)},{bits(w)},{bl(due)})')
 n+=1
body.append('for group,n in pairs(counts) do print("COUNT",group,n,bad[group] or 0) end')
source='local RemoteGuard=(function()\n'+a.source.read_text()+'\nend)()\n'+'\n'.join(body)
runs=[]
with tempfile.TemporaryDirectory() as td:
 path=Path(td)/'audit.luau';path.write_text(source)
 for opt in range(3):
  r=subprocess.run([str(root/'runtime/linux/luau'),f'-O{opt}',str(path)],capture_output=True,text=True,timeout=120)
  if r.returncode:raise RuntimeError(r.stderr+r.stdout[-2000:])
  counts={};diff=[]
  for line in r.stdout.splitlines():
   row=line.split('\t')
   if row[0]=='COUNT':counts[row[1]]={'checks':int(row[2]),'differences':int(row[3])}
   elif row[0]=='DIFF':diff.append(row[1:])
  assert counts['oracle']['checks']==128*128 and counts['boundary_admission']['checks']==a.boundary
  runs.append({'optimization':opt,'counts':counts,'witnesses':diff});print(opt,'checks',sum(v['checks'] for v in counts.values()),'differences',sum(v['differences'] for v in counts.values()),diff[:8],flush=True)
report={'source_sha256':sha(a.source),'campaign_sha256':sha(Path(__file__)),'tool_pins':pins,'seed':a.seed,'boundary_cases':a.boundary,'rounded_early_boundary_witnesses':early,'runs':runs,'elapsed_seconds':time.monotonic()-started,'scope':'finite arithmetic, integer/number/UTF8 acceptance, exact represented quota expiry and sweep; bundled Luau CLI only, not formal or Roblox verification'}
a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(report,indent=2)+'\n')
sys.exit(int(any(v['differences'] for run in runs for v in run['counts'].values())))
