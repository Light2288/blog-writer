# Codex Local/Desktop Support Implementation Plan

**Slug:** `codex-chatgpt-support`
**Status:** APPROVED
**Provenance:** `docs/superpowers/specs/2026-09-28-codex-chatgpt-support-design.md`
**Execution tier:** full
**Implementation model role:** full

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an additive, runtime-enforced Codex CLI/desktop workflow that consumes local Codex history and Git activity while preserving the existing OpenCode implementation and output formats.

**Architecture:** Repository Codex skills coordinate user interaction in the main chat and delegate bounded work to three project custom agents. Each custom agent runs read-only and starts the same local Node.js MCP bridge with a different role profile, so history access and every mutation remain operation- and path-scoped.

**Tech Stack:** Node.js 20+ ECMAScript modules, `@modelcontextprotocol/sdk` 1.30.1, Node's built-in test runner, Bash acceptance checks, Codex repository skills/custom-agent TOML, existing Python redaction behavior as the compatibility reference.

**Spec:** `docs/superpowers/specs/2026-09-28-codex-chatgpt-support-design.md`

## Global Constraints

- Preserve all existing `.opencode/**` runtime behavior and generated-file formats.
- Keep OpenCode and Codex manually invoked; add no automation or schedule.
- Treat source projects and local Codex history as read-only.
- Run the Codex main chat and every custom agent with a read-only sandbox; intended writes go only through profiled MCP operations.
- Keep the existing topic filename, scoring, DRAFT/FINAL markers, topic-key ledger, English-first bilingual workflow, and controlled MDX vocabulary.
- Do not ingest ordinary ChatGPT web history or internal Codex SQLite databases.
- Pin only runtime-essential dependencies through `codex-bridge/package-lock.json`.
- Default deterministic tests must not access real Codex history, require model calls, or initiate network access.
- Follow YAGNI: one bridge, one rollout adapter, three role profiles, and no general shell or file tool.

## Repository Evidence

- Approved specification: `docs/superpowers/specs/2026-09-28-codex-chatgpt-support-design.md` at HEAD `8d29ea676019d09a786b293171cc2253d95aeaa0`.
- Architecture map: `docs/architecture/map.md`; stale because its recorded HEAD is `b30cd10897015e092866465b0dc5720c3bfee767`, while planning HEAD is `8d29ea676019d09a786b293171cc2253d95aeaa0`. Every recorded key path checked during planning still exists. Per planning policy, the map was not regenerated.
- ADRs: none observed under `docs/`; no accepted or proposed ADR constrains this plan.
- Existing verification entry point: `bash tests/run_all.sh` from `README.md` and `tests/run_all.sh`.
- Existing live OpenCode pattern: `ACCEPTANCE_RUNTIME=1 bash tests/permission_check.sh` from `README.md` and `docs/acceptance.md`.
- Codex deterministic-test requirement and Node built-in runner: approved specification, Testing Strategy.
- MCP SDK version: npm registry reported `@modelcontextprotocol/sdk` `1.30.1` during read-only planning discovery.

## Assumptions and Decisions

- Supported rollout v1 consists of JSONL containing `session_meta` and timestamped records with `response_item` message payloads; unknown record types are ignored only when at least one supported session/message shape remains.
- A session is in `(lo, hi]` when its latest valid record timestamp is in that window, matching the existing updated-session semantics.
- Candidate rollout files are discovered recursively under `${CODEX_HOME:-~/.codex}/sessions`; file modification time may prune files at or before `lo`, but inclusion is decided from parsed record timestamps.
- Limits are constants: 2,000 candidate rollout files, 100 sessions, 40 text parts per session, 6,000 characters per session, 120,000 returned transcript characters, 20,000 characters per source-file fact check, and 1 MiB per generated-file write.
- The main chat owns user questions. Custom agents return structured summaries and never request user input.
- The project custom-agent MCP tables are the only bridge registrations; the main `.codex/config.toml` does not register the bridge.

## Review Focus

