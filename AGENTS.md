# Integration rules

Read docs/API.md. Keep the guard server-side; identity and action must be selected by server code. Pass all client arguments. Use per-subject quotas and Forget on removal. Authorization callbacks must not yield or mutate state; Check is admission, not transaction authorization after a yield. No anti-cheat guarantee, no auto-bind, no cross-server limits. Never log raw requests by default.
