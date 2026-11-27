-- Optional asynchronous filtering for ONE-WAY short labels, not conversational text.
local Pipeline = {}
local COOLDOWN, MAX_AGE, MAX_INPUT, MAX_OUTPUT = 60, 20, 128, 512
local function validClock(now)
    return type(now)=="number" and now>=0 and now<=2^40
end
local function validId(id)
    return type(id)=="number" and id>0 and id<=2^53-1 and id%1==0
end
local function isBlank(cp)
    return cp==32 or cp==0xA0 or cp==0x1680 or (cp>=0x2000 and cp<=0x200D)
        or cp==0x202F or cp==0x205F or cp==0x2060 or cp==0x3000 or cp==0xFEFF
        or cp==0xFE0E or cp==0xFE0F
end
local function validText(value, limit)
    if type(value)~="string" or #value==0 or #value>limit or not utf8.len(value) then return false end
    local visible=false
    for _,cp in utf8.codes(value) do
        if cp>0x10FFFF or (cp>=0xD800 and cp<=0xDFFF)
            or cp<32 or (cp>=127 and cp<=159)
            or cp==0x2028 or cp==0x2029
            or (cp>=0x202A and cp<=0x202E) or (cp>=0x2066 and cp<=0x2069) then return false end
        if not isBlank(cp) then visible=true end
    end
    -- A limited blank/control check, not full grapheme or display validation.
    return visible
end
function Pipeline.new(deps, maxConcurrent, supplemental)
    assert(type(maxConcurrent)=="number" and maxConcurrent>=1 and maxConcurrent<=32 and maxConcurrent%1==0)
    assert(supplemental==nil or type(supplemental)=="function")
    local now, identity, claim, beginFilter, broadcast =
        deps.now, deps.identity, deps.claim, deps.beginFilter, deps.broadcast
    assert(type(broadcast)=="function" and type(beginFilter)=="function" and type(claim)=="function"
        and type(identity)=="function" and type(now)=="function", "missing filter dependency")
    local busy, nextAttempt = {}, setmetatable({}, {__mode="k"})
    local active = 0
    return function(player, raw)
        if player==nil then return nil,"invalid_player" end
        if not validText(raw,MAX_INPUT) then return nil,"invalid_text" end
        local ok,id,started=pcall(function() return identity(player),now() end)
        if not ok or not validId(id) then return nil,"invalid_player" end
        if not validClock(started) then return nil,"invalid_clock" end
        if busy[id] then return nil,"busy" end
        local nextTime=nextAttempt[player]
        if nextTime and started<nextTime then return nil,"rate_limit" end
        if active>=maxConcurrent then return nil,"capacity" end
        -- Reserve before any yielding service call. Do not auto-release active work.
        nextAttempt[player]=started+COOLDOWN
        busy[id]=true
        active=active+1
        local function fresh()
            local current=now()
            return validClock(current) and current>=started and current-started<MAX_AGE
                and identity(player)==id
        end
        local success, filtered, reason=pcall(function()
            if supplemental and supplemental(raw)~=true then return nil,"supplemental_denied" end
            if claim(id)~=true then return nil,"rate_limit" end
            if not fresh() then return nil,"stale" end
            local result=beginFilter(raw,id)
            if result==nil then return nil,"filter_error" end
            if not fresh() then return nil,"stale" end
            local text=broadcast(result)
            if not fresh() then return nil,"stale" end
            if not validText(text,MAX_OUTPUT) then return nil,"filter_error" end
            return text,"allow"
        end)
        busy[id]=nil
        active=active-1
        if not success then return nil,"service_error" end
        return filtered,reason
    end
end
return Pipeline
