import argparse,pathlib,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--luau',required=True);p.add_argument('--optimization',default='2');p.add_argument('--source',type=pathlib.Path);a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1]
source='local RemoteGuard=(function()\n'+(r/'RemoteGuardRoblox.lua').read_text()+'\nend)()\n'+(r/'tests/adapter_prelude.luau').read_text()+'\n'
source+='local RemoteGuardServer=(function()\nlocal game=fakeGame\nlocal typeof=fakeTypeof\nlocal script={Parent={RemoteGuard={}}}\nlocal require=function() return RemoteGuard end\n'+(a.source or r/'RemoteGuardServer.lua').read_text()+'\nend)()\n'+(r/'tests/adapter.luau').read_text()
with tempfile.TemporaryDirectory() as d:
 f=pathlib.Path(d)/'test.luau';f.write_text(source);subprocess.run([a.luau,'-O'+a.optimization,str(f)],check=True)
