# Codex Desktop Workflows Implementation Plan

> **For agentic workers:** Use `personal-workflows:spec-implement` with `superpowers:executing-plans` to implement this plan task by task. Track progress using the checkboxes.

**Slug:** `codex-desktop-workflows`
**Status:** APPROVED
**Provenance:** Approved specification and repository investigation in this conversation; the user explicitly requested implementation of the complete plan on 2026-10-22.
**Goal:** Make all existing Blog-Writer workflows available directly in an ordinary Codex desktop project chat.
**Architecture:** Register one fixed desktop bridge containing the nine existing bounded operations. Run all three skills in the main chat, retaining the launcher's narrow profiles and existing approval gates.
**Tech Stack:** Node.js 20+, existing MCP SDK 1.30.1, TOML, Markdown skills, Bash and Python verification.
**Spec:** `docs/superpowers/specs/2026-10-22-codex-desktop-workflows-design.md`
**Execution tier:** full
**Implementation model role:** full
**Execution method:** Native implementation, followed by independent specification and quality review.

## Global Constraints

- Preserve existing shared artifact formats and real writing conventions.
- Do not change OpenCode configuration, skills, or behavior.
- Add no schedules, background watchers, source-project mutations, or global Codex settings.
- Expose only the fixed desktop union and existing narrow profiles.
- Keep user questions, writing, translation, and approval gates in the main chat.
- Preserve English approval before translation, bilingual review, explicit finalization, and separate explicit publication.
- Preserve publication ledger updates, collision protection, duplicate prevention, and rollback.
- Work in the existing checkout. Do not create a worktree, push, or merge the implementation.

After explicit plan approval and leaving Plan mode, save this plan, update `main` using `git pull --ff-only`, and create `feat/codex-desktop-workflows`. Preserve the uncommitted specification and plan; commit them on the implementation branch. Reassess any upstream changes affecting the plan before editing product files.

## Grounding and Review Focus

Current HEAD is `829709a04962cd33f27db1b3fdec32e8c32e82b9`. The bridge, launcher, three skills, and verification entrypoints exist. No applicable ADRs were found.

`docs/architecture/map.md` is stale: it records HEAD `b30cd10897015e092866465b0dc5720c3bfee767` and omits the Codex bridge. Refresh it during implementation, using current code as evidence.

Tests must address these five conditions:

1. Nested folders, spaces in checkout paths, and linked worktrees start the correct code and retain the primary workflow data root.
2. Launcher overrides replace the desktop catalog with exactly the selected narrow catalog.
3. Partial catalogs, unknown bridge tools, and explicit mode mismatches stop before workflow operations.
4. Finalization never implicitly publishes; publication updates the ledger through existing validated handlers.
5. Live evidence belongs to one parent chat; child-owned, split-session, failed, or prose-only evidence cannot pass.

Verification commands below come from the existing README, package scripts, and acceptance runner.

### Task 1: Add the desktop catalog [size: M | risk: security | mechanical: false | clear_pattern: true | objectively_verifiable: true | concerns: security]

**Acceptance criteria:** AC-01, AC-05, AC-06, AC-07

**Files:** `codex-bridge/src/profiles.mjs`, `codex-bridge/src/server.mjs`, and their existing tests.

**Interfaces:** Extend `PROFILE_TOOL_NAMES` and `parseProfile(argv)` with `desktop`. Preserve `createServer({ profile, projectRoot, dependencies })` and all tool argument schemas.

The security concern is broader parent-session exposure of existing privileged operations.

