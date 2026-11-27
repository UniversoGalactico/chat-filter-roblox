-- Differential + metamorphic admission campaign. Synthetic keys only.
-- Independent list-based oracle, no FIFO, scope buckets or ring arithmetic.
local Gate
if type(dofile)=="function" then Gate=dofile("server/DeliveryGate.lua")
else Gate=require("../server/DeliveryGate") end

local SCENARIOS = 32
local STEPS = 6000
local OFFSET=2^35
local total,noise,clears,forgets=0,0,0,0
local reasons={}
local function failEq(got,want,label,scenario,step)
    if got~=want then
        error(string.format("%s scenario=%d step=%d got=%s expected=%s",label,scenario,step,tostring(got),tostring(want)))
    end
end
local function reference(state,scope,id,now,cfg)
    if state.last and now<state.last then return false,"clock_regression" end
    state.last=now
    for _,row in ipairs(state.entries) do
        if row.scope==scope and row.id==id and row.expiry>now then
            return row.allow,row.reason
        end
    end
    local live={}
    for _,row in ipairs(state.entries) do
        if row.expiry>now then live[#live+1]=row end
    end
    state.entries=live
    if (state.quarantine and state.quarantine>now) or #live>=cfg.MaxCachedMessages then
        state.quarantine=now+cfg.DecisionTTL
        return false,"cache_capacity"
    end
    state.quarantine=nil
    local kept={}
    for _,t in ipairs(state.accepted) do
        if t>now-1 then kept[#kept+1]=t end
    end
    local allow=#kept<cfg.MessagesPerSecond
    local reason=allow and "allow" or "rate_limit"
    if allow then kept[#kept+1]=now end
    state.accepted=kept
    live[#live+1]={scope=scope,id=id,expiry=now+cfg.DecisionTTL,allow=allow,reason=reason}
    return allow,reason
end

local function forbidden() error("user key metamethod must not execute") end
local meta={__eq=forbidden,__index=forbidden,__newindex=forbidden}
local function keys()
    return {setmetatable({},meta),setmetatable({},meta),{},0,-2,"sender"}
end
local function scopes()
    return {setmetatable({},meta),setmetatable({},meta),{},0,"scope"}
end
local invalid={false,true,math.huge,-math.huge,0/0,"",string.rep("x",129),function()end}
local ttlOptions={1,1.25,2,7.5,10,60}
local deltas={0,0,0,1/64,1/8,0.5,1-1/64,1,1+1/64,2,8}
local ids={}
for i=1,512 do ids[i]="M"..i end
local invalidIds={false,0,{},string.rep("x",129),"",0/0}
for scenario=1,SCENARIOS do
    local rng=(((scenario+37)*104729)%2147483646)+1
    local function draw(n)
        rng=(rng*48271)%2147483647
        return rng%n+1
    end
    local limit=draw(20)
    local capOptions={limit,limit+1,math.min(256,2*limit),64,256}
    local cfg={MessagesPerSecond=limit,DecisionTTL=ttlOptions[draw(#ttlOptions)],MaxCachedMessages=capOptions[draw(#capOptions)]}
    local a,b=Gate.new(cfg),Gate.new(cfg)
    -- Change both key identities and types in the second implementation.
    local ownersA,ownersB=keys(),keys()
    local scopeA,scopeB=scopes(),scopes()
    local model,history={},{}
    local now=0
    local lastOwner,lastScope,lastId=1,1,ids[1]
    for step=1,STEPS do
        local action=draw(100)
        local owner,scope,id=draw(#ownersA),draw(#scopeA),ids[draw(#ids)]
        if action<=25 then owner,scope,id=lastOwner,lastScope,lastId end
        if action==99 then
            a:Clear() b:Clear() model={} clears=clears+1
        elseif action==98 then
            a:Forget(ownersA[owner]) b:Forget(ownersB[owner]) model[owner]=nil forgets=forgets+1
        else
            local delta
            if scenario%3==0 then delta=deltas[draw(5)] else delta=deltas[draw(#deltas)] end
            now=now+delta
            local t=now
            local state=model[owner]
            if not state then state={entries={},accepted={}} model[owner]=state end
            if action==97 and state.last and state.last>=1 then t=state.last-1/64 end
            -- Inject invalid noise into B only. These calls must not mutate its state.
            if action%7==0 then
                local k=invalid[draw(#invalid)]
                local denied,why=b:Admit(k,id,t+OFFSET,scopeB[scope])
                failEq(denied,false,"invalid sender",scenario,step)
                failEq(why,"invalid_identity","invalid sender reason",scenario,step)
                denied,why=b:Admit(ownersB[owner],id,t+OFFSET,k)
                failEq(denied,false,"invalid scope",scenario,step)
                failEq(why,"invalid_identity","invalid scope reason",scenario,step)
                denied,why=b:Admit(ownersB[owner],invalidIds[draw(#invalidIds)],t+OFFSET,scopeB[scope])
                failEq(denied,false,"invalid message id",scenario,step)
                failEq(why,"invalid_identity","invalid message reason",scenario,step)
                denied,why=b:Admit(ownersB[owner],id,0/0,scopeB[scope])
                failEq(denied,false,"invalid clock",scenario,step)
                failEq(why,"invalid_clock","invalid clock reason",scenario,step)
                noise=noise+4
            end
            local want,wantedReason=reference(state,scope,id,t,cfg)
            local actual,reason=a:Admit(ownersA[owner],id,t,scopeA[scope])
            local shifted,shiftedReason=b:Admit(ownersB[owner],id,t+OFFSET,scopeB[scope])
            failEq(actual,want,"oracle decision",scenario,step)
            failEq(reason,wantedReason,"oracle reason",scenario,step)
            failEq(shifted,want,"time-shift/key-renaming decision",scenario,step)
            failEq(shiftedReason,wantedReason,"time-shift/key-renaming reason",scenario,step)
            reasons[reason]=(reasons[reason] or 0)+1
            total=total+1
            lastOwner,lastScope,lastId=owner,scope,id
        end
    end
end
for _,reason in ipairs({"allow","rate_limit","cache_capacity","clock_regression"}) do
    assert((reasons[reason] or 0)>0,"campaign missed "..reason)
end
print(string.format("PASS: gate campaign scenarios=%d valid=%d noise=%d clears=%d forgets=%d",SCENARIOS,total,noise,clears,forgets))
for _,reason in ipairs({"allow","rate_limit","cache_capacity","clock_regression"}) do
    print("CAMPAIGN",reason,reasons[reason])
end
