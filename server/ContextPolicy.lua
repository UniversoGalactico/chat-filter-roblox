-- Content-independent gameplay delivery rules. No user text, metadata or identity storage.
local ContextPolicy = {}
local MAX_INTEGER = 2^53 - 1
local function validScope(value)
    if type(value) == "string" then return #value > 0 and #value <= 64 end
    return type(value) == "number" and value >= -MAX_INTEGER and value <= MAX_INTEGER and value % 1 == 0
end

function ContextPolicy.new(config)
    local configured = config.ScopeAttributes
    if configured == nil then configured = {} end
    assert(type(configured) == "table" and getmetatable(configured) == nil, "invalid scope rules")
    local scopes, count = {}, 0
    for channel, attribute in pairs(configured) do
        count = count + 1
        assert(count <= 32, "too many scope rules")
        assert(type(channel) == "string" and #channel > 0 and #channel <= 128, "invalid scope channel")
        assert(type(attribute) == "string" and #attribute > 0 and #attribute <= 64
            and attribute:match("^[A-Za-z_][A-Za-z0-9_]*$"), "invalid scope attribute")
        assert(attribute ~= "ChatFilterMuted", "mute flag cannot be a scope")
        scopes[channel] = attribute
    end
    return function(sender, receiver, channelName)
        local muted = sender:GetAttribute("ChatFilterMuted")
        -- A missing attribute is normal. Unexpected values indicate a broken server policy.
        if muted ~= nil and muted ~= false then return false, "muted" end
        local attribute = scopes[channelName]
        if attribute then
            -- Only server-owned gameplay groups, never a substitute for platform permissions.
            -- Missing or malformed group membership denies delivery.
            local left, right = sender:GetAttribute(attribute), receiver:GetAttribute(attribute)
            if not validScope(left) or not validScope(right) or left ~= right then return false, "scope" end
        end
        return true, "allow"
    end
end
return ContextPolicy
