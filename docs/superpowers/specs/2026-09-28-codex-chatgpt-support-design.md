# Codex Local/Desktop Support Design

**Slug:** `codex-chatgpt-support`
**Type:** feature
**Status:** APPROVED
**Provenance:** User request to add Codex local/desktop support without removing OpenCode support; `AGENTS.md`; `specs/blog-writer-project.md`; `docs/architecture/map.md`

## Problem

Blog-Writer currently depends on OpenCode-specific agent discovery, permissions,
interaction tools, and the schema of
`~/.local/share/opencode/opencode.db`. The editorial workflow itself is useful
outside OpenCode, but Codex cannot load the files under `.opencode/` as native
skills or reproduce OpenCode's per-agent write restrictions from that
configuration.

The project needs an additive Codex local/desktop implementation that can turn
recent Codex sessions and Git commits into the same reviewed candidate topics
and bilingual MDX articles, while the existing OpenCode implementation remains
operational and unchanged in behavior.

## Current Behavior

- OpenCode loads two primary agents and three supporting skills from
  `.opencode/`.
- The topic extractor correlates read-only Git history with OpenCode session
  transcripts, redacts secret-like text before writing it, scores candidates,
  and creates a DRAFT topics file under `inputs/`.
- The blog writer reads `CONVENTIONS.md`, drafts English before Italian, writes
  bilingual MDX under `drafts/`, and publishes only on explicit command.
- `.opencode/opencode.json` enforces per-agent write scopes and command
  restrictions.
- Generated topics, drafts, published articles, and the publication ledger use
  stable formats that are independent of the runtime.

## Desired Outcome

Add a Codex-native path that users invoke manually from Codex CLI or Codex
desktop. Codex repository skills drive the same user-visible workflows and use
a local MCP bridge as the only write and history-access surface. The Codex
workspace remains read-only to ordinary shell and edit operations; the bridge
exposes narrowly scoped operations for the files each workflow may change.

OpenCode keeps its existing agents, skills, configuration, history queries,
and acceptance suite. Both runtimes share the existing `CONVENTIONS.md`,
`tracked-projects.txt`, `inputs/`, `drafts/`, `published/`, topic-key rules,
DRAFT markers, and bilingual MDX vocabulary.

## Architecture

### Codex customization layer

- Keep the repository `AGENTS.md` as durable project guidance, updating its
  runtime-neutral wording where required while preserving OpenCode guidance.
- Add repository skills under `.agents/skills/` for:
  - `extract-topics`
  - `write-blog-article`
  - `author-conventions`
- Use the main Codex chat as the workflow coordinator. It owns every direct
  user question, approval gate, and summary so review remains conversational.
- Add project-scoped custom agents under `.codex/agents/` for topic extraction,
  convention authoring, and article writing. The main skills delegate bounded
  evidence and mutation steps to these agents; custom agents never ask the
  user questions themselves.
- Give each custom agent a read-only sandbox and only its matching MCP bridge
  profile. The bridge is not registered globally for the main chat, so an
  extractor cannot call writer tools and a writer cannot call convention or
  topic-output tools.
- Add `.codex/config.toml` with a read-only sandbox and multi-agent settings.
  The project configuration must not grant general workspace writes.

### Local MCP bridge

Implement a small Node.js ECMAScript-module MCP server using the official MCP
SDK. Each custom-agent configuration starts the bridge with exactly one role
profile, and the server exposes only that profile's tools. It must not expose
an arbitrary shell tool or an arbitrary-path file tool.

The profiles are:

- `topic`: `discover_projects`, `collect_activity`, `write_topic_draft`, and
  `finalize_topics`;
- `conventions`: `write_conventions`; and
- `writer`: `read_source_file`, `write_article_draft`,
  `finalize_article`, and `publish_article`.

The bridge owns these operations:

- `discover_projects`: discover candidate project directories from Codex
  session metadata within a time window.
