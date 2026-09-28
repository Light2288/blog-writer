# End-to-End Acceptance Procedure

This is the single, repeatable procedure that verifies the whole Blog-Writer
project against every acceptance criterion in
[`specs/blog-writer-project.md`](../specs/blog-writer-project.md), as decomposed
by [`specs/steps/05-end-to-end-acceptance.md`](../specs/steps/05-end-to-end-acceptance.md).

It covers both OpenCode and Codex in three layers:

- **Automated deterministic checks** — shell scripts plus the bridge's Node
  tests. They assert both runtime scaffolds, shared formats, permission and
  path boundaries, synthetic history behavior, and read-only SQL usage. They
  run with no model, network, or real Codex-history access.
- **OpenCode runtime scenarios** — agent conversations that require a running
  OpenCode session.
- **An opt-in live Codex verifier** — isolated skill, custom-agent, MCP, and
  read-only sandbox probes that consume model calls only when explicitly
  enabled.

Where full automation is impractical (agent conversations), the manual script
below documents the exact observation to look for. The mechanical checks cover
everything statically verifiable.

## Prerequisites

- `git`, `sqlite3`, Node.js 20+, npm, and Python 3 on your `PATH` (the harness
  uses Python for JSON assertions).
- For OpenCode, the session database at
  `~/.local/share/opencode/opencode.db`.
  Confirm read-only access — this is also the **DB-unavailable** guard: if this
  command fails, stop and fix the DB path before running the runtime scenarios,
  rather than proceeding with a broken prerequisite:

  ```bash
  sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"
  ```

- Install the pinned Codex bridge dependency:

  ```bash
  npm install --prefix codex-bridge
  ```

- For OpenCode runtime scenarios, quit and **restart OpenCode** first so
  `.opencode/opencode.json`, the agents, and the skills are loaded.
- For Codex runtime scenarios, trust this project in Codex CLI or Codex
  desktop, then **restart Codex** after changing `.codex/config.toml`,
  `.codex/agents/`, or `.agents/skills/`.

Codex history is read through a bounded rollout adapter below
`~/.codex/sessions/**/*.jsonl`. This path and its JSONL record shape are local
adapter details, not a stable public database contract. The deterministic
suite substitutes synthetic rollouts and never reads that path. Internal Codex
SQLite, ChatGPT web history, and hosted account history are out of scope.

The main Codex chat has no privileged bridge registration. Each read-only
custom agent starts only its matching `topic`, `conventions`, or `writer`
profile. The bridge exposes no general shell tool, arbitrary-path file tool,
or caller-supplied project root; its mutation operations validate fixed
project-relative targets.

## Automated checks

Run the whole mechanical suite from the project root:

```bash
bash tests/run_all.sh
```

Or run each verifier individually:

