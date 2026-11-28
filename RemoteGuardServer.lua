--!strict
-- Optional Roblox adapter. The owner explicitly connects or assigns callbacks.
local RemoteGuard: any = require(script.Parent.RemoteGuard)
local Players: any = game:GetService("Players")
local RunService: any = game:GetService("RunService")
local RemoteGuardServer = {VERSION="1.0.0"}
type Pending = {Thread: thread, Player: Player}
local MAX_COUNT=2^53-1

-- Check-mode handlers must finish synchronously. Unlike Begin-mode handlers,
-- they have no in-flight reservation; allowing a yield would defeat that limit.
local function typeName(v: any): string return typeof(v) end
local function synchronous(fn: any,...: any): ({[any]: any}?,string?)
 local thread=coroutine.create(fn)
 local results=table.pack(coroutine.resume(thread,...))
 if coroutine.status(thread)~="dead" then
  if task and task.cancel then pcall(task.cancel,thread) end
  pcall(coroutine.close,thread)
  return nil,"HANDLER_YIELDED"
 end
 if not results[1] then return nil,"HANDLER_ERROR" end
 return results,nil
end

function RemoteGuardServer.new(config: any): any
 assert(RunService:IsServer(),"SERVER_ONLY")
 local guard=RemoteGuard.new(config)
 local modes: {[string]: boolean}={}
 for name,action in pairs(config.Actions) do modes[name]=action.MaxInFlight~=nil end
 local active=true
 local departed: {[Player]: boolean}=setmetatable({}, {__mode="k"})
 local pending: {[any]: Pending}={}
 local stats: {[string]: number}={InvalidPlayer=0,HandlerErrors=0,HandlerYields=0,StaleCompletions=0,Reaped=0}
 local function bump(key: string) stats[key]=math.min(MAX_COUNT,stats[key]+1) end
 local function validPlayer(player: any): boolean
  return typeName(player)=="Instance" and player:IsA("Player")==true and player.Parent==Players
   and not departed[player] and Players:GetPlayerByUserId(player.UserId)==player
 end
 local removing=Players.PlayerRemoving:Connect(function(player: Player)
  departed[player]=true
  guard:Forget(player)
 end)
 local server={} :: any
 function server:IsCurrent(token: any): boolean
  if not active or type(token)~="table" then return false end
  local record=pending[token]
  return record~=nil and validPlayer(record.Player) and guard:IsCurrent(token)
 end
 function server:Wrap(action: string,handler: any): any
  assert(active,"DESTROYED")
  assert(type(action)=="string" and modes[action]~=nil,"UNKNOWN_ACTION")
  assert(type(handler)=="function","INVALID_HANDLER")
  local leased=modes[action]
  -- This closure can serve OnServerEvent or OnServerInvoke. It does not bind
  -- itself or expose a client-selected action; only the owner chooses the route.
  return function(player: Player,...: any): ...any
   if not active then return false,"DENIED" end
   if not validPlayer(player) then bump("InvalidPlayer");return false,"DENIED" end
   if not leased then
    if not guard:Check(player,action,...) then return false,"DENIED" end
    local results,err=synchronous(handler,player,nil,...)
    if not results then
     bump(if err=="HANDLER_YIELDED" then "HandlerYields" else "HandlerErrors")
     return false,"HANDLER_ERROR"
    end
    if not active or not validPlayer(player) then bump("StaleCompletions");return false,"DENIED" end
    return true,table.unpack(results,2,results.n)
   end
   local token=guard:Begin(player,action,...)
   if not token then return false,"DENIED" end
   local thread=coroutine.running()
   if not thread then guard:Release(token);bump("HandlerErrors");return false,"HANDLER_ERROR" end
   pending[token]={Thread=thread,Player=player}
   -- pcall supports yielding in Luau. Normal returns and errors release the
   -- permit. Externally closed threads are reaped by Sweep, never by a timeout.
   local results=table.pack(pcall(handler,player,token,...))
   local current=server:IsCurrent(token)
   pending[token]=nil
   guard:Release(token)
   if not results[1] then bump("HandlerErrors");return false,"HANDLER_ERROR" end
   if not current then bump("StaleCompletions");return false,"DENIED" end
   return true,table.unpack(results,2,results.n)
  end
 end
 function server:Sweep(): (number?,number?,string?)
  if not active then return nil,nil,"DESTROYED" end
  local reaped=0
  for token,record in pairs(pending) do
   -- A suspended request might still perform work. Never free it just because
   -- it is slow, a player left, or a clock moved. Only a dead thread is safe.
   if coroutine.status(record.Thread)=="dead" and guard:Release(token) then
    pending[token]=nil;reaped+=1;bump("Reaped")
   end
  end
  local removed,err=guard:Sweep()
  return reaped,removed,err
 end
 function server:GetStats(): {[string]: number}
  local result: {[string]: number}=guard:GetStats()
  for key,value in pairs(stats) do result[key]=value end
  return result
 end
 function server:Destroy(): (boolean,string?)
  if not active then return true,nil end
  local ok,err=guard:Destroy()
  if not ok then return false,err end
  active=false;removing:Disconnect();pending={};modes={};departed=setmetatable({}, {__mode="k"})
  return true,nil
 end
 table.freeze(server)
 return server
end
return table.freeze(RemoteGuardServer)
