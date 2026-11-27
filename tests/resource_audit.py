#!/usr/bin/env python3
"""Inspect private invariants in a temporary instrumented copy; never ship audit hooks."""
import argparse, hashlib, json, subprocess, tempfile, time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--luau',required=True);p.add_argument('--compiler',required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[1];start=time.monotonic();source=(root/'RemoteGuardRoblox.lua').read_text()
anchor=' table.freeze(guard)\n return guard :: Guard'
assert source.count(anchor)==1
hook=r'''
 function guard:_Audit()
  local slotsUsed=0
  local function bucketInvariant(b,q)
   assert(b.Count>=0 and b.Count<=q.Limit and b.Count%1==0,"audit: ring count")
   assert(b.Head>=1 and b.Head<=q.Limit and b.Head%1==0,"audit: ring head")
   for index,stamp in pairs(b.Times) do
    assert(type(index)=="number" and index%1==0 and index>=1 and index<=q.Limit,"audit: ring slot")
    assert(finite(stamp) and stamp>=0 and stamp<=last,"audit: timestamp")
    slotsUsed+=1
   end
   local previous=-1
   for i=0,b.Count-1 do
    local stamp=b.Times[(b.Head+i-1)%q.Limit+1]
    assert(stamp~=nil and stamp>=previous,"audit: ordered live timestamps")
    previous=stamp
   end
  end
  local observed,tracked,flights=0,{},{}
  for _,s in pairs(subjects) do
   observed+=1;tracked[s]=true
   assert(s.Live and s.Last<=last,"audit: tracked identity")
   bucketInvariant(s.Global,global)
   for action,b in pairs(s.Actions) do assert(actions[action],"audit: known action");bucketInvariant(b,actions[action].Quota) end
  end
  assert(observed==count and count<=capacity,"audit: subject count")
  if server then bucketInvariant(serverBucket,server) else assert(serverBucket.Count==0 and next(serverBucket.Times)==nil,"audit: disabled server") end
  local total=0
  for token,lease in pairs(leases) do
   total+=1;assert(type(token)=="table" and table.isfrozen(token),"audit: opaque frozen token")
   local s=lease.State
   assert((tracked[s]==true)==s.Live,"audit: retirement generation")
   if not s.Live then assert(s.Global.Count==0 and next(s.Global.Times)==nil and next(s.Actions)==nil,"audit: retired quota history") end
   local x=flights[s] or {total=0,actions={}};flights[s]=x;x.total+=1
   x.actions[lease.Action]=(x.actions[lease.Action] or 0)+1
  end
  assert(total==inFlight and inFlight<=flightLimit,"audit: shared permit count")
  local function flightInvariant(s)
   local x=flights[s] or {total=0,actions={}}
   assert(s.InFlight==x.total and s.InFlight<=subjectLimit,"audit: subject permit count")
   for action,n in pairs(s.Pending) do
    assert(n==(x.actions[action] or 0) and n>=0 and actions[action].MaxInFlight~=nil and n<=actions[action].MaxInFlight,"audit: action permit count")
   end
   for action,n in pairs(x.actions) do assert(s.Pending[action]==n,"audit: missing permit count") end
  end
  for s in pairs(tracked) do flightInvariant(s) end
  for s in pairs(flights) do if not tracked[s] then flightInvariant(s) end end
  assert(slotsUsed<=capacity*slots+(if server then server.Limit else 0),"audit: aggregate timestamp budget")
  for _,n in pairs(stats) do assert(integer(n) and n>=0 and n<=MAX_COUNT,"audit: counter range") end
  if destroyed then assert(count==0 and inFlight==0 and next(actions)==nil and clock==nil,"audit: destroy references") end
  return true
 end
 function guard:_NearCounterLimit()
  stats.Allowed=MAX_COUNT-1;stats.Denied=MAX_COUNT-1;stats.UNKNOWN_ACTION=MAX_COUNT-1
 end
'''
model=(root/'tests/model.luau').read_text().replace('  operations+=1','  assert(g:_Audit());operations+=1').replace('eq(g:Destroy(),true,"destroy");','eq(g:Destroy(),true,"destroy");assert(g:_Audit());')
stress=r'''
local now=0
local function config(cap,flight)
 return {Global={Limit=128,Window=1},MaxSubjects=cap,MaxInFlight=flight,MaxInFlightPerSubject=1,Clock=function()return now end,Actions={A={Quota={Limit=128,Window=1},Args={},MaxInFlight=1},B={Quota={Limit=128,Window=1},Args={}}}}
end
-- Retire a full generation of subjects while their tasks still own permits.
local g=RemoteGuard.new(config(128,64));local retirementChecks=0
for iteration=1,100 do
 now+=2;local tokens={}
 for i=1,64 do
  local id={}
  for j=1,8 do assert(g:Check(id,"B")) end
  local token=assert(g:Begin(id,"A"));tokens[i]=token
  assert(g:Forget(id));assert(g:_Audit());assert(not g:IsCurrent(token));retirementChecks+=1
 end
 assert(g:GetStats().InFlight==64 and g:Count()==0)
 local other={};local token,why=g:Begin(other,"A");assert(not token and why=="SERVER_IN_FLIGHT")
 assert(g:Forget(other));assert(g:_Audit())
 for _,token in ipairs(tokens) do assert(g:Release(token));assert(g:_Audit());retirementChecks+=1 end
end
assert(g:Destroy());assert(g:_Audit())
-- Full configured subject capacity, repeated expiry and reuse.
local c=config(4096,1);c.Global.Limit=1;c.Actions.A=nil;c.Actions.B.Quota.Limit=1
local h=RemoteGuard.new(c);local capacityChecks=0
for cycle=1,20 do
 now+=2
 for i=1,4096 do assert(h:Check(i,"B"));if i%128==0 then assert(h:_Audit());capacityChecks+=1 end end
 local ok,why=h:Check(4097,"B");assert(not ok and why=="CAPACITY")
 now+=1;assert(h:Sweep()==4096);assert(h:_Audit());capacityChecks+=1
end
h:_NearCounterLimit();assert(h:Check(1,"B"));now+=1;assert(h:Check(1,"B"));assert(not h:Check(1,"unknown"));assert(not h:Check(1,"unknown"));assert(h:_Audit())
assert(h:GetStats().Allowed==2^53-1 and h:GetStats().Denied==2^53-1 and h:GetStats().UNKNOWN_ACTION==2^53-1)
assert(h:Destroy());assert(h:_Audit())
print("PASS RESOURCE",retirementChecks,capacityChecks)
'''
mutants=[('retired_history_retained','s.Live=false;s.Global=bucket();s.Actions={};subjects[subject]=nil;count-=1','s.Live=false;subjects[subject]=nil;count-=1'),('release_map_leak','  leases[token]=nil\n  local s,action','  local s,action'),('ring_extra_slot',' b.Times[i]=now',' b.Times[i]=now;b.Times[q.Limit+1]=now'),('unmarked_retirement','s.Live=false;s.Global=bucket();','s.Global=bucket();'),('counter_overflow','stats[category]=math.min(MAX_COUNT,stats[category]+1)','stats[category]=stats[category]+1')]
rows=[]
with tempfile.TemporaryDirectory() as td:
 path=Path(td)/'audit.luau'
 for name,old,new in [('unmodified','','')]+mutants:
  code=source if name=='unmodified' else source.replace(old,new,1)
  if name!='unmodified':assert source.count(old)==1,(name,source.count(old))
  code=code.replace(anchor,hook+'\n'+anchor)
  path.write_text('local RemoteGuard=(function()\n'+code+'\nend)()\n'+(model+'\n' if name=='unmodified' else '')+stress)
  comp=subprocess.run([a.compiler,str(path)],capture_output=True,timeout=30);assert comp.returncode==0,comp.stderr.decode()[:300]
  r=subprocess.run([a.luau,'-O2',str(path)],capture_output=True,text=True,timeout=120)
  witness=next((x for x in r.stderr.splitlines() if 'audit:' in x),'')
  good=r.returncode==0 and 'PASS RESOURCE' in r.stdout if name=='unmodified' else r.returncode!=0 and bool(witness)
  row={'case':name,'passed':good,'witness':witness,'results':[x for x in r.stdout.splitlines() if x.startswith('PASS MODEL') or x.startswith('PASS RESOURCE')]}
  rows.append(row);print(row,flush=True)
  if not good:print(r.stderr[-1000:],r.stdout[-1000:],flush=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
a.out.write_text(json.dumps({'source_sha256':sha(root/'RemoteGuardRoblox.lua'),'campaign_sha256':sha(__file__),'model_sha256':sha(root/'tests/model.luau'),'vm_sha256':sha(a.luau),'compiler_sha256':sha(a.compiler),'results':rows,'elapsed_seconds':time.monotonic()-start,'scope':'private invariant instrumentation in temporary copies only, full 512k model plus retirement/capacity stress and five deliberate negative controls; entry counts not actual Roblox memory measurements'},indent=2)+'\n')
raise SystemExit(int(not all(x['passed'] for x in rows)))
