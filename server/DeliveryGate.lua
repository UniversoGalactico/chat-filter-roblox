-- Bounded, non-yielding message admission. No user callbacks or message content.
local DeliveryGate = {}
local MAX_CLOCK = 2^40
local function validSender(sender)
    return sender ~= nil and (type(sender) ~= "number" or sender == sender)
end
function DeliveryGate.new(config)
    local limit, ttl, capacity = config.MessagesPerSecond, config.DecisionTTL, config.MaxCachedMessages
    assert(type(limit) == "number" and limit >= 1 and limit <= 20 and limit % 1 == 0)
    assert(type(ttl) == "number" and ttl >= 1 and ttl <= 60)
    assert(type(capacity) == "number" and capacity >= limit and capacity <= 256 and capacity % 1 == 0)
    local senders = setmetatable({}, { __mode = "k" })
    local gate = {}
    function gate:Forget(sender)
        if validSender(sender) then senders[sender] = nil end
    end
    function gate:Clear()
        for sender in pairs(senders) do senders[sender] = nil end
    end
    function gate:Admit(sender, messageId, now)
        if not validSender(sender) or type(messageId) ~= "string" or #messageId == 0 or #messageId > 128 then
            return false, "invalid_identity"
        end
        if type(now) ~= "number" or not (now >= 0 and now <= MAX_CLOCK) then
            return false, "invalid_clock"
        end
        local state = senders[sender]
        if not state then
            state = { cache = {}, order = {}, attempts = {}, head = 1, count = 0, last = now }
            senders[sender] = state
        end
        if now < state.last then return false, "clock_regression" end
        state.last = now
        local cached = state.cache[messageId]
        if cached and cached.expires > now then return cached.allow, cached.reason end
        -- Equal TTL plus monotone time makes expiry FIFO.
        while state.count > 0 do
            local oldest = state.order[state.head]
            if state.cache[oldest].expires > now then break end
            state.cache[oldest] = nil
            state.order[state.head] = nil
            state.head = state.head % capacity + 1
            state.count = state.count - 1
        end
        -- Never evict a live decision to admit a new message.
        if (state.overflowUntil and state.overflowUntil > now) or state.count >= capacity then
            state.overflowUntil = now + ttl
            return false, "cache_capacity"
        end
        state.overflowUntil = nil
        while state.attempts[1] and now - state.attempts[1] >= 1 do
            table.remove(state.attempts, 1)
        end
        local allow = #state.attempts < limit
        local reason = allow and "allow" or "rate_limit"
        if allow then state.attempts[#state.attempts + 1] = now end
        local slot = (state.head - 1 + state.count) % capacity + 1
        state.order[slot] = messageId
        state.cache[messageId] = { expires = now + ttl, allow = allow, reason = reason }
        state.count = state.count + 1
        return allow, reason
    end
    return gate
end
return DeliveryGate