- Duplicate or long-running rollout files: deduplicate messages and select sessions by their latest valid record timestamp without silently dropping a session updated inside the window. Task 2 adds boundary and duplicate fixtures.
- Oversized or adversarial JSONL: bound files, records, parts, and characters; skip malformed lines without echoing raw content; fail if no supported record remains. Task 2 adds size and malformed-input tests.
- Profile leakage: each custom agent must advertise only its profile's tool names and the main chat must have no privileged bridge registration. Tasks 1 and 5 add negative tool-list and configuration tests.
- Path/symlink replacement: real-path containment and final-target checks must reject traversal and symlink escapes immediately before atomic rename. Tasks 3 and 4 add symlink and containment tests.
- Partial publication: a ledger or rename failure must restore the draft and leave no duplicate published article or ledger key. Task 4 adds injected-failure recovery tests.

## File Structure

- `codex-bridge/src/server.mjs`: MCP startup, profile selection, dependency construction, and tool registration.
- `codex-bridge/src/profiles.mjs`: immutable profile-to-tool mapping and CLI profile parsing.
- `codex-bridge/src/history.mjs`: rollout discovery, shape detection, message extraction, deduplication, and limits.
- `codex-bridge/src/git.mjs`: bounded read-only commit collection.
- `codex-bridge/src/activity.mjs`: normalized activity aggregation and warning/statistics shape.
- `codex-bridge/src/redact.mjs`: JavaScript equivalent of the existing conservative secret redaction contract.
- `codex-bridge/src/paths.mjs`: project-root containment, slug/date validation, symlink rejection, and size limits.
- `codex-bridge/src/atomic.mjs`: sibling temporary writes and atomic rename/rollback primitives.
- `codex-bridge/src/topics.mjs`: topic draft and marker-only finalization operations.
- `codex-bridge/src/conventions.mjs`: root conventions-file operation.
- `codex-bridge/src/source-files.mjs`: bounded reads from confirmed tracked-project roots.
- `codex-bridge/src/articles.mjs`: article draft/finalize/publish and idempotent ledger operations.
- `codex-bridge/src/tools/*.mjs`: MCP schemas and handlers grouped by `topic`, `conventions`, and `writer` profile.
- `codex-bridge/test/**/*.test.mjs`: focused Node tests with temporary projects and synthetic fixtures.
- `.agents/skills/*/SKILL.md`: Codex workflow coordinators.
- `.codex/agents/*.toml`: read-only custom agents with one MCP profile each.
- `.codex/config.toml`: read-only main session and multi-agent settings, without global bridge tools.
- `tests/codex_*_check.sh`: static/deterministic and opt-in live acceptance entry points.

## Criterion Traceability

| Criteria | Owning task | Primary verification |
|---|---|---|
| AC-01, AC-16 | Task 6 | `bash tests/run_all.sh` includes old and new deterministic suites |
| AC-02, AC-03, AC-04 | Tasks 1 and 5 | profile unit tests plus `tests/codex_scaffold_check.sh` |
| AC-05, AC-06, AC-07, AC-08, AC-15 | Task 2 | synthetic rollout/Git tests |
| AC-09, AC-10 | Task 3 and Task 5 | topic operation tests plus skill static checks |
| AC-11, AC-12, AC-13 | Task 4 and Task 5 | article/source/publication tests plus skill static checks |
| AC-14 | Task 3 and Task 5 | conventions operation and skill tests |
| AC-17 | Task 6 | `CODEX_ACCEPTANCE_RUNTIME=1 bash tests/codex_live_check.sh` |
| AC-18, AC-19 | Task 6 | documentation/static contract checks |

---

### Task 1: MCP bridge scaffold and role-profile isolation [size: M | risk: security | mechanical: false | clear_pattern: true | objectively_verifiable: true | concerns: security]

**Acceptance criteria:** AC-02, AC-03, AC-04

**Files:**
- Create: `codex-bridge/package.json`
- Create: `codex-bridge/package-lock.json`
- Create: `codex-bridge/src/profiles.mjs`
- Create: `codex-bridge/src/server.mjs`
- Create: `codex-bridge/test/profiles.test.mjs`
- Create: `codex-bridge/test/server.test.mjs`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: Node.js 20+; `@modelcontextprotocol/sdk` 1.30.1.
- Produces: `PROFILE_TOOL_NAMES: Readonly<Record<'topic'|'conventions'|'writer', readonly string[]>>`; `parseProfile(argv: string[]) -> 'topic'|'conventions'|'writer'`; `registerProfileTools(server, profile, handlers) -> void`; `createServer({ profile, projectRoot, dependencies }) -> McpServer`.

