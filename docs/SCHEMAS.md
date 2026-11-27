# Request schemas

Rules are compiled, copied and bounded at construction. Every rule has `Type` and optional `Optional=true` to accept nil/omission. Optional top-level arguments must be trailing; record fields can be individually optional. Extra top-level arguments (including nil) are rejected. Array/map items and map keys cannot be optional. No coercion or default filling.

| Type | Allowed fields | Validation |
| --- | --- | --- |
| `number` | Min?, Max?, Integer? | Finite; optional inclusive bounds. Integer does not imply unique safe integer identity beyond 2^53−1: set bounds for IDs/currency. |
| `string` | MaxBytes? (0–4096, default 256), Choices? (1–64 unique valid strings) | Valid UTF-8 and bounded bytes. Choices is exact allowlist, not sanitization. |
| `boolean` | — | true or false only. |
| `record` | Fields (dictionary, max 64) | Exact named fields; unknown keys rejected. Missing required field fails. |
| `array` | Items (rule), MaxItems? (0–256, default 32) | Contiguous one-based numeric keys; sparse/mixed tables rejected. |
| `map` | Keys (nonoptional string rule), Values (nonoptional rule), MaxItems? (0–256, default 32) | Bounded dynamic string-key dictionary, all keys and values checked. |
| `buffer` | MaxBytes (required 0–16384) | Actual Luau buffer and byte bound; content is not decoded. |
| `Vector2`, `Vector3` | MaxAbs (required 0–1e30) | Actual engine type and finite components each within absolute bound. This is not a magnitude/distance/physics check. |
| `Color3` | — | Actual engine type, finite R/G/B in [0,1]. |
| `Instance` | Class (required), Ancestor (required server-selected Instance) | Actual engine Instance satisfying IsA and IsDescendantOf. Root itself does not satisfy descendant. Not an ownership or permission check. |

Every request also has 512 logical validation visits and 16,384 aggregate string/buffer/key bytes. Missing optional fields count as visits, map keys count as visits, repeated references count each time. Metatables/cycles are rejected. Schema graph depth <=8; max 4096 compiled rule/choice entries across actions. These are structural work bounds, not bytecode, wire-size or exact CPU guarantees. Only values that actually arrive after Roblox deserialization are checked. Instances and vectors are not mocked as genuine Roblox datatypes by CLI tests.

Example for an interaction:

```lua
Args = {{Type = "record", Fields = {
    target = {Type = "Instance", Class = "BasePart", Ancestor = workspace.Interactables},
    position = {Type = "Vector3", MaxAbs = 10000},
    mode = {Type = "string", Choices = {"Inspect", "Use"}},
    extras = {Type = "map", Optional = true, MaxItems = 4,
        Keys = {Type = "string", MaxBytes = 16},
        Values = {Type = "boolean"}},
}}}
```

The server must still check that the player can interact with that specific target, actual distance, game state and authoritative values. Never allow arbitrary delete/modify paths or execute code/assets from payloads. Unlisted types such as CFrame and EnumItem are intentionally not admitted; design explicit rules for your application rather than relying on generic type acceptance.
