#!/usr/bin/env python3
"""Bounded reachable-state enumeration. Independent immutable integer-age model.
Concrete replay tests each outgoing command of every reached abstract state.
"""
import argparse, collections, hashlib, itertools, json, subprocess, tempfile, time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--luau',required=True);p.add_argument('--source',type=Path,default=Path('RemoteGuardRoblox.lua'));p.add_argument('--depth',type=int,default=7);p.add_argument('--plans',type=int,default=8);p.add_argument('--optimization',default='2');p.add_argument('--out',type=Path,required=True);p.add_argument('--enumerate-only',action='store_true');a=p.parse_args();start=time.monotonic()
assert 0<=a.depth<=9 and 1<=a.plans<=32
# A/B valid Check, C/D valid Begin, E/F invalid Check, G/H Forget,
# I/J advance by 1/2, K Sweep, L release latest, M release previous.
commands='ABCDEFGHIJKLM'
# Configuration (per-subject global limit/window, fast and slow limit/window,
# shared server limit/window, max subjects). One in-flight request per guard.
plans=[(2,2,1,3,1,1,2,2,2),(1,3,2,1,1,2,1,2,2),(3,1,1,2,2,3,2,1,2),(2,3,2,3,2,3,3,3,1),
       (1,1,1,1,1,1,1,1,1),(3,3,1,1,1,1,3,2,2),(2,1,2,2,1,3,1,3,2),(2,2,2,1,2,3,3,1,1)]
