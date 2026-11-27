# V3 simplification audit

Baseline: `8e6e9bff949643f02305dd1864d1fb8963cff62b`.

| Finding | Risk | Decision |
|---|---|---|
| Automatic callback discovery silently leaves duplicate names native and cannot detect callback ownership | Missing policy or overwritten game delivery rule | Remove automatic installation. Bind only a developer-owned explicit channel. |
| PublicFieldService adds a distributed service, async lifecycle, and authorization obligations unrelated to chat | Service availability, misuse, operational cost | Remove from active distribution; historical implementation remains at baseline. |
| Default native mode installs nothing | Confusing installation | Native chat needs no package. Optional policy is an explicit controller. |
| Recipient decisions must remain independent; native chat text is being retired | Incorrect cached allow or unavailable content | Preserve context-only default and explicit transitional lexical option. |
| Clock, cache and rate are bounded; expiry references can linger during inactivity | Bounded but unnecessary channel retention | Preserve admission invariant, expose no user callbacks, document lazy expiry. |
| Caller can omit expected channel | Wrong-channel invocation | Capture exact channel and name in a returned callback. |
| Tests are extensive but mocks are not the engine | False confidence | Keep pure tests, add one short real Studio exercise, and require actual recipient observation. |
| Lexical rules can block quotations and miss abuse | False positives/negatives | Keep fuzzy opt-in; no auto-punishment or safety classifier claims. |

Not a live Roblox safety certification. No chat bypass or raw text forwarding. No changes to main.
