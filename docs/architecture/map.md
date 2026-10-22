# Architecture Map

## Generation Metadata

- Generated: 2026-10-23
- Evidence baseline: `82d03ef052a419ce51e7faefbc8de5bf278c1763`, plus the documentation update containing this map
- Generation method: repository inspection during approved `codex-desktop-workflows` implementation
- Scope: both runtime adapters, bounded bridge, shared artifacts, and verification

## Modules

| Module | Responsibility | Entry points and key paths |
|---|---|---|
| Project guidance | Shared editorial invariants, runtime setup, and publication boundaries | `AGENTS.md`, `README.md`, `CONVENTIONS.md`, `CONVENTIONS.template.md` |
| OpenCode runtime | Two primary agents, scoped editing, read-only history, command permissions | `.opencode/opencode.json`, `.opencode/agents/`, `.opencode/skills/` |
| Codex main-chat workflows | Topic discovery/review, conventions interview, English-first writing/translation and approval gates | `.agents/skills/{extract-topics,author-conventions,write-blog-article}/SKILL.md` |
| Codex registration | Read-only main session and fixed desktop MCP bootstrap | `.codex/config.toml` |
| CLI compatibility | Fixed invocation-scoped topic/writer catalogs, prerequisite validation, primary-root prompt | `bin/blog-writer-codex` |
| MCP boundary | Fixed catalogs, matching schemas/handlers, primary-checkout data resolution | `codex-bridge/src/server.mjs`, `codex-bridge/src/profiles.mjs`, `codex-bridge/src/tools/` |
| Activity collection | Bounded rollout JSONL and Git observations, normalization, redaction | `codex-bridge/src/{history,git,activity,redact,limits}.mjs` |
| Validated persistence | Topic/conventions/article writes, bounded source reads, paths, atomic replacement and publication rollback | `codex-bridge/src/{topics,conventions,articles,source-files,paths,atomic}.mjs` |
| Design history | Governing specifications/plans and earlier project requirements | `docs/superpowers/`, `specs/`, `plans/` |
| Verification | Static checks, Node unit/SDK tests, protocol fixtures, isolated opt-in runtime probes | `tests/`, `codex-bridge/test/`, `docs/acceptance.md` |

## Dependency Graph

```text
OpenCode -> .opencode/opencode.json -> agents -> .opencode/skills/
                                             -> read-only OpenCode SQLite + Git
                                             -> shared workflow artifacts

Codex desktop -> .codex/config.toml -> fixed /bin/sh bootstrap -> Node MCP
               -> .agents/skills/ (main chat owns all approvals) -> MCP calls
Codex launcher -> canonical MCP command/args override -> topic or writer profile

Node MCP server -> profiles -> existing topic/conventions/writer handlers
                  -> read-only rollout adapter + Git + bounded source reads
                  -> validated shared workflow artifacts
```

The desktop profile is the fixed union of nine existing operations:
`discover_projects`, `collect_activity`, `write_topic_draft`, `finalize_topics`,
`write_conventions`, `read_source_file`, `write_article_draft`, `finalize_article`,
and `publish_article`. The narrow `topic` (four), `conventions` (one), and
`writer` (four) profiles preserve their exact catalogs and schemas.
There are no project Codex custom agents or delegation fallback. No bridge
operation accepts shell commands, arbitrary mutation paths, or a project root.

The fixed bootstrap resolves the code root through `git rev-parse
--show-toplevel` from the app working directory; MCP `cwd` is unset. The server
independently resolves Git's common `.git` directory and uses its parent as the
workflow data root. A linked worktree supplies code, while the primary checkout
supplies `CONVENTIONS.md`, `tracked-projects.txt`, `inputs/`, `drafts/`, and
`published/`. Source projects and runtime history are observational inputs.

## Data Stores and Boundaries

| Store | Data | Access |
|---|---|---|
| OpenCode SQLite | Sessions, messages, text parts | `sqlite3 -readonly`; bounded by `session.time_updated` (not indexed in the verified schema) |
| `~/.codex/sessions/**/*.jsonl` or selected `CODEX_HOME` | Local rollout activity | Bounded read-only adapter; missing/unsupported history fails closed; no internal SQLite or ChatGPT web history |
| Confirmed source projects | Git history and fact-check material | Read only; source paths require confirmed project allowlists |
| `CONVENTIONS.md` | Real writing guidance and fixed MDX vocabulary | Main-chat interview; Codex persistence through `write_conventions` |
| `inputs/topics-*.md` | DRAFT/FINAL topic lists with stable keys | DRAFT persistence; explicit marker-only finalization |
| `drafts/*.mdx` | English-first, then bilingual articles | Review stages; explicit finalization sets `draft: false` without publishing |
| `published/*.mdx`, `inputs/published-topics.md` | Finalized article and topic-key/slug/date ledger | Explicit publication; collision/duplicate protections and rollback |

The publication ledger feeds topic exclusion. Manual file moves do not update
it; there is no watcher or reconciliation operation. Generated topic, draft,
and publication content is ignored by Git except for `.gitkeep` files.

Both runtimes are invoked manually. Model execution can require network and
configured authentication; the bridge itself uses local files and Git. Output
targets the bilingual Tailwind/Next.js MDX format without deploying to a blog
repository. There are no schedules or source-project mutations.

## Test Topology

- `tests/run_all.sh` runs the complete deterministic suite without a model or real history.
- Existing OpenCode scaffold, extraction, conventions, article, acceptance,
  permission, and redaction checks preserve the original runtime contracts.
- `tests/codex_scaffold_check.sh` verifies direct skill routing, exact mode
  contracts, read-only configuration, and removal of custom-agent definitions.
- `tests/codex_launcher_check.sh` uses fake executables to check exact narrow
  overrides, prerequisites, prompt isolation, roots, and exit propagation.
- `codex-bridge/test/*.test.mjs` uses Node's test runner, temporary Git/data
  roots, synthetic rollouts, and the real MCP SDK. It covers path/symlink
  boundaries, history/redaction, exact catalogs and schema parity, portable
  nested/spaced/worktree startup, persistence, finalization, publication,
  collisions, deduplication, and rollback.
- `tests/codex_live_events_check.py` tests protocol/evidence correlation,
  including adversarial parent/child/turn identity, catalog, argument, and
  result cases. `tests/codex_acceptance_check.sh` invokes these offline fixtures.
- `tests/codex_live_check.sh` and `tests/codex_runtime_probe.py` opt in to actual
  app-server/model calls in a temporary trusted project with isolated homes and
  synthetic history. All three structured skill inputs share one parent;
  separate narrow-profile probes remain. Actual calls and bytes are required.
  The direct command RPC must demonstrate the configured sandbox's denial.
- A desktop restart and reviewed fixture smoke test is a separate UI rollout
  check. App-server evidence and static checks alone do not prove that step.

## Build and Test Commands

There is no build step. Install the pinned MCP SDK dependency with
`npm install --prefix codex-bridge` (Node.js 20+).

- Full offline suite: `bash tests/run_all.sh`
- Bridge tests: `npm test --prefix codex-bridge`
- Protocol fixtures: `python3 tests/codex_live_events_check.py`
- Opt-in Codex runtime: `CODEX_ACCEPTANCE_RUNTIME=1 bash tests/codex_live_check.sh`
- Opt-in OpenCode permissions: `ACCEPTANCE_RUNTIME=1 bash tests/permission_check.sh`
- OpenCode database prerequisite: `sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"`

See `docs/acceptance.md` for expected evidence, failures, and desktop smoke steps.
