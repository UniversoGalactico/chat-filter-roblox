#!/usr/bin/env python3
"""Selected semantic regressions. Compile every mutant; no syntax/timeout credit."""
import argparse,hashlib,json,subprocess,sys,tempfile,time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--luau',required=True);p.add_argument('--compiler',required=True);p.add_argument('--out',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[1];start=time.monotonic()
core=root/'RemoteGuardRoblox.lua';adapter=root/'RemoteGuardServer.lua'
mutants=[
 ('rounded_early_expiry','core','return math.max(0,-residual)','return 0'),
 ('ring_drop_extra','core','b.Count-=low','b.Count-=low+1'),
 ('ring_bad_head','core','b.Head=(b.Head+low-1)%q.Limit+1','b.Head=(b.Head+low)%q.Limit+1'),
 ('ring_retains_expired','core','b.Head,b.Count=1,0','b.Head=1'),
 ('no_server_quota','core','if serverWait>0 then return false,"SERVER_LIMIT",serverWait,nil end','if false then return false,"SERVER_LIMIT",serverWait,nil end'),
 ('no_subject_charge','core','charge(s.Global,global,now);s.Last=now','s.Last=now'),
 ('no_action_charge','core','charge(b,a.Quota,now)','-- no action charge'),
 ('ignore_arity','core','if n>#a.Args then return false,"ARG_COUNT",nil,nil end','if false then return false,"ARG_COUNT",nil,nil end'),
 ('accept_nonfinite','core','return finite(v) and (not r.Integer','return type(v)=="number" and (not r.Integer'),
 ('accept_invalid_utf8','core','and utf8.len(v)~=nil and (r.Choices','and (r.Choices'),
 ('accept_sparse_array','core','if count~=largest then return false end','if false then return false end'),
 ('ignore_extra_record_fields','core','or children[k]==nil then return false end','then return false end'),
 ('ignore_node_budget','core','if budget.Nodes>512 then return false end','if false then return false end'),
 ('ignore_string_byte_budget','core','return budget.Bytes<=16384 and utf8.len(v)','return utf8.len(v)'),
 ('alias_choices','core','out.Choices=choices','out.Choices=r.Choices'),
 ('sweep_short_window','core','remaining(now,s.Last,maxWindow)==0','remaining(now,s.Last,global.Window)==0'),
 ('sweep_active','core','if s.InFlight==0 and remaining','if remaining'),
 ('forget_frees_flight','core','s.Live=false;s.Global=bucket();s.Actions={};subjects[subject]=nil;count-=1','inFlight-=s.InFlight;s.Live=false;s.Global=bucket();s.Actions={};subjects[subject]=nil;count-=1'),
 ('stale_lease_current','core','return lease~=nil and lease.State.Live','return lease~=nil'),
 ('check_bypasses_permit','core','if acquire~=(a.MaxInFlight~=nil) then','if acquire and a.MaxInFlight==nil then'),
 ('no_permit_counters','core','inFlight+=1;s.InFlight+=1;','s.InFlight+=1;'),
 ('truthy_authorization','core','if value~=true then return false,"UNAUTHORIZED"','if not value then return false,"UNAUTHORIZED"'),
 ('no_server_flight_limit','core','if inFlight>=flightLimit then','if false then'),
 ('no_subject_flight_limit','core','if s.InFlight>=subjectLimit then','if false then'),
 ('no_action_flight_limit','core','if (s.Pending[action] or 0)>=(a.MaxInFlight :: number) then','if false then'),
 ('no_buffer_bound','core','return length<=(r.MaxBytes :: number) and budget.Bytes<=16384','return budget.Bytes<=16384'),
 ('no_map_key_validation','core','or not validArg(k,r.Keys :: Argument,budget)',''),
 ('reset_shared_quota_on_forget','core','s.Live=false;s.Global=bucket();s.Actions={};subjects[subject]=nil;count-=1','serverBucket=bucket();s.Live=false;s.Global=bucket();s.Actions={};subjects[subject]=nil;count-=1'),
 ('stats_alias','core','local result=table.clone(stats);','local result=stats;'),
 ('clock_regression_ignored','core','if hasClock and now<last then','if false then'),
 ('schema_budget_ignored','core','budget[1]<=4096 and plain(r)','plain(r)'),
 ('adapter_identity_skipped','adapter','and Players:GetPlayerByUserId(player.UserId)==player',''),
 ('adapter_departed_skipped','adapter','and not departed[player]',''),
 ('adapter_stale_result_allowed','adapter','if not current then bump("StaleCompletions");return false,"DENIED" end','if false then bump("StaleCompletions");return false,"DENIED" end'),
 ('adapter_lease_leak','adapter','   guard:Release(token)\n   if not results[1]','   if not results[1]'),
 ('adapter_reap_suspended','adapter','coroutine.status(record.Thread)=="dead" and guard:Release(token)','guard:Release(token)'),
 ('adapter_raw_error','adapter','if not results[1] then bump("HandlerErrors");return false,"HANDLER_ERROR" end','if not results[1] then bump("HandlerErrors");return false,results[2] end'),
 ('adapter_disconnect_leak','adapter','active=false;removing:Disconnect();pending={}','active=false;pending={}'),
 ('adapter_drop_extra_args','adapter','guard:Check(player,action,...)','guard:Check(player,action,(...))'),
]
rows=[]
with tempfile.TemporaryDirectory() as td:
 for name,kind,old,new in mutants:
  source=core if kind=='core' else adapter;s=source.read_text();assert s.count(old)==1,(name,s.count(old));f=Path(td)/source.name;f.write_text(s.replace(old,new,1))
  comp=subprocess.run([a.compiler,str(f)],capture_output=True,timeout=15);assert comp.returncode==0,(name,comp.stderr.decode()[:300])
  cmd=[sys.executable,str(root/'tests'/('run.py' if kind=='core' else 'run_adapter.py')),'--luau',a.luau,'--source',str(f),'--optimization','2']
  if kind=='core':cmd.append('--suite-only')
  r=subprocess.run(cmd,capture_output=True,text=True,timeout=30);error_lines=[line for line in (r.stderr+'\n'+r.stdout).splitlines() if ' ~= ' in line or 'attempt to ' in line or 'assertion failed' in line or 'invalid argument' in line]
  detected=r.returncode!=0 and bool(error_lines)
  rows.append({'name':name,'module':kind,'detected':detected,'witness':error_lines[0][:250] if error_lines else ''});print(name,detected,rows[-1]['witness'],flush=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
report={'core_sha256':sha(core),'adapter_sha256':sha(adapter),'campaign_sha256':sha(__file__),'compiler_sha256':sha(a.compiler),'vm_sha256':sha(a.luau),'mutants':rows,'detected':sum(x['detected'] for x in rows),'total':len(rows),'elapsed_seconds':time.monotonic()-start,'scope':'selected deliberately changed semantic operations; compiled every mutant; no syntax failure or timeout counted; not a universal mutation score'}
if a.out:a.out.write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(int(any(not x['detected'] for x in rows)))
