# Command-Scoped Codex Workflows Implementation Plan

**Slug:** `command-scoped-codex-workflows`
**Status:** DRAFT
**Provenance:** `docs/superpowers/specs/2026-09-28-command-scoped-codex-workflows-design.md`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reliable repository commands that run the reviewed topic and bilingual article workflows with one invocation-scoped bridge profile, without depending on custom-agent MCP propagation.

**Architecture:** A Bash launcher starts a fresh interactive Codex CLI session from the repository root with `--no-daemon`, a read-only sandbox, and one fixed `blog_writer_bridge` profile selected from a closed `topics|article` subcommand set. The existing topic and article skills gain a command-scoped path in which the main chat calls that narrow bridge directly, while preserving custom-agent delegation as the fallback for runtimes that propagate agent MCP configuration correctly.

**Tech Stack:** Bash, Codex CLI invocation-scoped TOML overrides, Node.js 20+ ESM, `@modelcontextprotocol/sdk` 1.30.1, Node test runner, Python `unittest`, Markdown skills and documentation.

**Spec:** `docs/superpowers/specs/2026-09-28-command-scoped-codex-workflows-design.md`

**Execution tier:** full
**Implementation model role:** full

**Planning evidence:** `codex --help` on 2026-09-28 documents `--no-daemon`, `--strict-config`, `--sandbox read-only`, `--cd`, and repeatable `--config key=value`; `codex-bridge/package.json` defines `npm test --prefix codex-bridge` as `node --test`; `README.md`, `docs/acceptance.md`, and `tests/run_all.sh` define the repository verification commands used below.

**Architecture map:** `docs/architecture/map.md` exists as an untracked, user-owned file. It records HEAD `b30cd10897015e092866465b0dc5720c3bfee767`, while planning HEAD is `d599e5bbac1fa1f6f6b45c6064b5c37d5a929f44`; it is stale and its module, dependency, and test sections do not include `.agents/`, `.codex/`, or `codex-bridge/`. Do not regenerate or modify it during this work.

**Applicable ADRs:** None found under `docs/`, `specs/`, or `plans/`. The approved design document is the governing decision record.

**Assumptions and unresolved decisions:** The current Codex CLI flags named in Planning evidence remain supported during implementation. Other user-configured MCP servers may remain available, but the launcher overrides the single `blog_writer_bridge` registration and each skill must stop on any matching cross-role bridge surface. The approved spec contains no acceptance-criterion IDs, so the `PC-*` identifiers below are plan-local traceability aliases, not invented spec IDs.

## Global Constraints

- Do not change any file under `.opencode/` or otherwise change OpenCode behavior.
- Do not add a privileged MCP registration to `.codex/config.toml` or expose topic and writer bridge profiles in one launcher-created session.
- Launch interactive Codex without an explicit model, without ephemeral mode, and with `--no-daemon`, a read-only sandbox, and the repository as the working root.
- Treat time-window and article-subject arguments only as prompt data; they must never influence the MCP command, bridge path, profile, or Codex configuration arguments.
- Keep every existing project confirmation, overwrite, DRAFT review, revision, finalization, and explicit publication approval gate.
- Topic finalization must not start article writing; article finalization must not publish.
- Keep the existing custom agents and their role-scoped bridge profiles as the fallback path.
- Never substitute shell or general filesystem writes for a bridge mutation, and never modify source projects, Codex history, Git state, or publication state outside an explicit workflow operation.
- Preserve the current shared topic, article, ledger, and bilingual MDX formats.
- Preserve unrelated working-tree content, especially the user-owned `docs/architecture/` files.

## Review Focus

- A time-window or article subject containing quotes, newlines, shell metacharacters, `--profile`, or TOML-looking text remains one prompt argument and cannot change the fixed Codex/MCP argv; Task 2 pins this with fake-Codex argv capture.
- A session exposing a partial expected bridge catalog, a cross-role bridge tool, or both topic and writer tools stops before any mutation; Task 3 pins each catalog case in the scaffold verifier.
- A launcher invoked from outside the repository or through a filesystem path alias still resolves the project and starts the bridge; Tasks 1 and 2 pin canonical entrypoint and working-directory behavior.
- A missing prerequisite, unknown subcommand, or missing article subject exits non-zero before Codex starts and names the corrective action; Task 2 pins each failure with a launch sentinel.
- A live runtime that still cannot propagate custom-agent MCP configuration reports that probe as diagnostic while command-scoped main-session evidence remains the acceptance gate; Task 4 pins both event-verifier outcomes.