- [ ] **Step 1: Write the failing profile tests**

Create tests named `parseProfile_accepts_exact_profiles`, `parseProfile_rejects_missing_or_unknown_profile`, and `profileToolNames_do_not_leak_cross_role_operations`. Assert the exact tool sets from the specification, including `read_source_file` only in `writer`.

- [ ] **Step 2: Run the profile test to verify it fails**

Run: `node --test codex-bridge/test/profiles.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `src/profiles.mjs`.

- [ ] **Step 3: Create the bridge package manifest and pinned dependency declaration**

Set `type` to `module`, `engines.node` to `>=20`, dependency `@modelcontextprotocol/sdk` to exact version `1.30.1`, and scripts `test: node --test` and `start: node src/server.mjs`. Add `codex-bridge/node_modules/` to `.gitignore`.

- [ ] **Step 4: Generate the package lock and install the declared dependency**

Run: `npm install --prefix codex-bridge`
Expected: exit 0; `codex-bridge/package-lock.json` pins the MCP SDK and transitive dependencies.

- [ ] **Step 5: Implement the immutable profile map and exact `--profile` parser**

Implement `PROFILE_TOOL_NAMES` and `parseProfile(argv)` in `src/profiles.mjs`. Reject absent, repeated, or unknown profiles with an error that lists only the three accepted names.

- [ ] **Step 6: Run the profile test to verify it passes**

Run: `node --test codex-bridge/test/profiles.test.mjs`
Expected: PASS with 3 tests and 0 failures.

- [ ] **Step 7: Write the failing server-registration tests**

Create tests named `registerProfileTools_registers_only_selected_names` and `createServer_does_not_register_arbitrary_shell_or_file_tools`. Use a fake server and fake handlers; assert exact advertised names for all three profiles.

- [ ] **Step 8: Run the server test to verify it fails**

Run: `node --test codex-bridge/test/server.test.mjs`
Expected: FAIL because `registerProfileTools` and `createServer` are not exported.

- [ ] **Step 9: Implement MCP server construction with injected handlers**

In `src/server.mjs`, use `McpServer` and `StdioServerTransport`; register tools solely through `registerProfileTools`. Keep handler dependencies injectable so later tasks add implementations without changing profile selection.

- [ ] **Step 10: Run Task 1 tests**

Run: `node --test codex-bridge/test/profiles.test.mjs codex-bridge/test/server.test.mjs`
Expected: PASS with 5 tests and 0 failures.

- [ ] **Step 11: Commit Task 1**

```bash
git add .gitignore codex-bridge/package.json codex-bridge/package-lock.json codex-bridge/src/profiles.mjs codex-bridge/src/server.mjs codex-bridge/test/profiles.test.mjs codex-bridge/test/server.test.mjs
git commit -m "feat(codex): scaffold profiled MCP bridge"
```

### Task 2: Bounded Codex-history and Git activity ingestion [size: L | risk: data | mechanical: false | clear_pattern: false | objectively_verifiable: true | concerns: ambiguous,data,performance]

**Acceptance criteria:** AC-05, AC-06, AC-07, AC-08, AC-15

**Files:**
- Create: `codex-bridge/src/limits.mjs`
- Create: `codex-bridge/src/redact.mjs`
- Create: `codex-bridge/src/history.mjs`
- Create: `codex-bridge/src/git.mjs`
- Create: `codex-bridge/src/activity.mjs`
- Create: `codex-bridge/src/tools/topic.mjs`
- Create: `codex-bridge/test/fixtures/rollouts/supported.jsonl`
- Create: `codex-bridge/test/fixtures/rollouts/duplicate.jsonl`
- Create: `codex-bridge/test/fixtures/rollouts/malformed.jsonl`
- Create: `codex-bridge/test/fixtures/rollouts/unsupported.jsonl`
- Create: `codex-bridge/test/redact.test.mjs`
- Create: `codex-bridge/test/history.test.mjs`
- Create: `codex-bridge/test/git.test.mjs`
- Create: `codex-bridge/test/activity.test.mjs`

**Interfaces:**
- Consumes: `createServer` handler injection from Task 1; existing redaction contract in `.opencode/skills/extract-topics/scripts/redact.py`.
- Produces: `LIMITS`; `redactText(text: string) -> { text: string, flagged: boolean, reasons: string[] }`; `scanRollouts(options) -> Promise<{ sessions, warnings, stats }>`; `collectGitCommits(options) -> Promise<{ records, warnings }>`; `collectActivity(options) -> Promise<{ records, warnings, stats }>` where every record has `source`, `project_dir`, `timestamp`, `kind`, `id`, `title`, `text`, and `metadata`.

- [ ] **Step 1: Write failing redaction compatibility tests**

Port the existing clean and secret-like fixtures. Assert identical replacement labels for `client_secret`, bearer, `api_key`, token, long hex, and long base64; assert unique `reasons` and no flag for clean prose.

- [ ] **Step 2: Run the redaction test to verify it fails**

Run: `node --test codex-bridge/test/redact.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `src/redact.mjs`.

