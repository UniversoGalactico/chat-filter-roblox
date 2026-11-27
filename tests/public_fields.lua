-- Synthetic service and yielding-interleaving tests; no actual Roblox service calls.
local Pipeline
if type(dofile)=="function" then Pipeline=dofile("server/PublicFieldPipeline.lua")
else Pipeline=require("../server/PublicFieldPipeline") end
local assertions=0
local function expect(value,wanted,label)
    assertions=assertions+1
    assert(value==wanted,label..": wanted "..tostring(wanted)..", got "..tostring(value))
end
local time=0
local claims,beginCalls,broadcastCalls=0,0,0
local shared={}
local pauseClaim,pauseBegin,pauseBroadcast=false,false,false
local throwClaim,throwBegin,throwBroadcast=false,false,false
local output="Filtered label"
local function identity(p) return p and p.live and p.id or nil end
local function claim(id)
    claims=claims+1
    if pauseClaim then coroutine.yield("claim") end
    if throwClaim then error("private") end
    if shared[id] and shared[id]>time then return false end
    shared[id]=time+61
    return true
end
local function beginFilter(raw,id)
    beginCalls=beginCalls+1
    if pauseBegin then coroutine.yield("begin") end
    if throwBegin then error("private") end
    return {id=id}
end
local function broadcast(result)
    broadcastCalls=broadcastCalls+1
    if pauseBroadcast then coroutine.yield("broadcast") end
    if throwBroadcast then error("private") end
    return output
end
local deps={now=function()return time end,identity=identity,claim=claim,beginFilter=beginFilter,broadcast=broadcast}
local f1,f2=Pipeline.new(deps,2),Pipeline.new(deps,2)
local function player(id) return {id=id,live=true} end
local a,b,c=player(1),player(2),player(3)
local function check(f,p,text,wantValue,wantReason)
    local v,r=f(p,text)
    expect(v,wantValue,"filtered value")
    expect(r,wantReason,"reason")
end
check(f1,a,"name","Filtered label","allow")
check(f1,a,"name",nil,"rate_limit")
expect(claims,1,"local rate guard before network")
local rejoin=player(1)
check(f2,rejoin,"name",nil,"rate_limit")
expect(beginCalls,1,"global denial before filter")
time=61
check(f2,rejoin,"name","Filtered label","allow")
check(f1,a,"name",nil,"rate_limit")
for _, invalid in ipairs({{},"",string.rep("x",129),"name\nline",string.char(255),"   "}) do
    check(f1,b,invalid,nil,"invalid_text")
end
for _,cp in ipairs({0xA0,0x1680,0x2000,0x200A,0x200B,0x200C,0x200D,0x202F,0x205F,0x2060,0x3000,0xFEFF,0xFE0E,0xFE0F}) do
    check(f1,b,utf8.char(cp),nil,"invalid_text")
end
for _,cp in ipairs({0x85,0x9F,0x2028,0x2029,0x202E,0x2066}) do
    check(f1,b,"label"..utf8.char(cp),nil,"invalid_text")
end
check(f1,nil,"name",nil,"invalid_player")
check(f1,player(0),"name",nil,"invalid_player")
pauseBegin=true
local worker=coroutine.create(function() check(f1,b,"name",nil,"stale") end)
local ok,stage=coroutine.resume(worker)
expect(ok,true,"begin yielded")
expect(stage,"begin","begin phase")
check(f1,b,"name",nil,"busy")
check(f1,player(2),"name",nil,"busy")
b.live=false
pauseBegin=false
expect(coroutine.resume(worker),true,"stale begin returned")
expect(coroutine.status(worker),"dead","lease released")
pauseClaim=true
local raceA=coroutine.create(function() check(f1,c,"name","Filtered label","allow") end)
local raceB=coroutine.create(function() check(f2,player(3),"name",nil,"rate_limit") end)
expect(coroutine.resume(raceA),true,"race A paused")
expect(coroutine.resume(raceB),true,"race B paused")
pauseClaim=false
expect(coroutine.resume(raceA),true,"race A wins")
expect(coroutine.resume(raceB),true,"race B denied")
time=200
pauseBroadcast=true
local d,e,g=player(4),player(5),player(6)
local w1=coroutine.create(function()check(f1,d,"name",nil,"stale")end)
local w2=coroutine.create(function()check(f1,e,"name",nil,"stale")end)
expect(coroutine.resume(w1),true,"first in flight")
expect(coroutine.resume(w2),true,"second in flight")
check(f1,g,"name",nil,"capacity")
time=220
pauseBroadcast=false
expect(coroutine.resume(w1),true,"late first denied")
expect(coroutine.resume(w2),true,"late second denied")
check(f1,g,"name","Filtered label","allow")
throwClaim=true
check(f1,player(7),"name",nil,"service_error")
throwClaim=false
throwBegin=true
check(f1,player(8),"name",nil,"service_error")
throwBegin=false
throwBroadcast=true
check(f1,player(9),"name",nil,"service_error")
throwBroadcast=false
output=nil
check(f1,player(10),"name",nil,"filter_error")
output="officially returned label"
check(f1,player(11),"name",output,"allow")
output=utf8.char(0x200B)..utf8.char(0xA0)
check(f1,player(100),"name",nil,"filter_error")
output="Luna 🐱"
check(f1,player(101),"Luna 🐱",output,"allow")
output="José"
check(f1,player(102),"José",output,"allow")
output="日本語"
check(f1,player(103),"日本語",output,"allow")
output="Filtered label"
local before=claims
local optional=Pipeline.new(deps,1,function()return false end)
check(optional,player(12),"name",nil,"supplemental_denied")
expect(claims,before,"supplemental deny avoids network")
time=-1
check(f1,player(13),"name",nil,"invalid_clock")
time=300
check(f1,player(13),"name","Filtered label","allow")
expect(pcall(Pipeline.new,deps,0),false,"invalid concurrency")
expect(pcall(Pipeline.new,{now=deps.now},1),false,"missing dependency")
-- Probe malformed byte strings without invoking any service: validation may reject
-- or the supplemental policy may deny, but the API must not throw.
local noService=Pipeline.new(deps,1,function()return false end)
local rng=13
time=500
for i=1,1000 do
    local bytes={}
    for j=1,1+i%32 do
        rng=(rng*48271)%2147483647
        bytes[j]=string.char(rng%256)
    end
    local ok,value=pcall(noService,player(1000+i),table.concat(bytes))
    expect(ok,true,"malformed input no throw")
    expect(value,nil,"no unfiltered output")
end
print("PASS: "..assertions.." public field assertions")