- `collect_activity`: read and normalize bounded Codex session text and Git
  commit history for confirmed projects.
- `write_topic_draft`: create or revise the date-stamped topics DRAFT inside
  `inputs/`.
- `finalize_topics`: change only the topics file's `Status: DRAFT` marker to
  `Status: FINAL`.
- `write_conventions`: create or revise only the root `CONVENTIONS.md`.
- `read_source_file`: read a bounded text file only from a confirmed tracked
  project for article fact-checking.
- `write_article_draft`: create or revise an MDX article inside `drafts/`
  while preserving `draft: true` until approval.
- `finalize_article`: change only an article's `draft: true` marker to
  `draft: false`.
- `publish_article`: validate the finalized draft, refresh `lastmod`, move it
  to `published/`, and update `inputs/published-topics.md` without duplicate
  ledger entries.

The bridge derives its project root from its configured launch directory. It
must not accept a caller-supplied project root.

### Codex history adapter

The bridge reads local Codex rollout files discovered below the active Codex
home, defaulting to `~/.codex/sessions/**/*.jsonl`. Rollout storage is treated
as a versioned internal input rather than a stable business interface.

The adapter:

1. detects supported rollout record shapes;
2. extracts session identity, timestamp, working directory, title when
   available, and bounded user/assistant prose;
3. filters by the inclusive requested project set and `(lo, hi]` time window;
4. normalizes results into runtime-independent activity records;
5. caps record count, text-part count, per-session characters, and total
   response characters; and
6. redacts secret-like session text before returning it to Codex, adding a
   flagged reason to affected records.

Normalized records contain `source`, `project_dir`, `timestamp`, `kind`, `id`,
`title`, `text`, and optional metadata. Skills depend only on this normalized
shape, never on rollout JSON fields.

No internal Codex SQLite database name is part of the contract. Support for a
future history representation belongs behind the same adapter and must be
fixture-tested before use.

## Data Flow

### Topic extraction

1. The Codex `extract-topics` skill resolves the requested time window.
2. A non-empty `tracked-projects.txt` is the allowlist. Otherwise the skill
   delegates discovery to the topic custom agent and asks the user to confirm
   the discovered list in the main chat.
3. The topic custom agent calls `collect_activity`; the bridge reads Codex
   rollout records and Git commits, applies limits and redaction, and returns
   normalized evidence plus warnings.
4. The skill correlates evidence by project and timestamp, excludes published
   topic keys, scores candidates, and orders them by Overall score.
5. The main skill delegates persistence to the topic custom agent, which calls
   `write_topic_draft` to create `inputs/topics-YYYY-MM-DD.md` with
   `Status: DRAFT`.
6. After a short review question and explicit approval, `finalize_topics`
   performs the marker-only transition to FINAL.

### Article authoring

1. The main Codex `write-blog-article` skill validates `CONVENTIONS.md`,
   resolves a candidate topic or free-text topic, and delegates bounded file
   work to the writer custom agent.
2. The skill drafts and iterates on English first; the writer custom agent
   persists each approved revision through `write_article_draft`.
3. After English approval, it translates the article and writes the Italian
   block into the same DRAFT.
4. After bilingual approval, `finalize_article` performs the marker-only
   transition to `draft: false`.
5. Only an explicit publish command permits `publish_article` to refresh
   `lastmod`, move the article, and update the topic ledger.

### Convention authoring

The main Codex `author-conventions` skill retains the focused interview and
DRAFT-first review flow. It delegates persistence to the conventions custom
agent. `write_conventions` is that agent's only MCP operation and can target
only the repository-root `CONVENTIONS.md`.

## Security and Validation

- Codex runs with a read-only project sandbox. All intended mutations pass
  through the MCP bridge.
- Every bridge operation resolves and validates real paths against its fixed
  project root before reading or writing.
- Write operations reject path traversal, symlink escapes, unexpected file
  extensions, invalid slugs, oversized content, and paths outside their
  operation-specific destination.