- [ ] **Step 3: Implement shared limits and redaction**

Define the exact numeric limits from Assumptions and implement `redactText` without logging input text.

- [ ] **Step 4: Run the redaction test to verify it passes**

Run: `node --test codex-bridge/test/redact.test.mjs`
Expected: PASS with all secret and clean fixtures.

- [ ] **Step 5: Write failing rollout-adapter tests and synthetic fixtures**

Cover `(lo, hi]` latest-record boundaries, `CODEX_HOME`, working-directory filtering, user/assistant message extraction, duplicate item IDs, per-session and total truncation, malformed-line warnings without raw content, unknown records mixed with supported records, zero-supported-record failure, and the 2,000-file cap.

- [ ] **Step 6: Run the rollout test to verify it fails**

Run: `node --test codex-bridge/test/history.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `src/history.mjs`.

- [ ] **Step 7: Implement rollout discovery and normalization**

Implement recursive JSONL discovery below `<codexHome>/sessions`, mtime pruning, supported-shape parsing, latest-valid-timestamp selection, `(lo, hi]` filtering, stable message deduplication, limits, redaction, warnings, and fail-closed errors.

- [ ] **Step 8: Run the rollout test to verify it passes**

Run: `node --test codex-bridge/test/history.test.mjs`
Expected: PASS for supported, boundary, duplicate, malformed, unsupported, and limit cases.

- [ ] **Step 9: Write failing temporary-Git tests**

Create temporary repositories with commits before, inside, and after the window. Assert only `git log` data inside `(lo, hi]`, stable SHA/timestamp/subject fields, warnings for missing/non-Git paths, and no working-tree mutation.

- [ ] **Step 10: Run the Git test to verify it fails**

Run: `node --test codex-bridge/test/git.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `src/git.mjs`.

- [ ] **Step 11: Implement read-only Git collection**

Use `execFile('git', ['-C', project, 'log', ...])` with no shell, return normalized records, and convert per-project failures into bounded warnings.

- [ ] **Step 12: Run the Git test to verify it passes**

Run: `node --test codex-bridge/test/git.test.mjs`
Expected: PASS and temporary repositories remain clean.

- [ ] **Step 13: Write failing activity-aggregation tests**

Assert confirmed-project filtering, deterministic sort by timestamp/source/id, combined stats, warnings, missing-history failure, valid-empty-window success, and transcript limits before Git records are appended.

- [ ] **Step 14: Run the activity test to verify it fails**

Run: `node --test codex-bridge/test/activity.test.mjs`
Expected: FAIL because `collectActivity` is not implemented.

- [ ] **Step 15: Implement `collectActivity` and topic-profile read handlers**

Compose rollout and Git collectors, create the topic-profile module with `discover_projects` and `collect_activity` handlers, validate millisecond bounds and absolute confirmed project paths, and return no raw exception payloads.

- [ ] **Step 16: Run Task 2 tests**

Run: `node --test codex-bridge/test/redact.test.mjs codex-bridge/test/history.test.mjs codex-bridge/test/git.test.mjs codex-bridge/test/activity.test.mjs`
Expected: PASS with 0 failures and no access to the real Codex home.

- [ ] **Step 17: Commit Task 2**

