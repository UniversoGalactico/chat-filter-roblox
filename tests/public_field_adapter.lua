-- Actual Roblox adapter with synthetic MemoryStore and TextService.
local Pipeline=dofile("server/PublicFieldPipeline.lua")
local Policy=dofile("server/TextPolicy.lua")
local Config=dofile("server/ChatConfiguration.lua")
local Data=dofile("server/ProfanityData.lua")
local time=0
local pauseFilter, failSchedule=false,false
local workers={}
local function spawn(fn)
    if failSchedule then error("private scheduler error") end
    local worker=coroutine.create(fn)
    workers[#workers+1]=worker
    assert(coroutine.resume(worker))
    return worker
end
local players={lookup={}}
local remove
players.PlayerRemoving={Connect=function(_,cb)remove=cb return {} end}
function players:GetPlayerByUserId(id)return self.lookup[id] end
local function player(id)
    local p={UserId=id,Parent=players,kind="Instance"}
    function p:IsA(name)return name=="Player" end
    players.lookup[id]=p
    return p
end
local map,stored={},{}
local mode="normal"
local updateCalls,filterCalls,serial=0,0,0
function map:UpdateAsync(key,transform,ttl)
    assert(key:match("^U_%d+$") and ttl==61)
    updateCalls=updateCalls+1
    if mode=="error" then error("private") end
    if mode=="contention" then
        assert(type(transform(nil))=="string")
        assert(transform("foreign-token")==nil)
        return nil
    end
    local old=stored[key]
    if old and old.expires<=time then stored[key]=nil old=nil end
    local value=transform(old and old.value or nil)
    if value~=nil then stored[key]={value=value,expires=time+ttl} end
    if mode=="unexpected_old" then return "foreign-token" end
    return value
end
local services={
    Players=players,
    MemoryStoreService={GetHashMap=function(_,name)assert(name=="ChatFilter_PublicFieldCooldown_v1")return map end},
    HttpService={GenerateGUID=function(_,braces)assert(braces==false)serial=serial+1 return "token-"..serial end},
    TextService={FilterStringAsync=function(_,raw,id)
        filterCalls=filterCalls+1
        assert(type(raw)=="string" and type(id)=="number")
        if pauseFilter then coroutine.yield("platform filter") end
        return {GetNonChatStringForBroadcastAsync=function()return "Safe" end}
    end},
}
local modules={PublicFieldPipeline=Pipeline,TextPolicy=Policy,ChatConfiguration=Config,ProfanityData=Data}
local env=setmetatable({
    game={GetService=function(_,name)return assert(services[name])end},
    script={Parent={PublicFieldPipeline="PublicFieldPipeline",TextPolicy="TextPolicy",ChatConfiguration="ChatConfiguration",ProfanityData="ProfanityData"}},
    require=function(name)return assert(modules[name])end,
    typeof=function(value)return type(value)=="table" and value.kind or type(value)end,
    os={clock=function()return time end},
    task={spawn=spawn},
},{__index=_G})
local service=assert(loadfile("server/PublicFieldService.lua","t",env))()
local function request(p,raw)
    local called,value,reason=0,nil,nil
    local scheduled,why=service.Request(p,raw,function(v,r)
        called=called+1 value,reason=v,r
    end)
    if scheduled then assert(called==1) else assert(called==0) end
    return value,reason or why
end
local a=player(10)
assert(request(a,"pet name")=="Safe")
assert(request(a,"another")==nil and updateCalls==1)
time=61
assert(request(a,"name")=="Safe" and filterCalls==2)
mode="contention"
assert(request(player(11),"pet")==nil and filterCalls==2)
mode="unexpected_old"
assert(request(player(12),"pet")==nil and filterCalls==2)
mode="error"
assert(request(player(13),"pet")==nil and filterCalls==2)
mode="normal"
local gone=player(14)
remove(gone)
assert(request(gone,"pet")==nil and filterCalls==2)
assert(request({},"pet")==nil and filterCalls==2)
assert(request(player(15),"IDIOTA")==nil and filterCalls==2)
assert(not service.Request(player(16),"pet",nil))
failSchedule=true
local failed=player(17)
local scheduled,why=service.Request(failed,"pet",function() error("must not run") end)
assert(not scheduled and why=="schedule_error")
failSchedule=false
assert(request(failed,"pet")=="Safe")
-- Simulate the requester's task being cancelled while a separate platform worker is suspended.
pauseFilter=true
local p=player(18)
local callbacks=0
local caller=coroutine.create(function()
    assert(service.Request(p,"pet",function(value,reason)
        assert(value=="Safe" and reason=="allow")
        callbacks=callbacks+1
    end))
    coroutine.yield("controller waiting")
end)
assert(coroutine.resume(caller))
local worker=workers[#workers]
assert(coroutine.status(worker)=="suspended" and worker~=caller)
assert(coroutine.close(caller))
assert(callbacks==0)
pauseFilter=false
assert(coroutine.resume(worker))
assert(callbacks==1 and coroutine.status(worker)=="dead")
time=122
assert(request(p,"new pet")=="Safe","cancelled caller must not strand lease")
-- A trusted callback error occurs after the pipeline has released its slot.
local q=player(19)
assert(service.Request(q,"pet",function() error("private callback failure") end))
time=183
assert(request(q,"new pet")=="Safe")
print("PASS: public field adapter atomic claim, identity, and owned worker cancellation")