## Plan Criteria

| ID | Approved-spec requirement | Owning task/test |
|---|---|---|
| PC-01 | `topics [time-window words...]` launches the reviewed topic workflow through only the topic profile. | Task 2 launcher argv tests; Task 3 skill-routing checks; Task 4 live topic probe |
| PC-02 | `article <subject...>` launches the English-first reviewed bilingual workflow through only the writer profile. | Task 2 launcher argv tests; Task 3 skill-routing checks; Task 4 live writer probe |
| PC-03 | The launcher resolves the repository root, uses current Codex without a model override or daemon, and propagates its exit status. | Task 2 fake-Codex tests |
| PC-04 | Invalid input and missing prerequisites fail locally before Codex startup with actionable usage/errors. | Task 2 launch-sentinel tests |
| PC-05 | User text cannot select a profile or alter MCP/configuration arguments; topic and writer tools never coexist. | Task 2 adversarial argv tests; Task 3 catalog checks |
| PC-06 | Skills use direct bridge calls only with the exact matching surface, stop on mismatch/cross-role exposure, and otherwise retain custom-agent fallback. | Task 3 static workflow checks; Task 4 live evidence checks |
| PC-07 | The bridge CLI starts when its entrypoint is reached through a filesystem alias. | Task 1 MCP client regression test |
| PC-08 | Offline verification covers launcher behavior, profile isolation, skills, and the full deterministic suite. | Tasks 1-4; `bash tests/run_all.sh` |
| PC-09 | Opt-in live verification requires correlated main-session tool/effect/isolation evidence; custom-agent propagation remains diagnostic. | Task 4 structured-event fixtures and live probes |
| PC-10 | README and acceptance guidance explain prerequisites, commands, sequence, approvals, failures, and live checks. | Task 4 documentation assertions |
| PC-11 | OpenCode behavior and existing custom-agent definitions remain unchanged. | Task 3/4 regression and diff checks |
| PC-12 | DRAFT-first finalization and publication remain separate explicit actions. | Task 3 skill checks; Task 4 docs/live fixture assertions |

## File Structure

- `bin/blog-writer-codex`: the only new user entrypoint; validates fixed prerequisites and subcommands, constructs the prompt, and `exec`s interactive Codex with one fixed profile.
- `tests/codex_launcher_check.sh`: deterministic fake-Codex tests for usage, prerequisite failures, exact argv, prompt data handling, working directory, and exit propagation.
- `codex-bridge/src/server.mjs`: canonical entrypoint identity check so path aliases still execute the CLI server.
- `codex-bridge/test/server.test.mjs`: MCP client regression for the aliased entrypoint.
- `.agents/skills/extract-topics/SKILL.md`: shared topic workflow with explicit command-scoped and custom-agent execution modes.
- `.agents/skills/write-blog-article/SKILL.md`: shared article workflow with explicit command-scoped and custom-agent execution modes.
- `tests/codex_scaffold_check.sh`: static assertions for mutually exclusive modes and exact role tool surfaces.
- `tests/codex_live_check.sh`: isolated command-scoped live probes plus non-gating custom-agent propagation diagnostics.
- `tests/codex_live_events_check.py`: offline structured-event fixtures for both direct main-session and custom-agent evidence rules.
- `tests/codex_acceptance_check.sh`: cross-runtime deterministic anchors for the launcher, modes, live gate, and documentation.
- `tests/run_all.sh`: includes the new offline launcher check; continues excluding live model calls.
- `README.md`: reliable Codex command path, conditional custom-agent path, prerequisites, examples, failures, and approval sequence.
- `docs/acceptance.md`: mechanical and opt-in live command-scoped acceptance procedure.

---

### Task 1: Canonical Bridge CLI Entrypoint [size: S | risk: none | mechanical: true | clear_pattern: true | objectively_verifiable: true | concerns: none]

**Acceptance criteria:** PC-07, PC-08

**Files:**
- Modify: `codex-bridge/src/server.mjs`
- Test: `codex-bridge/test/server.test.mjs`

**Interfaces:**
- Consumes: Node's `process.argv[1]` CLI entrypoint and `import.meta.url` for `codex-bridge/src/server.mjs`.
- Produces: entrypoint identity based on canonical filesystem paths; the exported `createServer` and `registerProfileTools` interfaces and all profile catalogs remain unchanged.

