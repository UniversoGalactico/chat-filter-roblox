# Verification
Run `lua5.4 tests/regression.lua` from the root. Pure modules intentionally use portable Lua syntax; these checks are not Roblox Studio tests.

Studio / live experience checklist (not yet executed):
1. Remove old ChatMessage RemoteEvent and all legacy scripts that send or display player text. Leave native chat enabled.
2. Test the default native-only configuration with PlatformIntegratedChat enabled. Verify reporting, mute/block, chat restrictions and no custom player-text path.
3. If testing the optional legacy hook, explicitly confirm platform-integrated chat is disabled in Studio, enable the policy, and use a channel whose delivery callback is owned exclusively by ChatFilter. Test two or more clients, recipient-specific privacy, blocked content, sender self-echo, rapid messages, joining/leaving and late-created channels.
4. Confirm native text filtering still applies to every delivery. Confirm a blocked message is not seen by other players; the sender may see local echo per Roblox documentation.
5. Compare against representative benign conversations in English, Spanish and Portuguese before changing lists or enabling fuzzy matching.
6. Do not use this package to circumvent future API restrictions. Disable the legacy hook before switching to platform-integrated chat.
