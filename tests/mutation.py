"""Targeted mutation testing. All mutations run only in a temporary copy.
A syntax failure or timeout is a harness error, never credited as a killed mutant.
These selected mutants do not measure complete fault coverage.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys

MUTANTS = [
  ["gate_recent_scope","DeliveryGate.lua","regression.lua","recent.scope == scope and recent.id == messageId","recent.id == messageId"],
  ["gate_recent_id","DeliveryGate.lua","regression.lua","recent.scope == scope and recent.id == messageId","recent.scope == scope"],
  ["gate_recent_expiry","DeliveryGate.lua","regression.lua","recent.id == messageId and recent.expires > now","recent.id == messageId"],
  ["adapter_released_callback","ChatFilter.lua","adapter.lua","if not active or bindings[channel] ~= token then record(\"stopped\") return false end","if not active then record(\"stopped\") return false end"],
  ["adapter_duplicate_binding","ChatFilter.lua","adapter.lua","assert(not bindings[channel], \"channel already bound; release before rebinding\")","assert(true)"],
  [
    "lexical_spanish_punctuation",
    "TextPolicy.lua",
    "regression.lua",
    "or cp == 0xA1 or cp == 0xBF or cp == 0xAB or cp == 0xBB or cp == 0xB7",
    "or false"
  ],
  [
    "gate_channel_isolation",
    "DeliveryGate.lua",
    "regression.lua",
    "if scope == nil then scope = DEFAULT_SCOPE end",
    "scope = DEFAULT_SCOPE"
  ],
  [
    "gate_rate_boundary",
    "DeliveryGate.lua",
    "regression.lua",
    "local allow = #state.attempts < limit",
    "local allow = #state.attempts <= limit"
  ],
  [
    "gate_expiry_boundary",
    "DeliveryGate.lua",
    "regression.lua",
    "if cached and cached.expires > now then",
    "if cached and cached.expires >= now then"
  ],
  [
    "gate_overflow_quarantine",
    "DeliveryGate.lua",
    "regression.lua",
    "if (state.overflowUntil and state.overflowUntil > now) or state.count >= capacity then",
    "if state.count >= capacity then"
  ],
  [
    "gate_clock_regression",
    "DeliveryGate.lua",
    "regression.lua",
    "if now < state.last then return false, \"clock_regression\" end",
    "if false then return false, \"clock_regression\" end"
  ],
  [
    "gate_session_cleanup",
    "DeliveryGate.lua",
    "regression.lua",
    "if validSender(sender) then senders[sender] = nil end",
    "if false then senders[sender] = nil end"
  ],
  [
    "lexical_exact",
    "TextPolicy.lua",
    "regression.lua",
    "if words[token] then return false, \"word\" end",
    "if false then return false, \"word\" end"
  ],
  [
    "lexical_phrase",
    "TextPolicy.lua",
    "regression.lua",
    "if node[true] then return false, \"phrase\" end",
    "if false then return false, \"phrase\" end"
  ],
  [
    "lexical_leet",
    "TextPolicy.lua",
    "regression.lua",
    "if token:find(\"[013457]\") and token:find(\"[a-z]\") then",
    "if false then"
  ],
  [
    "lexical_accents",
    "TextPolicy.lua",
    "regression.lua",
    "if fold[cp] then",
    "if false then"
  ],
  [
    "lexical_invisibles",
    "TextPolicy.lua",
    "regression.lua",
    "if not ignored[cp] then",
    "if true then"
  ],
  [
    "lexical_fuzzy_deletion",
    "TextPolicy.lua",
    "regression.lua",
    "if deletions[token] then return false, \"fuzzy\" end",
    "if false then return false, \"fuzzy\" end"
  ],
  [
    "lexical_fuzzy_insertion",
    "TextPolicy.lua",
    "regression.lua",
    "if fuzzyWords[removeAt(token,i)] or substitutions[maskAt(token,i)] then",
    "if substitutions[maskAt(token,i)] then"
  ],
  [
    "lexical_fuzzy_substitution",
    "TextPolicy.lua",
    "regression.lua",
    "if fuzzyWords[removeAt(token,i)] or substitutions[maskAt(token,i)] then",
    "if fuzzyWords[removeAt(token,i)] then"
  ],
  [
    "lexical_fuzzy_allowlist",
    "TextPolicy.lua",
    "regression.lua",
    "if fuzzy and not allowed[token] and #token >= 6 and #token <= 33",
    "if fuzzy and #token >= 6 and #token <= 33"
  ],
  [
    "context_scope_missing",
    "ContextPolicy.lua",
    "regression.lua",
    "if not validScope(left) or not validScope(right) or left ~= right then",
    "if left ~= right then"
  ],
  [
    "context_scope_mismatch",
    "ContextPolicy.lua",
    "regression.lua",
    "if not validScope(left) or not validScope(right) or left ~= right then",
    "if not validScope(left) or not validScope(right) then"
  ],
  [
    "context_mute",
    "ContextPolicy.lua",
    "regression.lua",
    "if muted ~= nil and muted ~= false then",
    "if false then"
  ],
  [
    "adapter_channel_mismatch",
    "ChatFilter.lua",
    "adapter.lua",
    "if message.TextChannel ~= channel then return false, \"invalid_identity\" end",
    "if false then return false, \"invalid_identity\" end"
  ],
  [
    "adapter_detached_channel",
    "ChatFilter.lua",
    "adapter.lua",
    "if not channel:IsDescendantOf(TextChatService) or channel.Name ~= name then",
    "if channel.Name ~= name then"
  ],
  [
    "adapter_rename",
    "ChatFilter.lua",
    "adapter.lua",
    "if not channel:IsDescendantOf(TextChatService) or channel.Name ~= name then",
    "if not channel:IsDescendantOf(TextChatService) then"
  ],
  [
    "adapter_sender_membership",
    "ChatFilter.lua",
    "adapter.lua",
    "source.Parent ~= channel or recipient.Parent ~= channel or source.CanSend ~= true",
    "recipient.Parent ~= channel or source.CanSend ~= true"
  ],
  [
    "adapter_recipient_membership",
    "ChatFilter.lua",
    "adapter.lua",
    "source.Parent ~= channel or recipient.Parent ~= channel or source.CanSend ~= true",
    "source.Parent ~= channel or source.CanSend ~= true"
  ],
  [
    "adapter_readonly_sender",
    "ChatFilter.lua",
    "adapter.lua",
    "source.Parent ~= channel or recipient.Parent ~= channel or source.CanSend ~= true",
    "source.Parent ~= channel or recipient.Parent ~= channel"
  ],
  [
    "adapter_departure",
    "ChatFilter.lua",
    "adapter.lua",
    " or leaving[sender]",
    ""
  ],
  [
    "adapter_context_text_access",
    "ChatFilter.lua",
    "adapter.lua",
    "if not evaluate then return true, \"allow\" end",
    "if not evaluate then local _ = message.Text return true, \"allow\" end"
  ],
  [
    "adapter_legacy_verdict",
    "ChatFilter.lua",
    "adapter.lua",
    "return evaluate(text)",
    "return true, \"allow\""
  ],
  [
    "adapter_reserved",
    "ChatFilter.lua",
    "adapter.lua",
    "assert(name:sub(1,3):upper() ~= \"RBX\", \"reserved channel\")",
    "assert(true)"
  ],
  [
    "adapter_unknown_option",
    "ChatFilter.lua",
    "adapter.lua",
    "for key in pairs(options) do assert(known[key], \"unknown ChatFilter option\") end",
    "for key in pairs(options) do end"
  ]
]

ROOT = Path(__file__).resolve().parents[1]


def run(args, cwd):
    return subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, timeout=30, check=False)


def main():
    with tempfile.TemporaryDirectory(prefix="chatfilter-mutations-") as tmp:
        work = Path(tmp)
        shutil.copytree(ROOT / "server", work / "server")
        (work / "tests").mkdir()
        for source in (ROOT / "tests").glob("*.lua"):
            shutil.copy2(source, work / "tests" / source.name)
        for suite in sorted({m[2] for m in MUTANTS}):
            result = run(["lua5.4", "tests/" + suite], work)
            if result.returncode:
                print("Baseline failed:", suite, result.stdout[-1000:])
                return 2
        survivors = []
        for name, module, suite, before, after in MUTANTS:
            path = work / "server" / module
            original = path.read_text(encoding="utf-8")
            if original.count(before) != 1:
                print("Invalid mutation anchor:", name)
                return 2
            try:
                path.write_text(original.replace(before, after, 1), encoding="utf-8")
                compiled = run(["luac5.4", "-p", str(path)], work)
                if compiled.returncode:
                    print("Invalid mutation syntax:", name, compiled.stdout[-1000:])
                    return 2
                result = run(["lua5.4", "tests/" + suite], work)
                if result.returncode == 0:
                    print("SURVIVED", name)
                    survivors.append(name)
                else:
                    print("KILLED", name)
            finally:
                path.write_text(original, encoding="utf-8")
        print(f"MUTATION {len(MUTANTS)-len(survivors)}/{len(MUTANTS)} selected faults detected")
        return 1 if survivors else 0


if __name__ == "__main__":
    sys.exit(main())
