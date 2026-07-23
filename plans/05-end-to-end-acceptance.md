# Plan: End-to-End Acceptance

| Field        | Value                              |
|--------------|------------------------------------|
| **Title**    | End-to-End Acceptance              |
| **Spec**     | specs/steps/05-end-to-end-acceptance.md |
| **Type**     | feature                            |
| **Branch**   | feat/05-end-to-end-acceptance      |
| **Created**  | 2026-07-23 14:52:54               |
| **Status**   | IMPLEMENTED                       |

## Context

Steps 01–04 delivered the scaffold, both agents, both skills, and the
conventions authoring flow, each with its own `tests/*_check.sh` static
verifier. This step (5 of 5) adds **no new functionality**: it ties the whole
system together with a single, repeatable acceptance procedure that exercises
every parent-spec guarantee end to end — automating the mechanical checks
(file existence, frontmatter shape, permission rejections, SQL read-only
usage) and documenting a precise manual script for the agent-conversation
scenarios that cannot be automated. Permission-boundary and destructive-command
scenarios must demonstrate an **actual runtime rejection**, not just intent.

## Branch Strategy

> **Before implementation, create a new branch from the repo's base
> branch.** The implementer auto-detects the base in this priority
> order: `develop` → `main` → `master` → `origin/HEAD`. This repo's
> current branch is `develop` and `origin/HEAD` → `origin/develop`, so
> `develop` is the expected base. The branch name is
> `feat/05-end-to-end-acceptance`.
>
> Reference command (the implementer adapts to the detected base):
>
> ```bash
> git checkout develop && git pull --ff-only && git checkout -b feat/05-end-to-end-acceptance
> ```

Branch type mapping: feature → `feat/<slug>`.

## Commit Strategy

All commits follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

Format: `<type>[(<scope>)]: <imperative description>`

One commit per task. Each task below maps to exactly one commit.

## Build & Test Commands

This project has no package manifest or build step. Tests are shell scripts
run directly with `bash`, following the established pattern
(`tests/scaffold_check.sh`, `tests/extract_topics_check.sh`,
`tests/conventions_check.sh`, `tests/blog_writer_check.sh`).

| Action | Command |
|--------|---------|
| Acceptance (this step) | `bash tests/acceptance_check.sh` |
| Full suite (regression) | `bash tests/scaffold_check.sh && bash tests/extract_topics_check.sh && bash tests/conventions_check.sh && bash tests/blog_writer_check.sh && bash tests/acceptance_check.sh` |

## Tasks

### Task 1: Static acceptance harness — artifacts, frontmatter shapes & SQL read-only `[M]`

**Goal**: Add `tests/acceptance_check.sh` that mechanically asserts the
system-wide, statically-verifiable acceptance criteria in one pass, reusing
the established harness idiom.

**Files**:

| File                        | Action | Description                                                                 |
|-----------------------------|--------|-----------------------------------------------------------------------------|
| `tests/acceptance_check.sh` | create | End-to-end static verifier: fresh-clone readiness, DRAFT-first markers, MDX vocabulary, bilingual frontmatter shape, SQL read-only + `time_updated` usage |

**Reuse**:

| File                          | What to reuse                                                        |
|-------------------------------|---------------------------------------------------------------------|
| `tests/scaffold_check.sh`     | `set -u`, `SCRIPT_DIR`/`ROOT` resolution, `pass`/`fail`/`assert_*` helpers, `python3` heredoc for JSON, exit-code idiom |
| `tests/extract_topics_check.sh` | `assert_contains`/`assert_contains_ci`/`assert_absent` helpers; the extract-topics skill anchors (`sqlite3 -readonly`, `time_updated`, `SELECT DISTINCT directory`) |
| `tests/blog_writer_check.sh`  | The write-blog-article skill anchors (`<Lang value="en"`, `<Lang value="it"`, `<TOCInline`, `lang:filename`, `draft: true`/`draft: false`, `published/`) |

**Steps**:

1. Copy the harness scaffolding (root resolution + `pass`/`fail`/`assert_file`/
   `assert_nonempty`/`assert_contains`/`assert_contains_ci`/`assert_absent`)
   from `tests/scaffold_check.sh`.
2. **Fresh-clone readiness (scenario 1)**: assert the required tree exists
   (`inputs/`, `drafts/`, `published/` + their `.gitkeep`s, `AGENTS.md`,
   `README.md`, `CONVENTIONS.template.md`, both agents, all three skills, and
   `.opencode/opencode.json`); assert `tracked-projects.txt` is optional
   (pass whether present or absent).