- Topic and article draft creation rejects collisions unless the user has
  explicitly selected overwrite through the workflow.
- Marker-only finalization tools reject missing, ambiguous, or already-invalid
  markers rather than rewriting arbitrary content.
- Publication requires an existing article with `draft: false`; it never
  publishes directly from `draft: true`.
- Session collection never writes to Codex history and never invokes Git
  commands that modify tracked projects.
- Source-file reads require a path inside the confirmed tracked-project
  allowlist and enforce per-file and per-call character limits.
- Session-derived prose is redacted before it is returned to the model. A
  redaction adds a flagged reason that the topic workflow carries into review.
- Generated writes use a temporary sibling file and atomic rename. Publication
  must preserve the original draft and ledger if validation fails before the
  move; recovery behavior for an I/O failure after the move must be tested and
  reported clearly.

## Error Handling

- A missing Codex history directory or a history set with no supported rollout
  schema stops extraction with a clear error. Extraction does not silently
  degrade to Git-only evidence.
- A valid history store with no matching sessions is a valid empty result and
  still produces the normal empty topics DRAFT.
- Individual malformed rollout files are skipped, counted, and returned as
  warnings for the topics appendix. If no valid rollout remains, extraction
  fails.
- Missing, deleted, non-Git, or inactive allowlisted projects are reported and
  skipped consistently with the OpenCode workflow.
- Bridge protocol, validation, and file-system errors include the operation and
  safe target context without including transcript contents or secrets.
- Unknown rollout shapes fail closed and name the unsupported record types or
  schema version without dumping raw records.

## Acceptance Criteria

- **AC-01:** All pre-existing files under `.opencode/` remain present, and the
  existing OpenCode mechanical suite passes without changed expected behavior.
- **AC-02:** Codex discovers the three repository skills from
  `.agents/skills/` and the three role-scoped custom agents from
  `.codex/agents/`; each skill coordinates its Codex workflow without
  depending on OpenCode tools or database paths.
- **AC-03:** The trusted project `.codex/config.toml` configures a read-only
  sandbox and multi-agent support without granting general workspace write
  access or registering privileged bridge tools for the main chat.
- **AC-04:** Each custom agent starts only its matching bridge profile, and
  cross-role MCP operations are absent from its advertised tool list.
- **AC-05:** The bridge discovers Codex sessions by time window and working
  directory from supported rollout fixtures and returns the documented
  normalized activity shape.
- **AC-06:** `collect_activity` includes bounded Git commits and bounded,
  redacted Codex prose for confirmed projects only.
- **AC-07:** Missing or wholly unsupported Codex history fails clearly rather
  than falling back to Git-only topic generation.
- **AC-08:** Malformed individual rollouts produce bounded warnings while
  valid rollouts continue to be processed; zero valid rollouts fails.
- **AC-09:** The Codex topic workflow preserves the existing time-window,
  allowlist/confirmation, correlation, scoring, ordering, deduplication,
  Flagged-note, filename, DRAFT-first, and FINAL-transition behavior.
- **AC-10:** Topic write operations cannot modify anything outside
  `inputs/topics-*.md` and reject traversal, symlink escape, invalid dates,
  collisions without overwrite approval, invalid markers, and oversized
  content.
- **AC-11:** The Codex article workflow preserves the existing conventions
  guard, topic resolution, English-first iteration, Italian translation,
  bilingual MDX vocabulary, topic key, dates, DRAFT-first, finalization, and
  explicit publication behavior.
- **AC-12:** Article write and publication operations cannot modify arbitrary
  repository or source-project files and reject traversal, symlink escape,
  invalid slugs, wrong extensions, invalid markers, and oversized content.
- **AC-13:** Publication refreshes `lastmod`, preserves `date`, moves only a
  finalized article, and creates or updates the published-topic ledger without
  duplicate topic keys.