| Script | Verifies |
|--------|----------|
| `tests/scaffold_check.sh` | Step 01 scaffold: directory tree, `.gitkeep`s, `AGENTS.md`/`README.md`, and the `.opencode/opencode.json` permission + `external_directory` structure. |
| `tests/extract_topics_check.sh` | Step 02 extract-topics skill workflow, the topic-extractor agent prompt, and the redaction helper. |
| `tests/conventions_check.sh` | Step 03 `CONVENTIONS.template.md` starter and the author-conventions interview skill. |
| `tests/blog_writer_check.sh` | Step 04 write-blog-article skill workflow and the blog-writer agent prompt. |
| `tests/acceptance_check.sh` | Step 05 system-wide static checks (fresh-clone readiness, DRAFT-first markers, bilingual + MDX vocabulary, read-only SQL, and this doc's scenario/verifier coverage). |
| `tests/permission_check.sh` | Step 05 permission boundary & destructive-command denial (config-level always; live runtime opt-in via `ACCEPTANCE_RUNTIME=1`). |
| `tests/redaction_check.sh` | Step 05 deterministic redaction/flagging using fixtures (no live DB). |
| `tests/codex_scaffold_check.sh` | Codex skill discovery anchors, custom-agent profile isolation, and read-only project configuration. |
| `npm test --prefix codex-bridge` | Bridge unit/integration behavior using synthetic rollout and temporary Git/project fixtures. |
| `tests/codex_acceptance_check.sh` | Cross-runtime AC-01 through AC-19 static/deterministic anchors and documentation contracts. |
| `tests/codex_live_check.sh` | Opt-in live Codex checks; defaults to `SKIP` and is never called by `run_all.sh`. |

Every script prints `PASS:` / `FAIL:` / `SKIP:` lines and exits non-zero on any
failure. `SKIP` (used only for the opt-in live runtime cases) is not a failure.

### Opt-in live runtime permission proof

The permission-boundary and destructive-command scenarios (13 and 14) require
an **actual runtime rejection**, not just intent. `tests/permission_check.sh`
always asserts the deny matrix encoded in `.opencode/opencode.json` (the
authoritative enforcement point). To additionally drive the agents headlessly
and observe live rejections:

```bash
ACCEPTANCE_RUNTIME=1 bash tests/permission_check.sh
```

This asks each agent (via `opencode run --agent ...`) to perform a forbidden
write / destructive command and asserts the forbidden target was never created.
It consumes model calls and needs network/credentials, so it is opt-in and not
part of the default mechanical suite.

### Opt-in live Codex proof

The live Codex entry point is separate from the deterministic suite:

```bash
CODEX_ACCEPTANCE_RUNTIME=1 bash tests/codex_live_check.sh
```

When the variable is unset, the script prints `SKIP` and exits 0. When enabled,
it creates a temporary trusted fixture project and isolated `CODEX_HOME`, copies
only authentication material needed for the invocation, and provides synthetic
rollout history. It verifies repository skill and custom-agent visibility,
exact MCP tool lists for the `topic`, `conventions`, and `writer` profiles, a
rejected direct write in the read-only Codex sandbox, and a successful scoped
MCP write inside the fixture. It never uses the real rollout store for a write
or destructive-boundary probe.

## OpenCode manual runtime script

Restart OpenCode, then walk these scenarios inside the project. For each, send
the prompt and confirm the expected observation.

For a manual Codex smoke test in a trusted project chat, use “Use
`extract-topics` to find topics from last week”, “Use `write-blog-article` to
write about topic 2”, or “Use `author-conventions` to complete the writing
conventions”. The main chat must keep the review questions and approvals while
delegating only bounded operations to the matching custom agent.

### Scenario 1 — Fresh-clone readiness

After editing `CONVENTIONS.md` (from `CONVENTIONS.template.md`), the project is
usable with no other setup; `tracked-projects.txt` remains optional.
**Observe**: `bash tests/acceptance_check.sh` passes on a fresh clone.

### Scenario 2 — Extractor DRAFT

Invoke `topic-extractor`: *"extract topics from last week"*.
**Observe**: `inputs/topics-YYYY-MM-DD.md` is created with `Status: DRAFT`, a
correct frontmatter table, candidate topics with correlated commit + session
sources, and an appendix.

### Scenario 3 — Auto-discovery path

With `tracked-projects.txt` absent (or comment-only), repeat scenario 2.
**Observe**: the extractor auto-discovers projects from the DB and confirms the
list via a `question` before writing.

### Scenario 4 — Allowlist path

With `tracked-projects.txt` present and listing specific paths, repeat.
**Observe**: only listed projects appear in the topics file.

### Scenario 5 — Redaction / flagging

Seed a session (or fixture) containing a secret-like string.
**Observe**: it is redacted and its topic carries a **Flagged** note. Automated
by `bash tests/redaction_check.sh`.

### Scenario 6 — Topics finalise

Approve the DRAFT via the agent's `question`.
**Observe**: `Status` flips to `FINAL`; no file body was embedded in the
`question`.

### Scenario 7 — Blog draft

Invoke `blog-writer`: *"write about topic 2"*.
**Observe**: it reads the right topic, reads `CONVENTIONS.md`, and creates
`drafts/<slug>.mdx` with `draft: true`.

### Scenario 8 — Bilingual sequence

Continue scenario 7.
**Observe**: English is drafted and iterated first, then the Italian
`<Lang value="it">` block and Italian frontmatter are added; the final file has
both `<Lang>` blocks and valid bilingual frontmatter with `tags` in
`{ id, label:{en,it} }` shape.

### Scenario 9 — MDX vocabulary

Inspect the drafted file.
**Observe**: only allowed components appear (`<Lang>`, `<TOCInline>`,
`lang:filename` code fences, footnotes, `<video>`, images).

### Scenario 10 — Article finalise

Approve the draft.
**Observe**: frontmatter `draft:` flips to `false`.

### Scenario 11 — Publish on command

Send *"publish &lt;slug&gt;"*.
**Observe**: `lastmod` changes to today's local `YYYY-MM-DD`, the original
`date` stays unchanged, and the file moves to `published/<slug>.mdx` with
`draft: false`. A publish for a **nonexistent slug** warns and does nothing.

### Scenario 12 — Missing conventions guard

Blank or remove `CONVENTIONS.md` (or leave it all-`<!-- TODO: -->`), then ask
`blog-writer` to draft.
**Observe**: it asks via `question` and refuses to draft.

### Scenario 13 — Permission boundaries (must reject)

Ask each agent to write outside its scope.
**Observe** (each a runtime rejection):

- topic-extractor writing outside `inputs/**` → rejected.
- blog-writer writing outside `drafts/**`/`inputs/**`/`published/**` → rejected.
- blog-writer editing a source project → refused.

Automated: `bash tests/permission_check.sh` (config-level always;
`ACCEPTANCE_RUNTIME=1` for the live proof).

### Scenario 14 — Destructive / remote git denied (must reject)

Ask each agent to run `git push`, `git commit --amend`, and `rm -rf`.
**Observe**: all denied for **both** agents. Automated as in scenario 13.

### Scenario 15 — Read-only DB

Inspect the extractor's DB usage.
**Observe**: all DB access uses `sqlite3 -readonly` and filters on the
`time_updated` column (no full-table scans of `session`). Automated by the
read-only SQL assertion in `bash tests/acceptance_check.sh`.

## Scenario → check → parent-criterion mapping

| Scenario | Check | Parent acceptance criterion |
|----------|-------|-----------------------------|
| 1 Fresh-clone readiness | `acceptance_check.sh` + manual | Fresh clone works after editing `CONVENTIONS.md`; `tracked-projects.txt` optional |
| 2 Extractor DRAFT | manual + `extract_topics_check.sh` | Running topic-extractor produces `topics-YYYY-MM-DD.md` with `Status: DRAFT` |
| 3 Auto-discovery | manual + `extract_topics_check.sh` | Absent allowlist → auto-discovers and confirms via `question` |
| 4 Allowlist | manual | Allowlist present → only listed projects considered |
| 5 Redaction/flagging | `redaction_check.sh` | Sensitive-keyword detection flags matching topics |
| 6 Topics finalise | manual | Approving flips topics `Status` to `FINAL`; DRAFT-first, no body in `question` |
| 7 Blog draft | manual + `blog_writer_check.sh` | blog-writer reads topic + `CONVENTIONS.md`, drafts `drafts/<slug>.mdx` `draft: true` |
| 8 Bilingual sequence | manual + `acceptance_check.sh` | English first, then Italian; both `<Lang>` blocks; `{id,label:{en,it}}` tags |
| 9 MDX vocabulary | manual + `acceptance_check.sh` | Articles use only allowed MDX components |
| 10 Article finalise | manual | Approval flips frontmatter `draft:` to `false` |
| 11 Publish on command | manual + `blog_writer_check.sh` | `publish <slug>` refreshes `lastmod`, preserves `date`, then moves the file to `published/`; nonexistent slug warns/no-op |
| 12 Missing conventions | manual + `blog_writer_check.sh` | Missing `CONVENTIONS.md` → asks and refuses to draft |
| 13 Permission boundaries | `permission_check.sh` (+ live) | Runtime rejects out-of-scope writes for both agents |
| 14 Destructive git denied | `permission_check.sh` (+ live) | `git push` / `git commit --amend` / `rm -rf` denied for both |
| 15 Read-only DB | `acceptance_check.sh` | DB access uses `sqlite3 -readonly` on `time_updated` |

## Edge cases

- **Empty activity window**: the extractor still writes a DRAFT stating the
  empty result; the blog-writer can still take a free-text topic.
- **DB unavailable**: the read-only `.tables` prerequisite above fails fast with
  a clear message; fix the DB path before running runtime scenarios.
- **Deleted tracked project**: the extractor warns and skips that project rather
  than aborting the run.
- **Empty commit/session window for a project**: skipped silently and noted in
  the topics appendix.
- **Fixtures vs. live data**: default checks use synthetic rollouts, temporary
  Git repositories, and temporary projects. They never inspect real Codex
  history or invoke a model.
