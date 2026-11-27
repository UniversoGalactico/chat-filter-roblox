--!strict
-- Server-side request admission. No implicit remotes, tasks, or gameplay effects.
local RemoteGuard = {VERSION = "1.0.0-rc.2"}
export type Quota = {Limit: number, Window: number}
export type Argument = {
 Type: string, Optional: boolean?, Min: number?, Max: number?, Integer: boolean?,
 MaxBytes: number?, Choices: {string}?, Fields: {[string]: Argument}?, Items: Argument?, MaxItems: number?, Keys: Argument?, Values: Argument?,
 MaxAbs: number?, Class: string?, Ancestor: Instance?,
}
export type Action = {Quota: Quota, Args: {Argument}, MaxInFlight: number?, Authorize: ((any, ...any) -> boolean)?}
export type Config = {Actions: {[string]: Action}, Global: Quota, Server: Quota?, MaxSubjects: number?, MaxInFlight: number?, MaxInFlightPerSubject: number?, Clock: (() -> number)?}
type Bucket = {Times: {number}, Head: number, Count: number}
type Subject = {Global: Bucket, Actions: {[string]: Bucket}, Last: number, Live: boolean, InFlight: number, Pending: {[string]: number}}
type Lease = {State: Subject, Action: string}
export type Token = {}
type Budget = {Nodes: number, Bytes: number, Active: {[any]: boolean}?}
export type Guard = {
 Check: (self: Guard, subject: any, action: string, ...any) -> (boolean, string?, number?),
 Begin: (self: Guard, subject: any, action: string, ...any) -> (Token?, string?, number?),
 Release: (self: Guard, token: Token) -> (boolean, string?),
 IsCurrent: (self: Guard, token: Token) -> boolean,
 Forget: (self: Guard, subject: any) -> (boolean, string?),
 Sweep: (self: Guard) -> (number?, string?),
 Count: (self: Guard) -> number,
 GetStats: (self: Guard) -> {[string]: number},
 Destroy: (self: Guard) -> (boolean, string?),
}
local MAX_TIME, MAX_COUNT = 2^32, 2^53-1
local function finite(n: any): boolean
 return type(n)=="number" and n==n and math.abs(n)<math.huge
end
local function integer(n: any): boolean return finite(n) and n%1==0 end
local function plain(t: any): boolean return type(t)=="table" and getmetatable(t)==nil end
local function nameValid(n: any): boolean
 return type(n)=="string" and #n>0 and #n<=64 and utf8.len(n)~=nil and string.find(n,"%c")==nil
end
local function fields(t: any, allowed: {[string]: boolean})
 assert(plain(t),"INVALID_CONFIG_TABLE")
 for k in next,t do assert(type(k)=="string" and allowed[k]==true,"UNKNOWN_CONFIG_FIELD") end
end
local function array(t: any, maximum: number): number
 assert(plain(t),"INVALID_ARRAY")
 local count=0
 for k in next,t do
  assert(type(k)=="number" and integer(k) and k>=1 and k<=maximum,"INVALID_ARRAY_INDEX")
  count+=1
 end
 for i=1,count do assert(rawget(t,i)~=nil,"SPARSE_ARRAY") end
 return count
end
local function quota(q: any, maximum: number): Quota
 fields(q,{Limit=true,Window=true})
 assert(integer(q.Limit) and q.Limit>=1 and q.Limit<=maximum,"INVALID_LIMIT")
 assert(finite(q.Window) and q.Window>=0.001 and q.Window<=3600,"INVALID_WINDOW")
 return {Limit=q.Limit,Window=q.Window}
end
local function bucket(): Bucket return {Times={},Head=1,Count=0} end
-- TwoSum residual of now + (-then). Only the rounded-equal boundary needs
-- the residual to decide whether the exact represented interval has elapsed.
local function remaining(now: number, earlier: number, window: number): number
 local d=now-earlier
 if d>window then return 0 end
 if d<window then return window-d end
 local z=d-now
 local residual=(now-(d-z))+(-earlier-z)
 return math.max(0,-residual)
end
local function waitFor(b: Bucket, q: Quota, now: number): number
 if b.Count==0 then return 0 end
 local wait=remaining(now,b.Times[b.Head],q.Window)
 if wait>0 then return if b.Count==q.Limit then wait else 0 end
 -- FIFO order is monotone. Keep old scalar slots for reuse, not references to
 -- requests. An expired prefix can be dropped with O(log Limit) comparisons.
 local last=(b.Head+b.Count-2)%q.Limit+1
 if remaining(now,b.Times[last],q.Window)==0 then
  b.Head,b.Count=1,0
  return 0
 end
 local low,high=1,b.Count-1
 while low<high do
  local mid=math.floor((low+high)/2)
  local index=(b.Head+mid-1)%q.Limit+1
  if remaining(now,b.Times[index],q.Window)==0 then low=mid+1 else high=mid end
 end
 b.Head=(b.Head+low-1)%q.Limit+1
 b.Count-=low
 return 0
