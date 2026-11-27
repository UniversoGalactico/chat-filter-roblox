#!/usr/bin/env python3
"""Alternating local Luau CLI measurements; no Roblox throughput claims."""
import argparse,hashlib,json,platform,statistics,subprocess,tempfile,time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--luau',required=True);p.add_argument('--source',type=Path,default=Path('RemoteGuardRoblox.lua'));p.add_argument('--baseline',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
body=r'''
local mode=MODE
local tick=0
local function config(args)
 return {Global={Limit=256,Window=1},Clock=function()return tick end,MaxSubjects=64,Actions={A={Quota={Limit=256,Window=1},Args=args}}}
end
local start,seconds,units,checksum
if mode=="primitive" then
 local g=RemoteGuard.new(config({{Type="number",Min=0,Max=100,Integer=true},{Type="string",Choices={"x","y"}}}))
 units=400000;checksum=0;start=os.clock()
 for i=1,units do tick+=1;if g:Check(1,"A",i%100,"x") then checksum+=1 end end
 seconds=os.clock()-start;assert(checksum==units)
elseif mode=="nested" then
 local args={{Type="record",Fields={x={Type="number",Min=0,Max=100},list={Type="array",MaxItems=8,Items={Type="string",MaxBytes=8}},flags={Type="map",Keys={Type="string",MaxBytes=4},Values={Type="boolean"},MaxItems=4}}}}
 local g=RemoteGuard.new(config(args));local value={x=1,list={"x","y","z"},flags={a=true,b=false}}
 units=150000;checksum=0;start=os.clock()
 for i=1,units do tick+=1;if g:Check(1,"A",value) then checksum+=1 end end
 seconds=os.clock()-start;assert(checksum==units)
elseif mode=="burst_full" or mode=="burst_partial" then
 local partial=mode=="burst_partial";local c=config({});c.Server={Limit=8192,Window=1};local g=RemoteGuard.new(c)
 units=80;seconds=0;checksum=0
 for i=1,units do
  tick=3*i
  for j=1,8192 do
   if partial and j==4097 then tick+=0.5 end
   assert(g:Check((j-1)%64+1,"A"))
  end
  tick=3*i+1;start=os.clock();local ok=g:Check(1,"A");seconds+=os.clock()-start;assert(ok);checksum+=1
  if partial then
   for j=2,4096 do assert(g:Check((j-1)%64+1,"A")) end
   local ok,code=g:Check(2,"A");assert(not ok and code=="SERVER_LIMIT")
  else
   for j=2,8192 do assert(g:Check((j-1)%64+1,"A")) end
   local ok,code=g:Check(2,"A");assert(not ok and code=="SERVER_LIMIT")
  end
 end
else error("unknown mode") end
print("RESULT",mode,seconds,units,checksum)
'''
rows=[];started=time.monotonic()
with tempfile.TemporaryDirectory() as td:
 path=Path(td)/'bench.luau'
 for mode in ('primitive','nested','burst_full','burst_partial'):
  for trial in range(5):
   for label,src in ([('before',a.baseline),('after',a.source)] if trial%2==0 else [('after',a.source),('before',a.baseline)]):
    path.write_text('local RemoteGuard=(function()\n'+src.read_text()+'\nend)()\n'+body.replace('MODE','"'+mode+'"'))
    r=subprocess.run([a.luau,'-O2',str(path)],capture_output=True,text=True,timeout=120)
    if r.returncode:raise RuntimeError(r.stderr+r.stdout)
    row=r.stdout.strip().split('\t');assert row[0]=='RESULT' and row[1]==mode
    rows.append({'mode':mode,'version':label,'trial':trial,'seconds':float(row[2]),'units':int(row[3]),'checksum':int(row[4])})
  print(mode,{label:statistics.median(x['seconds'] for x in rows if x['mode']==mode and x['version']==label) for label in ('before','after')},flush=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
report={'source_sha256':sha(a.source),'baseline_sha256':sha(a.baseline),'vm_sha256':sha(a.luau),'campaign_sha256':sha(__file__),'platform':platform.platform(),'rows':rows,'elapsed_seconds':time.monotonic()-started,'scope':'five alternating local Luau O2 trials, injected clock; burst measurement isolates first admission after expiration; no network, Roblox engine or server capacity claim'}
a.out.write_text(json.dumps(report,indent=2)+'\n')
