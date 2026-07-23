---
description: >-
  Read-only analyst that surfaces candidate blog topics from recent git
  history and opencode session transcripts. Writes a DRAFT topics file to
  inputs/. Never writes an article.
mode: primary
---

# topic-extractor (stub)

**This is a minimal placeholder created in step 01.** Its full prompt body —
the extraction workflow (auto-discovery vs. `tracked-projects.txt` allowlist,
`git log` per project, `sqlite3 -readonly` session queries over the indexed
`time_updated` column, timestamp correlation, secret redaction, and the
DRAFT-first topics-file output) — is authored in **step 02**.

The permission boundary for this agent is defined in
`.opencode/opencode.json`, not here.
