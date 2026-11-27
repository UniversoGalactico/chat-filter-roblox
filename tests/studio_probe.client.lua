-- LocalScript template cloned into PlayerGui by the Studio-only smoke script.
local root=game:GetService("ReplicatedStorage"):WaitForChild(script:GetAttribute("ProbeFolder"),10)
if not root then warn("[RemoteGuard CLIENT] missing probe folder");return end
local passed,failed=0,0
local function check(name,fn)
 local ok,result=pcall(fn)
 if ok and result==true then passed+=1;print("[RemoteGuard CLIENT] PASS "..name)
 else failed+=1;warn("[RemoteGuard CLIENT] FAIL "..name,ok and tostring(result) or result) end
end
local function invoke(name,...)
 return root:WaitForChild(name,10):InvokeServer(...)
end
local function untilFlag(predicate,seconds)
 local endTime=os.clock()+seconds
 while not predicate() and os.clock()<endTime do task.wait(0.02) end
 return predicate()
end
check("valid record over actual RemoteFunction",function()
 local ok,count=invoke("Shape",{id="apple",count=2});return ok and count==2
end)
check("malformed or extra remote arguments",function()
 return not invoke("Shape",{id="apple",count=0}) and not invoke("Shape",{id="apple",count=2,admin=true})
  and not invoke("Shape",{id="apple",count=2},"extra")
end)
check("Vector3 across network",function()
 local ok,x=invoke("Vector",Vector3.new(3,2,1));return ok and x==3 and not invoke("Vector",Vector3.new(11,0,0))
end)
check("Instance ancestry across network",function()
 local ok,name=invoke("Instance",root:WaitForChild("Allowed"));return ok and name=="Allowed" and not invoke("Instance",workspace) and not invoke("Instance",{Name="Allowed"})
end)
check("actual request quota",function() return invoke("Quota") and invoke("Quota") and not invoke("Quota") end)
check("server authorization denies",function() return not invoke("Permission") end)
check("in-flight remote limit",function()
 local began,returned=false,false;local firstOK,firstResult
 local conn=root:WaitForChild("Started").OnClientEvent:Connect(function()began=true end)
 task.spawn(function()firstOK,firstResult=invoke("Slow");returned=true end)
 local arrived=untilFlag(function()return began end,5)
 local denied=false;if arrived then denied=not invoke("SlowAgain") end
 local released=invoke("Release")
 local ended=untilFlag(function()return returned end,8);conn:Disconnect()
 return arrived and denied and released and ended and firstOK and firstResult=="done"
end)
check("handler error redacted and permit reusable",function()
 local ok,code=invoke("Error");return not ok and code=="HANDLER_ERROR"
end)
check("sync yield denied",function()
 local ok,code=invoke("SyncYield");task.wait(0.2);return not ok and code=="HANDLER_ERROR"
end)
check("actual RemoteEvent rejects malformed payload",function()
 local got=false;local conn=root:WaitForChild("Ack").OnClientEvent:Connect(function()got=true end)
 local event=root:WaitForChild("Event");event:FireServer(2);event:FireServer(1)
 local received=untilFlag(function()return got end,5);conn:Disconnect()
 local ok,count=invoke("EventCount");return received and ok and count==1
end)
root:WaitForChild("Done"):FireServer(passed,failed)