```bash
git add codex-bridge/src/limits.mjs codex-bridge/src/redact.mjs codex-bridge/src/history.mjs codex-bridge/src/git.mjs codex-bridge/src/activity.mjs codex-bridge/src/tools codex-bridge/test
git commit -m "feat(codex): collect bounded local activity"
```

### Task 3: Scoped topic and convention mutations [size: M | risk: security | mechanical: false | clear_pattern: true | objectively_verifiable: true | concerns: security,data]

**Acceptance criteria:** AC-09, AC-10, AC-14

**Files:**
- Create: `codex-bridge/src/paths.mjs`
- Create: `codex-bridge/src/atomic.mjs`
- Create: `codex-bridge/src/topics.mjs`
- Create: `codex-bridge/src/conventions.mjs`
- Modify: `codex-bridge/src/tools/topic.mjs`
- Create: `codex-bridge/src/tools/conventions.mjs`
- Create: `codex-bridge/test/paths.test.mjs`
- Create: `codex-bridge/test/topics.test.mjs`
- Create: `codex-bridge/test/conventions.test.mjs`

**Interfaces:**
- Consumes: `LIMITS`, profile registration, and project root from Tasks 1-2.
- Produces: `assertContainedTarget(root, target, policy) -> Promise<string>`; `atomicWrite(target, content, { fsOps, beforeRename }) -> Promise<void>` where `fsOps` and `beforeRename` are injectable test seams with production defaults; `writeTopicDraft({ date, content, overwrite })`; `finalizeTopics({ date })`; `writeConventions({ content, overwrite })`.

- [ ] **Step 1: Write failing containment and atomic-write tests**

Cover exact allowed targets, `..`, absolute escape, existing symlink target, symlink parent, wrong extension, invalid date, 1 MiB boundary, collision without `overwrite`, and a target swapped to a symlink immediately before rename.

- [ ] **Step 2: Run the path test to verify it fails**

Run: `node --test codex-bridge/test/paths.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `src/paths.mjs`.

- [ ] **Step 3: Implement containment and atomic-write primitives**

Resolve the fixed root once; use `lstat`/`realpath` on existing ancestors and target, create same-directory temporary files with restrictive mode, revalidate before rename, and remove temporary files on every failure.

- [ ] **Step 4: Run the path test to verify it passes**

Run: `node --test codex-bridge/test/paths.test.mjs`
Expected: PASS for containment, symlink, collision, size, and cleanup cases.

- [ ] **Step 5: Write failing topic-operation tests**

Assert `inputs/topics-YYYY-MM-DD.md` only, exactly one `Status: DRAFT`, overwrite approval, marker-only `DRAFT` to `FINAL`, rejection of missing/duplicate/already-final markers, and unchanged bytes outside the marker.

- [ ] **Step 6: Run the topic test to verify it fails**

Run: `node --test codex-bridge/test/topics.test.mjs`
Expected: FAIL because topic operations are absent.

- [ ] **Step 7: Implement topic operations and MCP handlers**

Implement `writeTopicDraft` and `finalizeTopics`; expose schemas with only `date`, `content`, and explicit `overwrite` where applicable.

- [ ] **Step 8: Run the topic test to verify it passes**

Run: `node --test codex-bridge/test/topics.test.mjs`
Expected: PASS and every rejected request leaves the temporary project unchanged.

- [ ] **Step 9: Write failing conventions-operation tests**

Assert the only target is root `CONVENTIONS.md`, content must be non-empty and within 1 MiB, collision requires overwrite approval, and sibling/root files remain unchanged.

- [ ] **Step 10: Run the conventions test to verify it fails**

Run: `node --test codex-bridge/test/conventions.test.mjs`
Expected: FAIL because `writeConventions` is absent.

- [ ] **Step 11: Implement conventions operation and MCP handler**

Implement `writeConventions` using the shared atomic primitive and register it only in the `conventions` profile.

- [ ] **Step 12: Run Task 3 tests**

Run: `node --test codex-bridge/test/paths.test.mjs codex-bridge/test/topics.test.mjs codex-bridge/test/conventions.test.mjs codex-bridge/test/server.test.mjs`
Expected: PASS with exact profile tool lists unchanged.

- [ ] **Step 13: Commit Task 3**

```bash
git add codex-bridge/src/paths.mjs codex-bridge/src/atomic.mjs codex-bridge/src/topics.mjs codex-bridge/src/conventions.mjs codex-bridge/src/tools/topic.mjs codex-bridge/src/tools/conventions.mjs codex-bridge/test
git commit -m "feat(codex): enforce topic and convention writes"
```

### Task 4: Scoped source reads and recoverable article publication [size: L | risk: data | mechanical: false | clear_pattern: true | objectively_verifiable: true | concerns: security,data]

**Acceptance criteria:** AC-11, AC-12, AC-13

**Files:**
- Create: `codex-bridge/src/source-files.mjs`
- Create: `codex-bridge/src/articles.mjs`
- Create: `codex-bridge/src/tools/writer.mjs`
- Create: `codex-bridge/test/source-files.test.mjs`
- Create: `codex-bridge/test/articles.test.mjs`

**Interfaces:**
- Consumes: containment/atomic primitives and limits from Tasks 2-3.
- Produces: `readSourceFile({ path, confirmedProjects }) -> Promise<{ path, text, truncated }>`; `writeArticleDraft({ slug, content, overwrite })`; `finalizeArticle({ slug })`; `publishArticle({ slug, publicationDate }) -> Promise<{ publishedPath, ledgerUpdated }>`.

- [ ] **Step 1: Write failing bounded source-read tests**

Assert absolute paths only, containment within a confirmed project, rejection of symlink escapes/directories/binary content, 20,000-character truncation, and no access when the confirmed list is empty.

- [ ] **Step 2: Run the source-read test to verify it fails**

Run: `node --test codex-bridge/test/source-files.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `src/source-files.mjs`.