**Working-tree note:** The intended failing regression and minimal fix already exist as uncommitted edits. Preserve and validate those edits; do not discard, duplicate, or broaden them.

- [ ] **Step 1: Preserve the aliased-entrypoint regression test**

  Keep `cli_starts_when_entrypoint_path_uses_a_symlink` in `codex-bridge/test/server.test.mjs`. It must create a temporary symlink to `src/server.mjs`, connect an MCP `Client` through `StdioClientTransport`, call `listTools()`, and assert the conventions profile returns exactly `['write_conventions']`; cleanup must close the client and remove the temporary directory.

- [ ] **Step 2: Reconfirm the regression against the pre-fix entrypoint comparison in an isolated copy**

  Run:

  ```bash
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/blog-writer-entrypoint-red.XXXXXX")"
  cp -R codex-bridge "$scratch/codex-bridge"
  git show HEAD:codex-bridge/src/server.mjs > "$scratch/codex-bridge/src/server.mjs"
  if node --test "$scratch/codex-bridge/test/server.test.mjs"; then
    rm -r -- "$scratch"
    exit 1
  fi
  rm -r -- "$scratch"
  ```

  Expected: the isolated pre-fix copy reports the aliased-entrypoint test as FAIL because the MCP client cannot receive a catalog. The repository working tree remains unchanged.

- [ ] **Step 3: Preserve the minimal canonical-path comparison**

  Import `realpathSync` from `node:fs` and compare `realpathSync(fileURLToPath(import.meta.url))` with `realpathSync(process.argv[1])` before calling `startCli()`. Do not change profile parsing, tool registration, transport startup, or error reporting.

- [ ] **Step 4: Run the focused bridge test**

  Run: `node --test codex-bridge/test/server.test.mjs`

  Expected: PASS, including `cli_starts_when_entrypoint_path_uses_a_symlink`.

- [ ] **Step 5: Run the full bridge regression suite**

  Run: `npm test --prefix codex-bridge`

  Expected: exit 0 with all Node tests passing and unchanged exact topic, conventions, and writer tool catalogs.

- [ ] **Step 6: Commit the bridge hardening**

  ```bash
  git add codex-bridge/src/server.mjs codex-bridge/test/server.test.mjs
  git commit -m "fix(codex): start bridge through aliased entrypoints"
  ```

### Task 2: Fixed-Profile Interactive Launcher [size: M | risk: security | mechanical: false | clear_pattern: true | objectively_verifiable: true | concerns: security]

Risk explanation: argv construction is the least-privilege boundary that prevents user prompt text from selecting a bridge profile or changing Codex configuration.

**Acceptance criteria:** PC-01, PC-02, PC-03, PC-04, PC-05, PC-08

**Files:**
- Create: `bin/blog-writer-codex`
- Create: `tests/codex_launcher_check.sh`

**Interfaces:**
- Consumes: `topics [time-window words...]` or `article <topic reference or free-text subject...>` plus `codex` and `node` on `PATH`.
- Produces: one interactive `codex` process with `--no-daemon --strict-config --sandbox read-only --cd <canonical-repository-root>`, exactly one invocation-scoped `mcp_servers.blog_writer_bridge` command/args override, and one initial prompt; returns Codex's exact exit status.

- [ ] **Step 1: Write deterministic launcher tests around a fake `codex` executable**

  In `tests/codex_launcher_check.sh`, create a temporary fixture and fake `codex` that records its current directory and every argv element separately. Assert:

  - no subcommand and an unknown subcommand print both supported forms, exit non-zero, and never create the launch sentinel;
  - `article` with no subject exits non-zero before launch;
  - copied-fixture variants report missing `codex`, missing `node`, missing `codex-bridge/src/server.mjs`, and missing `codex-bridge/node_modules/@modelcontextprotocol/sdk` with one actionable message each before launch;
  - `topics` with no window launches with the seven-day-default prompt, while `topics last week` includes `last week` only in the prompt;
  - `article topic 2` selects only `--profile writer`; topic mode selects only `--profile topic`;
  - both modes include `--no-daemon`, `--strict-config`, `--sandbox read-only`, and `--cd <canonical-root>`, omit `--model`, `--ephemeral`, and every non-selected bridge profile, and run the fake Codex from the canonical repository root;
  - an argument containing quotes, newlines, `$()`, `--profile writer`, and TOML-looking text remains inside the single prompt argv and cannot add or alter config argv;
  - fake Codex exit 23 makes the launcher exit 23.

