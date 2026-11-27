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
 for _,v in ipairs({0/0,math.huge,-math.huge,0,11,1.5,"1",{},false}) do now=0;local g=RemoteGuard.new(config());eq(g:Check(1,"Buy","a",v),false) end
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
  eq(g:Forget(p),false);eq(g:Destroy(),false);eq(g:Sweep(),nil);eq(g:Begin(p,"Ping"),nil);eq(g:Release({}),false);return true
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
 function(c)c.MaxInFlight=false end,function(c)c.Server=false end,function(c)c.Actions.Ping.MaxInFlight=5 end,
 }) do local c=config();mutate(c);eq(pcall(RemoteGuard.new,c),false) end
end)
suite("independent sliding window model",function()
 now=0;local c=config();c.MaxSubjects=16;local g=RemoteGuard.new(c)
 local model={};local seed=35149
 local function rand(n)seed=seed*48271%2147483647;return seed%n end
 local function expire(list,window) while list[1] and now-list[1]>=window do table.remove(list,1) end end
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
suite("multiple optional arguments omitted",function()
 now=0;local c=config();c.Actions.Ping.Args={{Type="boolean",Optional=true},{Type="number",Optional=true},{Type="string",Optional=true}}
 local g=RemoteGuard.new(c);eq(g:Check(1,"Ping"),true);eq(g:Check(1,"Ping",nil,3),true)
end)
suite("default clock and memory budget",function()
 local c=config();c.Clock=nil;local g=RemoteGuard.new(c);eq(g:Check(1,"Ping"),true)
 c.MaxSubjects=4096;c.Global.Limit=256;eq(pcall(RemoteGuard.new,c),false)
end)
local function richConfig(args)
 return {Global={Limit=256,Window=1},MaxSubjects=16,Clock=function() return now end,Actions={A={Quota={Limit=256,Window=1},Args=args}}}
end
local function validate(rule,v)
 now=0;local g=RemoteGuard.new(richConfig({rule}));return g:Check(1,"A",v)
end
local schema={Type="record",Fields={
 id={Type="string",Choices={"A","B"},MaxBytes=2},
 quantity={Type="number",Integer=true,Min=1,Max=9},
 tags={Type="array",MaxItems=3,Items={Type="string",MaxBytes=8}},
 options={Type="record",Optional=true,Fields={gift={Type="boolean"}}},
}}
suite("closed nested schema",function()
 eq(validate(schema,{id="A",quantity=1,tags={"x","y"},options={gift=false}}),true)
 eq(validate(schema,{id="B",quantity=9,tags={}}),true)
 local bad={
 {id="X",quantity=1,tags={}}, {id="A",quantity=1,tags={},extra=true},
 {id="A",quantity=1,tags={[2]="x"}}, {id="A",quantity=1,tags={"a","b","c","d"}},
 {id="A",quantity=1,tags={"123456789"}}, {id="A",quantity=1,tags={"x",foo="y"}},
 {id="A",quantity=0,tags={}}, {id="A",quantity=1.1,tags={}},
 {id="A",quantity=1,tags={},options={}}, {id="A",quantity=1,tags={},options={gift=false,admin=true}},
 {id="A",quantity=1}, {id="A",quantity=1,tags={string.char(255)}},
 {id="A",quantity=1,tags=setmetatable({},{})}, setmetatable({id="A",quantity=1,tags={}},{__index={}}),
 }
 for _,v in ipairs(bad) do eq(validate(schema,v),false) end
end)
suite("recursive config copied and invalid rules rejected",function()
 now=0;local rule={Type="record",Fields={v={Type="string",Choices={"yes"}}}}
 local g=RemoteGuard.new(richConfig({rule}));rule.Fields.v.Choices[1]="no";rule.Fields.v=nil
 eq(g:Check(1,"A",{v="yes"}),true);eq(g:Check(1,"A",{v="no"}),false)
 local cycle={Type="array"};cycle.Items=cycle
 local tooDeep={Type="boolean"};for i=1,9 do tooDeep={Type="array",Items=tooDeep} end
 for _,r in ipairs({cycle,tooDeep,{Type="array",Items={Type="number",Optional=true}},{Type="record",Fields={[false]={Type="number"}}},{Type="string",Choices={"a","a"}},{Type="string",Choices={}},{Type="Vector3",MaxAbs=math.huge},{Type="Instance",Class="Part",Ancestor={}},{Type="record",Fields={},Min=0}}) do
  eq(pcall(RemoteGuard.new,richConfig({r})),false)
 end
end)
suite("hostile cycles and alias budget",function()
 local r={Type="array",MaxItems=256,Items={Type="array",MaxItems=256,Items={Type="number"}}}
 local cyclic={};cyclic[1]=cyclic;eq(validate(r,cyclic),false)
 local arr=table.create(256,1)
 eq(validate(r,{arr}),true);eq(validate(r,{arr,arr}),false) -- 515 logical visits
 local t={};for i=1,300 do t[i]=1 end;eq(validate({Type="array",MaxItems=256,Items={Type="number"}},t),false)
end)
suite("total payload byte budget",function()
 local r={Type="array",MaxItems=16,Items={Type="string",MaxBytes=4096}}
 local s=string.rep("x",4096)
 eq(validate(r,{s,s,s,s}),true);eq(validate(r,{s,s,s,s,"x"}),false)
 eq(validate({Type="record",Fields={abc={Type="array",Items=r.Items}}},{abc={s,s,s,s}}),false)
end)
suite("engine type spoof rejected",function()
 eq(validate({Type="Vector3",MaxAbs=100},{X=1,Y=2,Z=3}),false)
 eq(validate({Type="Vector2",MaxAbs=100},{X=1,Y=2}),false)
end)
suite("shared server quota and priority",function()
 now=0;local c=config();c.MaxSubjects=8;c.Server={Limit=2,Window=2};local g=RemoteGuard.new(c)
 eq(g:Check(1,"Buy","a",0),false);eq(g:Check(1,"Buy","a",1),true)
 local ok,why,wait=g:Check(2,"Ping");eq(ok,false);eq(why,"SERVER_LIMIT");eq(wait,2)
 ok,why=g:Check(1,"Buy","a",1);eq(ok,false);eq(why,"ACTION_LIMIT")
 eq(g:Forget(1),true);eq(g:Check(1,"Ping"),false)
 now=1;eq(g:Check(3,"Ping"),false);now=2;eq(g:Check(3,"Ping"),true)
 local stats=g:GetStats();eq(stats.Allowed,2);eq(stats.Denied,5);eq(stats.SERVER_LIMIT,3)
 stats.Allowed=0;eq(g:GetStats().Allowed,2)
end)
suite("sweep does not erase longer quotas or server history",function()
 now=0;local c=config();c.Actions.Buy.Quota.Window=10;c.Server={Limit=2,Window=20};local g=RemoteGuard.new(c)
 eq(g:Check(1,"Buy","a",1),true);eq(g:Check(2,"Ping"),true)
 now=1;eq(g:Sweep(),0);now=9;eq(g:Sweep(),0);now=10;eq(g:Sweep(),2);eq(g:Count(),0)
 local ok,why=g:Check(3,"Ping");eq(ok,false);eq(why,"SERVER_LIMIT")
 now=20;eq(g:Sweep(),1);eq(g:Check(3,"Ping"),true)
end)
suite("exact boundary resists rounded early admission",function()
 now=2^-60;local c=config();c.Global.Limit=1;c.Actions.Ping.Quota.Limit=1;local g=RemoteGuard.new(c)
 eq(g:Check(1,"Ping"),true);now=1
 local ok,why,wait=g:Check(1,"Ping");eq(ok,false);eq(why,"GLOBAL_LIMIT");eq(wait,2^-60)
 eq(g:Sweep(),0);now=1+2^-52;eq(g:Sweep(),1);eq(g:Check(1,"Ping"),true)
end)
local function leasedConfig()
 local c=richConfig({});c.MaxInFlight=3;c.MaxInFlightPerSubject=2;c.Actions.A.MaxInFlight=1
 c.Actions.B={Quota={Limit=256,Window=1},Args={},MaxInFlight=2}
 c.Actions.C={Quota={Limit=256,Window=1},Args={}}
 return c
end
suite("in-flight budgets, mode enforcement and token release",function()
 now=0;local g=RemoteGuard.new(leasedConfig())
 local ok,why=g:Check(1,"A");eq(ok,false);eq(why,"ACQUIRE_REQUIRED")
 local token,err=g:Begin(1,"C");eq(token,nil);eq(err,"NOT_LEASE_ACTION")
 local a=assert(g:Begin(1,"A"));eq(g:IsCurrent(a),true)
 token,err=g:Begin(1,"A");eq(token,nil);eq(err,"ACTION_IN_FLIGHT")
 local b=assert(g:Begin(1,"B"));token,err=g:Begin(1,"B");eq(token,nil);eq(err,"SUBJECT_IN_FLIGHT")
 local c=assert(g:Begin(2,"A"));token,err=g:Begin(3,"A");eq(token,nil);eq(err,"SERVER_IN_FLIGHT")
 eq(g:GetStats().InFlight,3);eq(g:Release({}),false);eq(g:Release(a),true);eq(g:Release(a),false);eq(g:IsCurrent(a),false)
 local d=assert(g:Begin(3,"A"));eq(g:IsCurrent(d),true);eq(g:GetStats().InFlight,3)
 eq(g:Release(b),true);eq(g:Release(c),true);eq(g:Release(d),true);eq(g:GetStats().InFlight,0)
end)
suite("departure invalidates tokens but retains occupied server slots",function()
 now=0;local cfg=leasedConfig();cfg.MaxInFlight=1;cfg.MaxInFlightPerSubject=1;cfg.Actions.B.MaxInFlight=1
 local g=RemoteGuard.new(cfg);local old=assert(g:Begin(1,"A"));eq(g:Forget(1),true);eq(g:IsCurrent(old),false);eq(g:GetStats().InFlight,1)
 local token,err=g:Begin(1,"A");eq(token,nil);eq(err,"SERVER_IN_FLIGHT")
 eq(g:Release(old),true);local fresh=assert(g:Begin(1,"A"));eq(g:IsCurrent(fresh),true);eq(g:Release(old),false)
 now=5;eq(g:Sweep(),0);eq(g:Count(),1);eq(g:Release(fresh),true);eq(g:Sweep(),1)
 local other=RemoteGuard.new(cfg);local foreign=assert(other:Begin(1,"A"));eq(g:Release(foreign),false);eq(g:IsCurrent(foreign),false)
 eq(other:Destroy(),true);eq(other:IsCurrent(foreign),false);eq(other:GetStats().InFlight,0)
end)
suite("authorization failure does not reserve permit",function()
 now=0;local c=leasedConfig();c.Actions.A.Authorize=function() return false end;local g=RemoteGuard.new(c)
 eq(g:Begin(1,"A"),nil);eq(g:GetStats().InFlight,0);eq(g:Begin(1,"B")~=nil,true)
end)
suite("clock callback reentry and failure",function()
 local c=config();local g;c.Clock=function() eq(g:Forget(1),false);eq(g:Sweep(),nil);eq(g:Destroy(),false);return 0 end
 g=RemoteGuard.new(c);eq(g:Check(1,"Ping"),true)
 c.Clock=function() coroutine.yield() end;g=RemoteGuard.new(c);eq(g:Check(1,"Ping"),false);eq(g:Count(),0)
end)
suite("bounded dynamic maps and binary payloads",function()
 local rule={Type="map",MaxItems=2,Keys={Type="string",MaxBytes=4},Values={Type="number",Integer=true,Min=1,Max=9}}
 eq(validate(rule,{abc=1,b=9}),true);eq(validate(rule,{}),true)
 for _,v in ipairs({{[1]=1},{abcde=1},{a=0},{a=1,b=1,c=1},{[string.char(255)]=1}}) do eq(validate(rule,v),false) end
 eq(validate({Type="buffer",MaxBytes=16},buffer.create(16)),true)
 eq(validate({Type="buffer",MaxBytes=16},buffer.create(17)),false)
 eq(validate({Type="buffer",MaxBytes=16},"fake"),false)
 eq(validate({Type="Color3"},{R=1,G=1,B=1}),false)
 eq(pcall(RemoteGuard.new,richConfig({{Type="map",Keys={Type="number"},Values={Type="boolean"}}})),false)
end)
suite("ring wrap and partially expired prefix",function()
 now=0;local c=richConfig({});c.Actions.A.Quota={Limit=4,Window=4};c.Global.Window=4;local g=RemoteGuard.new(c)
 for i=0,3 do now=i;eq(g:Check(1,"A"),true) end
 eq(g:Check(1,"A"),false);now=4;eq(g:Check(1,"A"),true);eq(g:Check(1,"A"),false)
 now=6;eq(g:Check(1,"A"),true);eq(g:Check(1,"A"),true);eq(g:Check(1,"A"),false)
 now=100;for i=1,4 do eq(g:Check(1,"A"),true) end;eq(g:Check(1,"A"),false)
end)
suite("unbounded numeric rules still reject nonfinite",function()
 eq(validate({Type="number"},0/0),false);eq(validate({Type="number"},math.huge),false);eq(validate({Type="number"},-math.huge),false)
 eq(validate({Type="number"},1e300),true)
end)
suite("schema size budget is aggregate",function()
 local fields={};for i=1,65 do fields[tostring(i)]={Type="boolean"} end
 eq(pcall(RemoteGuard.new,richConfig({{Type="record",Fields=fields}})),false)
 local children={};for i=1,64 do children[tostring(i)]={Type="boolean"} end
 local cfg=richConfig({});cfg.Actions={}
 for i=1,64 do cfg.Actions[tostring(i)]={Quota={Limit=1,Window=1},Args={{Type="record",Fields=children}}} end
 eq(pcall(RemoteGuard.new,cfg),false)
end)
print("PASS "..count.." suites")