- [ ] **Step 3: Implement `readSourceFile`**

Validate confirmed project real paths, revalidate the requested file, read UTF-8 text only, and return truncation metadata without permitting writes.

- [ ] **Step 4: Run the source-read test to verify it passes**

Run: `node --test codex-bridge/test/source-files.test.mjs`
Expected: PASS for containment, symlink, binary, and limit cases.

- [ ] **Step 5: Write failing article draft/finalization tests**

Assert canonical kebab slugs, `.mdx` only, exact `draft: true`, collision approval, marker-only finalization, rejection of duplicate/missing markers, and no writes outside `drafts/`.

- [ ] **Step 6: Run the article test to verify it fails**

Run: `node --test codex-bridge/test/articles.test.mjs`
Expected: FAIL because article operations are absent.

- [ ] **Step 7: Implement article draft and finalization operations**

Implement `writeArticleDraft` and `finalizeArticle` with shared validation and atomic writes; register schemas under the `writer` profile.

- [ ] **Step 8: Add failing publication and rollback tests**

Assert publication requires `draft: false`, validates `YYYY-MM-DD`, changes exactly one `lastmod`, preserves `date`, moves only the requested slug, creates/idempotently updates the ledger, and restores the draft plus prior ledger when an injected post-move ledger failure occurs.

- [ ] **Step 9: Run the publication test to verify it fails**

Run: `node --test codex-bridge/test/articles.test.mjs`
Expected: FAIL because `publishArticle` and rollback are absent.

- [ ] **Step 10: Implement recoverable publication**

Validate all inputs first; stage the updated article in `published/` and the updated ledger beside the ledger; rename the original draft to a backup sibling in `drafts/`; rename the staged article to its final published path; replace the ledger; then remove the backup. If either final rename fails, remove any new published file, restore the draft backup and prior ledger, clean staged files, and rethrow a contextual error.

- [ ] **Step 11: Run Task 4 tests**

Run: `node --test codex-bridge/test/source-files.test.mjs codex-bridge/test/articles.test.mjs codex-bridge/test/server.test.mjs`
Expected: PASS, including injected rollback and cross-profile negative assertions.

- [ ] **Step 12: Commit Task 4**

```bash
git add codex-bridge/src/source-files.mjs codex-bridge/src/articles.mjs codex-bridge/src/tools/writer.mjs codex-bridge/test
git commit -m "feat(codex): enforce article publication boundaries"
```

### Task 5: Codex skills, custom agents, and read-only project configuration [size: L | risk: security | mechanical: false | clear_pattern: true | objectively_verifiable: true | concerns: security]

**Acceptance criteria:** AC-02, AC-03, AC-04, AC-09, AC-11, AC-14