3. **DRAFT-first markers (scenarios 2, 6, 7, 10)**: assert the extract-topics
   skill writes `Status: DRAFT` and flips to `FINAL`; assert the
   write-blog-article skill writes `draft: true` and flips to `draft: false`;
   assert both skills carry the "never embed" no-body-in-question rule.
4. **Bilingual + MDX vocabulary (scenarios 8, 9)**: assert the write-blog-article
   skill emits both `<Lang value="en"` and `<Lang value="it"` blocks, the
   `{ id, label:{en,it} }` tag shape (`label:` / `en:` / `it:`), the allowed
   components (`<TOCInline`, `lang:filename`), and English-first ordering
   (`english` before `translat`).
5. **Read-only DB + indexed column (scenario 15)**: assert the extract-topics
   skill mandates `sqlite3 -readonly`, filters on `time_updated`, and uses the
   `SELECT DISTINCT directory` discovery query; `grep` the whole repo to assert
   **no** `sqlite3` invocation omits `-readonly` (i.e. every `sqlite3 …` string
   in tracked files also contains `-readonly`).
6. **Auto-discovery vs allowlist wiring (scenarios 3, 4)**: assert the skill
   documents both the `tracked-projects.txt` allowlist path and the
   auto-discovery fallback confirmed via `question`.
