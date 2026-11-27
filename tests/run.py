import argparse,pathlib,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--luau',required=True);p.add_argument('--optimization',default='2');p.add_argument('--source',type=pathlib.Path);p.add_argument('--suite-only',action='store_true');p.add_argument('--large',action='store_true');a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
 f=pathlib.Path(d)/'test.luau'
 f.write_text('local RemoteGuard=(function()\n'+(a.source or r/'RemoteGuardRoblox.lua').read_text()+'\nend)()\n'+(r/'tests/regression.luau').read_text()+('' if a.suite_only else '\n'+(r/'tests/model.luau').read_text()))
 if a.large:
  f.write_text(f.read_text()+'\n'+(r/'tests/large_model.luau').read_text())
 subprocess.run([a.luau,'-O'+a.optimization,str(f)],check=True)
