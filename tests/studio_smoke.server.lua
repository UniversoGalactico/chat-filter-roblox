-- Import the QuickTest model into ServerScriptService and press Play in a blank place.
-- Real engine datatypes and a real one-client round trip; no data stores or web APIs.
local RunService=game:GetService("RunService")
if not RunService:IsStudio() then warn("[RemoteGuard] Studio test only");return end
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local RemoteGuard=require(script.Parent.RemoteGuard)
local RemoteGuardServer=require(script.Parent.RemoteGuardServer)
local passed,failed=0,0
local function check(name,fn)
 local ok,result=pcall(fn)
 if ok and result==true then passed+=1;print("[RemoteGuard] PASS "..name)
 else failed+=1;warn("[RemoteGuard] FAIL "..name,ok and tostring(result) or result) end
end
local function admit(rule,value)
 local g=RemoteGuard.new({Global={Limit=2,Window=1},Actions={A={Quota={Limit=2,Window=1},Args={rule}}}})
 local ok=g:Check("test","A",value);g:Destroy();return ok
end
check("real numeric and UTF-8 checks",function()
 return admit({Type="number",Integer=true,Min=1,Max=10},2)
  and not admit({Type="number"},0/0) and not admit({Type="number"},math.huge)
  and not admit({Type="string",MaxBytes=4},string.char(255))
end)
check("real Vector3",function()
 local r={Type="Vector3",MaxAbs=100}
 return admit(r,Vector3.new(2,3,4)) and not admit(r,Vector3.new(101,0,0)) and not admit(r,{X=2,Y=3,Z=4})
end)
check("real Vector2",function()
 local r={Type="Vector2",MaxAbs=10}
 return admit(r,Vector2.new(2,3)) and not admit(r,Vector2.new(-11,0))
end)
check("real Color3",function()
 return admit({Type="Color3"},Color3.fromRGB(40,120,200)) and not admit({Type="Color3"},{R=0,G=0,B=0})
end)
check("real buffer",function()
 return admit({Type="buffer",MaxBytes=8},buffer.create(8)) and not admit({Type="buffer",MaxBytes=8},buffer.create(9))
end)
check("real Instance class and ancestry",function()
 local root=Instance.new("Folder");root.Parent=script.Parent
 local child=Instance.new("Part");child.Parent=root
 local foreign=Instance.new("Part");foreign.Parent=script.Parent
 local rule={Type="Instance",Class="BasePart",Ancestor=root}
 local ok=admit(rule,child) and not admit(rule,foreign) and not admit(rule,root) and not admit(rule,{Name="Fake"})
 root:Destroy();foreign:Destroy();return ok
end)
check("closed structures and cyclic rejection",function()
 local rule={Type="record",Fields={id={Type="string",Choices={"x"}},values={Type="array",Items={Type="number"},MaxItems=2}}}
 local cycle={};cycle[1]=cycle
 return admit(rule,{id="x",values={1,2}}) and not admit(rule,{id="x",values={[2]=1}})
  and not admit(rule,{id="x",values=cycle}) and not admit(rule,{id="x",values={},admin=true})
end)
check("exact fractional quota boundary",function()
 local now=2^-60
 local g=RemoteGuard.new({Global={Limit=1,Window=1},Actions={A={Quota={Limit=1,Window=1},Args={}}},Clock=function()return now end})
 local first=g:Check(1,"A");now=1;local second,code,wait=g:Check(1,"A");now=1+2^-52;local third=g:Check(1,"A");g:Destroy()
 return first and not second and code=="GLOBAL_LIMIT" and wait==2^-60 and third
end)
check("authorization yield cancelled by actual scheduler",function()
 local resumed=false
 local g=RemoteGuard.new({Global={Limit=3,Window=1},Actions={A={Quota={Limit=3,Window=1},Args={},Authorize=function()task.wait(0.1);resumed=true;return true end}}})
 local ok,code=g:Check(1,"A");task.wait(0.2);g:Destroy();return not ok and code=="CALLBACK_YIELDED" and not resumed
end)
check("old lease stays occupied until release",function()
 local g=RemoteGuard.new({Global={Limit=8,Window=1},MaxInFlight=1,Actions={A={Quota={Limit=8,Window=1},Args={},MaxInFlight=1}}})
 local token=assert(g:Begin(1,"A"));g:Forget(1);local stale=not g:IsCurrent(token);local blocked,code=g:Begin(2,"A")
 local released=g:Release(token);local nextToken=g:Begin(2,"A");g:Destroy();return stale and blocked==nil and code=="SERVER_IN_FLIGHT" and released and nextToken~=nil
end)
-- One actual Studio client. A watchdog distinguishes no client from a pass.
local player=Players:GetPlayers()[1]
local deadline=os.clock()+15
while not player and os.clock()<deadline do task.wait(0.05);player=Players:GetPlayers()[1] end
if not player then warn("[RemoteGuard] RESULT: INCOMPLETE — use Play (F5), not Run");return end
check("real task.cancel and permit reaping",function()
 local server=RemoteGuardServer.new({Global={Limit=8,Window=1},MaxInFlight=1,Actions={A={Quota={Limit=8,Window=1},Args={},MaxInFlight=1}}})
 local wrapper=server:Wrap("A",function() task.wait(10) end)
 local thread=task.spawn(function()wrapper(player)end)
 local active=server:GetStats().InFlight==1
 task.cancel(thread)
 local reaped=server:Sweep();local free=server:GetStats().InFlight==0
 server:Destroy();return active and reaped==1 and free
end)
local root=Instance.new("Folder");root.Name="RemoteGuardProbe_"..HttpService:GenerateGUID(false);root.Parent=ReplicatedStorage
local allowed=Instance.new("Folder");allowed.Name="Allowed";allowed.Parent=root
local function rf(name) local r=Instance.new("RemoteFunction");r.Name=name;r.Parent=root;return r end
local function re(name) local r=Instance.new("RemoteEvent");r.Name=name;r.Parent=root;return r end
local started,ack,done=re("Started"),re("Ack"),re("Done")
local event=re("Event")
local q={Limit=100,Window=10}
local config={Global={Limit=200,Window=10},Server={Limit=200,Window=10},MaxInFlight=1,Actions={
 Shape={Quota=q,Args={{Type="record",Fields={id={Type="string",Choices={"apple"}},count={Type="number",Integer=true,Min=1,Max=5}}}}},
 Vector={Quota=q,Args={{Type="Vector3",MaxAbs=10}}},
 Instance={Quota=q,Args={{Type="Instance",Class="Folder",Ancestor=root}}},
 Quota={Quota={Limit=2,Window=30},Args={}},
 Permission={Quota=q,Args={},Authorize=function()return false end},
 Slow={Quota=q,Args={},MaxInFlight=1},
 Release={Quota=q,Args={}},
 Error={Quota=q,Args={},MaxInFlight=1},
 SyncYield={Quota=q,Args={}},
 Event={Quota=q,Args={{Type="number",Min=1,Max=1}}},
 EventCount={Quota=q,Args={}},
}}
local server=RemoteGuardServer.new(config)
local calls,slowStarts,events=0,0,0
local releaseFlag,yieldResumed=false,false
rf("Shape").OnServerInvoke=server:Wrap("Shape",function(p,_,data)assert(p==player);calls+=1;return data.count end)
rf("Vector").OnServerInvoke=server:Wrap("Vector",function(_,_,v)return v.X end)
rf("Instance").OnServerInvoke=server:Wrap("Instance",function(_,_,v)return v.Name end)
rf("Quota").OnServerInvoke=server:Wrap("Quota",function()return true end)
rf("Permission").OnServerInvoke=server:Wrap("Permission",function()error("unauthorized handler reached")end)
local slowHandler=server:Wrap("Slow",function(p,token)
 slowStarts+=1;started:FireClient(p)
 local untilTime=os.clock()+8
 while not releaseFlag and os.clock()<untilTime do task.wait(0.02) end
 assert(releaseFlag and server:IsCurrent(token),"lease not current")
 return "done"
end)
rf("Slow").OnServerInvoke=slowHandler
rf("SlowAgain").OnServerInvoke=slowHandler
rf("Release").OnServerInvoke=server:Wrap("Release",function() releaseFlag=true;return true end)
rf("Error").OnServerInvoke=server:Wrap("Error",function()error("private test error")end)
rf("SyncYield").OnServerInvoke=server:Wrap("SyncYield",function()task.wait(0.1);yieldResumed=true end)
event.OnServerEvent:Connect(server:Wrap("Event",function(p)events+=1;ack:FireClient(p)end))
rf("EventCount").OnServerInvoke=server:Wrap("EventCount",function()return events end)
local finished=false
local doneConn
doneConn=done.OnServerEvent:Connect(function(p,clientPass,clientFail)
 if p~=player or finished then return end
 finished=true;doneConn:Disconnect()
 check("actual server handler counters",function()return calls==1 and slowStarts==1 and events==1 end)
 check("real async permits and handler errors released",function()
  local stats=server:GetStats();return stats.InFlight==0 and stats.HandlerErrors==1 and stats.HandlerYields==1
 end)
 check("real synchronous handler never resumed",function()return not yieldResumed end)
 if type(clientPass)~="number" or type(clientFail)~="number" or clientPass+clientFail~=10 or clientPass<0 or clientFail<0 or clientPass%1~=0 or clientFail%1~=0 then
  warn("[RemoteGuard] RESULT: INCOMPLETE — malformed client report")
 else
  passed+=clientPass;failed+=clientFail
  print(string.format("[RemoteGuard] RESULT: %d/%d PASS; %d FAIL",passed,passed+failed,failed))
 end
 server:Destroy();root:Destroy()
end)
local gui=player:WaitForChild("PlayerGui",10)
local template=script.Parent:FindFirstChild("ClientProbe")
if not gui or not template or not template:IsA("LocalScript") then
 warn("[RemoteGuard] RESULT: INCOMPLETE — missing ClientProbe or PlayerGui");doneConn:Disconnect();server:Destroy();root:Destroy();return
end
local probe=template:Clone();probe:SetAttribute("ProbeFolder",root.Name);probe.Disabled=false;probe.Parent=gui
local timeout=os.clock()+30
while not finished and os.clock()<timeout do task.wait(0.1) end
if not finished then
 finished=true;doneConn:Disconnect();server:Destroy();root:Destroy()
 warn("[RemoteGuard] RESULT: INCOMPLETE — client test timed out")
end
