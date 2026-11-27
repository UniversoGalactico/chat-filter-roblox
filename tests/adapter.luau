local count=0
local now=0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function suite(name,fn) fn();count+=1;print("PASS ADAPTER "..name) end
local function config()
 return {Global={Limit=20,Window=1},Clock=function()return now end,MaxInFlight=1,MaxInFlightPerSubject=1,Actions={
  Fast={Quota={Limit=20,Window=1},Args={{Type="number",Integer=true,Min=1,Max=5}}},
  Slow={Quota={Limit=20,Window=1},Args={},MaxInFlight=1},
 }}
end
suite("server only and explicit route",function()
 fakeRunService.server=false;eq(pcall(RemoteGuardServer.new,config()),false);fakeRunService.server=true
 local server=RemoteGuardServer.new(config());eq(fakePlayers:connections(),1)
 eq(pcall(function() server:Wrap("unknown",function()end) end),false)
 eq(pcall(function() server:Wrap("Fast",false) end),false)
 eq(server:Destroy(),true);eq(fakePlayers:connections(),0);eq(server:Destroy(),true)
end)
suite("actual identity predicate and argument forwarding",function()
 now=0;local p=fakePlayers:add(1);local server=RemoteGuardServer.new(config());local called=0
 local w=server:Wrap("Fast",function(player,token,n) eq(player,p);eq(token,nil);called+=1;return n,nil,"ok" end)
 local fake={_mockInstance=true,Parent=fakePlayers,UserId=1,IsA=p.IsA}
 eq(w(fake,1),false);eq(w({},1),false);eq(w(p,1,2),false);eq(w(p,0),false);eq(called,0)
 local r=table.pack(w(p,3));eq(r.n,4);eq(r[1],true);eq(r[2],3);eq(r[3],nil);eq(r[4],"ok");eq(called,1)
 fakePlayers:remove(p,false);eq(w(p,3),false);eq(called,1);eq(server:GetStats().InvalidPlayer,3)
 eq(server:Destroy(),true);eq(w(p,3),false)
end)
suite("shared quota across wrappers",function()
 now=0;local p=fakePlayers:add(2);local c=config();c.Actions.Fast.Quota.Limit=1;local s=RemoteGuardServer.new(c)
 c.Actions.Fast.MaxInFlight=1
 local a=s:Wrap("Fast",function()return 1 end);local b=s:Wrap("Fast",function()return 2 end)
 eq(a(p,1),true);eq(b(p,1),false);now=1;local ok,v=b(p,1);eq(ok,true);eq(v,2);s:Destroy()
end)
suite("sync handler cannot yield, errors redacted",function()
 now=0;local p=fakePlayers:add(3);local s=RemoteGuardServer.new(config());local resumed=false;local yielded
 local a=s:Wrap("Fast",function() yielded=coroutine.running();coroutine.yield();resumed=true end)
 local ok,err=a(p,1);eq(ok,false);eq(err,"HANDLER_ERROR");eq(coroutine.status(yielded),"dead");eq(resumed,false)
 local b=s:Wrap("Fast",function()error("private secret")end);ok,err=b(p,1);eq(ok,false);eq(err,"HANDLER_ERROR")
 local stats=s:GetStats();eq(stats.HandlerErrors,1);eq(stats.HandlerYields,1);stats.HandlerErrors=42;eq(s:GetStats().HandlerErrors,1);s:Destroy()
end)
suite("leased handler and stale departure response",function()
 now=0;local p=fakePlayers:add(4);local s=RemoteGuardServer.new(config());local token
 local w=s:Wrap("Slow",function(player,permit) token=permit;eq(s:IsCurrent(permit),true);coroutine.yield("waiting");return "finished" end)
 local t=coroutine.create(function()return w(p)end);local ok,v=coroutine.resume(t);eq(ok,true);eq(v,"waiting");eq(s:GetStats().InFlight,1)
 eq(w(p),false);eq(s:Sweep(),0);eq(s:GetStats().InFlight,1)
 fakePlayers:remove(p,false);eq(s:IsCurrent(token),false);eq(w(p),false)
 local q=fakePlayers:add(4);eq(w(q),false);eq(s:GetStats().InFlight,1)
 local ran,allowed,code=coroutine.resume(t);eq(ran,true);eq(allowed,false);eq(code,"DENIED");eq(s:GetStats().InFlight,0);eq(s:GetStats().StaleCompletions,1)
 local w2=s:Wrap("Slow",function(_,permit)eq(s:IsCurrent(permit),true);return nil,7 end)
 local r=table.pack(w2(q));eq(r.n,3);eq(r[1],true);eq(r[2],nil);eq(r[3],7);eq(s:GetStats().InFlight,0);s:Destroy()
end)
suite("ordinary handler errors release permits",function()
 now=0;local p=fakePlayers:add(5);local s=RemoteGuardServer.new(config())
 local w=s:Wrap("Slow",function()coroutine.yield();error("secret")end)
 local t=coroutine.create(function()return w(p)end);eq(coroutine.resume(t),true);eq(s:GetStats().InFlight,1)
 local ok,allowed,why=coroutine.resume(t);eq(ok,true);eq(allowed,false);eq(why,"HANDLER_ERROR");eq(s:GetStats().InFlight,0);eq(s:GetStats().HandlerErrors,1);s:Destroy()
end)
suite("sweep reaps dead thread only",function()
 now=0;local p=fakePlayers:add(6);local s=RemoteGuardServer.new(config());local token
 local w=s:Wrap("Slow",function(_,permit)token=permit;coroutine.yield()end)
 local t=coroutine.create(function()return w(p)end);eq(coroutine.resume(t),true);now=100
 eq(s:Sweep(),0);eq(s:IsCurrent(token),true);eq(s:GetStats().InFlight,1);eq(w(p),false)
 eq(coroutine.close(t),true);eq(s:Sweep(),1);eq(s:GetStats().InFlight,0);eq(s:IsCurrent(token),false);eq(s:GetStats().Reaped,1)
 eq(s:Sweep(),0);s:Destroy()
end)
suite("destroy during handler and busy authorization",function()
 now=0;local p=fakePlayers:add(7);local s;local c=config()
 c.Actions.Fast.Authorize=function()local ok,why=s:Destroy();eq(ok,false);eq(why,"BUSY");return true end
 s=RemoteGuardServer.new(c);local fast=s:Wrap("Fast",function()return true end);eq(fast(p,1),true)
 local token;local w=s:Wrap("Slow",function(_,permit)token=permit;coroutine.yield();return 1 end)
 local t=coroutine.create(function()return w(p)end);eq(coroutine.resume(t),true);eq(s:Destroy(),true);eq(s:IsCurrent(token),false);eq(fakePlayers:connections(),0)
 local ran,allowed,err=coroutine.resume(t);eq(ran,true);eq(allowed,false);eq(err,"DENIED");eq(fast(p,1),false);eq(w(p),false)
end)
print("PASS ADAPTER "..count.." suites")
