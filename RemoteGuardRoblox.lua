--!strict
-- Server-side request admission. No remote binding or gameplay side effects.
local RemoteGuard = {VERSION = "1.0.0-rc.1"}
export type Quota = {Limit: number, Window: number}
export type Argument = {Type: string, Min: number?, Max: number?, Integer: boolean?, MaxBytes: number?, Optional: boolean?}
export type Action = {Quota: Quota, Args: {Argument}, Authorize: ((any, ...any) -> boolean)?}
export type Config = {Actions: {[string]: Action}, Global: Quota, MaxSubjects: number?, Clock: (() -> number)?}
type Bucket = {Times: {number}, Head: number, Count: number}
type Subject = {Global: Bucket, Actions: {[string]: Bucket}}
export type Guard = {
	Check: (self: Guard, subject: any, action: string, ...any) -> (boolean, string?, number?),
	Forget: (self: Guard, subject: any) -> (boolean, string?),
	Count: (self: Guard) -> number,
	Destroy: (self: Guard) -> (boolean, string?),
}
local function finite(n: any): boolean
	return type(n)=="number" and n==n and math.abs(n)<math.huge
end
local function integer(n: any): boolean
	return finite(n) and n%1==0
end
local function fields(t: any, allowed: {[string]: boolean})
	assert(type(t)=="table" and getmetatable(t)==nil,"INVALID_CONFIG_TABLE")
	for k in next,t do assert(allowed[k]==true,"UNKNOWN_CONFIG_FIELD") end
end
local function array(t: any, maximum: number): number
	assert(type(t)=="table" and getmetatable(t)==nil,"INVALID_ARRAY")
	local count=0
	for k in next,t do
		assert(integer(k) and k>=1 and k<=maximum,"INVALID_ARRAY_INDEX")
		count+=1
	end
	for i=1,count do assert(rawget(t,i)~=nil,"SPARSE_ARRAY") end
	return count
end
local function quota(q: any): Quota
	fields(q,{Limit=true,Window=true})
	assert(integer(q.Limit) and q.Limit>=1 and q.Limit<=256,"INVALID_LIMIT")
	assert(finite(q.Window) and q.Window>=0.001 and q.Window<=3600,"INVALID_WINDOW")
	return {Limit=q.Limit,Window=q.Window}
end
local function bucket(): Bucket
	return {Times={},Head=1,Count=0}
end
local function waitFor(b: Bucket, q: Quota, now: number): number
	while b.Count>0 and now-b.Times[b.Head]>=q.Window do
		b.Times[b.Head]=nil
		b.Head=b.Head%q.Limit+1
		b.Count-=1
	end
	if b.Count<q.Limit then return 0 end
	return math.max(0,q.Window-(now-b.Times[b.Head]))
end
local function charge(b: Bucket,q: Quota,now: number)
	local i=(b.Head+b.Count-1)%q.Limit+1
	b.Times[i]=now
	b.Count+=1
