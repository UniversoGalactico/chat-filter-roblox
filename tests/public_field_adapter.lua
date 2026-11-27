-- Actual Roblox adapter with synthetic MemoryStore and TextService.
local Pipeline=dofile("server/PublicFieldPipeline.lua")
local Policy=dofile("server/TextPolicy.lua")
local Config=dofile("server/ChatConfiguration.lua")
local Data=dofile("server/ProfanityData.lua")
local time=0
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
    local value=transform(stored[key])
    if value~=nil then stored[key]=value end
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
},{__index=_G})
local service=assert(loadfile("server/PublicFieldService.lua","t",env))()
local a=player(10)
assert(service.FilterAsync(a,"pet name")=="Safe")
assert(service.FilterAsync(a,"another")==nil and updateCalls==1)
time=62
assert(service.FilterAsync(a,"name")==nil and filterCalls==1)
mode="contention"
assert(service.FilterAsync(player(11),"pet")==nil and filterCalls==1)
mode="unexpected_old"
assert(service.FilterAsync(player(12),"pet")==nil and filterCalls==1)
mode="error"
assert(service.FilterAsync(player(13),"pet")==nil and filterCalls==1)
mode="normal"
local gone=player(14)
remove(gone)
assert(service.FilterAsync(gone,"pet")==nil and filterCalls==1)
assert(service.FilterAsync({},"pet")==nil and filterCalls==1)
assert(service.FilterAsync(player(15),"IDIOTA")==nil and filterCalls==1)
print("PASS: public field adapter atomic-claim and identity checks")