- **AC-14:** The Codex convention-authoring workflow can modify only the root
  `CONVENTIONS.md` and retains the focused interview and review behavior.
- **AC-15:** Deterministic tests use synthetic rollout and Git fixtures and do
  not inspect the user's real Codex history.
- **AC-16:** The default verification command runs the existing OpenCode suite
  and all deterministic Codex unit, integration, configuration, and skill
  checks without network access or model calls.
- **AC-17:** An opt-in live Codex acceptance command verifies skill discovery,
  MCP availability, read-only sandbox behavior, and scoped bridge writes while
  remaining excluded from the default suite.
- **AC-18:** README and acceptance documentation explain both runtimes,
  prerequisites, configuration trust/restart requirements, local-history
  privacy, deterministic versus live verification, and their invocation
  commands.
- **AC-19:** The known shared-contract contradictions are corrected: the
  `time_updated` index claim matches the verified OpenCode schema, topic
  filenames consistently use the run date, and placeholder-only conventions
  are consistently rejected.

## Testing Strategy

- Use Node's built-in test runner for bridge unit and integration tests.
- Use synthetic JSONL rollouts covering supported records, malformed lines,
  unknown records, multiple working directories, boundary timestamps,
  redaction, and volume limits.
- Create temporary Git repositories for commit-window and read-only behavior
  tests.
- Test every bridge operation against temporary project roots, including
  containment, symlinks, collisions, marker transitions, atomic writes,
  publication recovery, and ledger idempotence.
- Add static shell checks for Codex skill metadata and workflow anchors,
  custom-agent role isolation, `.codex/config.toml`, bridge profiles, and
  runtime-neutral documentation.
- Keep `bash tests/run_all.sh` as the complete default verification entry point
  by extending it to run deterministic Codex tests after the existing checks.
- Add an explicit environment-gated live Codex verifier. It must use temporary
  fixture projects rather than real history for destructive or write-boundary
  probes.

## Edge Cases

- The Codex home is overridden through `CODEX_HOME`.
- Rollout files span multiple date directories or contain sessions that began
  before but were updated within the requested window.
- A session changes working directory or references a project that no longer
  exists.
- Multiple rollout files refer to the same session or message.
- The time window crosses a daylight-saving or local-date boundary.
- The allowlist contains comments, blank lines, duplicates, relative paths, or
  nonexistent directories.
- Redaction expands or shortens text near configured character limits.
- A topics or draft filename already exists for the requested date or slug.
- An article ledger entry already exists, or publication is retried after a
  partially completed I/O operation.
- Codex launches with an untrusted project configuration and therefore does
  not start the bridge.

## Constraints

- Preserve the current OpenCode implementation and generated-file formats.
- Keep both runtimes manually invoked; add no scheduling or automation.
- Source projects and Codex history are strictly read-only.
- Continue using the existing controlled MDX component vocabulary.
- Apply YAGNI: one local bridge, one Codex history adapter, and no abstraction
  for remote ChatGPT data sources.
- The deterministic suite must run without network access, model calls, or
  access to real user history.
- New dependencies must be runtime-essential and pinned through the bridge's
  package lock.

## Out of Scope

- Ingesting ordinary ChatGPT web conversation history.
- Accessing OpenAI-hosted account history or building a remote connector.
- Replacing, deleting, or migrating the OpenCode implementation.
- Scheduling extraction or publication.
- Copying published articles into the separate blog repository.
- Supporting arbitrary Codex internal SQLite database schemas.
- Adding a general-purpose file manager, shell, or Git mutation tool to the
  bridge.

## Notes

- Current local evidence shows Codex rollout JSONL under
  `~/.codex/sessions/YYYY/MM/DD/`, but that path and schema remain behind the
  adapter and are not treated as a public persistence API.
- Codex command rules may supplement the read-only sandbox, but command rules
  alone do not establish the per-path write guarantees required here.
- The architecture map was created during discovery and remains a separate
  documentation artifact; it is not part of this specification commit.