end
local function charge(b: Bucket,q: Quota,now: number)
 local i=(b.Head+b.Count-1)%q.Limit+1
 b.Times[i]=now
 b.Count+=1
end
local function validSubject(subject: any): boolean
 local t=type(subject)
 return t=="table" or typeof(subject)=="Instance" or
  (integer(subject) and math.abs(subject)<=MAX_COUNT) or (t=="string" and #subject>0 and #subject<=128)
end
local COMMON: {[string]: boolean}={Type=true,Optional=true}
local RULE_KEYS: {[string]: {[string]: boolean}}={
 number={Min=true,Max=true,Integer=true}, string={MaxBytes=true,Choices=true}, boolean={},
 record={Fields=true}, array={Items=true,MaxItems=true}, map={Keys=true,Values=true,MaxItems=true}, buffer={MaxBytes=true}, Color3={}, Vector2={MaxAbs=true},Vector3={MaxAbs=true},
 Instance={Class=true,Ancestor=true},
}
-- Compile closed, acyclic, bounded schemas; no caller-owned nested rule table survives.
local function compileRule(r: any, depth: number, budget: {number}): Argument
 budget[1]+=1
 assert(depth<=8 and budget[1]<=4096 and plain(r),"SCHEMA_BUDGET_OR_TABLE")
 local kind=r.Type
 assert(type(kind)=="string" and RULE_KEYS[kind]~=nil,"INVALID_TYPE")
 local allowed=RULE_KEYS[kind]
 for k in next,r do assert(type(k)=="string" and (COMMON[k] or allowed[k]),"UNKNOWN_RULE_FIELD") end
 assert(r.Optional==nil or type(r.Optional)=="boolean","INVALID_OPTIONAL")
 local out: Argument={Type=kind,Optional=r.Optional}
 if kind=="number" then
  assert(r.Min==nil or finite(r.Min),"INVALID_MIN")
  assert(r.Max==nil or finite(r.Max),"INVALID_MAX")
  assert(r.Min==nil or r.Max==nil or r.Min<=r.Max,"INVALID_RANGE")
  assert(r.Integer==nil or type(r.Integer)=="boolean","INVALID_INTEGER")
  out.Min,out.Max,out.Integer=r.Min,r.Max,r.Integer
 elseif kind=="string" then
  local max=if r.MaxBytes==nil then 256 else r.MaxBytes
  assert(integer(max) and max>=0 and max<=4096,"INVALID_MAX_BYTES")
  out.MaxBytes=max
  if r.Choices~=nil then
   local choices: {string}={}
   local n=array(r.Choices,64)
   assert(n>0,"EMPTY_CHOICES")
   for i=1,n do
    local choice=r.Choices[i]
    assert(type(choice)=="string" and #choice<=max and utf8.len(choice)~=nil,"INVALID_CHOICE")
    assert(not table.find(choices,choice),"DUPLICATE_CHOICE")
    budget[1]+=1;assert(budget[1]<=4096,"SCHEMA_BUDGET")
    choices[i]=choice
   end
   out.Choices=choices
  end
 elseif kind=="record" then
  assert(plain(r.Fields),"INVALID_FIELDS")
  local children: {[string]: Argument}={}
  local count=0
  for k,child in next,r.Fields do
   count+=1;assert(type(k)=="string" and nameValid(k) and count<=64,"INVALID_FIELD_NAME")
   children[k]=compileRule(child,depth+1,budget)
  end
  out.Fields=children
 elseif kind=="array" or kind=="map" then
  local max=if r.MaxItems==nil then 32 else r.MaxItems
  assert(integer(max) and max>=0 and max<=256,"INVALID_MAX_ITEMS")
  out.MaxItems=max
  if kind=="array" then
   local item=compileRule(r.Items,depth+1,budget)
   assert(not item.Optional,"OPTIONAL_ARRAY_ITEM")
   out.Items=item
  else
   local key=compileRule(r.Keys,depth+1,budget)
   local value=compileRule(r.Values,depth+1,budget)
   assert(key.Type=="string" and not key.Optional and not value.Optional,"INVALID_MAP_RULE")
   out.Keys,out.Values=key,value
  end
 elseif kind=="buffer" then
  assert(integer(r.MaxBytes) and r.MaxBytes>=0 and r.MaxBytes<=16384,"INVALID_BUFFER_BOUND")
  out.MaxBytes=r.MaxBytes
 elseif kind=="Vector2" or kind=="Vector3" then
  assert(finite(r.MaxAbs) and r.MaxAbs>=0 and r.MaxAbs<=1e30,"INVALID_VECTOR_BOUND")
  out.MaxAbs=r.MaxAbs
 elseif kind=="Instance" then
  assert(nameValid(r.Class) and typeof(r.Ancestor)=="Instance","INVALID_INSTANCE_RULE")
  out.Class,out.Ancestor=r.Class,r.Ancestor
 end
 return out
end
local function validArg(v: any, r: Argument, budget: Budget): boolean
 budget.Nodes+=1
 if budget.Nodes>512 then return false end
 if v==nil then return r.Optional==true end
 local kind=r.Type
 if kind=="number" then
  return finite(v) and (not r.Integer or v%1==0) and (r.Min==nil or v>=r.Min) and (r.Max==nil or v<=r.Max)
 elseif kind=="string" then
  if type(v)~="string" or #v>(r.MaxBytes :: number) then return false end
  budget.Bytes+=#v
  return budget.Bytes<=16384 and utf8.len(v)~=nil and (r.Choices==nil or table.find(r.Choices,v)~=nil)
 elseif kind=="boolean" then return type(v)=="boolean"
 elseif kind=="Vector2" or kind=="Vector3" then
  if typeof(v)~=kind then return false end
  local max=r.MaxAbs :: number
  return finite(v.X) and math.abs(v.X)<=max and finite(v.Y) and math.abs(v.Y)<=max
   and (kind=="Vector2" or (finite(v.Z) and math.abs(v.Z)<=max))
 elseif kind=="Color3" then
  return typeof(v)=="Color3" and finite(v.R) and v.R>=0 and v.R<=1
   and finite(v.G) and v.G>=0 and v.G<=1 and finite(v.B) and v.B>=0 and v.B<=1
 elseif kind=="buffer" then
  if typeof(v)~="buffer" then return false end
  local length=buffer.len(v)
  budget.Bytes+=length
  return length<=(r.MaxBytes :: number) and budget.Bytes<=16384
 elseif kind=="Instance" then
  if typeof(v)~="Instance" then return false end
  local ok,allowed=pcall(function()
   return v:IsA(r.Class :: string) and v:IsDescendantOf(r.Ancestor :: Instance)
  end)
  return ok and allowed==true
 end
 if not plain(v) then return false end
 local active=budget.Active
 if active==nil then active={};budget.Active=active end
 if active[v] then return false end
 active[v]=true
 if kind=="record" then
  local children=r.Fields :: {[string]: Argument}
  for k in next,v do
   if type(k)~="string" or #k>64 or children[k]==nil then return false end
   budget.Bytes+=#k
   if budget.Bytes>16384 then return false end
  end
  for k,child in pairs(children) do
   if not validArg(rawget(v,k),child,budget) then return false end
  end
 elseif kind=="map" then
  local count=0
  for k,x in next,v do
   count+=1
   if count>(r.MaxItems :: number) or not validArg(k,r.Keys :: Argument,budget)
    or not validArg(x,r.Values :: Argument,budget) then return false end
  end
 else
  local count,largest=0,0
  local max=r.MaxItems :: number
  for k,x in next,v do
   if type(k)~="number" or not integer(k) or k<1 or k>max then return false end
   count+=1;largest=math.max(largest,k)
   if not validArg(x,r.Items :: Argument,budget) then return false end
  end
  if count~=largest then return false end
 end
 active[v]=nil
 return true
end
local function invoke(fn: any,...: any): (boolean,any)
 local thread=coroutine.create(fn)
 local ok,value=coroutine.resume(thread,...)
 if coroutine.status(thread)~="dead" then
  if task and task.cancel then pcall(task.cancel,thread) end
  pcall(coroutine.close,thread)
  return false,"CALLBACK_YIELDED"
 end
 if not ok then return false,"CALLBACK_ERROR" end
 return true,value
end
function RemoteGuard.new(config: Config): Guard
 fields(config,{Actions=true,Global=true,Server=true,MaxSubjects=true,MaxInFlight=true,MaxInFlightPerSubject=true,Clock=true})
 local global=quota(config.Global,256)
 local server=if config.Server==nil then nil else quota(config.Server,8192)
 local serverBucket=bucket()
 local capacity=if config.MaxSubjects==nil then 256 else config.MaxSubjects
 assert(integer(capacity) and capacity>=1 and capacity<=4096,"INVALID_CAPACITY")
 local flightLimit=if config.MaxInFlight==nil then 128 else config.MaxInFlight
 local subjectLimit=if config.MaxInFlightPerSubject==nil then math.min(4,flightLimit) else config.MaxInFlightPerSubject
 assert(integer(flightLimit) and flightLimit>=1 and flightLimit<=4096,"INVALID_IN_FLIGHT")
 assert(integer(subjectLimit) and subjectLimit>=1 and subjectLimit<=flightLimit,"INVALID_SUBJECT_IN_FLIGHT")
 assert(config.Clock==nil or type(config.Clock)=="function","INVALID_CLOCK")
 local clock=config.Clock
 local actions: {[string]: Action}={}
 assert(plain(config.Actions),"INVALID_ACTIONS")
 local actionCount,slots,maxWindow=0,global.Limit,global.Window
 local schemaBudget={0}
 for name,a in next,config.Actions do
  actionCount+=1
  assert(actionCount<=64 and nameValid(name),"INVALID_ACTION")
  fields(a,{Quota=true,Args=true,MaxInFlight=true,Authorize=true})
  assert(a.Authorize==nil or type(a.Authorize)=="function","INVALID_AUTHORIZE")
  local args: {Argument}={}
  local optional=false
  for i=1,array(a.Args,16) do
   local r=compileRule(a.Args[i],1,schemaBudget)
   assert(not optional or r.Optional==true,"OPTIONAL_MUST_BE_TRAILING")
   optional=r.Optional==true
   args[i]=r
  end
  local q=quota(a.Quota,256)
  local inFlight=a.MaxInFlight
  assert(inFlight==nil or (integer(inFlight) and inFlight>=1 and inFlight<=subjectLimit),"INVALID_ACTION_IN_FLIGHT")
  slots+=q.Limit;maxWindow=math.max(maxWindow,q.Window)
  actions[name]={Quota=q,Args=args,MaxInFlight=inFlight,Authorize=a.Authorize}
 end
 assert(actionCount>0,"NO_ACTIONS")
 assert(capacity*slots+(if server then server.Limit else 0)<=1000000,"TIMESTAMP_BUDGET")
 local subjects: {[any]: Subject}={}
 local stats: {[string]: number}={Allowed=0,Denied=0}
 local count,last,inFlight=0,0,0
 local leases: {[Token]: Lease}={}
 local hasClock,busy,destroyed=false,false,false
 local guard={} :: any
 local function timeNow(): (number?,string?)
  local now: any
  if clock then
   busy=true;local ran,value=invoke(clock);busy=false
   if not ran then return nil,"INVALID_CLOCK" end
   now=value
  else now=os.clock() end
  if not finite(now) or now<0 or now>MAX_TIME then return nil,"INVALID_CLOCK" end
  if hasClock and now<last then return nil,"CLOCK_REGRESSION" end
  last,hasClock=now,true
  return now,nil
 end
 local function check(acquire: boolean, subject: any, action: any, ...: any): (boolean,string?,number?,Subject?)
  if destroyed then return false,"DESTROYED",nil,nil end
  if busy then return false,"BUSY",nil,nil end
  if not validSubject(subject) then return false,"INVALID_SUBJECT",nil,nil end
  if type(action)~="string" or #action>64 then return false,"UNKNOWN_ACTION",nil,nil end
  local a=actions[action]
  if a==nil then return false,"UNKNOWN_ACTION",nil,nil end
  if acquire~=(a.MaxInFlight~=nil) then
   return false,if acquire then "NOT_LEASE_ACTION" else "ACQUIRE_REQUIRED",nil,nil
  end
  local now,err=timeNow()
  if now==nil then return false,err,nil,nil end
  local s=subjects[subject]
  if s==nil then
   if count>=capacity then return false,"CAPACITY",nil,nil end
   s={Global=bucket(),Actions={},Last=now,Live=true,InFlight=0,Pending={}};subjects[subject]=s;count+=1
  end
  local globalWait=waitFor(s.Global,global,now)
  if globalWait>0 then return false,"GLOBAL_LIMIT",globalWait,nil end
  charge(s.Global,global,now);s.Last=now
  local b=s.Actions[action]
  if b==nil then b=bucket();s.Actions[action]=b end
  local actionWait=waitFor(b,a.Quota,now)
  if actionWait>0 then return false,"ACTION_LIMIT",actionWait,nil end
  charge(b,a.Quota,now)
  -- Server quota bounds expensive validation across all subjects. Per-subject
  -- quotas are charged first so one attacker cannot bypass its own budget.
  if server then
   local serverWait=waitFor(serverBucket,server,now)
   if serverWait>0 then return false,"SERVER_LIMIT",serverWait,nil end
   charge(serverBucket,server,now)
  end
  if acquire then
   if inFlight>=flightLimit then return false,"SERVER_IN_FLIGHT",nil,nil end
   if s.InFlight>=subjectLimit then return false,"SUBJECT_IN_FLIGHT",nil,nil end
   if (s.Pending[action] or 0)>=(a.MaxInFlight :: number) then return false,"ACTION_IN_FLIGHT",nil,nil end
  end
  local n=select("#",...)
  if n>#a.Args then return false,"ARG_COUNT",nil,nil end
  local budget: Budget={Nodes=0,Bytes=0}
  for i,r in ipairs(a.Args) do
   local value: any=if i<=n then select(i,...) else nil
   if not validArg(value,r,budget) then return false,"INVALID_ARGUMENT",i,nil end
  end
  if a.Authorize then
   busy=true;local ok,value=invoke(a.Authorize,subject,...);busy=false
   if not ok then return false,value,nil,nil end
   if value~=true then return false,"UNAUTHORIZED",nil,nil end
  end
  return true,nil,nil,s
 end
 local function record(ok: boolean, code: string?)
  local category=if ok then "Allowed" else "Denied"
  stats[category]=math.min(MAX_COUNT,stats[category]+1)
  if code then stats[code]=math.min(MAX_COUNT,(stats[code] or 0)+1) end
 end
 function guard:Check(subject: any,action: any,...: any): (boolean,string?,number?)
  local ok,code,detail=check(false,subject,action,...)
  record(ok,code)
  return ok,code,detail
 end
 function guard:Begin(subject: any,action: any,...: any): (Token?,string?,number?)
  local ok,code,detail,s=check(true,subject,action,...)
  record(ok,code)
  if not ok or s==nil then return nil,code,detail end
  local token: Token={}
  table.freeze(token)
  leases[token]={State=s,Action=action}
  inFlight+=1;s.InFlight+=1;s.Pending[action]=(s.Pending[action] or 0)+1
  return token,nil,nil
 end
 function guard:Release(token: any): (boolean,string?)
  if destroyed then return false,"DESTROYED" end
  if busy then return false,"BUSY" end
  if type(token)~="table" then return false,"INVALID_TOKEN" end
  local lease=leases[token]
  if lease==nil then return false,"INVALID_TOKEN" end
  leases[token]=nil
  local s,action=lease.State,lease.Action
  s.InFlight-=1;s.Pending[action]-=1;inFlight-=1
  return true,nil
 end
 function guard:IsCurrent(token: any): boolean
  if destroyed or type(token)~="table" then return false end
  local lease=leases[token]
  return lease~=nil and lease.State.Live
 end
 function guard:Forget(subject: any): (boolean,string?)
  if destroyed then return false,"DESTROYED" end
  if busy then return false,"BUSY" end
  if not validSubject(subject) then return false,"INVALID_SUBJECT" end
  local s=subjects[subject]
  if s==nil then return false,"NOT_FOUND" end
  s.Live=false;s.Global=bucket();s.Actions={};subjects[subject]=nil;count-=1
  return true,nil
 end
 function guard:Sweep(): (number?,string?)
  if destroyed then return nil,"DESTROYED" end
  if busy then return nil,"BUSY" end
  local now,err=timeNow();if now==nil then return nil,err end
  local removed=0
  -- Last charged attempt is no earlier than any retained timestamp. Never
  -- evict an active quota or reset the shared server window.
  for subject,s in pairs(subjects) do
   if s.InFlight==0 and remaining(now,s.Last,maxWindow)==0 then s.Live=false;subjects[subject]=nil;removed+=1 end
  end
  count-=removed
  return removed,nil
 end
 function guard:Count(): number return count end
 function guard:GetStats(): {[string]: number}
  local result=table.clone(stats);result.Subjects=count;result.InFlight=inFlight
  return result
 end
 function guard:Destroy(): (boolean,string?)
  if busy then return false,"BUSY" end
  if destroyed then return true,nil end
  destroyed=true;clock=nil;subjects={};actions={};serverBucket=bucket();leases={};count=0;inFlight=0
  return true,nil
 end
 table.freeze(guard)
 return guard :: Guard
end
return table.freeze(RemoteGuard)
