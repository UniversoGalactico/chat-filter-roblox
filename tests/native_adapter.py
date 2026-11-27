"""Run the same trusted mock suites in Luau CLI using in-memory source loading.

Luau CLI does not implement filesystem loadfile/dofile. The shim exposes only
the explicitly reviewed project files, not arbitrary paths or real Roblox APIs.
This tests the adapter under Luau semantics; it is not an engine simulation.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    "server/ChatFilter.lua", "server/DeliveryGate.lua", "server/ContextPolicy.lua",
    "server/TextPolicy.lua", "server/ChatConfiguration.lua", "server/ProfanityData.lua",
    "tests/adapter.lua", "tests/studio_mock.lua", "tests/studio/Smoke.server.lua",
]


def literal(source):
    for n in range(1, 32):
        fence = "=" * n
        if "]" + fence + "]" not in source:
            return "[" + fence + "[" + source + "]" + fence + "]"
    raise ValueError("cannot delimit source")


def build():
    # Prepend a newline so the long-string initial newline rule cannot remove
    # the first actual byte when a file starts with one.
    mapping = "\n".join(f'    ["{p}"]={literal(chr(10)+(ROOT/p).read_text(encoding="utf-8"))},' for p in SOURCES)
    return """local sources = {
""" + mapping + """
}
local original = getfenv(0)
local env = setmetatable({}, {__index=original})
env._G = env
function env.loadfile(path, mode, custom)
    local source = sources[path]
    if not source then return nil,"unreviewed path" end
    local chunk, err = loadstring(source,"@"..path)
    if chunk then setfenv(chunk,custom or env) end
    return chunk, err
end
function env.dofile(path)
    return assert(env.loadfile(path))()
end
for _,path in ipairs({"tests/adapter.lua","tests/studio_mock.lua"}) do
    env.dofile(path)
end
"""


def main():
    p=argparse.ArgumentParser()
    p.add_argument("vm",type=Path)
    p.add_argument("--optimization",type=int,choices=(0,1,2),default=1)
    args=p.parse_args()
    with tempfile.TemporaryDirectory(prefix="chatfilter-native-adapter-") as tmp:
        runner=Path(tmp)/"runner.luau"
        runner.write_text(build(),encoding="utf-8")
        result=subprocess.run([str(args.vm.resolve()),f"-O{args.optimization}",str(runner)],cwd=ROOT,timeout=120)
        if result.returncode:
            raise SystemExit(result.returncode)
    print(f"PASS: Luau O{args.optimization} adapter and Studio mock")


if __name__=="__main__":
    main()
