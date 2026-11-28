# RemoteGuardRoblox

Server-side request admission for Roblox. **1.0.0** — stable release, MIT, no external dependencies. Check quotas, payload shape and permissions before executing game logic. Optional adapter handles real Player identity and request lifetime.

## Start here

Install [RemoteGuardRoblox.lua](RemoteGuardRoblox.lua) as `RemoteGuard` and [RemoteGuardServer.lua](RemoteGuardServer.lua) as `RemoteGuardServer`, siblings under ServerScriptService. The second module is optional; the core can be used without Roblox services.

```lua
local RemoteGuardServer = require(game.ServerScriptService.RemoteGuardServer)
local gate = RemoteGuardServer.new({
    Global = {Limit = 20, Window = 1}, -- per Player, across actions
    Server = {Limit = 300, Window = 1}, -- shared across Players in this gate
    Actions = {
        Buy = {
            Quota = {Limit = 3, Window = 1},
            Args = {{Type = "string", MaxBytes = 64}},
            Authorize = function(player, itemId)
                return player:GetAttribute("ShopOpen") == true
            end,
        },
    },
})

-- remote is a server-owned RemoteEvent; keep one authoritative handler.
local connection = remote.OnServerEvent:Connect(gate:Wrap("Buy", function(player, _, itemId)
    -- Verify actual price, stock, balance, distance and ownership on the server.
    -- This example grants nothing. Check-mode handlers must not yield.
end))
-- On teardown: connection:Disconnect(); gate:Destroy()
```

For a yielding handler, set `MaxInFlight` on its action; the adapter reserves a permit, releases it on return/error, and supplies an opaque token. Check `gate:IsCurrent(token)` and your game's permissions before committing after a yield. Assign the returned callback to a RemoteFunction only as its sole owner. [Async example](examples/Async.server.lua).

## Features

| Capability | Purpose |
| --- | --- |
| Per-player, per-action, optional shared server sliding windows | Bound admissions before expensive validation |
| Closed records, arrays, bounded maps, strings, numbers, booleans, buffers | Reject malformed or oversized structures |
| Vector2/3, Color3, Instance class + ancestry rules | Validate common Roblox payload types |
| Optional in-flight limits | Bound outstanding leased requests, not just request rate |
| Opaque permits and player departure invalidation | Reject stale continuations; keep occupied slots until work ends |
| Explicit `Wrap` or core `Check` / `Begin` / `Release` | No automatic remote discovery or callback replacement |
| `Sweep` and aggregate `GetStats` | Reclaim expired idle subjects and, in the adapter, dead handler threads |

[API contracts](docs/API.md) · [Schema reference](docs/SCHEMAS.md) · [Security model](SECURITY.md) · [Verification](docs/TESTING.md) · [Examples](examples/) · [AI guide](AGENTS.md).

## Studio test

Import the QuickTest model produced by `python3 tests/build_studio_model.py --out RemoteGuardQuickTest.rbxmx` into ServerScriptService and use **Play (F5)** in a blank Studio place. It runs engine datatype checks and actual client-server calls. No API access or publishing needed. See [test instructions](tests/STUDIO.md). The maintainer reported 24/24 passing in Studio on rc.2. The stable runtime differs only in version strings. [Download release](https://github.com/UniversoGalactico/RemoteGuardRoblox/releases/tag/v1.0.0).

## Important limits

- This is not an anti-cheat or firewall. Roblox still receives and deserializes requests before the gate sees them. Use server-owned player identity and a fixed server-chosen action; never route arbitrary client code or trust client prices or permissions.
- The core does not run gameplay, create remotes, ban players or log payloads. The adapter does not overwrite callbacks. Other unguarded listeners can still act on a remote.
- Quotas are local to one guard in one serial server context. They do not synchronize across servers or Parallel Luau Actors. Use `MaxInFlight` for yielding handlers; never release a still-running permit merely because it is old.
- A valid request is not a valid transaction. Revalidate ownership, distance, state and authoritative values at the point of mutation, especially after yielding. Detached work and infinite loops are outside the contract.

Formerly ChatFilter; the chat implementation remains in history. Native Roblox chat needs no additional filter. See [official Roblox server boundary guidance](https://create.roblox.com/docs/scripting/security/client-server-boundary).

MIT — [LICENSE](LICENSE).
