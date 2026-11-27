-- Run from repository root: lua5.4 tests/regression.lua
local Policy, Gate, Context, config, data
if type(dofile) == "function" then
    Policy = dofile("server/TextPolicy.lua")
    Gate = dofile("server/DeliveryGate.lua")
    Context = dofile("server/ContextPolicy.lua")
    config = dofile("server/ChatConfiguration.lua")
    data = dofile("server/ProfanityData.lua")
else
    Policy = require("../server/TextPolicy")
    Gate = require("../server/DeliveryGate")
    Context = require("../server/ContextPolicy")
    config = require("../server/ChatConfiguration")
    data = require("../server/ProfanityData")
end
local check = Policy.new(config, data)
local count = 0
local function expect(value, wanted, label)
    count = count + 1
    assert(value == wanted, label .. ": expected " .. tostring(wanted) .. ", got " .. tostring(value))
end
for _, s in ipairs({"hola", "banana", "cereza", "attack the boss", "kill the NPC", "nice class", "hello ~", "🥵", "12345", "bom dia", "mesa", "asistente"}) do
    expect(check(s), true, "benign")
end
for _, s in ipairs({"IDIOTA", "imbécil", "IMBÉCIL", "imbe" .. utf8.char(0x301) .. "cil", "1diota", "idi" .. utf8.char(0x200B) .. "ota", "hdp", "kill yourself!", "hello, kill yourself", "vou te matar"}) do
    expect(check(s), false, "blocked")
end
expect(check("skill yourselfish"), true, "phrase boundary")
expect(check("ＩＤＩＯＴＡ"), false, "fullwidth ASCII")
expect(check("idio" .. utf8.char(0x2060) .. "ta"), false, "word joiner")
expect(check("idio" .. utf8.char(0x202E) .. "ta"), false, "format control")
expect(check("kill" .. utf8.char(0xA0) .. "yourself"), false, "NBSP separator")
expect(check("kill—yourself"), false, "em dash separator")
expect(check("日本語"), true, "non-Latin text remains native moderated")
expect(check("こんにちは"), true, "unsupported scripts remain native moderated")
expect(check("assistant"), true, "word boundary")
expect(check(""), false, "empty")
expect(check(nil), false, "nil")
expect(check({}), false, "table")
expect(check(string.char(255)), false, "invalid UTF8")
expect(check(string.rep("a", 513)), false, "byte budget")
expect(check(string.rep("a", 65)), false, "token budget")
expect(check(string.rep("a ", 81)), false, "token count")
local fuzzyConfig = {}
for k, v in pairs(config) do fuzzyConfig[k] = v end
fuzzyConfig.EnableFuzzy = true
local fuzzy = Policy.new(fuzzyConfig, data)
expect(fuzzy("pelotud"), false, "one deletion")

expect(fuzzy("pelotxdo"), false, "one substitution")
expect(fuzzy("pelotudoz"), false, "one insertion")
expect(fuzzy("pelxxudo"), true, "two edits")
expect(check("pelotxdo"), true, "fuzzy disabled by default")

local scopeConfig = {ScopeAttributes={Match="MatchId"}}
local context = Context.new(scopeConfig)
local function mockPlayer(group, muted)
    return {GetAttribute=function(_,name)
        if name=="ChatFilterMuted" then return muted end
        if name=="MatchId" then return group end
        error("unexpected attribute")
    end}
end
local p1,p2=mockPlayer("g1"),mockPlayer("g1")
expect(context(p1,p2,"Match"),true,"matching scope")
expect(context(p1,mockPlayer("g2"),"Match"),false,"mismatching scope")
expect(context(p1,mockPlayer(nil),"Match"),false,"missing scope")
expect(context(p1,mockPlayer("g2"),"Other"),true,"unconfigured scope")
expect(context(mockPlayer("g1",true),p2,"Match"),false,"mute before scope")
for _,badMute in ipairs({"false",0,1,{}}) do
    expect(context(mockPlayer("g1",badMute),p2,"Match"),false,"malformed mute fails closed")
end
expect(context(mockPlayer("g1",false),p2,"Match"),true,"explicit unmute")
for _, bad in ipairs({false,true,{},math.huge,-math.huge,0/0,1.5,2^53,"",string.rep("x",65)}) do
    expect(context(mockPlayer(bad),mockPlayer(bad),"Match"),false,"malformed group")
