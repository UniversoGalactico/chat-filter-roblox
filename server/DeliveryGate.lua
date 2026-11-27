-- Bounded, non-yielding message admission. Roblox invokes delivery once per recipient.
-- Cache only the message ID, expiry and boolean; never the message text.
local DeliveryGate = {}
local reasons = { allow=true, invalid_length=true, invalid_utf8=true, complexity_limit=true, symbol=true, phrase=true, word=true, fuzzy=true, text_unavailable=true }
function DeliveryGate.new(config)
    local limit, ttl, capacity = config.MessagesPerSecond, config.DecisionTTL, config.MaxCachedMessages
    assert(type(limit) == "number" and limit >= 1 and limit <= 20 and limit % 1 == 0)
    assert(type(ttl) == "number" and ttl >= 1 and ttl <= 60)
    assert(type(capacity) == "number" and capacity >= limit and capacity <= 256 and capacity % 1 == 0)
    local senders = setmetatable({}, { __mode = "k" })
    local gate = {}

    function gate:Forget(sender)
        senders[sender] = nil
    end
    function gate:Clear()
        for sender in pairs(senders) do senders[sender] = nil end
    end

    function gate:Decide(sender, messageId, now, evaluate)
        if sender == nil or type(messageId) ~= "string" or #messageId == 0 or #messageId > 128 then
            return false, "invalid_identity"
        end
        if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge then
            return false, "invalid_clock"
        end
        local state = senders[sender]
        if not state then
            state = { cache = {}, attempts = {}, count = 0, last = now }
            senders[sender] = state
        end
        if now < state.last then return false, "clock_regression" end
        state.last = now
        local cached = state.cache[messageId]
        if cached and cached.expires > now then return cached.allow, cached.reason end
        -- Keep all live decisions, including denials. Never evict an unexpired deny.
        for id, decision in pairs(state.cache) do
            if decision.expires <= now then
                state.cache[id] = nil
                state.count = state.count - 1
            end
        end
        -- Saturation quarantine: every unseen decision denied during overflow stays
        -- denied for at least TTL from its most recent callback, without storing IDs.
        if (state.overflowUntil and state.overflowUntil > now) or state.count >= capacity then
            state.overflowUntil = now + ttl
            return false, "cache_capacity"
        end
        state.overflowUntil = nil
        while state.attempts[1] and now - state.attempts[1] >= 1 do
            table.remove(state.attempts, 1)
        end
        local allow, reason = false, "rate_limit"
        if #state.attempts < limit then
            state.attempts[#state.attempts + 1] = now
            local ok, decision, why = pcall(evaluate)
            -- Accept only the known decision/reason contract. Never retain caller text.
            local known = ok and type(why) == "string" and reasons[why]
            allow = known == true and decision == true and why == "allow"
            reason = known and why or "policy_error"
            if decision == true and not allow then reason = "policy_error" end
        end
        state.cache[messageId] = { expires = now + ttl, allow = allow, reason = reason }
        state.count = state.count + 1
        return allow, reason
    end
    return gate
end
return DeliveryGate
