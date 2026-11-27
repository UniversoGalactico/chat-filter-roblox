# Security boundary

RemoteGuard is an opt-in server request admission library, not Roblox transport security, anti-cheat or a sandbox. Report minimal synthetic reproductions through Issues; never include private player data, tokens or game secrets.

- Put server modules/config in ServerScriptService. Use the actual engine-provided Player and server-selected action. The optional adapter checks identity, current membership and departure. No client-chosen action, permission or price is trusted.
- All configured rate layers charge before costly validation. No automatic evictions of active histories. Server quota and in-flight caps are local to one guard; no distributed synchronization or network/deserialization protection. Shared quotas can deny legitimate work under load; choose policies with game-specific fairness in mind.
- Payload schemas are closed and bounded; only explicitly supported types pass. Instance ancestry/class does not establish permission. Callers must check ownership, distance, game state, inventory, balances and server-calculated costs. Revalidate after yields before irreversible mutation.
- Leased actions cannot use Check. Outstanding permits survive Forget until confirmed release; old generations are invalidated. Never free a suspended request just because it is old. The optional adapter reaps only dead recorded threads and withholds stale responses. A handler that ignores its token can still perform stale side effects. Do not spawn detached work under a permit or assume cancellation rolls back side effects.
- Errors/yields from trusted synchronous predicates are rejected. No protection against infinite loops or arbitrary trusted server code. No raw payload, user-ID or error-text logging by the library. Aggregate counters are not proof of delivery, receipt or transaction success.
- The adapter does not install callbacks; exactly one owner must route all requests through the gate. Disconnect external listeners on teardown. Do not treat a successful test as permission to remove domain validation.

References: [server boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary), [remote serialization](https://create.roblox.com/docs/scripting/events/remote), [task cancellation](https://create.roblox.com/docs/reference/engine/libraries/task).
