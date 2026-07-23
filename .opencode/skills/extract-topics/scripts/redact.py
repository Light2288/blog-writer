#!/usr/bin/env python3
"""Redaction helper for the extract-topics skill.

Reads text on stdin, writes redacted text to stdout, and emits a flag
signal on stderr when at least one secret-like pattern was redacted.

Contract (relied on by tests/extract_topics_check.sh and SKILL.md step 6):
  - stdout  : the input text with every match replaced by
              ``[REDACTED:<reason>]``.
  - stderr  : the single line ``FLAG`` iff one or more redactions occurred;
              otherwise nothing is written to stderr.
  - exit    : always 0 (redaction is advisory, never fatal).

The regexes are deliberately conservative: the DRAFT review step and the
tracked-projects allowlist are the real safety net (see the parent spec).
Only material destined for the topics file should be piped through here;
internal-only reasoning is never written and needs no redaction.

Stdlib only — this project has no package manifest.
"""

import re
import sys

# Each rule: (compiled regex, reason). The portion to redact is group 1 when
# the pattern defines one, otherwise the whole match.
_RULES = [
    # key=value / key: value style secrets for common secret-bearing keys.
    (re.compile(r"(?i)\b(client_secret)\b\s*[:=]\s*(\S+)"), "client_secret"),
    (re.compile(r"(?i)\b(api[_-]?key)\b\s*[:=]\s*(\S+)"), "api_key"),
    (re.compile(r"(?i)\b(token)\b\s*[:=]\s*(\S+)"), "token"),
    # Bearer tokens: "bearer <token>".
    (re.compile(r"(?i)\bbearer\s+(\S+)"), "bearer"),
    # Long hex / base64-ish runs that look like raw secrets (>=32 chars).
    (re.compile(r"\b[A-Fa-f0-9]{32,}\b"), "hex-secret"),
    (re.compile(r"\b[A-Za-z0-9+/]{32,}={0,2}\b"), "base64-secret"),
]


def redact(text: str) -> "tuple[str, bool]":
    """Return (redacted_text, flagged)."""
    flagged = False

    def _sub_kv(reason):
        def repl(m):
            nonlocal flagged
            flagged = True
            # Preserve the key name, redact the value.
            return "%s=[REDACTED:%s]" % (m.group(1), reason)

        return repl

    def _sub_whole(reason):
        def repl(m):
            nonlocal flagged
            flagged = True
            return "[REDACTED:%s]" % reason

        return repl

    for rx, reason in _RULES:
        if reason in ("client_secret", "api_key", "token"):
            text = rx.sub(_sub_kv(reason), text)
        else:
            text = rx.sub(_sub_whole(reason), text)

    return text, flagged


def main() -> int:
    data = sys.stdin.read()
    out, flagged = redact(data)
    sys.stdout.write(out)
    if flagged:
        sys.stderr.write("FLAG\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