end
local function validSubject(subject: any): boolean
	-- Trusted server-owned identity, normally the Player instance itself.
	local t=type(subject)
	return t=="table" or typeof(subject)=="Instance" or
		(integer(subject) and math.abs(subject)<=2^53-1) or
		(t=="string" and #subject>0 and #subject<=128)
end
local function validArg(v: any, rule: Argument): boolean
	if v==nil then return rule.Optional==true end
	if rule.Type=="number" then
		return finite(v) and (not rule.Integer or v%1==0)
			and (rule.Min==nil or v>=rule.Min) and (rule.Max==nil or v<=rule.Max)
	elseif rule.Type=="string" then
		return type(v)=="string" and #v<=(rule.MaxBytes or 256) and utf8.len(v)~=nil
	elseif rule.Type=="boolean" then
		return type(v)=="boolean"
	end
	return false
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
	fields(config,{Actions=true,Global=true,MaxSubjects=true,Clock=true})
	local global=quota(config.Global)
	local capacity=if config.MaxSubjects==nil then 256 else config.MaxSubjects
	assert(integer(capacity) and capacity>=1 and capacity<=4096,"INVALID_CAPACITY")
	assert(config.Clock==nil or type(config.Clock)=="function","INVALID_CLOCK")
	local clock=config.Clock or os.clock
	local actions: {[string]: Action}={}
	assert(type(config.Actions)=="table" and getmetatable(config.Actions)==nil,"INVALID_ACTIONS")
	local actionCount=0
	for name,a in next,config.Actions do
		actionCount+=1
		assert(actionCount<=64 and type(name)=="string" and #name>0 and #name<=64,"INVALID_ACTION")
		fields(a,{Quota=true,Args=true,Authorize=true})
		assert(a.Authorize==nil or type(a.Authorize)=="function","INVALID_AUTHORIZE")
		local args: {Argument}={}
		local optional=false
		for i=1,array(a.Args,16) do
			local r=a.Args[i]
			fields(r,{Type=true,Min=true,Max=true,Integer=true,MaxBytes=true,Optional=true})
			assert(r.Type=="number" or r.Type=="string" or r.Type=="boolean","INVALID_TYPE")
			assert(r.Optional==nil or type(r.Optional)=="boolean","INVALID_OPTIONAL")
			assert(not optional or r.Optional==true,"OPTIONAL_MUST_BE_TRAILING")
			optional=r.Optional==true
			if r.Type=="number" then
				assert(r.Min==nil or finite(r.Min),"INVALID_MIN")
				assert(r.Max==nil or finite(r.Max),"INVALID_MAX")
				assert(r.Min==nil or r.Max==nil or r.Min<=r.Max,"INVALID_RANGE")
				assert(r.Integer==nil or type(r.Integer)=="boolean","INVALID_INTEGER")
				assert(r.MaxBytes==nil,"INVALID_NUMBER_RULE")
			elseif r.Type=="string" then
				assert(r.MaxBytes==nil or (integer(r.MaxBytes) and r.MaxBytes>=0 and r.MaxBytes<=4096),"INVALID_MAX_BYTES")
				assert(r.Min==nil and r.Max==nil and r.Integer==nil,"INVALID_STRING_RULE")
			else
				assert(r.Min==nil and r.Max==nil and r.Integer==nil and r.MaxBytes==nil,"INVALID_BOOLEAN_RULE")
			end
			args[i]=table.clone(r)
		end
		actions[name]={Quota=quota(a.Quota),Args=args,Authorize=a.Authorize}
	end
	assert(actionCount>0,"NO_ACTIONS")
	-- Worst-case timestamp slots are bounded by the global quota and configured
	-- per-action quotas, even for idle subjects; callers must Forget on departure.
	local subjects: {[any]: Subject}={}
	local count,last=0,0
	local hasClock,busy,destroyed=false,false,false
	local guard={} :: any
	function guard:Check(subject: any, action: any, ...: any): (boolean,string?,number?)
		if destroyed then return false,"DESTROYED",nil end
		if busy then return false,"BUSY",nil end
		if not validSubject(subject) then return false,"INVALID_SUBJECT",nil end
		if type(action)~="string" or #action>64 then return false,"UNKNOWN_ACTION",nil end
		local a=actions[action]
		if a==nil then return false,"UNKNOWN_ACTION",nil end
		busy=true
		local ran,now=invoke(clock)
		busy=false
		if not ran or not finite(now) or now<0 or now>2^32 then return false,"INVALID_CLOCK",nil end
		if hasClock and now<last then return false,"CLOCK_REGRESSION",nil end
		last,hasClock=now,true
		local s=subjects[subject]
		if s==nil then
			if count>=capacity then return false,"CAPACITY",nil end
			s={Global=bucket(),Actions={}}
			subjects[subject]=s
			count+=1
		end
		local globalWait=waitFor(s.Global,global,now)
		if globalWait>0 then return false,"GLOBAL_LIMIT",globalWait end
		-- Every globally admitted known-action attempt consumes a slot, even
		-- when action quota, argument validation or authorization rejects it.
		charge(s.Global,global,now)
		local b=s.Actions[action]
		if b==nil then b=bucket(); s.Actions[action]=b end
		local actionWait=waitFor(b,a.Quota,now)
		if actionWait>0 then return false,"ACTION_LIMIT",actionWait end
		charge(b,a.Quota,now)
		local n=select("#",...)
		if n>#a.Args then return false,"ARG_COUNT",nil end
		for i,r in ipairs(a.Args) do
			if not validArg(select(i,...),r) then return false,"INVALID_ARGUMENT",i end
		end
		if a.Authorize then
			busy=true
			local ok,value=invoke(a.Authorize,subject,...)
			busy=false
			if not ok then return false,value,nil end
			if value~=true then return false,"UNAUTHORIZED",nil end
		end
		return true,nil,nil
	end
	function guard:Forget(subject: any): (boolean,string?)
		if destroyed then return false,"DESTROYED" end
		if busy then return false,"BUSY" end
		if not validSubject(subject) then return false,"INVALID_SUBJECT" end
		if subjects[subject]==nil then return false,"NOT_FOUND" end
		subjects[subject]=nil
		count-=1
		return true,nil
	end
	function guard:Count(): number return count end
	function guard:Destroy(): (boolean,string?)
		if busy then return false,"BUSY" end
		if destroyed then return true,nil end
		destroyed=true
		table.clear(subjects)
		table.clear(actions)
		count=0
		return true,nil
	end
	table.freeze(guard)
	return guard :: Guard
end
return table.freeze(RemoteGuard)
