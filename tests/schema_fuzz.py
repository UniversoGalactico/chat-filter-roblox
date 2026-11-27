#!/usr/bin/env python3
"""Independent finite schema interpreter and generated payloads (no Roblox engine types)."""
import argparse, hashlib, json, math, random, subprocess, tempfile, time
from dataclasses import dataclass
from pathlib import Path
@dataclass
class Tbl:
 entries: list
@dataclass
class Buf:
 size: int
@dataclass
class Meta:
 table: Tbl
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--luau',required=True);p.add_argument('--source',type=Path,default=Path('RemoteGuardRoblox.lua'));p.add_argument('--seed',type=int,default=38101);p.add_argument('--schemas',type=int,default=512);p.add_argument('--cases',type=int,default=100);p.add_argument('--out',type=Path,required=True);p.add_argument('--optimization',default='all');a=p.parse_args();start=time.monotonic();rng=random.Random(a.seed)
def literal(v):
 if v is None:return 'nil'
 if type(v)==bool:return str(v).lower()
 if type(v)==bytes:return '"'+''.join('\\%03d'%b for b in v)+'"'
 if type(v)==str:return literal(v.encode())
 if type(v)==float:
  if math.isnan(v):return '(0/0)'
  if math.isinf(v):return 'math.huge' if v>0 else '-math.huge'
 if type(v) in (int,float):return repr(v)
 if isinstance(v,Buf):return f'buffer.create({v.size})'
 if isinstance(v,Meta):return 'setmetatable('+literal(v.table)+',{})'
 if isinstance(v,Tbl):return '{'+','.join('['+literal(k)+']='+literal(x) for k,x in v.entries if x is not None)+'}'
 if isinstance(v,list):return literal(Tbl(list(enumerate(v,1))))
 if isinstance(v,dict):return literal(Tbl(list(v.items())))
 raise TypeError(v)
def utf8(b):
 if type(b)!=bytes:return False
 try:b.decode('utf-8');return True
 except UnicodeDecodeError:return False
# Independent interpreter: no Lua ring or schema compiler; only finite generated plain values.
def reference(rule,value):
 nodes=0;length=0
 def visit(r,v):
  nonlocal nodes,length
  nodes+=1
  if nodes>512:return False
  if v is None:return r.get('Optional',False)
  kind=r['Type']
  if kind=='number':return type(v) in (int,float) and math.isfinite(v) and (not r.get('Integer') or v%1==0) and r.get('Min',-math.inf)<=v<=r.get('Max',math.inf)
  if kind=='string':
   if not utf8(v) or len(v)>r.get('MaxBytes',256):return False
   length+=len(v);return length<=16384 and ('Choices' not in r or v in r['Choices'])
  if kind=='boolean':return type(v)==bool
  if kind=='buffer':
   if not isinstance(v,Buf):return False
   length+=v.size;return v.size<=r['MaxBytes'] and length<=16384
  if not isinstance(v,Tbl):return False
  items=[(k,x) for k,x in v.entries if x is not None]
  if kind=='record':
   data={}
   for k,x in items:
    if type(k)!=bytes or k not in r['Fields']:return False
    data[k]=x;length+=len(k)
   return length<=16384 and all(visit(child,data.get(k)) for k,child in r['Fields'].items())
  if len(items)>r.get('MaxItems',32):return False
  if kind=='array':
   if any(type(k)!=int for k,_ in items) or {k for k,_ in items}!=set(range(1,len(items)+1)):return False
   return all(visit(r['Items'],x) for _,x in items)
  if kind=='map':return all(visit(r['Keys'],k) and visit(r['Values'],x) for k,x in items)
  raise ValueError(kind)
 return visit(rule,value)
def rule(depth=0,optional=False):
 kinds=['number','string','boolean','buffer']+(['record','array','map'] if depth<3 else [])
 k=rng.choice(kinds);r={'Type':k}
 if optional and rng.randrange(3)==0:r['Optional']=True
 if k=='number':
  if rng.randrange(2):r['Integer']=True
  if rng.randrange(2):r['Min']=rng.randrange(-12,1)
  if rng.randrange(2):r['Max']=rng.randrange(0,12)
 elif k=='string':
  r['MaxBytes']=rng.choice([0,1,4,16,64,256])
  if rng.randrange(3)==0:r['Choices']=[b'']+([b'x'] if r['MaxBytes']>0 else [])
 elif k=='buffer':r['MaxBytes']=rng.choice([0,1,4,64,1024])
 elif k=='record':r['Fields']={f'f{i}'.encode():rule(depth+1,True) for i in range(rng.randrange(5))}
 elif k=='array':r['MaxItems']=rng.randrange(5);r['Items']=rule(depth+1)
 elif k=='map':r['MaxItems']=rng.randrange(5);r['Keys']={'Type':'string','MaxBytes':4};r['Values']=rule(depth+1)
 return r
