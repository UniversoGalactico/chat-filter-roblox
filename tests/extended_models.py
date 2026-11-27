#!/usr/bin/env python3
"""Record independent large quota and adapter lifecycle campaigns."""
import argparse,hashlib,json,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--luau',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();start=time.monotonic();runs=[]
for opt in range(3):
 for runner,flag,marker,n in [('run.py','--large','PASS LARGE MODEL',1000000),('run_adapter.py','--model','PASS ADAPTER MODEL',160000)]:
  proc=subprocess.run(['python3',str(r/'tests'/runner),'--luau',str(a.luau.resolve()),'--optimization',str(opt),flag],capture_output=True,text=True,check=True)
  lines=proc.stdout.splitlines();print('\n'.join(lines),flush=True);assert any(s.split('\t')[0]==marker and int(s.split('\t')[1])==n for s in lines), (marker,lines[-10:])
  runs.append({'optimization':opt,'runner':runner,'additional_operations':n,'output':lines})
files=['RemoteGuardRoblox.lua','RemoteGuardServer.lua','tests/run.py','tests/run_adapter.py','tests/regression.luau','tests/model.luau','tests/large_model.luau','tests/adapter.luau','tests/adapter_prelude.luau','tests/adapter_model.luau','tests/extended_models.py']
a.out.write_text(json.dumps({'sha256':{f:sha(r/f) for f in files},'vm_sha256':sha(a.luau),'runs':runs,'elapsed_seconds':time.monotonic()-start,'scope':'Finite list-model quota and coroutine/service-double lifecycle comparisons; repeated seeds across optimizations; not real Roblox networking.'},indent=2)+'\n')