- [x] Add failing tests asserting that desktop contains exactly `discover_projects`, `collect_activity`, `write_topic_draft`, `finalize_topics`, `write_conventions`, `read_source_file`, `write_article_draft`, `finalize_article`, `publish_article`. Assert narrow catalogs remain unchanged, unknown profiles fail, and arbitrary handlers are never registered.
- [x] Run `npm test --prefix codex-bridge`; confirm failures identify missing desktop support.
- [x] Add the frozen desktop catalog and compose the three existing handler factories in `createProfileHandlers`. Update profile types and error messages. Introduce no new workflow operations.
- [x] Add SDK tests comparing desktop tool schemas with their narrow-profile equivalents. Exercise topic persistence, conventions persistence, source reads, article drafting, finalization, and publication using disposable fixture data. Confirm finalization leaves the ledger untouched and publication records the topic once.
- [x] Run `npm test --prefix codex-bridge`; expect all tests to pass, including existing path, history, redaction, collision, and rollback coverage.
- [x] Commit as `feat: add bounded desktop bridge profile`.

### Task 2: Register portable desktop startup and preserve the launcher [size: M | risk: security | mechanical: false | clear_pattern: true | objectively_verifiable: true | concerns: security]

**Acceptance criteria:** AC-01, AC-06, AC-07, AC-08

**Files:** `.codex/config.toml`, `bin/blog-writer-codex`, and existing scaffold, launcher, and server tests.

**Interfaces:** Ordinary chats receive `blog_writer_bridge` with profile `desktop`; `topics` and `article` retain their existing interfaces and exact narrow profiles.

- [x] Add failing checks for parent registration, startup from nested directories and checkout paths containing spaces, linked-worktree data routing, and narrow launcher overrides.
- [x] Run `bash tests/codex_scaffold_check.sh`, `bash tests/codex_launcher_check.sh`, and `npm test --prefix codex-bridge`; confirm the new assertions fail.
- [x] Keep `sandbox_mode = "read-only"` and register the desktop server with `/bin/sh` and fixed startup arguments: `set -eu; bridge_code_root=$(git rev-parse --show-toplevel); exec node "$bridge_code_root/codex-bridge/src/server.mjs" --profile desktop`. Leave MCP `cwd` unset. This startup mechanism was verified from nested directories and paths containing spaces. It exposes no shell tool.
- [x] Preserve launcher overrides of the canonical server's `command` and complete `args` array. Retain prerequisite errors, user-text handling, working-directory selection, and exit propagation.
- [x] Repeat the three checks; expect startup and launcher tests to pass. Any remaining scaffold failures must concern the skill contracts addressed by Task 3.
- [x] Commit as `feat: register desktop bridge in project configuration`.

### Task 3: Route all skills directly through the main chat [size: M | risk: security | mechanical: false | clear_pattern: true | objectively_verifiable: true | concerns: security]

**Acceptance criteria:** AC-01, AC-02, AC-03, AC-04, AC-06, AC-08

**Files:** The three skills under `.agents/skills`, obsolete definitions under `.codex/agents`, project configuration, and scaffold checks.

**Interfaces:** All bridge calls originate in the main chat. Desktop mode requires exactly nine tools; explicitly selected command mode requires the selected workflow's exact narrow catalog.

- [x] Update scaffold assertions to require direct routing and reject obsolete delegation. Cover missing, partial, unexpected, and mismatched catalogs, including unrelated MCP servers that must be ignored.
- [x] Run `bash tests/codex_scaffold_check.sh`; expect failures against the old skills.
- [x] Update all three skills, applying the skill-editing guidance. Preserve existing workflow steps, approval gates, overwrite requirements, and primary-checkout artifact resolution.
- [x] Add prerequisite and restart guidance for invalid catalogs. Retain the prohibition on shell or filesystem substitutes for bridge operations.
- [x] Remove the three project custom-agent definitions and project settings used only for them. Remove custom-agent fallback instructions.
- [x] Run `bash tests/codex_scaffold_check.sh` and `bash tests/codex_launcher_check.sh`; expect both to pass.
- [x] Commit as `refactor: run Codex workflows directly in the main chat`.

### Task 4: Verify real parent-session configuration and operations [size: L | risk: security | mechanical: false | clear_pattern: false | objectively_verifiable: true | concerns: security]

**Acceptance criteria:** AC-01, AC-02, AC-03, AC-04, AC-05, AC-06, AC-07, AC-08, AC-09

**Files:** Existing live, event-fixture, and acceptance checks under `tests`. Add `tests/codex_runtime_probe.py`.

