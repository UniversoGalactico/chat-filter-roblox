-- Independent list-based reference model. All times are integer ticks / 16.
-- No ring arithmetic, schema compiler, or token implementation shared with target.
local seed=8753181
local function rand(n) seed=(seed*48271)%2147483647;return seed%n end
local operations=0
local reasons={}
local function eq(a,b,label) assert(a==b,label..": "..tostring(a).." ~= "..tostring(b).." seed="..seed) end
local function admit(list,limit,window,t)
 local kept={}
 for _,x in ipairs(list) do if t-x<window then kept[#kept+1]=x end end
 if #kept>=limit then return kept,false,(window-(t-kept[1]))/16 end
 kept[#kept+1]=t;return kept,true,nil
end
for campaign=1,64 do
 local tick=0;local limit=rand(7)+1;local window=rand(64)+1
 local serverLimit=rand(20)+1;local serverWindow=rand(80)+1
 local maxSubjects=rand(8)+1;local maxFlight=rand(7)+1;local maxSubjectFlight=rand(maxFlight)+1
 local actionLimits={rand(4)+1,rand(5)+1,rand(7)+1}
 local actionWindows={rand(48)+1,rand(64)+1,rand(96)+1}
 local flightLimits={rand(maxSubjectFlight)+1,rand(maxSubjectFlight)+1,0}
 local maxWindow=math.max(window,table.unpack(actionWindows))
 local cfg={Global={Limit=limit,Window=window/16},Server={Limit=serverLimit,Window=serverWindow/16},MaxSubjects=maxSubjects,MaxInFlight=maxFlight,MaxInFlightPerSubject=maxSubjectFlight,Clock=function() return tick/16 end,Actions={}}
 for i=1,3 do
  cfg.Actions[tostring(i)]={Quota={Limit=actionLimits[i],Window=actionWindows[i]/16},Args={{Type="number",Integer=true,Min=0,Max=9}},MaxInFlight=if i<3 then flightLimits[i] else nil,
   Authorize=function(_,n) return n~=9 end}
 end
 local g=RemoteGuard.new(cfg);local subjects={};local all={};local server={};local count=0;local totalFlight=0;local accepted=0;local denied=0
 local function expected(id,a,begin,n)
  if begin~=(a<3) then return false,if begin then "NOT_LEASE_ACTION" else "ACQUIRE_REQUIRED" end
  local s=subjects[id]
  if not s then
   if count>=maxSubjects then return false,"CAPACITY" end
   s={global={},actions={{},{},{}},last=tick,live=true,flight=0,pending={0,0,0}}
   subjects[id]=s;count+=1
  end
  local ok,delay
  s.global,ok,delay=admit(s.global,limit,window,tick)
  if not ok then return false,"GLOBAL_LIMIT",delay end
  s.last=tick
  s.actions[a],ok,delay=admit(s.actions[a],actionLimits[a],actionWindows[a],tick)
  if not ok then return false,"ACTION_LIMIT",delay end
  server,ok,delay=admit(server,serverLimit,serverWindow,tick)
  if not ok then return false,"SERVER_LIMIT",delay end
  if begin then
   if totalFlight>=maxFlight then return false,"SERVER_IN_FLIGHT" end
   if s.flight>=maxSubjectFlight then return false,"SUBJECT_IN_FLIGHT" end
   if s.pending[a]>=flightLimits[a] then return false,"ACTION_IN_FLIGHT" end
  end
  if n<0 or n>9 then return false,"INVALID_ARGUMENT",1 end
  if n==9 then return false,"UNAUTHORIZED" end
  if begin then s.flight+=1;s.pending[a]+=1;totalFlight+=1 end
  return true,nil,nil,s
 end
 for step=1,8000 do
  local op=rand(100);local id=rand(12)+1
  if op<60 then
   local a=rand(3)+1;local begin=if rand(10)==0 then a==3 else a<3
   local value=rand(12)-1
   local expectedOk,code,detail,s=expected(id,a,begin,value)
   local ok,why,d,token
   if begin then token,why,d=g:Begin(id,tostring(a),value);ok=token~=nil
   else ok,why,d=g:Check(id,tostring(a),value) end
   eq(ok,expectedOk,"admission");eq(why,code,"reason");eq(d,detail,"detail")
   reasons[why or "ALLOW"]=(reasons[why or "ALLOW"] or 0)+1
   if ok then accepted+=1 else denied+=1 end
   if token then all[#all+1]={token=token,s=s,action=a,active=true};eq(g:IsCurrent(token),true,"new token") end
  elseif op<76 then
   local index=if #all>0 then rand(#all)+1 else 0
   local record=all[index]
   if record then
    eq(g:IsCurrent(record.token),record.active and record.s.live,"token status")
    local ok=g:Release(record.token);eq(ok,record.active,"release")
    if record.active then record.active=false;record.s.flight-=1;record.s.pending[record.action]-=1;totalFlight-=1 end
    if rand(2)==0 then eq(g:Release(record.token),false,"duplicate release") end
   else eq(g:Release({}),false,"foreign token") end
  elseif op<84 then
   local s=subjects[id];eq(g:Forget(id),s~=nil,"forget")
   if s then s.live=false;subjects[id]=nil;count-=1 end
  elseif op<91 then
   local removed=0
   for key,s in pairs(subjects) do
    if s.flight==0 and tick-s.last>=maxWindow then s.live=false;subjects[key]=nil;removed+=1 end
   end
   count-=removed;eq(g:Sweep(),removed,"sweep")
  else tick+=rand(200) end
  local stats=g:GetStats();eq(stats.Subjects,count,"subjects");eq(stats.InFlight,totalFlight,"in flight");eq(stats.Allowed,accepted,"accepted stats");eq(stats.Denied,denied,"denied stats")
  operations+=1
 end
 eq(g:Destroy(),true,"destroy");eq(g:GetStats().InFlight,0,"destroy count")
 for _,record in ipairs(all) do eq(g:IsCurrent(record.token),false,"destroy token") end
end
for _,code in ipairs({"GLOBAL_LIMIT","ACTION_LIMIT","SERVER_LIMIT","SERVER_IN_FLIGHT","SUBJECT_IN_FLIGHT","ACTION_IN_FLIGHT","INVALID_ARGUMENT","UNAUTHORIZED","CAPACITY","ACQUIRE_REQUIRED","NOT_LEASE_ACTION","ALLOW"}) do assert((reasons[code] or 0)>0,"uncovered "..code);print("MODEL_REASON",code,reasons[code]) end
print("PASS MODEL",operations)
