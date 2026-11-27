import argparse,pathlib,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument("--luau",required=True);p.add_argument("--optimization",default="2");a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
 f=pathlib.Path(d)/"test.luau"
 f.write_text("local RemoteGuard=(function()\n"+(r/"RemoteGuardRoblox.lua").read_text()+"\nend)()\n"+(r/"tests/regression.luau").read_text())
 subprocess.run([a.luau,"-O"+a.optimization,str(f)],check=True)