**Interfaces:** Preserve the opt-in runtime command and existing success/failure/`NEEDS_CONTEXT` distinction. The new helper drives app-server JSON-RPC and records requests, responses, and notifications for verification.

- [x] Add failing event fixtures for desktop mode, all three workflows on one parent, narrow-profile isolation, and adversarial evidence. Preserve rejection of wrong arguments, failed or missing results, unknown tools, child ownership, split sessions, and assistant claims.
- [x] Run `python3 tests/codex_live_events_check.py`; expect failures for unsupported desktop/protocol cases.
- [x] Implement app-server probing using `initialize`, `thread/start`, `mcpServerStatus/list`, and `turn/start`. Desktop probing loads the trusted fixture project configuration without MCP overrides. Invoke each skill using explicit structured skill input.
- [x] Correlate the catalog response with its request and parent thread. Correlate skill requests, completed MCP calls, exact arguments, successful results, and resulting fixture bytes. All three workflow probes identify the same parent.
- [x] Retain narrow runtime probes using the launcher's override values. Remove obsolete custom-agent probes. Correct `--no-daemon` placement wherever CLI execution remains.
- [x] Preserve isolated `CODEX_HOME`, synthetic history, disposable workflow files, bounded waits, process cleanup, and the direct-write sandbox probe.
- [x] Run `python3 tests/codex_live_events_check.py` and `bash tests/codex_acceptance_check.sh`; expect deterministic checks to pass.
- [x] Run `CODEX_ACCEPTANCE_RUNTIME=1 bash tests/codex_live_check.sh`. Require tool and file evidence for success. Report unavailable authentication or unsupported runtime evidence as incomplete verification.
- [x] Commit as `test: verify direct desktop workflow execution`.

### Task 5: Document, review, and finish [size: M | risk: none | mechanical: false | clear_pattern: true | objectively_verifiable: true | concerns: none]

**Acceptance criteria:** AC-05, AC-07, AC-08, AC-09

**Files:** `README.md`, `AGENTS.md`, `docs/acceptance.md`, `docs/architecture/map.md`, and documentation checks.

- [x] Update documentation assertions for desktop setup, direct invocation, narrow CLI compatibility, troubleshooting, and verification limits.
- [x] Document dependency installation, project trust, restart, catalog inspection, and supported prompts. Explain that explicit publication updates the ledger; manual moves do not.
- [x] Refresh the architecture map to include both runtimes, bridge profiles, primary-checkout data resolution, and current test topology.
- [x] Run `bash tests/run_all.sh`; expect `SUITE PASSED`. Confirm the implementation diff contains no OpenCode or real workflow-data changes.
- [ ] Perform independent specification review followed by quality review using `personal-workflows:code-review`. Address findings and rerun affected checks.
- [x] Commit as `docs: document direct Codex desktop workflows`.
- [ ] Report commits, verification results, and any outstanding desktop smoke check. After a desktop restart, confirm the nine tools and a reviewed fixture operation in an ordinary project chat before claiming desktop verification.


## Acceptance Traceability

| Criteria | Implementation and evidence |
|---|---|
| AC-01 | Tasks 1–4: exact catalog, project startup, direct routing, parent-session probe |
| AC-02–AC-04 | Tasks 3–4: preserved skill gates and three workflow families |
| AC-05 | Tasks 1, 4–5: publication fixtures, existing regression coverage, documentation |
| AC-06 | Tasks 1–4: bounded handlers, unchanged schemas, negative checks |
| AC-07 | Tasks 1–2, 4–5: narrow profiles, roots, launcher, OpenCode regression suite |
| AC-08 | Tasks 2–5: catalog failures, setup guidance, removal of fallback |
| AC-09 | Tasks 4–5: deterministic fixtures, live evidence, documented desktop smoke check |

## Assumptions and Approval State

No article authoring, workflow-data migration, manual-move reconciliation, or deployment is included. Existing publication behavior remains unchanged. Explicit user approval is recorded above; implementation uses Default mode.
