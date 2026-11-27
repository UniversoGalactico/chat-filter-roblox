"""White-box verification in a TEMPORARY copy of DeliveryGate.

No debug API is shipped. The production source is copied, and a wrapper
checks every reachable sender state after Admit/Forget/Clear. The independent
gate campaign then exercises the instrumented module. Two deliberate corruptions
verify that the checker itself rejects incorrect resource bookkeeping.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
ANCHOR="    return gate\nend\nreturn DeliveryGate"
WRAPPER=r'''
    local function check(condition,label)
        assert(condition,"INVARIANT: "..label)
    end
    local function inspect(state)
        check(state.count>=0 and state.count<=capacity and state.count%1==0,"ring count")
        check(state.head>=1 and state.head<=capacity and state.head%1==0,"ring head")
        check(state.last>=0 and state.last<=MAX_CLOCK,"clock")
        local expectedSlots,seen={},{}
        local previous=-math.huge
        for offset=0,state.count-1 do
            -- Deliberately use the original modulo formulation, not ringSlot().
            local slot=(state.head-1+offset)%capacity+1
            local row=state.order[slot]
            check(type(row)=="table","missing ring entry")
            check(not seen[row],"duplicate entry")
            check(row.expires>=previous,"non-FIFO expiry")
            check(row.expires>=0 and row.expires<=MAX_CLOCK+ttl,"expiry bound")
            check(row.reason=="allow" or row.reason=="rate_limit","cached reason")
            check(row.allow==(row.reason=="allow"),"cached decision contract")
            local bucket=state.scopes[row.scope]
            check(bucket~=nil and rawequal(bucket.ids[row.id],row),"ring to map identity")
            expectedSlots[slot]=true
            seen[row]=true
            previous=row.expires
        end
        local ringCount=0
        for slot,row in pairs(state.order) do
            check(expectedSlots[slot] and seen[row],"stale or foreign ring slot")
            ringCount=ringCount+1
        end
        check(ringCount==state.count,"ring cardinality")
        local mapCount=0
        for scope,bucket in pairs(state.scopes) do
            local n=0
            for id,row in pairs(bucket.ids) do
                check(seen[row] and rawequal(row.scope,scope) and row.id==id,"map to ring identity")
                n=n+1
            end
            check(n>0 and n==bucket.count,"bucket count")
            mapCount=mapCount+n
        end
        check(mapCount==state.count,"map cardinality")
        check(#state.attempts<=limit,"accepted window size")
        previous=-math.huge
        for _,t in ipairs(state.attempts) do
            check(t>=previous and t<=state.last,"accepted timestamps")
            previous=t
        end
        if state.overflowUntil then
            check(state.overflowUntil>=0 and state.overflowUntil<=MAX_CLOCK+ttl,"quarantine bound")
        end
    end
    local function inspectAll()
        for _,state in pairs(senders) do inspect(state) end
    end
    local admit,forget,clear=gate.Admit,gate.Forget,gate.Clear
    function gate:Admit(...)
        local allowed,reason=admit(self,...)
        inspectAll()
        return allowed,reason
    end
    function gate:Forget(sender)
        forget(self,sender)
        if validSender(sender) then check(senders[sender]==nil,"forgotten state") end
        inspectAll()
    end
    function gate:Clear()
        clear(self)
        check(next(senders)==nil,"cleared state")
    end
'''
MUTANTS=[
    ("bucket count", "bucket.count = bucket.count + 1", "bucket.count = bucket.count"),
    ("stale ring slot", "state.order[state.head] = nil", "-- intentionally retained slot"),
]


def execute(vm, source, campaign, expected_failure=None):
    if source.count(ANCHOR)!=1:
        raise ValueError("instrumentation anchor changed")
    instrumented=source.replace(ANCHOR,WRAPPER+"\n"+ANCHOR)
    with tempfile.TemporaryDirectory(prefix="chatfilter-invariants-") as td:
        root=Path(td)
        (root/"server").mkdir()
        (root/"tests").mkdir()
        (root/"server/DeliveryGate.lua").write_text(instrumented,encoding="utf-8")
        (root/"tests/gate_campaign.lua").write_text(campaign,encoding="utf-8")
        p=subprocess.run([str(vm),"tests/gate_campaign.lua"],cwd=root,capture_output=True,text=True,timeout=120)
        if expected_failure is not None:
            if not p.returncode or "INVARIANT: "+expected_failure not in p.stderr:
                raise RuntimeError("checker failed its negative control: "+expected_failure+"\n"+p.stdout+"\n"+p.stderr)
            print("PASS: invariant negative control",expected_failure)
        else:
            if p.returncode:
                raise RuntimeError(p.stdout+"\n"+p.stderr)
            print(p.stdout,end="")
            print("PASS: internal ring, bucket, cache and window invariants")


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("vm",type=Path)
    parser.add_argument("--full",action="store_true")
    args=parser.parse_args()
    source=(ROOT/"server/DeliveryGate.lua").read_text(encoding="utf-8")
    campaign=(ROOT/"tests/gate_campaign.lua").read_text(encoding="utf-8")
    if not args.full:
        campaign=re.sub(r"local SCENARIOS = \d+", "local SCENARIOS = 12",campaign,count=1)
        campaign=re.sub(r"local STEPS = \d+", "local STEPS = 2500",campaign,count=1)
    execute(args.vm.resolve(),source,campaign)
    for expected,before,after in MUTANTS:
        if source.count(before)!=1:
            raise ValueError("negative control anchor changed")
        execute(args.vm.resolve(),source.replace(before,after,1),campaign,expected)


if __name__=="__main__":
    main()