- [ ] **Step 2: Run the launcher test to verify it fails**

  Run: `bash tests/codex_launcher_check.sh`

  Expected: FAIL because `bin/blog-writer-codex` does not exist.

- [ ] **Step 3: Implement the closed launcher interface**

  Create executable `bin/blog-writer-codex` with `set -u`. Resolve its own repository root canonically, validate the recognized subcommand before model/MCP startup, validate `codex`, `node`, the bridge entrypoint, and the pinned SDK installation, and map only `topics -> topic` and `article -> writer`. Pass the fixed overrides `-c 'mcp_servers.blog_writer_bridge.command="node"'` and `-c 'mcp_servers.blog_writer_bridge.args=["codex-bridge/src/server.mjs","--profile","<fixed-profile>"]'`, with `<fixed-profile>` selected only by the closed subcommand case; never interpolate user text into a config value.

  The topics prompt must name `extract-topics`, state command-scoped mode, forbid custom-agent delegation for the run, and either carry the joined requested window as data or request the existing seven-day default. The article prompt must do the same for `write-blog-article` and carry the required joined subject as data. End with `exec codex ... "$prompt"` so signals and the exit status propagate.

- [ ] **Step 4: Make the launcher executable and run its focused tests**

  Run: `chmod +x bin/blog-writer-codex && bash tests/codex_launcher_check.sh`

  Expected: every case prints `PASS:` and the script exits 0; the fake invocation contains one fixed profile and no user-controlled config argument.

- [ ] **Step 5: Commit the launcher**

  ```bash
  git add bin/blog-writer-codex tests/codex_launcher_check.sh
  git commit -m "feat(codex): add fixed-profile workflow launcher"
  ```

### Task 3: Mutually Exclusive Skill Execution Modes [size: M | risk: security | mechanical: false | clear_pattern: true | objectively_verifiable: true | concerns: security,borderline]

Risk explanation: mode selection controls which principal can mutate Blog-Writer outputs and must fail closed on partial or cross-role bridge exposure.

**Acceptance criteria:** PC-01, PC-02, PC-05, PC-06, PC-11, PC-12

**Files:**
- Modify: `.agents/skills/extract-topics/SKILL.md`
- Modify: `.agents/skills/write-blog-article/SKILL.md`
- Modify: `tests/codex_scaffold_check.sh`

**Interfaces:**
- Consumes: the bridge tools visible to the main chat and the launcher prompt's explicit command-scoped-mode instruction.
- Produces: one mode per run: direct main-chat topic/writer bridge operations when and only when the exact matching surface is present, otherwise the existing bounded `topic-extractor`/`blog-writer` delegation path when no bridge surface is present.

- [ ] **Step 1: Add failing static checks for exact mode selection**

  Extend `tests/codex_scaffold_check.sh` to assert both skills define `Command-scoped mode` and `Custom-agent mode`, keep all user questions and approvals in the main chat, and preserve existing DRAFT/finalize/publish anchors. Assert exact allowed surfaces:

  - topic: `discover_projects`, `collect_activity`, `write_topic_draft`, `finalize_topics`;
  - writer: `read_source_file`, `write_article_draft`, `finalize_article`, `publish_article`.

  For each skill, assert command-scoped mode requires all allowed tools, stops on any other `blog_writer_bridge` role tool or a partial matching surface, forbids custom-agent delegation in that mode, and forbids shell/general-file mutation fallback. Assert custom-agent mode retains only the existing matching agent. Continue asserting `.codex/config.toml` has no `mcp_servers` table and each custom-agent TOML has one unchanged profile.

- [ ] **Step 2: Run the scaffold check to verify it fails**

  Run: `bash tests/codex_scaffold_check.sh`

  Expected: FAIL because the skills document only unconditional custom-agent delegation.

- [ ] **Step 3: Add a fail-closed execution-mode preamble to `extract-topics`**

  Before its ten-step workflow, define this decision order: stop if any cross-role bridge tool is visible; use command-scoped mode only when all four topic tools are callable and the launcher selected it; stop on a partial topic surface; otherwise use custom-agent mode and delegate bounded operations only to `topic-extractor`. Replace each operation instruction with mode-neutral wording that calls the named tool directly in command-scoped mode or delegates that same operation in custom-agent mode. Do not change time-window resolution, confirmation, scoring, DRAFT, overwrite, review, or finalization behavior.

