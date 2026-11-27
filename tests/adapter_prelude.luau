-- Minimal service doubles. No claim of Roblox transport or engine scheduling.
local fakePlayers={byId={},listeners={}}
fakePlayers.PlayerRemoving={}
function fakePlayers.PlayerRemoving:Connect(fn)
 local c={connected=true,fn=fn};table.insert(fakePlayers.listeners,c)
 function c:Disconnect() self.connected=false end
 return c
end
function fakePlayers:GetPlayerByUserId(id) return self.byId[id] end
function fakePlayers:add(id)
 local p={_mockInstance=true,Parent=self,UserId=id}
 function p:IsA(class) return class=="Player" end
 self.byId[id]=p;return p
end
function fakePlayers:remove(p,detach)
 for _,c in ipairs(self.listeners) do if c.connected then c.fn(p) end end
 if detach then p.Parent=nil;self.byId[p.UserId]=nil end
end
function fakePlayers:connections()
 local n=0;for _,c in ipairs(self.listeners) do if c.connected then n+=1 end end;return n
end
local fakeRunService={server=true}
function fakeRunService:IsServer() return self.server end
local fakeGame={}
function fakeGame:GetService(name)
 if name=="Players" then return fakePlayers elseif name=="RunService" then return fakeRunService end
 error("unexpected service")
end
local function fakeTypeof(v)
 if type(v)=="table" and rawget(v,"_mockInstance")==true then return "Instance" end
 return typeof(v)
end