end
expect(context(mockPlayer(42),mockPlayer(42),"Match"),true,"integer scope")
expect(context(mockPlayer("42"),mockPlayer(42),"Match"),false,"no type coercion")
scopeConfig.ScopeAttributes.Match="wrong"
expect(context(p1,p2,"Match"),true,"compiled scope stable")
expect(pcall(Context.new,{ScopeAttributes={Match="ChatFilterMuted"}}),false,"scope mute conflict")
expect(pcall(Context.new,{ScopeAttributes={Match="invalid name"}}),false,"bad scope attribute")
local gate = Gate.new(config)
expect(gate:Admit("A", "id1", 0), true, "first")
for i = 1, 200 do expect(gate:Admit("A", "id1", 0.1), true, "recipient dedup") end
expect(gate:Admit("A", "id2", 0.1), true, "second")
expect(gate:Admit("A", "id3", 0.2), true, "third")
expect(gate:Admit("A", "id4", 0.3), false, "rate limit")
expect(gate:Admit("A", "id4", 1.2), false, "denial stable after rate window")
expect(gate:Admit("A", "id5", 1.2), true, "new window")
expect(gate:Admit("B", "id1", 0), true, "separate sender")
expect(gate:Admit("A", "backwards", 1), false, "clock regression")
expect(gate:Admit("A", "", 2), false, "empty ID")
expect(gate:Admit("A", "badclock", 0/0), false, "nan clock")
expect(gate:Admit("A", "badclock", -1), false, "negative clock")
expect(gate:Admit("A", "badclock", 2^41), false, "clock precision bound")
expect(gate:Admit(nil, "bad", 0), false, "nil sender")
expect(gate:Admit(0/0, "bad", 0), false, "nan sender")
for _,bad in ipairs({false,true,math.huge,-math.huge,"",string.rep("x",129),function() end}) do
    expect(gate:Admit(bad,"bad",0),false,"unsupported sender key")
    expect(gate:Admit("A","bad",2,bad),false,"unsupported scope key")
    gate:Forget(bad)
end
expect(gate:Admit("A", string.rep("a",129), 0), false, "ID length")
gate:Forget(nil)
gate:Forget(0/0)
gate:Forget("A")
expect(gate:Admit("A", "id4", 0), true, "forget")
local tiny = Gate.new({MessagesPerSecond=1, DecisionTTL=2, MaxCachedMessages=2})
expect(tiny:Admit("X", "1", 0), true, "capacity first")
expect(tiny:Admit("X", "2", 0), false, "capacity deny")
expect(tiny:Admit("X", "3", 1.5), false, "capacity full")
expect(tiny:Admit("X", "2", 1.5), false, "cached deny not evicted")
expect(tiny:Admit("X", "3", 2), false, "overflow denial stays stable")
expect(tiny:Admit("X", "4", 4.1), true, "idle quarantine expires")
tiny:Clear()
expect(tiny:Admit("X", "4", 0), true, "clear state")
local channelsGate = Gate.new({MessagesPerSecond=2,DecisionTTL=2,MaxCachedMessages=4})
local ch1,ch2,ch3={},{},{}
expect(channelsGate:Admit("P","same",0,ch1),true,"first channel")
expect(channelsGate:Admit("P","same",0,ch1),true,"same channel duplicate")
expect(channelsGate:Admit("P","same",0,ch2),true,"second channel uses quota")
expect(channelsGate:Admit("P","same",0,ch3),false,"third channel cannot reuse allow")
expect(channelsGate:Admit("P","same",2,ch3),true,"expired scope reused")
expect(channelsGate:Admit("P","same",2,ch1),true,"empty bucket was safely removed")
expect(channelsGate:Admit("P","same",2,ch2),false,"shared quota across scopes")
expect(channelsGate:Admit("P","same",2,0/0),false,"invalid scope")
local boundary = Gate.new({MessagesPerSecond=1,DecisionTTL=2,MaxCachedMessages=3})
expect(boundary:Admit("P","a",0),true,"boundary first")
expect(boundary:Admit("P","b",0),false,"boundary deny")
expect(boundary:Admit("P","b",2),true,"denial expires exactly at TTL")
local ring = Gate.new({MessagesPerSecond=1, DecisionTTL=1, MaxCachedMessages=1})
for i = 0, 1000 do expect(ring:Admit("R", "same", i), true, "ring wraps") end
-- Deterministic malformed/random-byte smoke test; no raw input printed.
local rng = 7
for i = 1, 1000 do
    rng = (rng * 48271) % 2147483647
    local parts = {}
    for j = 1, rng % 40 do
        rng = (rng * 48271) % 2147483647
        parts[j] = string.char(rng % 256)
    end
    local ok, result = pcall(check, table.concat(parts))
    expect(ok, true, "random input does not crash")
    expect(type(result), "boolean", "random input decision type")
