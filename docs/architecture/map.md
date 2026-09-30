# Architecture Map

## Generation Metadata

- Generated: 2026-09-28T01:25:38+02:00
- HEAD SHA: `b30cd10897015e092866465b0dc5720c3bfee767`
- Generation method: `arch-map (in-context fallback)`
- Scope: current repository state

## Modules

| Module | Responsibility | Entry points and key paths |
|---|---|---|
| Project guidance | Defines the two roles, safety invariants, and bilingual MDX target | `AGENTS.md`, `README.md` |
| OpenCode runtime adapter | Registers the two primary agents and enforces their per-agent read, write, and shell permissions | `.opencode/opencode.json`, `.opencode/agents/topic-extractor.md`, `.opencode/agents/blog-writer.md` |
| Topic extraction workflow | Resolves a time window and tracked projects, reads Git and OpenCode sessions, redacts quoted text, scores topics, and writes a reviewed candidate list | `.opencode/skills/extract-topics/SKILL.md`, `.opencode/skills/extract-topics/scripts/redact.py`, `tracked-projects.txt`, `inputs/` |
| Convention authoring workflow | Interviews the user and maintains the writing/MDX conventions consumed by the writer | `.opencode/skills/author-conventions/SKILL.md`, `CONVENTIONS.template.md`, `CONVENTIONS.md` |
| Article workflow | Resolves a topic, drafts English first, translates to Italian, manages draft approval, and records publication | `.opencode/skills/write-blog-article/SKILL.md`, `drafts/`, `published/`, `inputs/published-topics.md` |
| Specifications and plans | Records the intended behavior, implementation steps, and acceptance criteria | `specs/`, `plans/`, `docs/acceptance.md` |
| Verification | Performs static contract checks, redaction fixtures, and optional live OpenCode permission probes | `tests/run_all.sh`, `tests/*_check.sh` |

## Dependency Graph

```text
OpenCode runtime
  -> .opencode/opencode.json
  -> .opencode/agents/{topic-extractor,blog-writer}.md
       -> .opencode/skills/{extract-topics,write-blog-article}/SKILL.md

extract-topics
  -> tracked-projects.txt (optional allowlist)
  -> external Git repositories (read-only git log)
  -> ~/.local/share/opencode/opencode.db (read-only SQLite)
  -> redact.py
  -> CONVENTIONS.md (storytelling and taboo guidance)
  -> inputs/topics-*.md
  -> inputs/published-topics.md + published/*.mdx (deduplication)

write-blog-article
  -> CONVENTIONS.md
  -> inputs/topics-*.md or free text
  -> drafts/*.mdx
  -> published/*.mdx + inputs/published-topics.md
```

- Direction: runtime configuration selects agents; agents delegate behavior to skills; skills read external evidence and local conventions, then write only local workflow artifacts.
- Boundary: tracked source projects and the OpenCode database are observational inputs. `inputs/`, `drafts/`, and `published/` are the only workflow output stores.
- Observed cycles: the extractor reads the publication ledger produced by the writer to suppress already-published topics; no code-level dependency cycle was observed.

## Data Stores

| Store | Data | Access |
|---|---|---|
| `~/.local/share/opencode/opencode.db` | OpenCode `session`, `message`, and `part` rows with millisecond timestamps and JSON text parts | Read only through `sqlite3 -readonly`; queries filter `session.time_updated` |
| Tracked Git repositories | Commit SHA, timestamp, subject, and source material for fact checking | Read only through Git commands |
| `inputs/` | DRAFT/FINAL candidate-topic files and the published-topic ledger | Topic extractor writes candidates; writer appends publication records |
| `drafts/` | Bilingual MDX articles with `draft: true` during review | Writer only |
| `published/` | Approved bilingual MDX articles moved from drafts | Writer only, on explicit publish command |
| `CONVENTIONS.md` | Voice, structure, bilingual, MDX, tag, and taboo rules | Read by extraction/writer; authored by the conventions workflow |

Generated content under `inputs/`, `drafts/`, and `published/` is ignored by Git except for `.gitkeep` files.

## External Integrations

- OpenCode project runtime: agent discovery, skill loading, the `question` interaction, scoped editing, and command permissions are configured under `.opencode/`.
- OpenCode local history: `~/.local/share/opencode/opencode.db` is queried directly with the schema documented in the extraction skill.
- Git: each tracked repository is queried with `git -C <dir> log`; no source repository is modified.
- Tailwind/Next.js MDX blog: this repository generates files matching its bilingual frontmatter and component vocabulary but does not write to the blog repository.
- Remote services: None observed at runtime. Optional live permission tests invoke the locally installed OpenCode CLI and may require its configured model/network access.

## Test Topology

- Framework: Bash verification scripts with small inline Python checks; no unit-test framework.
- `tests/scaffold_check.sh`: repository structure and OpenCode permission schema.
- `tests/extract_topics_check.sh`: extractor skill, agent, SQL, and redaction contract anchors.
- `tests/conventions_check.sh`: conventions template and authoring workflow.
- `tests/blog_writer_check.sh`: writer workflow, MDX shape, publication behavior, and ledger anchors.
- `tests/acceptance_check.sh`: cross-cutting static acceptance scenarios.
- `tests/permission_check.sh`: deterministic OpenCode deny-matrix checks plus opt-in live runtime probes.
- `tests/redaction_check.sh`: secret-like and clean-text fixtures for `redact.py`.
- Fixtures: inline shell strings and temporary files; no separate fixture directory observed.

## Build and Test Commands

- Build: None. `README.md` and `.opencode/package.json` describe a configuration/prompt project; no build step is defined.
- Full mechanical suite: `bash tests/run_all.sh` (`README.md`, `tests/run_all.sh`).
- Individual checks: `bash tests/<name>_check.sh` (`README.md`, `docs/acceptance.md`).
- Optional live OpenCode permission proof: `ACCEPTANCE_RUNTIME=1 bash tests/permission_check.sh` (`README.md`, `docs/acceptance.md`).
- Database prerequisite check: `sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"` (`README.md`).