7. Print a section banner per scenario group and exit non-zero on any failure,
   matching the existing scripts' final `ALL CHECKS PASSED` / `SOME CHECKS
   FAILED` idiom.

**Tests**: This task *is* the test; run `bash tests/acceptance_check.sh`.

**Acceptance criteria covered**: static portions of scenarios 1, 2, 3, 4, 6,
7, 8, 9, 10, 15; contributes to "every scenario has a documented check" and
"each parent-spec criterion maps to at least one scenario".

**Commit**: `test(acceptance): add static end-to-end verification harness`

---

### Task 2: Runtime rejection harness — permission boundaries & destructive commands `[M]`

**Goal**: Add `tests/permission_check.sh` that drives the **actual** opencode
runtime to prove disallowed writes and destructive/remote git commands are
rejected (not merely intended to be), for both agents.

**Files**:

| File                        | Action | Description                                                                 |
|-----------------------------|--------|-----------------------------------------------------------------------------|
| `tests/permission_check.sh` | create | Runtime verifier that invokes opencode headlessly per agent and asserts rejection of out-of-scope writes and denied bash commands |

**Reuse**:

| File                        | What to reuse                                                          |
|-----------------------------|------------------------------------------------------------------------|
| `tests/scaffold_check.sh`   | Harness scaffolding + helpers; the `python3` JSON reader for cross-checking `.opencode/opencode.json` deny rules |
| `.opencode/opencode.json`   | The authoritative `edit`/`bash` deny rules the runtime enforces (source of the expected-rejection matrix) |

**Steps**:

1. Copy the harness scaffolding and helpers.
2. **Preflight**: detect the opencode CLI (`command -v opencode`). If absent,
   print a clear `SKIP` explaining the runtime checks need the opencode CLI,
   and fall back to a **config-level** assertion (parse
   `.opencode/opencode.json` and confirm each expected deny rule is present:
   topic-extractor `edit` default-deny with only `inputs/**` allowed;
   blog-writer `edit` default-deny with only `drafts/**`/`inputs/**`/
   `published/**` allowed; both agents deny `git push*`, `git commit --amend*`,
   `rm -rf*`). This keeps the script green on a fresh clone while documenting
   the true runtime requirement.
3. **Runtime rejection matrix (scenarios 13, 14)** — when the CLI is present,
   run one non-interactive invocation per case using the headless run mode
   (e.g. `opencode run --agent <name> "<prompt>"`), each asking the agent to
   perform a forbidden action, and assert the transcript/exit shows a runtime
   **rejection**:
   - topic-extractor writing outside `inputs/**` (e.g. into `drafts/`) →
     rejected.
   - blog-writer writing outside `drafts/**`/`inputs/**`/`published/**` (e.g.
     into `.opencode/`) → rejected.
   - blog-writer editing a path inside a source project → refused.
   - `git push`, `git commit --amend`, `rm -rf` for **both** agents → denied.
4. Write forbidden targets into a temp scratch dir (never into real config);
   assert the target file was **not** created after each attempt as the
   positive proof of rejection.
5. Exit non-zero on any failure; print `ALL CHECKS PASSED` / `SOME CHECKS
   FAILED`.

**Tests**: This task *is* the test; run `bash tests/permission_check.sh`.

**Acceptance criteria covered**: scenarios 13 and 14; the criterion
"permission-boundary and destructive-command scenarios demonstrate an actual
runtime rejection, not just intent".

**Commit**: `test(acceptance): add runtime permission-rejection harness`

---

### Task 3: Redaction & flagging fixture check `[S]`

**Goal**: Add a deterministic fixture-based check that a secret-like string is
redacted and its topic carries a **Flagged** note, without depending on live DB
contents.

**Files**:

| File                        | Action | Description                                                                 |
|-----------------------------|--------|-----------------------------------------------------------------------------|
| `tests/redaction_check.sh`  | create | Feeds secret and clean fixtures through the redaction helper and asserts redaction + flagging vs clean pass-through |

**Reuse**:

| File                                              | What to reuse                                             |
|---------------------------------------------------|-----------------------------------------------------------|
| `tests/extract_topics_check.sh` (lines ~114–153)  | The exact secret/clean fixture loop and `redact.py` invocation pattern |
| `.opencode/skills/extract-topics/scripts/redact.py` | The redaction helper under test                          |

**Steps**:

1. Copy the harness scaffolding + helpers.
2. Reuse the secret fixtures (`client_secret`, `bearer`, `api_key`, `token`,
   long hex) and the clean sentence from `extract_topics_check.sh`; assert each
   secret is `REDACTED` and raises a flag, and the clean text passes through
   unchanged with no flag.
3. Assert the extract-topics skill maps a flag onto a topic's **Flagged** note
   in the DRAFT topics file (static anchor: `Flagged`).
4. Exit non-zero on any failure.

**Tests**: This task *is* the test; run `bash tests/redaction_check.sh`.

**Acceptance criteria covered**: scenario 5 (redaction/flagging), deterministic
via fixtures per the spec's "Fixtures vs. live data" guidance.

**Commit**: `test(acceptance): add deterministic redaction/flagging fixture check`

---

### Task 4: Document the repeatable acceptance procedure `[M]`

**Goal**: Add `docs/acceptance.md` — a single, repeatable procedure that maps
every scenario 1–15 (and each parent-spec acceptance criterion) to its check,
distinguishing automated checks from the manual agent-conversation script, and
records the expected observation (PASS) for each.

**Files**:

| File                 | Action | Description                                                                           |
|----------------------|--------|---------------------------------------------------------------------------------------|
| `docs/acceptance.md` | create | The acceptance runbook: prerequisites, automated commands, manual scripts, scenario→check→criterion mapping table |
| `README.md`          | modify | Add an "Acceptance testing" section linking to `docs/acceptance.md` and listing the test commands |

**Reuse**:

| File                                    | What to reuse                                                      |
|-----------------------------------------|--------------------------------------------------------------------|
| `README.md` (prereqs + restart sections) | The DB prereq command and the "restart opencode" guidance to reference as procedure preconditions |
| `plans/0{1,2,3,4}-*.md` Verification sections | The manual runtime-script wording pattern (invoke agent, observe DRAFT, approve, observe FINAL) to keep the manual steps consistent |

**Steps**:

1. Create `docs/acceptance.md` with:
   - **Prerequisites**: `git` + `sqlite3` on PATH; the DB read-only check
     (`sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"`); note
     that runtime scenarios require restarting opencode so config/agents/skills
     load; note the **DB-unavailable** edge case fails fast with a clear
     message.
   - **Automated checks**: the full-suite command; state each script's scope.
   - **Manual script** for the conversation-only scenarios (2, 3, 4, 6, 7, 8,
     10, 11, 12): the exact prompt to send each agent and the precise expected
     observation (files created, statuses flipped, no body embedded in a
     `question`), including the empty-activity-window and publish-nonexistent-
     slug edges.
   - **Scenario → check → parent-criterion mapping table** covering all 15
     scenarios so every parent acceptance criterion maps to at least one
     scenario (satisfies AC "each parent-spec criterion maps to at least one
     scenario").
2. Add a short **Acceptance testing** section to `README.md` linking to
   `docs/acceptance.md` and listing the test commands, so the procedure is
   discoverable on a fresh clone (satisfies AC "documented in README.md or a
   linked docs/acceptance.md").
3. Keep the doc within the two writable planning deliverables' spirit — no
   application behaviour changes.

**Tests**: No script; verified by the mapping being complete (cross-checked in
Task 5) and by the README link resolving.

**Acceptance criteria covered**: "the procedure is repeatable on a fresh clone
and documented in README.md (or a linked docs/acceptance.md)"; documents
scenarios 11, 12 and the empty-window / DB-unavailable edge cases; provides the
scenario↔criterion mapping.

**Commit**: `docs(acceptance): add repeatable end-to-end acceptance procedure`

---

### Task 5: Coverage cross-check & suite runner `[S]`

**Goal**: Guarantee every scenario 1–15 has a documented check and that the
acceptance doc and scripts stay in sync, and provide one entry point to run
the whole suite.

**Files**:

| File                        | Action | Description                                                                 |
|-----------------------------|--------|-----------------------------------------------------------------------------|
| `tests/acceptance_check.sh` | modify | Add a coverage sub-check: assert `docs/acceptance.md` references every scenario number 1–15 and each `tests/*_check.sh` script by name |
| `tests/run_all.sh`          | create | Convenience runner invoking all `tests/*_check.sh` in order, aggregating exit codes |

**Reuse**:

| File                        | What to reuse                                                    |
|-----------------------------|------------------------------------------------------------------|
| `tests/acceptance_check.sh` | Its helpers (extended in Task 1) for the doc-coverage assertions |
| Existing `tests/*_check.sh` | Invoked verbatim by the runner                                   |

**Steps**:

1. In `tests/acceptance_check.sh`, add a "coverage" section that asserts
   `docs/acceptance.md` mentions each scenario `1`–`15` and names each verifier
   script (`scaffold_check.sh`, `extract_topics_check.sh`, `conventions_check.sh`,
   `blog_writer_check.sh`, `permission_check.sh`, `redaction_check.sh`).
2. Create `tests/run_all.sh` that runs every `tests/*_check.sh` (excluding
   itself) in a stable order, prints each script's result, and exits non-zero
   if any failed — reusing the `SCRIPT_DIR`/`ROOT` resolution idiom.
3. Ensure `run_all.sh` tolerates the `SKIP` path from Task 2 (skips are not
   failures).

**Tests**: `bash tests/run_all.sh` → all present checks pass (permission
runtime cases may report `SKIP` without a CLI).

**Acceptance criteria covered**: "every scenario 1–15 has a documented check";
keeps the mapping honest over time.

**Commit**: `test(acceptance): cross-check scenario coverage and add suite runner`

---

**Task ordering**: Task 1 establishes the harness other tasks lean on. Tasks 2
and 3 are independent of each other and can follow Task 1 in any order. Task 4
(docs) can be authored in parallel but should land before Task 5, which
cross-checks the doc against the scripts. Recommended order: 1 → 2 → 3 → 4 → 5.

## Edge Cases & Error Handling

- **Empty activity window** (spec edge): manual script in `docs/acceptance.md`
  states the extractor still writes a DRAFT noting the empty result and the
  blog-writer can still take a free-text topic (Task 4).
- **DB unavailable during test** (spec edge): the acceptance doc lists the DB
  read-only check as a prerequisite and instructs failing fast with a clear
  message (Task 4).
- **Deleted tracked project / empty commit-session window** (spec edges): noted
  in the manual script as warn+skip / skip-silently-and-note-in-appendix
  (Task 4).
- **Fixtures vs. live data** (spec edge): redaction and auto-discovery checks
  use fixtures/temp scratch, never the live DB, for determinism (Tasks 2, 3).
- **opencode CLI absent on the test host**: Task 2 degrades to a config-level
  deny-rule assertion and reports `SKIP` for the true runtime cases, so the
  suite stays green on a fresh clone while documenting the runtime requirement.
- **Publish for a nonexistent slug**: covered as a manual observation (warn,
  do nothing) in the acceptance doc (Task 4, scenario 11).

## Verification

1. Run `bash tests/acceptance_check.sh` → all static + coverage checks pass.
2. Run `bash tests/redaction_check.sh` → secrets redacted+flagged, clean text
   untouched.
3. Run `bash tests/permission_check.sh` → with the opencode CLI present, every
   forbidden write and destructive command is rejected at runtime (target files
   are never created); without the CLI, the config-level deny rules are
   asserted and runtime cases report `SKIP`.
4. Run `bash tests/run_all.sh` → the whole suite (steps 01–05) passes with no
   regressions.
5. Open `docs/acceptance.md` and confirm: every scenario 1–15 has a check,
   each parent-spec acceptance criterion maps to at least one scenario, and the
   README links to the procedure.
6. **Runtime (manual, after restarting opencode)**: walk the manual script in
   `docs/acceptance.md` — extractor DRAFT→FINAL, auto-discovery confirmation,
   blog-writer draft→publish, missing-conventions refusal — observing the
   documented PASS for each conversation-only scenario.
