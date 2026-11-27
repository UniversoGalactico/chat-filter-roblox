-- Large-ring stress against independent non-circular FIFO queues.
-- Integer ticks maintain exact timing; all retained slots bounded by test work.
local seed=20261127
local function rand(n)seed=seed*48271%2147483647;return seed%n end
local function eq(a,b,label)assert(a==b,label..": "..tostring(a).." ~= "..tostring(b).." seed="..seed)end
local function queue()return {head=1,tail=0,data={}}end
local function admit(q,limit,window,t)
 while q.head<=q.tail and t-q.data[q.head]>=window do q.data[q.head]=nil;q.head+=1 end
 if q.tail-q.head+1>=limit then return false,(window-(t-q.data[q.head]))/16 end
 q.tail+=1;q.data[q.tail]=t;return true,nil
end
local operations=0;local totalReasons={}
for scenario=1,4 do
 local tick=0;local base=if scenario==4 then 2^32-100000 else 0
 local subjectCount=if scenario==1 then 128 else 512
 local sharedLimit=if scenario==2 then 8191 else 8192
 local sharedWindow=if scenario==3 then 201 else 64
 local config={Global={Limit=128,Window=64/16},Server={Limit=sharedLimit,Window=sharedWindow/16},MaxSubjects=subjectCount,Clock=function()return base+tick/16 end,Actions={
  A={Quota={Limit=64,Window=32/16},Args={{Type="number",Integer=true,Min=0,Max=100}}},
  B={Quota={Limit=256,Window=80/16},Args={}},
 }}
 local guard=RemoteGuard.new(config);local server=queue();local subjects={}
 for i=1,250000 do
  -- Long bursts, irregular short advances and full expiry create wraparound
  -- and varying expired prefixes. The reference queue never uses modulo.
  if i%97==0 then tick+=rand(4) end
  if i%10007==0 then tick+=rand(256) end
  local id=if scenario==1 and rand(3)==0 then 1 else rand(subjectCount)+1
  local action=if (scenario==1 and id==1) or rand(3)==0 then "A" else "B"
  local subject=subjects[id]
  if not subject then subject={global=queue(),A=queue(),B=queue()};subjects[id]=subject end
  local expected,why,detail=false,nil,nil
  local ok,delay=admit(subject.global,128,64,tick)
  if not ok then why,detail="GLOBAL_LIMIT",delay else
   ok,delay=admit(subject[action],if action=="A" then 64 else 256,if action=="A" then 32 else 80,tick)
   if not ok then why,detail="ACTION_LIMIT",delay else
    ok,delay=admit(server,sharedLimit,sharedWindow,tick)
    if not ok then why,detail="SERVER_LIMIT",delay else expected=true end
   end
  end
  local actual,code,wait
  if action=="A" then actual,code,wait=guard:Check(id,action,rand(101)) else actual,code,wait=guard:Check(id,action) end
  eq(actual,expected,"large ring admission");eq(code,why,"large ring code");eq(wait,detail,"large ring wait")
  totalReasons[code or "ALLOW"]=(totalReasons[code or "ALLOW"] or 0)+1;operations+=1
 end
 guard:Destroy()
end
for _,name in ipairs({"ALLOW","SERVER_LIMIT","GLOBAL_LIMIT","ACTION_LIMIT"}) do assert((totalReasons[name] or 0)>0,"large model uncovered "..name) end
for reason,n in pairs(totalReasons) do print("LARGE_REASON",reason,n) end
print("PASS LARGE MODEL",operations)