def good(r):
 if r.get('Optional') and rng.randrange(4)==0:return None
 k=r['Type']
 if k=='number':
  lo=r.get('Min',-100);hi=r.get('Max',100)
  return rng.randint(lo,hi) if r.get('Integer') else rng.uniform(lo,hi)
 if k=='string':return rng.choice(r['Choices']) if 'Choices' in r else b'x'*rng.randint(0,min(32,r['MaxBytes']))
 if k=='boolean':return rng.choice([True,False])
 if k=='buffer':return Buf(rng.randrange(r['MaxBytes']+1))
 if k=='record':return Tbl([(key,good(child)) for key,child in r['Fields'].items()])
 if k=='array':return Tbl([(i,good(r['Items'])) for i in range(1,rng.randrange(r['MaxItems']+1)+1)])
 if k=='map':return Tbl([(f'k{i}'.encode(),good(r['Values'])) for i in range(rng.randrange(r['MaxItems']+1))])
def garbage():
 return rng.choice([None,True,False,0,1,-1,1.5,2**53,float('inf'),float('-inf'),float('nan'),b'',b'a',b'x'*300,b'\xff',b'\xed\xa0\x80',b'\xc0\xaf',b'\x00',Tbl([]),Tbl([(1,2)]),Tbl([(2,3)]),Tbl([(True,1)]),Tbl([(b'x',False)]),Meta(Tbl([])),Buf(16385)])
def mutate(r,v):
 if not isinstance(v,Tbl) or rng.randrange(3)==0:return garbage()
 items=list(v.entries);kind=r['Type'];mode=rng.randrange(6)
 if mode==0:return Meta(Tbl(items))
 if mode==1:return Tbl(items[:-1])
 if mode==2:
  # Extra keys have different behavior in a record, array, and map.
  key={k for k,_ in items};extra=rng.choice([b'extra',b'\xff',257,-1,0])
  return Tbl(items+[(extra,garbage())]) if extra not in key else Tbl(items)
 if mode==3 and kind=='array' and items:return Tbl([(k+1,x) for k,x in items])
 if items:
  index=rng.randrange(len(items));key,x=items[index]
  child=(r['Fields'][key] if kind=='record' else r['Items'] if kind=='array' else r['Values'])
  items[index]=(key,mutate(child,x))
 return Tbl(items)
header=r'''
local total,allowed,denied,errors=0,0,0,0
local function run(schema,cases,id)
 local t=0
 local g=RemoteGuard.new({Global={Limit=1,Window=1},Clock=function()return t end,MaxSubjects=1,Actions={A={Quota={Limit=1,Window=1},Args={schema}}}})
 for i,c in ipairs(cases) do
  t+=1;local ok,code,detail=g:Check(1,"A",c.v);total+=1
  if c.good then allowed+=1 else denied+=1 end
  if ok~=c.good or (not ok and (code~="INVALID_ARGUMENT" or detail~=1)) then
   errors+=1;if errors<=10 then print("DIFF",id,i,ok,code,detail,c.good) end
  end
 end
end
'''
source='local RemoteGuard=(function()\n'+a.source.read_text()+'\nend)()\n'+header
rows=[];expected_allowed=0;expected_denied=0;type_counts={}
for i in range(a.schemas):
 r=rule(optional=True);type_counts[r['Type']]=type_counts.get(r['Type'],0)+1;cases=[]
 for j in range(a.cases):
  v=good(r);v= v if j%4==0 else mutate(r,v) if j%4 in (1,2) else garbage()
  result=reference(r,v);expected_allowed+=int(result);expected_denied+=int(not result)
  cases.append('{v='+literal(v)+',good='+str(result).lower()+'}')
 rows.append('run('+literal(r)+',{'+','.join(cases)+'},'+str(i)+')')
end='print("TOTAL",total,allowed,denied,errors)\n'
runs=[]
with tempfile.TemporaryDirectory() as td:
 path=Path(td)/'schema.luau'
 for opt in (range(3) if a.optimization=='all' else [int(a.optimization)]):
  sums=[0,0,0,0];witness=[]
  for i in range(0,len(rows),64):
   path.write_text(source+'\n'+'\n'.join(rows[i:i+64])+'\n'+end)
   result=subprocess.run([a.luau,f'-O{opt}',str(path)],capture_output=True,text=True,timeout=120)
   if result.returncode:raise RuntimeError(result.stderr+result.stdout[-1000:])
   for line in result.stdout.splitlines():
    row=line.split('\t')
    if row[0]=='TOTAL':sums=[x+int(y) for x,y in zip(sums,row[1:])]
    elif row[0]=='DIFF' and len(witness)<16:witness.append(row[1:])
  assert sums[:3]==[a.schemas*a.cases,expected_allowed,expected_denied],sums
  runs.append({'optimization':opt,'cases':sums[0],'expected_allowed':sums[1],'expected_denied':sums[2],'differences':sums[3],'witnesses':witness});print(opt,sums,witness[:5],flush=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps({'source_sha256':sha(a.source),'campaign_sha256':sha(__file__),'vm_sha256':sha(a.luau),'seed':a.seed,'schemas':a.schemas,'cases_per_schema':a.cases,'root_types':type_counts,'runs':runs,'elapsed_seconds':time.monotonic()-start,'scope':'finite generated schemas and payloads against independent Python interpreter; no engine type simulation'},indent=2)+'\n')
raise SystemExit(int(any(x['differences'] for x in runs)))
