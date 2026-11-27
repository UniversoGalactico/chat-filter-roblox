#!/usr/bin/env python3
"""Check recorded source provenance and reported finite campaign counts.

This verifies consistency, not authenticity or correctness of recorded results.
Re-run individual campaigns for independent confirmation.
"""
import hashlib,json,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];e=root/'tests/evidence';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
core=sha(root/'RemoteGuardRoblox.lua');adapter=sha(root/'RemoteGuardServer.lua')
def read(name):return json.loads((e/name).read_text())
def patched(name):
 with tempfile.TemporaryDirectory() as d:
  p=Path(d)/'source.lua';p.write_bytes((root/'RemoteGuardRoblox.lua').read_bytes())
  subprocess.run(['patch','--batch','--silent',str(p),str(e/name)],check=True)
  return sha(p)
num=0
for seed in (32071,32072):
 d=read(f'numeric_{seed}.json');assert d['source_sha256']==core and d['campaign_sha256']==sha(root/'tests/luauproof_attack.py')
 assert [r['optimization'] for r in d['runs']]==[0,1,2]
 for run in d['runs']:
  for c in run['counts'].values():assert c['differences']==0;num+=c['checks']
assert num==982275
negative=read('rounded_negative_32071.json');assert negative['source_sha256']==patched('rounded_negative.diff')
assert sum(c['differences'] for r in negative['runs'] for c in r['counts'].values())==41922
schemas=0
for seed in (38101,38102):
 d=read(f'schema_{seed}.json');assert d['source_sha256']==core and d['campaign_sha256']==sha(root/'tests/schema_fuzz.py')
 for run in d['runs']:assert run['differences']==0;schemas+=run['cases']
assert schemas==307200
ex=read('exhaustive_o2.json');assert ex['source_sha256']==core and ex['campaign_sha256']==sha(root/'tests/exhaustive.py')
assert ex['total_states']==376433 and ex['concrete_commands']==2674724 and ex['differences']==0
mut=read('mutations.json');assert mut['core_sha256']==core and mut['adapter_sha256']==adapter and mut['campaign_sha256']==sha(root/'tests/mutation.py')
assert mut['total']==mut['detected']==39 and all(m['detected'] for m in mut['mutants'])
resource=read('resource_audit.json');assert resource['source_sha256']==core and resource['campaign_sha256']==sha(root/'tests/resource_audit.py') and resource['model_sha256']==sha(root/'tests/model.luau')
assert len(resource['results'])==6 and all(x['passed'] for x in resource['results'])
extended=read('extended_models.json');assert all(sha(root/f)==h for f,h in extended['sha256'].items())
assert len(extended['runs'])==6
for run in extended['runs']:
 if run['runner']=='run.py':
  assert 'PASS LARGE MODEL\t1000000' in run['output'] and 'PASS MODEL\t512000' in run['output'] and 'PASS 29 suites' in run['output']
 else:assert 'PASS ADAPTER MODEL\t160000' in run['output'] and 'PASS ADAPTER 8 suites' in run['output']
bench=read('benchmark.json');assert bench['source_sha256']==core and bench['baseline_sha256']==patched('pre_ring.diff') and bench['campaign_sha256']==sha(root/'tests/benchmark.py')
assert len(bench['rows'])==40
print('PASS recorded evidence consistency',num,schemas,ex['total_states'],ex['concrete_commands'])
