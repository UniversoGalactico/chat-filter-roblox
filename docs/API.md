# API contracts

## Configuration

`RemoteGuard.new(config)` compiles and copies a plain configuration. Unknown fields and invalid limits throw during initialization. The optional `RemoteGuardServer.new(config)` owns one core guard and a PlayerRemoving connection; install both sibling modules on the server. Server-side configuration is trusted code, not data received from a client.

| Field | Contract |
| --- | --- |
| `Global` | Required quota across configured actions for one subject. `Limit` integer 1–256, `Window` finite 0.001–3600 s. |
| `Server` | Optional quota across all subjects and actions in this guard. Limit 1–8192, same Window range. |
| `Actions` | 1–64 named actions. Each has `Quota` (same bounds as Global), `Args` (0–16 rules), optional `Authorize` and `MaxInFlight`. Names nonempty valid UTF-8, <=64 bytes, no ASCII controls. |
| `MaxSubjects` | 1–4096, default 256. Retains identities until Forget, Sweep or Destroy. Capacity denies new subjects without evicting live quotas. |
| `MaxInFlight` | 1–4096, default 128, shared across leased actions only. |
| `MaxInFlightPerSubject` | 1–MaxInFlight, default min(4, MaxInFlight). Across all leased actions per subject. |
| action `MaxInFlight` | Optional integer 1–MaxInFlightPerSubject, per subject/action. Enables leased mode for that action. |
| `Clock` | Optional trusted synchronous monotone seconds function (default os.clock), finite [0, 2^32]. Clock error/regression fails closed. |

Worst-case configured timestamp slots `MaxSubjects * (Global.Limit + sum(action.Quota.Limit)) + Server.Limit` (if present) must be <=1,000,000. This is an entry-count bound, not a byte-size or Roblox capacity estimate. Idle timestamps are numeric only; retired leased subjects have their quota histories cleared. The maximum schema depth is 8 and aggregate compiled rule/choice count is 4096. [Schema reference](SCHEMAS.md).

## Core API

| Call | Result |
| --- | --- |
| `Check(subject, action, ...)` | true on admission or false, code, optional number. Only for non-leased actions. |
| `Begin(subject, action, ...)` | opaque token on admission or nil, code, optional number. Only for leased actions. |
| `Release(token)` | true exactly once for a token issued by this guard; false otherwise. Does not undo gameplay. |
| `IsCurrent(token)` | true while the token is outstanding and its subject generation is live. Not a distributed lock or authorization proof. |
| `Forget(subject)` | remove tracked subject and invalidate its permits. Outstanding retired work still occupies shared in-flight slots until released. |
| `Sweep()` | count of conservatively expired idle subjects, or nil, code. No active permits are swept. |
| `Count()` | tracked subject count (not retired permit count). |
| `GetStats()` | detached aggregate counters including Allowed, Denied, Subjects, InFlight, and observed denial codes. Saturating counters; no raw payloads or identities. |
| `Destroy()` | idempotent. Invalidate all tokens and release internal subject, action, clock and permit references. Does not cancel application tasks. |

Subject is a **trusted** server-chosen identity (normally a Player instance, or a scalar/table identity in pure tests). Unknown actions/invalid subjects or a mismatched Check/Begin mode allocate nothing. Do not accept identity or action name from a remote payload. Only one serial execution context per guard; mutation reentry from callbacks returns BUSY. Read methods remain available. `Forget` intentionally resets per-subject budgets and should be called only from trusted lifecycle code. Server quota survives Forget/Sweep.

## Admission order

1. Validate identity, fixed action, method mode and clock; reserve tracked subject if capacity allows.
2. Check per-subject Global window, charge if admitted. Then action window, charge if admitted. Then optional shared Server window, charge if admitted. No rollback of prior-layer charges on later denial.
3. For Begin, check server/subject/action in-flight ceilings before expensive payload validation.
4. Validate exact argument arity and schema; check synchronous authorization. Only then issue a permit or return successful Check.

