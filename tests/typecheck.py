import argparse,pathlib,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--analyzer',required=True);a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
 paths=[]
 for name in ('RemoteGuardRoblox.lua','RemoteGuardServer.lua'):
  s=(root/name).read_text();assert s.startswith('--!strict\n')
  # CLI lacks Roblox type declarations. Only these boundary globals are stubbed;
  # Studio's engine-aware analyzer remains a separate gate.
  stubs='type Instance = any\ntype Player = any\nlocal task: any = nil\n'
  if name=='RemoteGuardServer.lua':stubs+='local game: any = nil\nlocal script: any = nil\nlocal require: any = nil\n'
  f=pathlib.Path(d)/name;f.write_text('--!strict\n'+stubs+s.split('\n',1)[1]);paths.append(str(f))
 subprocess.run([a.analyzer,*paths],check=True)