**Files:**
- Create: `.agents/skills/extract-topics/SKILL.md`
- Create: `.agents/skills/write-blog-article/SKILL.md`
- Create: `.agents/skills/author-conventions/SKILL.md`
- Create: `.codex/config.toml`
- Create: `.codex/agents/topic-extractor.toml`
- Create: `.codex/agents/blog-writer.toml`
- Create: `.codex/agents/conventions-writer.toml`
- Create: `tests/codex_scaffold_check.sh`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: exact bridge profile commands and tool names from Tasks 1-4; existing OpenCode skills as behavioral references.
- Produces: three discoverable Codex skills; three custom agents whose `developer_instructions` forbid direct questions and bind one bridge profile; read-only main/custom-agent sandbox configuration.

- [ ] **Step 1: Write the failing Codex scaffold/static verifier**

Assert all skill and agent files exist; skill metadata uses exact names/descriptions; main skills own user questions and delegate only to the matching custom agent; each agent has `name`, `description`, `developer_instructions`, `sandbox_mode = "read-only"`, exactly one profiled stdio MCP entry, and no cross-role profile; `.codex/config.toml` enables agents, uses read-only sandbox, and contains no `mcp_servers` table.

- [ ] **Step 2: Run the scaffold verifier to verify it fails**

Run: `bash tests/codex_scaffold_check.sh`
Expected: FAIL reporting missing `.agents/skills`, `.codex/config.toml`, and `.codex/agents` files.

- [ ] **Step 3: Create read-only Codex config and role-scoped custom agents**

Use project-relative `node codex-bridge/src/server.mjs --profile <role>` commands. Set the topic agent to the `topic` profile, convention agent to `conventions`, and writer agent to `writer`; instruct each to return concise structured results to the parent and never interact with the user directly.

- [ ] **Step 4: Port the extraction skill as a main-chat coordinator**

Preserve the ten-step OpenCode behavior and output format, replace SQLite/OpenCode references with normalized bridge activity, delegate only to `topic-extractor`, keep project confirmation and DRAFT review in the main chat, and carry bridge warnings/flags into the appendix.

- [ ] **Step 5: Port the convention-authoring skill as a main-chat coordinator**

Preserve the focused interview and placeholder rules, delegate only persistence to `conventions-writer`, and keep every question and final review in the main chat.

- [ ] **Step 6: Port the article skill as a main-chat coordinator**

Preserve convention checks, topic resolution, English-first review, translation, MDX restrictions, finalization, and explicit publication; delegate only fact-check and mutation operations to `blog-writer`.

- [ ] **Step 7: Update root project guidance for dual-runtime routing**

Make `AGENTS.md` runtime-neutral at the project level, retain the OpenCode section, add Codex skill/custom-agent routing, state that placeholder-only conventions are rejected, and state correctly that OpenCode `time_updated` is not indexed.

- [ ] **Step 8: Run the Codex scaffold verifier**

Run: `bash tests/codex_scaffold_check.sh`
Expected: PASS with role isolation, read-only sandbox, skill routing, and no privileged main-chat MCP registration.

- [ ] **Step 9: Run bridge and legacy regressions**

Run: `npm test --prefix codex-bridge`
Expected: PASS with 0 failures.

Run: `bash tests/scaffold_check.sh && bash tests/extract_topics_check.sh && bash tests/conventions_check.sh && bash tests/blog_writer_check.sh`
Expected: all four scripts report `ALL CHECKS PASSED`.

- [ ] **Step 10: Commit Task 5**

```bash
git add .agents/skills .codex/config.toml .codex/agents AGENTS.md tests/codex_scaffold_check.sh
git commit -m "feat(codex): add guarded project workflows"
```

### Task 6: Cross-runtime acceptance, documentation, and contract corrections [size: M | risk: none | mechanical: true | clear_pattern: true | objectively_verifiable: true | concerns: none]

**Acceptance criteria:** AC-01, AC-16, AC-17, AC-18, AC-19

**Files:**
- Create: `tests/codex_acceptance_check.sh`
- Create: `tests/codex_live_check.sh`
- Modify: `tests/run_all.sh`
- Modify: `tests/acceptance_check.sh`
- Modify: `.opencode/agents/topic-extractor.md`
- Modify: `README.md`
- Modify: `docs/acceptance.md`