Malformed/unauthorized requests consume quota; quota rejection cannot generate a new slot in an already full layer. No deduplication or retry immunity. One attacker can still consume its allowed share of a shared server quota; choose separate guards for distinct resource pools if needed. A guard is not a transport-level limit.

Timestamp rings use exact comparison of represented binary64 intervals at the rounded-equal boundary. Expired prefixes are removed logically by binary search; old scalar slots are reused. Retry detail is an approximate number of seconds until the relevant layer opens, not a reservation or a guarantee. `Sweep` uses the largest configured per-subject window after the most recent charged global attempt; conservative retention avoids forgetting longer action quotas. A clock regression rejects rather than rewinding time. No background tasks.

## Authorization and permits

`Authorize(subject, ...)` runs after quota and argument validation. It must return exactly true, must finish synchronously, and must be a bounded, side-effect-free server predicate. Error or yield denies; suspended threads are cancelled/closed on a best-effort basis. Side effects already performed cannot be undone. Never use an authorization callback to spawn detached work. `Check` alone does not bound a yielding handler.

For an action with MaxInFlight, acquire using Begin and always Release, including error paths. A token is a frozen identity local to this guard. `Forget` invalidates current-generation permits but does **not** release their occupied shared slots. Do not release on timeout while the handler might still execute. After a yield, check IsCurrent and revalidate game permissions and resources immediately before committing. A stuck task retains its permit (fail-closed) until confirmed stopped; explicit Destroy stops new admissions, not side effects. No transaction atomicity or automatic rollback.

## Optional Roblox adapter

`RemoteGuardServer.new(config)` requires server context. It creates a core guard and owns PlayerRemoving cleanup. `server:Wrap(action, handler)` returns an ordinary callback for a RemoteEvent or RemoteFunction; it never binds or replaces callbacks itself. One authoritative owner must connect or assign it. Every invocation verifies the actual Player object, current Players membership, identity returned by GetPlayerByUserId, and departure status before admission. No client-chosen action routing.

The handler receives `(player, tokenOrNil, ...)`. For non-leased actions it must be synchronous; errors/yields return `false, "HANDLER_ERROR"` and no raw error content. For leased actions it may yield; pcall catches ordinary errors and releases the permit. The wrapper returns `true, ...handlerResults` on completed current execution (business success may be a separate handler result), `false, "DENIED"` for admission/stale completion, or `false, "HANDLER_ERROR"`. It preserves handler nil return positions. Never expose confidential handler returns to a client.

`server:IsCurrent(token)` verifies the pending leased request and real Player membership. A stale result is withheld, but already-performed side effects are not undone. `server:Sweep()` returns reapedDeadThreads, prunedSubjects, error; only permits whose recorded thread is dead are reclaimed automatically. A suspended handler can still perform work and must retain its slot. Call Sweep periodically from an existing owner loop, especially if handlers may be cancelled externally. `server:GetStats()` includes core counters plus InvalidPlayer, HandlerErrors, HandlerYields, StaleCompletions, Reaped. `server:Destroy()` disconnects the PlayerRemoving listener and invalidates tokens; externally connected callbacks should be disconnected by their owner. A retained callback denies after destruction. Do not replace a destroyed controller while old work can still mutate the same resources without independent domain fencing.

## Error codes

DESTROYED, BUSY, INVALID_SUBJECT, UNKNOWN_ACTION, ACQUIRE_REQUIRED, NOT_LEASE_ACTION, INVALID_CLOCK, CLOCK_REGRESSION, CAPACITY, GLOBAL_LIMIT, ACTION_LIMIT, SERVER_LIMIT, SERVER_IN_FLIGHT, SUBJECT_IN_FLIGHT, ACTION_IN_FLIGHT, ARG_COUNT, INVALID_ARGUMENT, CALLBACK_ERROR, CALLBACK_YIELDED, UNAUTHORIZED, INVALID_TOKEN, NOT_FOUND. The third Check/Begin result is quota wait seconds or invalid top-level argument index. Release, Forget and Sweep have their own status contracts above. No automatic retries or raw error strings.
