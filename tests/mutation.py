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
  ["adapter_sender_membership","ChatFilter.lua","adapter.lua","source.Parent ~= channel or recipient.Parent ~= channel or source.CanSend ~= true","recipient.Parent ~= channel or source.CanSend ~= true"],
  ["adapter_recipient_membership","ChatFilter.lua","adapter.lua","source.Parent ~= channel or recipient.Parent ~= channel or source.CanSend ~= true","source.Parent ~= channel or source.CanSend ~= true"],
  ["adapter_readonly_sender","ChatFilter.lua","adapter.lua","source.Parent ~= channel or recipient.Parent ~= channel or source.CanSend ~= true","source.Parent ~= channel or recipient.Parent ~= channel"],
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
    "adapter_cached_lexical_allow",
    "ChatFilter.lua",
    "adapter.lua",
    "if mode == \"context\" then return true, \"allow\" end",
    "if admitted then return true, \"allow\" end"
  ],
  [
    "adapter_context_text_access",
    "ChatFilter.lua",
    "adapter.lua",
    "if mode == \"context\" then return true, \"allow\" end",
    "if mode == \"context\" then local _ = message.Text return true, \"allow\" end"
  ],
  [
    "adapter_departure",
    "ChatFilter.lua",
    "adapter.lua",
    " or leaving[sender]",
    ""
  ],
  [
    "adapter_channel_mismatch",
    "ChatFilter.lua",
    "adapter.lua",
    "or (expectedChannel and channel ~= expectedChannel) then",
    "then"
  ],
  [
    "bootstrap_reserved_channel",
    "ChatServer.lua",
    "bootstrap.lua",
    "if name:sub(1,3):upper() == \"RBX\" and name ~= \"RBXGeneral\" then",
    "if false then"
  ],
  [
    "bootstrap_detached_channel",
    "ChatServer.lua",
    "bootstrap.lua",
    "or not ownsLocation(channel) then return false end",
    "then return false end"
  ],
  [
    "field_global_claim",
    "PublicFieldPipeline.lua",
    "public_fields.lua",
    "if claim(id)~=true then return nil,\"rate_limit\" end",
    "if false then return nil,\"rate_limit\" end"
  ],
  [
    "field_stale_output",
    "PublicFieldPipeline.lua",
    "public_fields.lua",
    "local text=broadcast(result)\n            if not fresh() then return nil,\"stale\" end",
    "local text=broadcast(result)"
  ],
  [
    "field_local_cooldown",
    "PublicFieldPipeline.lua",
    "public_fields.lua",
    "if nextTime and started<nextTime then return nil,\"rate_limit\" end",
    "if false then return nil,\"rate_limit\" end"
  ],
  [
    "field_single_flight",
    "PublicFieldPipeline.lua",
    "public_fields.lua",
    "if busy[id] then return nil,\"busy\" end",
    "if false then return nil,\"busy\" end"
  ],
  [
    "field_capacity",
    "PublicFieldPipeline.lua",
    "public_fields.lua",
    "if active>=maxConcurrent then return nil,\"capacity\" end",
    "if false then return nil,\"capacity\" end"
  ],
  [
    "field_fail_open",
    "PublicFieldPipeline.lua",
    "public_fields.lua",
    "if not success then return nil,\"service_error\" end",
    "if not success then return raw,\"allow\" end"
  ],
  [
    "field_filter_output",
    "PublicFieldPipeline.lua",
    "public_fields.lua",
    "if not validText(text,MAX_OUTPUT) then return nil,\"filter_error\" end",
    "if false then return nil,\"filter_error\" end"
  ],
  [
    "field_claim_token",
    "PublicFieldService.lua",
    "public_field_adapter.lua",
    "return result==token",
    "return result~=nil"
  ],
  [
    "field_owned_worker",
    "PublicFieldService.lua",
    "public_field_adapter.lua",
    "local scheduled=pcall(task.spawn,function()",
    "local scheduled=pcall(function()"
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