**Interfaces:**
- Consumes: all bridge/config/skill deliverables from Tasks 1-5 and existing verification harness conventions.
- Produces: one offline default suite covering both runtimes and one `CODEX_ACCEPTANCE_RUNTIME=1` live Codex entry point.

- [ ] **Step 1: Write the failing Codex acceptance verifier**

Assert every AC-01 through AC-19 static/deterministic anchor: OpenCode artifacts remain, package lock pins SDK 1.30.1, bridge tests use fixture Codex homes, no internal Codex SQLite path appears in skills, output markers/formats match, role tool lists are isolated, and documentation names both runtimes and commands.

- [ ] **Step 2: Run the acceptance verifier to verify it fails**

Run: `bash tests/codex_acceptance_check.sh`
Expected: FAIL on missing dual-runtime documentation, run-all integration, live verifier, and the active topic-agent filename contradiction.

- [ ] **Step 3: Add the opt-in live Codex verifier**

Follow the existing `ACCEPTANCE_RUNTIME` harness style. When `CODEX_ACCEPTANCE_RUNTIME` is not `1`, report SKIP and exit 0. When enabled, use an isolated temporary fixture project and Codex home to verify skill discovery, custom-agent visibility, profiled MCP tool lists, read-only direct writes, and successful scoped MCP fixture writes without reading real history.

- [ ] **Step 4: Correct active shared-contract contradictions**

Change `.opencode/agents/topic-extractor.md` to `inputs/topics-YYYY-MM-DD.md`. Confirm `AGENTS.md` from Task 5 says placeholder-only conventions are rejected and `time_updated` is not indexed. Do not modify legacy `specs/` or `plans/` artifacts.

- [ ] **Step 5: Document dual-runtime setup and privacy behavior**

Update `README.md` and `docs/acceptance.md` with Node/npm install (`npm install --prefix codex-bridge`), Codex project trust/restart, local rollout path as an adapter detail, manual invocation examples, bridge scope, offline deterministic tests, live opt-in command, and the fact that ChatGPT web history is out of scope.

- [ ] **Step 6: Integrate deterministic Codex checks into the default suite**

Add `tests/codex_scaffold_check.sh`, `npm test --prefix codex-bridge`, and `tests/codex_acceptance_check.sh` after the existing scripts in `tests/run_all.sh`. Keep the live verifier opt-in and outside the default suite.

- [ ] **Step 7: Run the new acceptance verifier**

Run: `bash tests/codex_acceptance_check.sh`
Expected: `ALL CHECKS PASSED` with no real Codex-history access.

- [ ] **Step 8: Run the complete deterministic suite**

Run: `bash tests/run_all.sh`
Expected: every existing OpenCode check and every new Codex check passes; final output is `SUITE PASSED`.

- [ ] **Step 9: Exercise the live verifier's default-safe path**

Run: `bash tests/codex_live_check.sh`
Expected: reports live Codex cases as SKIP and exits 0.

- [ ] **Step 10: Inspect repository scope**

Run: `git status --short`
Expected: only planned Codex bridge/config/skill/test/documentation files and the pre-existing untracked `docs/architecture/map.md`; no generated topics, drafts, published articles, real history, or source-project files.

- [ ] **Step 11: Commit Task 6**

```bash
git add tests/run_all.sh tests/acceptance_check.sh tests/codex_acceptance_check.sh tests/codex_live_check.sh .opencode/agents/topic-extractor.md README.md docs/acceptance.md
git commit -m "test(codex): verify dual-runtime workflows"
```

## Final Verification

- [ ] Run `npm ci --prefix codex-bridge`; expected exit 0 with the committed lockfile and no manifest changes.
- [ ] Run `bash tests/run_all.sh`; expected `SUITE PASSED` with every OpenCode and deterministic Codex check passing.
- [ ] Run `bash tests/codex_live_check.sh`; expected safe SKIP with exit 0 when `CODEX_ACCEPTANCE_RUNTIME` is unset.
- [ ] Run `git diff --check`; expected no output and exit 0.
- [ ] Confirm `git status --short` contains no generated content, dependency directories, or real history data; the separate untracked architecture map may remain.