- [ ] **Step 4: Add the symmetric fail-closed preamble to `write-blog-article`**

  Apply the same decision order for the four writer tools and `blog-writer`. Keep the main chat responsible for conventions validation, source confirmation, all prose, English approval, translation, bilingual approval, finalization, and publication. Do not let an article command publish, bypass a collision/overwrite question, or treat finalization as publication.

- [ ] **Step 5: Run focused skill and scaffold regressions**

  Run: `bash tests/codex_scaffold_check.sh && bash tests/extract_topics_check.sh && bash tests/blog_writer_check.sh`

  Expected: exit 0; both execution modes are present, the legacy workflow anchors remain, and no OpenCode test changes are required.

- [ ] **Step 6: Verify custom-agent configuration is byte-unchanged**

  Run: `git diff --exit-code HEAD -- .codex/config.toml .codex/agents .opencode`

  Expected: exit 0 with no diff.

- [ ] **Step 7: Commit the dual-mode skills**

  ```bash
  git add .agents/skills/extract-topics/SKILL.md .agents/skills/write-blog-article/SKILL.md tests/codex_scaffold_check.sh
  git commit -m "feat(codex): support direct profiled skill execution"
  ```

### Task 4: Command-Scoped Acceptance and Operator Guidance [size: L | risk: security | mechanical: false | clear_pattern: false | objectively_verifiable: true | concerns: borderline,security]

Risk explanation: the live verifier must distinguish correlated main-session evidence from assistant prose and must not turn a known upstream custom-agent propagation failure into a false product failure or false pass.

**Acceptance criteria:** PC-01, PC-02, PC-05, PC-06, PC-08, PC-09, PC-10, PC-11, PC-12

**Files:**
- Modify: `tests/codex_live_check.sh`
- Modify: `tests/codex_live_events_check.py`
- Modify: `tests/codex_acceptance_check.sh`
- Modify: `tests/run_all.sh`
- Modify: `README.md`
- Modify: `docs/acceptance.md`

**Interfaces:**
- Consumes: the launcher contract from Task 2, skill mode contract from Task 3, Codex `exec --json` structured events, isolated fixture project, and isolated `CODEX_HOME`.
- Produces: offline checks for all command contracts; opt-in live topic/writer acceptance based on exact main-session tool catalog/call/effect correlation; non-gating diagnostics for custom-agent MCP propagation; documented operator sequence.

- [ ] **Step 1: Add failing offline event-verifier fixtures for main-session evidence**

  Extend `tests/codex_live_events_check.py` with direct-mode fixtures and assertions that accept only one structured skill invocation plus an exact expected profile catalog and completed expected tool call with exact arguments on the parent session. Add rejection cases for assistant-text-only claims, wrong arguments, missing effect correlation metadata, partial catalogs, extra/cross-role bridge tools, a child-owned call, and evidence split across sessions. Retain every existing custom-agent correlation test.

- [ ] **Step 2: Add failing deterministic acceptance anchors**

  Extend `tests/codex_acceptance_check.sh` to require the executable launcher, `tests/codex_launcher_check.sh`, both command examples, `--no-daemon`, read-only/fixed-profile argv, two skill modes, direct structured-event verification, custom-agent diagnostic wording, and unchanged `.opencode/` contracts. Require `tests/run_all.sh` to run the launcher check and continue to exclude `tests/codex_live_check.sh`.

- [ ] **Step 3: Run the new offline checks to verify they fail**

  Run: `python3 tests/codex_live_events_check.py && bash tests/codex_acceptance_check.sh`

  Expected: FAIL on missing direct-mode verifier/anchors and missing command documentation.

- [ ] **Step 4: Implement the command-scoped structured-event verifier**

  Add a `verify_command_events` path to `tests/codex_live_check.sh` that parses JSONL structurally, normalizes only recognized bridge tool names, binds catalog and tool call to the parent invocation, requires the exact selected profile catalog and exact fixture arguments, rejects any successful cross-role/unknown bridge call or child-owned expected call, and never treats assistant prose as evidence. Expose this parser to the Python fixture tests through a fixture-only environment branch, parallel to the existing `CODEX_LIVE_EVENT_FIXTURE=1` path.