end
-- Cross-check one-edit matcher against an independent dynamic-programming reference.
local function distance(a, b)
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local nextRow = {[0] = i}
        for j = 1, #b do
            nextRow[j] = math.min(prev[j]+1, nextRow[j-1]+1, prev[j-1]+(a:byte(i)==b:byte(j) and 0 or 1))
        end
        prev = nextRow
    end
    return prev[#b]
end
local target = "abcdefg"
local synthetic = Policy.new(fuzzyConfig, {Words={target}, Phrases={}, AllowWords={}, BlockSymbols={}})
for i = 1, 2000 do
    rng = (rng * 48271) % 2147483647
    local candidate = target
    for _ = 1, rng % 4 do
        rng = (rng * 48271) % 2147483647
        local pos = 1 + rng % #candidate
        local replacement = string.char(97 + rng % 7)
        local op = rng % 3
        candidate = candidate:sub(1,pos-1) .. (op==0 and "" or replacement)
            .. candidate:sub(op==2 and pos or pos+1)
    end
    local shouldBlock = #candidate >= 6 and distance(candidate,target) <= 1
    expect(synthetic(candidate), not shouldBlock, "differential fuzzy")
end
-- Compare the indexed fuzzy matcher against full edit distance on a multi-word corpus.
-- Synthetic words only: this is an algorithm test, not a language-quality benchmark.
local dictionary = {"abcdef", "abcdefg", "cabdef", "defabc", "abcdefghijklmnop", string.rep("z",32), string.rep("y",33)}
local indexed = Policy.new(fuzzyConfig, {Words=dictionary, Phrases={"alpha beta", "alpha beta gamma", "beta gamma", "delta"}, AllowWords={"abxdef"}, BlockSymbols={}})
local function referenceText(candidate)
    if candidate=="abxdef" then return true end
    for _, word in ipairs(dictionary) do
        if candidate==word or (#word>=6 and #word<=32 and #candidate>=6 and #candidate<=33 and distance(candidate,word)<=1) then return false end
    end
    return true
end
local function checkCandidate(candidate)
    expect(indexed(candidate),referenceText(candidate),"indexed fuzzy differential")
end
for _, word in ipairs(dictionary) do
    checkCandidate(word)
    for pos=1,#word do
        checkCandidate(word:sub(1,pos-1)..word:sub(pos+1))
        for byte=97,122 do
            local c=string.char(byte)
            checkCandidate(word:sub(1,pos-1)..c..word:sub(pos+1))
            checkCandidate(word:sub(1,pos-1)..c..word:sub(pos))
        end
    end
    checkCandidate(word.."x")
end
expect(indexed("alpha beta gamma"),false,"trie shared prefix")
expect(indexed("alpha delta beta"),false,"single token phrase")
expect(indexed("alpha—beta"),false,"trie punctuation")
expect(indexed("alphabet beta"),true,"trie token boundary")
expect(indexed("alpha bet"),true,"trie incomplete phrase")
expect(indexed("abxdef"),true,"fuzzy allow")
expect(pcall(Policy.new,config,{Words={[1]="aaa",[3]="bbb"},Phrases={},AllowWords={},BlockSymbols={}}),false,"sparse array")
expect(pcall(Policy.new,config,{Words={foo="aaa"},Phrases={},AllowWords={},BlockSymbols={}}),false,"named array key")
expect(pcall(Policy.new,config,{Words=setmetatable({},{}),Phrases={},AllowWords={},BlockSymbols={}}),false,"metatable array")
-- Independent ASCII reference for the optimized byte-pattern fast path.
local asciiPolicy=Policy.new(config,{Words={"abcdef","a1b","123"},Phrases={"alpha beta"},AllowWords={},BlockSymbols={}})
local asciiWords={abcdef=true,aib=true,["123"]=true}
local asciiMap={["0"]="o",["1"]="i",["3"]="e",["4"]="a",["5"]="s",["7"]="t"}
local function referenceAscii(input)
    local tokens={}
    local chars={}
    local function flush()
        if #chars==0 then return end
        local token=table.concat(chars)
        chars={}
        if token:match("[a-z]") then
            local out={}
            for j=1,#token do
                local ch=token:sub(j,j)
                out[j]=asciiMap[ch] or ch
            end
            token=table.concat(out)
        end
        tokens[#tokens+1]=token
    end
    for i=1,#input do
        local byte=input:byte(i)
        if byte>=65 and byte<=90 then
            chars[#chars+1]=string.char(byte+32)
        elseif (byte>=97 and byte<=122) or (byte>=48 and byte<=57) then
            chars[#chars+1]=string.char(byte)
        else
            flush()
        end
    end
    flush()
    for i,token in ipairs(tokens) do
        if asciiWords[token] or (token=="alpha" and tokens[i+1]=="beta") then return false end
    end
    return true
end
for byte=0,127 do
    local separator=string.char(byte)
    for _,candidate in ipairs({"alpha"..separator.."beta","x"..separator.."abcdef","a"..separator.."1b","x"..separator.."123","abcdef"..separator.."x"}) do
        expect(asciiPolicy(candidate),referenceAscii(candidate),"all ASCII separators")
    end
end
for i=1,5000 do
    rng=(rng*48271)%2147483647
    local parts={"alpha"}
    for j=1,1+rng%15 do
        rng=(rng*48271)%2147483647
        parts[#parts+1]=string.char(rng%128)
    end
    parts[#parts+1]=(rng%2==0) and "beta" or "abcdef"
    local candidate=table.concat(parts)
    expect(asciiPolicy(candidate),referenceAscii(candidate),"ASCII reference")
end
local unicodeSynthetic=Policy.new(config,{Words={"abcdef"},Phrases={"alpha beta"},AllowWords={},BlockSymbols={}})
for _,cp in ipairs({0xA0,0x1680,0x2000,0x200A,0x2014,0x2028,0x2029,0x202F,0x205F,0x3000}) do
    expect(unicodeSynthetic("alpha"..utf8.char(cp).."beta"),false,"Unicode separator")
end
expect(unicodeSynthetic("ａｂｃｄｅｆ"),false,"fullwidth lowercase")
expect(unicodeSynthetic("Ábçdéf"),false,"accent folding")
expect(unicodeSynthetic("école"),true,"unrelated accented word")
expect(unicodeSynthetic("日本語"),true,"unrelated script")
for _,cp in ipairs({0xA1,0xBF,0xAB,0xBB,0xB7,0x3001,0x3002,0x3008,0x3011,0x2600,0x27BF,0x1F600,0x1F9EA}) do
    local boundary=utf8.char(cp)
    expect(unicodeSynthetic(boundary.."abcdef"..boundary),false,"selected punctuation boundary")
    expect(unicodeSynthetic("hello"..boundary.."world"),true,"punctuation alone not blocked")
end
expect(unicodeSynthetic("🐱"),true,"emoji alone permitted")
expect(unicodeSynthetic("¿hola? ¡bien!"),true,"benign Spanish punctuation")
expect(unicodeSynthetic("alpha🐱beta"),false,"emoji separates phrase tokens")
expect(unicodeSynthetic("a"..utf8.char(0x200D).."bcdef"),false,"selected format control")
-- Independent scan-based model; compare every result and reason with the FIFO.
local function reference(state, id, now, limit, ttl, capacity)
    if now < state.last then return false, "clock_regression" end
    state.last = now
    local entry = state.cache[id]
    if entry and entry.time + ttl > now then return entry.allow, entry.reason end
    local countLive = 0
    for key, value in pairs(state.cache) do
        if value.time + ttl <= now then state.cache[key] = nil else countLive = countLive + 1 end
    end
    if now < state.quarantine or countLive >= capacity then
        state.quarantine = now + ttl
        return false, "cache_capacity"
    end
    state.quarantine = 0
    local current = {}
    for _, time in ipairs(state.accepted) do if now-time < 1 then current[#current+1]=time end end
    state.accepted=current
    local allow=#current < limit
    local reason=allow and "allow" or "rate_limit"
    if allow then current[#current+1]=now end
    state.cache[id]={time=now,allow=allow,reason=reason}
    return allow,reason
end
for _, spec in ipairs({{1,1,1},{3,5,24},{20,60,256},{5,2.5,6},{2,10,32}}) do
    local limit,ttl,capacity=spec[1],spec[2],spec[3]
    local modelGate=Gate.new({MessagesPerSecond=limit,DecisionTTL=ttl,MaxCachedMessages=capacity})
    local models,sequenceTime={},0
    for i=1,20000 do
        rng=(rng*48271)%2147483647
        sequenceTime=sequenceTime+(rng%20)/100
        local sender="S"..(rng%4)
        local model=models[sender]
        if not model then
            model={cache={},accepted={},last=0,quarantine=0}
            models[sender]=model
        end
        if rng%97==0 then
            modelGate:Forget(sender)
            models[sender]=nil
        elseif rng%199==0 then
            modelGate:Clear()
            models={}
        else
            local id="M"..(rng%120)
            local now=sequenceTime
            if rng%41==0 and model.last>1 then now=model.last-0.5 end
            local scope = "C" .. (rng % 3)
            local wanted,reason=reference(model,scope .. ":" .. id,now,limit,ttl,capacity)
            local actual,why=modelGate:Admit(sender,id,now,scope)
            expect(actual,wanted,"reference decision")
            expect(why,reason,"reference reason")
        end
    end
end
-- Bounded exhaustive black-box comparison. Every length-five trace over these
-- nine operations is replayed from an empty gate. This is not an unbounded proof.
local ops={
    {sender="A",scope="X",id="1",delta=0},
    {sender="A",scope="X",id="2",delta=0},
    {sender="A",scope="Y",id="1",delta=0},
    {sender="B",scope="X",id="1",delta=0},
    {sender="A",scope="X",id="1",delta=0.5},
    {sender="A",scope="Y",id="2",delta=1},
    {sender="A",scope="X",id="1",delta=2},
    {forget="A"},
    {clear=true},
}
local traces=0
local path={}
for _, spec in ipairs({{1,1,1},{1,2,2},{2,2,3}}) do
    local limit,ttl,capacity=spec[1],spec[2],spec[3]
    local function replay()
        local gate=Gate.new({MessagesPerSecond=limit,DecisionTTL=ttl,MaxCachedMessages=capacity})
        local models,now={},0
        for _,index in ipairs(path) do
            local op=ops[index]
            if op.clear then gate:Clear() models={}
            elseif op.forget then gate:Forget(op.forget) models[op.forget]=nil
            else
                now=now+op.delta
                local model=models[op.sender]
                if not model then
                    model={cache={},accepted={},last=0,quarantine=0}
                    models[op.sender]=model
                end
                local expected,why=reference(model,op.scope..":"..op.id,now,limit,ttl,capacity)
                local actual,reason=gate:Admit(op.sender,op.id,now,op.scope)
                expect(actual,expected,"exhaustive admission")
                expect(reason,why,"exhaustive reason")
            end
        end
        traces=traces+1
    end
    local function enumerate(depth)
        if depth==5 then replay() return end
        for i=1,#ops do
            path[depth+1]=i
            enumerate(depth+1)
        end
        path[depth+1]=nil
    end
    enumerate(0)
end
assert(traces==3*9^5)
print("PASS: "..traces.." bounded exhaustive admission traces")

-- Exact token/phrase trie versus a simple independent substring-of-token-list oracle.
local vocabulary={"aa","bb","cc","dd","ee"}
local function draw(n)
    rng=(rng*48271)%2147483647
    return rng%n+1
end
local function tokens(n)
    local result={}
    for i=1,n do result[i]=vocabulary[draw(#vocabulary)] end
    return result
end
local function containsSequence(input,pattern)
    for first=1,#input-#pattern+1 do
        local same=true
        for j=1,#pattern do
            if input[first+j-1]~=pattern[j] then same=false break end
        end
        if same then return true end
    end
    return false
end
for _=1,80 do
    local data={Words={},Phrases={},AllowWords={},BlockSymbols={}}
    local patterns={}
    for i=1,draw(5) do
        local p=tokens(1)
        data.Words[i]=p[1]
        patterns[#patterns+1]=p
    end
    for i=1,draw(10) do
        local p=tokens(draw(5))
        data.Phrases[i]=table.concat(p," ")
        patterns[#patterns+1]=p
    end
    local check=Policy.new(config,data)
    for _=1,100 do
        local input=tokens(draw(12))
        local expected=true
        for _,p in ipairs(patterns) do
            if containsSequence(input,p) then expected=false break end
        end
        expect(check(table.concat(input," ")),expected,"generated token sequence oracle")
    end
end
print("PASS: " .. count .. " assertions")