for i in range(24):
 plans.append((1+i%3,1+(i//3)%3,1+(i//5)%3,1+(i//2)%3,1+(i//7)%2,1+(i//4)%3,1+(i//6)%3,1+(i//8)%3,1+i%2))
# Subject = (global ages, fast ages, slow ages, last charged age),
# Permit = (subject index, current generation is live) or None.
empty=((),(None,None),None)
def step(s,c,plan):
 gl,gw,fl,fw,sl,sw,cl,cw,cap=plan;maximum=max(gw,fw,sw)
 shared,subjects,permit=s;ss=list(subjects)
 if c in 'IJ':
  dt=1 if c=='I' else 2
  def age(seq,window):return tuple(x+dt for x in seq if x+dt<window)
  shared=age(shared,cw)
  ss=[None if x is None else (age(x[0],gw),age(x[1],fw),age(x[2],sw),min(maximum,x[3]+dt)) for x in ss]
  return (shared,tuple(ss),permit),'T'
 if c=='K':
  removed=0
  for i,x in enumerate(ss):
   if x is not None and x[3]>=maximum and permit!=(i,True):ss[i]=None;removed+=1
  return (shared,tuple(ss),permit),str(removed)
 if c in 'LM':
  if c=='L' and permit is not None:return (shared,tuple(ss),None),'Y'
  return s,'N'
 if c in 'GH':
  i=ord(c)-ord('G')
  if ss[i] is None:return s,'N'
  ss[i]=None
  if permit==(i,True):permit=(i,False)
  return (shared,tuple(ss),permit),'Y'
 i=(ord(c)-ord('A'))%2;slow=c in 'CD';bad=c in 'EF'
 x=ss[i]
 if x is None:
  if sum(v is not None for v in ss)>=cap:return s,'P'
  x=((),(),(),0);ss[i]=x
 # Ages already expired by advance. Admit and charge one layer at a time.
 if len(x[0])>=gl:return (shared,tuple(ss),permit),'G'
 x=(x[0]+(0,),x[1],x[2],0);ss[i]=x
 if len(x[2 if slow else 1])>=(sl if slow else fl):return (shared,tuple(ss),permit),'A'
 x=(x[0],x[1] if slow else x[1]+(0,),x[2]+(0,) if slow else x[2],0);ss[i]=x
 if len(shared)>=cl:return (shared,tuple(ss),permit),'S'
 shared=shared+(0,)
 if slow and permit is not None:return (shared,tuple(ss),permit),'F'
 if bad:return (shared,tuple(ss),permit),'V'
 if slow:permit=(i,True)
 return (shared,tuple(ss),permit),'Y'
def signature(s,code):
 shared,subjects,permit=s
 return code+str(sum(x is not None for x in subjects))+('0' if permit is None else '1')+('1' if permit is not None and permit[1] else '0')
header=r'''
local checks,bad=0,0
local function run(plan,path,expected,id)
 local gl,gw,fl,fw,sl,sw,cl,cw,cap=table.unpack(plan)
 local now=0;local g=RemoteGuard.new({Global={Limit=gl,Window=gw},Server={Limit=cl,Window=cw},MaxSubjects=cap,MaxInFlight=1,Clock=function()return now end,Actions={Fast={Quota={Limit=fl,Window=fw},Args={{Type="number",Min=1,Max=1}}},Slow={Quota={Limit=sl,Window=sw},Args={},MaxInFlight=1}}})
 local latest,previous
 local code="T"
 local reasons={CAPACITY="P",GLOBAL_LIMIT="G",ACTION_LIMIT="A",SERVER_LIMIT="S",SERVER_IN_FLIGHT="F",INVALID_ARGUMENT="V"}
 for index=1,#path do
  local c=path:sub(index,index);local success,why
  if c=="I" or c=="J" then now+=(if c=="I" then 1 else 2);code="T"
  elseif c=="K" then code=tostring(g:Sweep())
  elseif c=="L" or c=="M" then code=if g:Release((if c=="L" then latest else previous) or {}) then "Y" else "N"
  elseif c=="G" or c=="H" then code=if g:Forget(if c=="G" then 1 else 2) then "Y" else "N"
  elseif c=="C" or c=="D" then
   local token;token,why=g:Begin(if c=="C" then 1 else 2,"Slow")
   if token then previous,latest=latest,token;code="Y" else code=reasons[why] or "?" end
  else
   success,why=g:Check(if c=="A" or c=="E" then 1 else 2,"Fast",if c=="E" or c=="F" then 0 else 1)
   code=if success then "Y" else reasons[why] or "?"
  end
 end
 local st=g:GetStats();local actual=code..st.Subjects..st.InFlight..(if g:IsCurrent(latest) then "1" else "0")
 checks+=1
 if actual~=expected then bad+=1;if bad<=10 then print("DIFF",id,path,expected,actual) end end
end
'''
source='local RemoteGuard=(function()\n'+a.source.read_text()+'\nend)()\n'+header
summaries=[];total=0;diff=0;totalstates=0
with tempfile.TemporaryDirectory() as td:
 path=Path(td)/'replay.luau'
 for index,plan in enumerate(plans[:a.plans]):
  seen={empty:''};queue=collections.deque([empty]);rows=[];count=0;bad=0;witness=[];by_depth=collections.Counter()
  plan_literal='{'+','.join(map(str,plan))+'}'
  def flush():
   global count,bad
   if not rows or a.enumerate_only:rows.clear();return
   path.write_text(source+'\n'+'\n'.join(rows)+'\nprint("TOTAL",checks,bad)\n')
   r=subprocess.run([a.luau,'-O'+a.optimization,str(path)],capture_output=True,text=True,timeout=120)
   if r.returncode:raise RuntimeError(r.stderr+r.stdout[-1000:])
   for line in r.stdout.splitlines():
    row=line.split('\t')
    if row[0]=='TOTAL':count+=int(row[1]);bad+=int(row[2])
    elif row[0]=='DIFF' and len(witness)<10:witness.append(row[1:])
   rows.clear()
  expanded=0
  while queue:
   state=queue.popleft();prefix=seen[state];by_depth[len(prefix)]+=1
   if len(prefix)>=a.depth:continue
   expanded+=1
   for c in commands:
    new,code=step(state,c,plan);p2=prefix+c
    if new not in seen:seen[new]=p2;queue.append(new)
    if not a.enumerate_only:
     rows.append(f'run({plan_literal},"{p2}","{signature(new,code)}",{index})')
     if len(rows)>=5000:flush()
  flush();assert a.enumerate_only or count==expanded*len(commands),(count,expanded)
  summaries.append({'plan':plan,'states':len(seen),'expanded':expanded,'commands':expanded*len(commands),'replayed':count,'differences':bad,'witnesses':witness,'states_by_depth':dict(by_depth)})
  total+=count;diff+=bad;totalstates+=len(seen);print(index,'states',len(seen),'expanded',expanded,'commands',expanded*len(commands),'diff',bad,flush=True)
  if bad:break
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps({'source_sha256':sha(a.source),'campaign_sha256':sha(__file__),'vm_sha256':sha(a.luau),'optimization':int(a.optimization),'depth':a.depth,'plans':summaries,'enumeration_only':a.enumerate_only,'total_states':totalstates,'concrete_commands':total,'differences':diff,'elapsed_seconds':time.monotonic()-start,'scope':'finite reachable integer-time states, canonical age model; representative-path concrete replay; not formal or production verification'},indent=2)+'\n')
raise SystemExit(int(diff>0))
