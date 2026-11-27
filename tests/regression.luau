local count=0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function suite(name,fn) fn(); count+=1; print("PASS "..name) end
local now=0
local function config()
 return {Global={Limit=4,Window=1},MaxSubjects=2,Clock=function() return now end,Actions={
 Buy={Quota={Limit=2,Window=1},Args={{Type="string",MaxBytes=8},{Type="number",Integer=true,Min=1,Max=10}}},
 Ping={Quota={Limit=4,Window=1},Args={}},
 }}
end
suite("validation and attempt charging",function()
 now=0;local g=RemoteGuard.new(config())
 local ok,why,i=g:Check(1,"Buy","item",0/0);eq(ok,false);eq(why,"INVALID_ARGUMENT");eq(i,2)
 eq(g:Check(1,"Buy","item",1),true)
 ok,why=g:Check(1,"Buy","item",1);eq(ok,false);eq(why,"ACTION_LIMIT")
 eq(g:Check(1,"Ping"),true)
 ok,why=g:Check(1,"Ping");eq(ok,false);eq(why,"GLOBAL_LIMIT")
 now=1;eq(g:Check(1,"Buy","item",1),true)
end)
suite("isolation and capacity",function()
 now=0;local g=RemoteGuard.new(config());local a,b,c={},{},{}
 eq(g:Check(a,"Ping"),true);eq(g:Check(b,"Ping"),true)
 local ok,why=g:Check(c,"Ping");eq(ok,false);eq(why,"CAPACITY");eq(g:Count(),2)
 eq(g:Forget(a),true);eq(g:Check(c,"Ping"),true);eq(g:Count(),2)
 eq(g:Destroy(),true);eq(g:Count(),0);eq(g:Check(c,"Ping"),false);eq(g:Destroy(),true)
end)
suite("invalid identities and action names",function()
 now=0;local g=RemoteGuard.new(config())
 for _,v in ipairs({0/0,math.huge,1.5,false,"",function() end}) do eq(g:Check(v,"Ping"),false) end
 eq(g:Check(nil,"Ping"),false);eq(g:Check(1,{}),false);eq(g:Check(1,"Missing"),false);eq(g:Count(),0)
end)
suite("malformed arguments",function()
 local values={0/0,math.huge,-math.huge,0,11,1.5,"1",{},false}
 for _,v in ipairs(values) do now=0;local g=RemoteGuard.new(config());eq(g:Check(1,"Buy","a",v),false) end
 for _,v in ipairs({string.char(255),string.rep("a",9),{},7}) do now=0;local g=RemoteGuard.new(config());eq(g:Check(1,"Buy",v,1),false) end
 now=0;local g=RemoteGuard.new(config());eq(g:Check(1,"Buy","a"),false);eq(g:Check(1,"Ping",nil),false)
end)
suite("optional trailing values",function()
 now=0;local c=config();c.Actions.Ping.Args={{Type="boolean",Optional=true}};local g=RemoteGuard.new(c)
 eq(g:Check(1,"Ping"),true);eq(g:Check(1,"Ping",nil),true);eq(g:Check(1,"Ping",false),true);eq(g:Check(1,"Ping","false"),false)
end)
suite("authorization errors yields and strict true",function()
 for _,fn in ipairs({function() return false end,function() return 1 end,function() error("failure") end,function() coroutine.yield() end}) do
  now=0;local c=config();c.Actions.Ping.Authorize=fn;local g=RemoteGuard.new(c)
  eq(g:Check(1,"Ping"),false);eq(g:Count(),1)
 end
 now=0;local c=config();local player={};c.Actions.Ping.Authorize=function(p) return p==player end;local g=RemoteGuard.new(c)
 eq(g:Check(player,"Ping"),true);eq(g:Check({},"Ping"),false)
end)
suite("no callback reentry",function()
 now=0;local c=config();local g
 c.Actions.Ping.Authorize=function(p)
  local ok,why=g:Check(p,"Ping");eq(ok,false);eq(why,"BUSY")
  eq(g:Forget(p),false);eq(g:Destroy(),false);return true
 end
 g=RemoteGuard.new(c);eq(g:Check(1,"Ping"),true)
end)
suite("clock regression and invalid clock",function()
 now=5;local g=RemoteGuard.new(config());eq(g:Check(1,"Ping"),true)
 now=4;local ok,why=g:Check(1,"Ping");eq(ok,false);eq(why,"CLOCK_REGRESSION")
 for _,v in ipairs({0/0,math.huge,-1,2^33,false}) do now=v;eq(g:Check(2,"Ping"),false) end
 eq(g:Count(),1);now=6;eq(g:Check(1,"Ping"),true)
end)
suite("configuration copied",function()
 now=0;local c=config();local g=RemoteGuard.new(c)
 c.Global.Limit=1;c.Actions.Buy.Quota.Limit=1;c.Actions.Buy.Args[1].Type="boolean";c.Actions.Buy=nil
 eq(g:Check(1,"Buy","a",1),true);eq(g:Check(1,"Buy","a",1),true)
end)
suite("reject configuration errors",function()
 for _,mutate in ipairs({
 function(c)c.MaxSubjects=false end,function(c)c.Global.Window=0/0 end,function(c)c.Global.Limit=257 end,
 function(c)c.Actions.Buy.Args[3]={Type="table"} end,function(c)c.Actions.Buy.Args[1].Optional=true end,
 function(c)c.Actions.Ping.Quota.Typo=1 end,function(c)c.Actions.Buy.Args[1].Min=0 end,
 function(c)c.Actions.Ping.Args={[2]={Type="number"}} end,function(c)c.Actions.Ping.Authorize=false end,
 }) do local c=config();mutate(c);eq(pcall(RemoteGuard.new,c),false) end
end)
suite("independent sliding window model",function()
 now=0;local c=config();c.MaxSubjects=16;local g=RemoteGuard.new(c)
 local model={};local seed=35149
 local function rand(n)seed=seed*48271%2147483647;return seed%n end
 local function expire(list,window)
  while list[1] and now-list[1]>=window do table.remove(list,1) end
 end
 for _=1,100000 do
  now+=rand(5)/16;local id=rand(16)+1;local action=if rand(2)==0 then "Buy" else "Ping"
  local s=model[id];if not s then s={global={},Buy={},Ping={}};model[id]=s end
  expire(s.global,1);expire(s[action],1)
  local expected=false;local reason
  if #s.global>=4 then reason="GLOBAL_LIMIT" else
   table.insert(s.global,now)
   if #s[action]>=c.Actions[action].Quota.Limit then reason="ACTION_LIMIT" else
    table.insert(s[action],now);expected=true
   end
  end
  local ok,why
  if action=="Buy" then ok,why=g:Check(id,action,"a",1) else ok,why=g:Check(id,action) end
  eq(ok,expected);eq(why,reason)
 end
end)
print("PASS "..count.." suites")
