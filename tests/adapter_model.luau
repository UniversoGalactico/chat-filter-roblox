-- Interleaved coroutine and departure model against mocked engine membership.
local seed=3519821
local function rand(n)seed=seed*48271%2147483647;return seed%n end
local function eq(a,b,label)assert(a==b,label..": "..tostring(a).." ~= "..tostring(b).." seed="..seed)end
local operations=0;local coverage={started=0,blocked=0,finished=0,stale=0,cancelled=0,reaped=0,departed=0}
for trial=1,16 do
 local now=0;local players={};for i=1,16 do players[i]=fakePlayers:add(1000+i) end
 local server=RemoteGuardServer.new({Global={Limit=10,Window=1},MaxSubjects=32,MaxInFlight=16,MaxInFlightPerSubject=2,Clock=function()return now end,
  Actions={Slow={Quota={Limit=10,Window=1},Args={},MaxInFlight=2},Fast={Quota={Limit=10,Window=1},Args={}}}})
 local issued={}
 local slow=server:Wrap("Slow",function(player,token)
  issued[coroutine.running()]=token
  eq(server:IsCurrent(token),true,"new token current")
  coroutine.yield("WAIT")
  return player.UserId
 end)
 local fast=server:Wrap("Fast",function(player)return player.UserId end)
 local pending={};local active=0;local reaped=0;local stale=0
 for step=1,10000 do
  now+=1;local op=rand(100);local id=rand(16)+1;local player=players[id]
  if op<45 then
   local own=0;for _,r in ipairs(pending) do if r.player==player then own+=1 end end
   local expected=active<16 and own<2
   local thread=coroutine.create(function()return slow(player)end)
   local ran,result,code=coroutine.resume(thread);eq(ran,true,"start invocation")
   if expected then
    eq(result,"WAIT","expected suspended");active+=1;pending[#pending+1]={thread=thread,token=issued[thread],player=player,id=id,cancelled=false};coverage.started+=1
   else eq(result,false,"expected denied");eq(code,"DENIED","denial code");coverage.blocked+=1 end
  elseif op<64 and #pending>0 then
   local i=rand(#pending)+1;local r=pending[i]
   if not r.cancelled then
    local current=players[r.id]==r.player;eq(server:IsCurrent(r.token),current,"before resume")
    local ran,result,detail=coroutine.resume(r.thread);eq(ran,true,"finish coroutine");eq(result,current,"completion current")
    eq(detail,if current then r.player.UserId else "DENIED","completion result")
    if not current then stale+=1;coverage.stale+=1 end
    active-=1;issued[r.thread]=nil;table.remove(pending,i);coverage.finished+=1
   end
  elseif op<74 and #pending>0 then
   local r=pending[rand(#pending)+1]
   if not r.cancelled then eq(coroutine.close(r.thread),true,"external close");r.cancelled=true;coverage.cancelled+=1 end
  elseif op<83 then
   fakePlayers:remove(player,false);eq(fast(player),false,"departed player denied")
   players[id]=fakePlayers:add(1000+id);coverage.departed+=1
  elseif op<92 then
   local expected=0
   for i=#pending,1,-1 do local r=pending[i];if r.cancelled then expected+=1;active-=1;issued[r.thread]=nil;table.remove(pending,i) end end
   eq(server:Sweep(),expected,"only dead reaped");reaped+=expected;coverage.reaped+=expected
  else local ok,value=fast(player);eq(ok,true,"current fast");eq(value,player.UserId,"fast result") end
  local stats=server:GetStats();eq(stats.InFlight,active,"adapter permit count");eq(stats.Reaped,reaped,"reaped total");eq(stats.StaleCompletions,stale,"stale total")
  operations+=1
 end
 server:Destroy();eq(server:GetStats().InFlight,0,"destroy clears permits")
 for _,r in ipairs(pending) do
  eq(server:IsCurrent(r.token),false,"destroy invalidates")
  if not r.cancelled then local ran,ok,code=coroutine.resume(r.thread);eq(ran,true,"old invocation resumes");eq(ok,false,"destroy denies result");eq(code,"DENIED","destroy code") end
 end
end
for name,n in pairs(coverage) do assert(n>0,"adapter model uncovered "..name);print("ADAPTER_MODEL",name,n) end
print("PASS ADAPTER MODEL",operations)