- [ ] **Step 5: Add isolated live command-scoped topic and writer probes**

  In the existing temporary fixture project and `CODEX_HOME`, run two `codex exec --json --no-daemon --sandbox read-only --cd "$FIXTURE_PROJECT"` probes with the same fixed invocation-scoped MCP overrides as the launcher:

  - topic profile: invoke `extract-topics` in command-scoped mode, call `write_topic_draft` with a unique date/content sentinel, attempt a valid writer cross-role call, and verify exact structured evidence plus the exact topic file effect;
  - writer profile: invoke `write-blog-article` in command-scoped mode, call `write_article_draft` with a unique slug/content sentinel, attempt a valid topic cross-role call, and verify exact structured evidence plus the exact draft effect.

  Keep all effects inside the fixture. The main-session command-scoped probes are the live acceptance gate. Run the existing custom-agent probes afterward as diagnostics: report PASS when propagation works, or a clear non-fatal diagnostic/SKIP when structured events show the known missing-child/missing-MCP condition; still fail on a demonstrated cross-role exposure or out-of-fixture effect.

- [ ] **Step 6: Update deterministic suite wiring**

  Add `tests/codex_launcher_check.sh` to the Codex section of `tests/run_all.sh` before bridge tests. Keep the opt-in live verifier out of `run_all.sh`. Update acceptance anchors so `python3 tests/codex_live_events_check.py`, `bash tests/codex_launcher_check.sh`, and the existing Node/static suites are all mechanically covered.

- [ ] **Step 7: Document the reliable and conditional Codex paths**

  Update `README.md` and `docs/acceptance.md` with:

  - Node/npm/Codex prerequisites and `npm install --prefix codex-bridge`;
  - `./bin/blog-writer-codex topics "last week"` followed by review/final approval;
  - `./bin/blog-writer-codex article "topic 2"` followed by English and bilingual review/final approval;
  - a separate later `publish <slug>` instruction and the statement that neither topic nor article finalization triggers the next state;
  - local prerequisite/usage errors and model/service exit propagation;
  - exact one-profile/no-daemon/read-only boundaries;
  - ordinary Desktop/custom-agent invocation as conditional on a runtime that propagates custom-agent MCP configuration;
  - the deterministic launcher test and opt-in command-scoped live verification, with custom-agent checks labeled diagnostic.

- [ ] **Step 8: Run the focused acceptance checks**

  Run: `bash tests/codex_launcher_check.sh && bash tests/codex_scaffold_check.sh && python3 tests/codex_live_events_check.py && bash tests/codex_acceptance_check.sh`

  Expected: exit 0; all command, skill-mode, event-correlation, profile-isolation, and documentation assertions pass without model calls.

- [ ] **Step 9: Verify the live check's safe default**

  Run: `bash tests/codex_live_check.sh`

  Expected: `SKIP: live Codex cases ...` and exit 0; no Codex/model invocation and no repository output file.

- [ ] **Step 10: Run the complete deterministic regression suite**

  Run: `bash tests/run_all.sh`

  Expected: `SUITE PASSED`; OpenCode checks, launcher checks, bridge tests, Codex scaffold, and cross-runtime acceptance all pass.

- [ ] **Step 11: Inspect the final scope**

  Run: `git status --short && git diff --check && git diff --name-only HEAD`

  Expected: no whitespace errors; only the planned bridge, launcher, Codex skill, test, README, and acceptance files differ from the pre-implementation base. `.opencode/` and the user-owned `docs/architecture/` content are absent from the implementation diff.

- [ ] **Step 12: Commit acceptance and documentation**

  ```bash
  git add tests/codex_live_check.sh tests/codex_live_events_check.py tests/codex_acceptance_check.sh tests/run_all.sh README.md docs/acceptance.md
  git commit -m "test(codex): verify command-scoped workflows"
  ```

## Final Verification

- [ ] Run `bash tests/run_all.sh`; expected `SUITE PASSED` with no live model calls.
- [ ] Run `bash tests/codex_live_check.sh`; expected one safe `SKIP:` and exit 0 when `CODEX_ACCEPTANCE_RUNTIME` is unset.
- [ ] If credentials and model budget are intentionally available, run `CODEX_ACCEPTANCE_RUNTIME=1 bash tests/codex_live_check.sh`; expected command-scoped topic and writer probes PASS with exact profile/effect evidence, while custom-agent propagation is reported separately as PASS or a non-gating diagnostic.
- [ ] Run `git diff --check`; expected no output and exit 0.
- [ ] Run `git status --short`; expected only deliberate implementation state plus the pre-existing untracked `docs/architecture/` directory, if it remains user-owned and uncommitted.
