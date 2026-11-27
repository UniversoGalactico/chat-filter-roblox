# Design audit: RemoteGuard 1.0.0-rc.2

This is an engineering argument for the design, supported by bounded tests; not a proof of security in arbitrary Roblox games.

## Resource admission

- Each ring contains at most its configured limit of active timestamps. On monotone time, expiration is a prefix; find the first nonexpired timestamp and drop the preceding prefix. A charge writes only after a free slot is established. A completely expired ring resets in constant time; a partially expired prefix takes logarithmic comparisons. Storage retains numeric slots only, never request data.
- The common rounded comparison can admit too early when `now - earlier` rounds upward to the window. The equality branch computes the TwoSum residual of the subtraction. For finite operands in the configured domain, when the rounded difference equals the window, a negative residual means the exact represented interval is shorter than the window. Retry detail is approximate. This concerns represented timestamps, not an exact physical clock.
- Known actions charge subject, action and shared server quotas in order before payload inspection. No denied later layer restores an earlier quota. Unknown routes and wrong admission modes are rejected without allocating subject state. Server quota is shared across wrappers of one guard, not across guards or Roblox servers.
- Tracked subject and configured timestamp counts are bounded. Sweep cannot erase an unexpired subject/action history: the latest charged global attempt is no earlier than any action charge, and the sweep horizon is the largest configured subject/action window. A full subject table denies rather than evicts. Forget is a trusted explicit reset and may not be exposed to clients.

## Work lifetime

- Begin inserts exactly one opaque identity and increments server, subject and action active counters. Release removes that identity exactly once. Check cannot bypass a leased action. Neither rate-limit expiration nor departure releases an occupied permit.
- Forget detaches the subject generation and drops its timestamp histories; existing permits remain counted until their work ends. A subsequent identity obtains new state; releasing an old token cannot decrement the replacement generation. The adapter retains a pending token/thread association and reaps only dead threads, not slow or suspended ones.
- IsCurrent is a local generation check, not a lock or transactional guarantee. A yielding handler can still mutate game state incorrectly if it ignores its token or neglects game-specific reauthorization. Destroy invalidates the controller but does not kill running application work. Replacing a destroyed guard while old work remains requires independent application-level fencing.

## Payload and callback boundaries

- Schema compilation copies the trusted definition, rejects unsupported fields and bounds recursive depth/rule count. Request validation uses closed record keys, contiguous numeric arrays, bounded string-key maps, cycle detection and aggregate node/byte limits. Instance class and ancestry are only structural checks; they never imply ownership or authority.
- Admission is nonyielding. Predicates must finish synchronously and return exactly true. Error or yield denies; cancellation cannot undo a prior side effect. The adapter checks actual player membership and routes to a server-selected action, then releases leases on return/error. Raw errors are redacted and aggregate counters contain no payload or identity.
- The library cannot prevent inbound bandwidth/deserialization work, another unguarded listener, trusted code scheduling detached jobs, infinite loops, compromised server code, parallel Actors or distributed abuse. A shared quota is a resource ceiling, not a guarantee of fair access. Capacity and latency need actual game profiling.

## Verification strategy

Independent list-model and immutable finite-state references check public behavior; generated schema cases use a Python interpreter; numerical tests use a pinned external rational oracle. The internal audit instruments temporary source copies and validates its own sensitivity with five selected negative controls. The public semantic mutation suite detects 39 selected defects. None establishes universal correctness. See [TESTING.md](TESTING.md) for exact campaign scope and [machine-readable evidence](../tests/evidence/) for source hashes. Real Studio/network smoke and multi-player integration are separate gates.
