# Plan: topic-extractor Agent & extract-topics Skill

| Field        | Value                                            |
|--------------|--------------------------------------------------|
| **Title**    | topic-extractor Agent & extract-topics Skill     |
| **Spec**     | specs/steps/02-topic-extractor-agent-and-skill.md |
| **Type**     | feature                                          |
| **Branch**   | feat/02-topic-extractor-agent-and-skill          |
| **Created**  | 2026-07-23 08:20:00                              |
| **Status**   | IMPLEMENTED                                      |

## Context

Step 01 laid down the project scaffold: permissions in
`.opencode/opencode.json`, a `topic-extractor` **stub** agent, the optional
`tracked-projects.txt` allowlist, and a shell-based verification harness at
`tests/scaffold_check.sh`. This step replaces the stub with the agent's full
prompt body and authors the `extract-topics` skill it loads: auto-discover (or
allowlist) tracked projects, `git log` each, query opencode sessions with
`sqlite3 -readonly`, correlate commits and sessions by timestamp, redact
secret-like strings, and write a DRAFT `inputs/topics-YYYY-Www.md` that is
flipped to FINAL only on explicit approval. The agent never writes an article.

## Branch Strategy

> **Before implementation, create a new branch from the repo's base
> branch.** The implementer auto-detects the base in this priority
> order: `develop` → `main` → `master` → `origin/HEAD`. This repo's
> current branch is `develop`, so that is the expected base. The branch
> name is `feat/02-topic-extractor-agent-and-skill`.
>
> Reference command (the implementer adapts to the detected base):
>
> ```bash
> git checkout develop && git pull --ff-only && git checkout -b feat/02-topic-extractor-agent-and-skill
> ```

Branch type mapping: feature → `feat/<slug>`.

## Commit Strategy

All commits follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

Format: `<type>[(<scope>)]: <imperative description>`

One commit per task. Each task below maps to exactly one commit.

## Build & Test Commands

This project has no package manifest or build step. Tests are shell scripts
run directly with `bash`, following the step-01 pattern
(`tests/scaffold_check.sh`).

| Action | Command |
|--------|---------|
| Test (this step) | `bash tests/extract_topics_check.sh` |
| Test (step 01, regression) | `bash tests/scaffold_check.sh` |
| DB prereq check | `sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"` |

## Key Findings From Exploration

Recorded here so the implementer does not re-discover them:

- **`time_updated` is NOT indexed.** Verified against the live DB: `session`
  has indexes only on `project_id`, `parent_id`, `workspace_id`. Filtering on
  `time_updated` produces `SCAN session`. The table is small, so a scan is
  cheap. The skill/agent must **filter on `time_updated`** (correct, read-only)
  but must **not** claim the column is indexed or that scans are avoided. Do
  NOT create an index — the DB is accessed read-only.
- **Verified schema.** `session(id, project_id, parent_id, slug, directory,
  title, agent, model, time_created, time_updated, path, ...)`;
  `message(id, session_id, time_created, time_updated, data)`;
  `part(id, message_id, session_id, time_created, time_updated, data)`. All
  timestamps are Unix **ms** integers.
- **Text extraction.** `part.data` is JSON with a `type` field
  (`text`, `step-start`, `tool`, `patch`, `file`, ...). Human/agent prose lives
  in `type='text'` parts at `json_extract(data,'$.text')`. `message.data` has a
  `role` (`user`/`assistant`). Topic substance should come from `type='text'`
  parts of the matched sessions.
- **Existing permissions already support this step.** `.opencode/opencode.json`
  already allows `read` anywhere, `git *`, `sqlite3 ... -readonly ...`, edit of
  `inputs/**`, and denies `git push` / `git commit --amend` / `rm -rf`. No
  config change is needed in this step.
- **Test style.** Step 01 uses a `bash` script with `pass`/`fail` helpers and an
  embedded `python3` heredoc for JSON assertions. Reuse that structure.

## Tasks

### Task 1: Author the `extract-topics` skill workflow `[M]`

**Goal**: Create the skill document that encodes the full extraction workflow
the agent follows.

**Files**:

| File                                          | Action | Description                        |
|-----------------------------------------------|--------|------------------------------------|
| `.opencode/skills/extract-topics/SKILL.md`    | create | Full 10-step extraction workflow   |

**Reuse**:

| File                                     | What to reuse                                   |
|------------------------------------------|-------------------------------------------------|
| `specs/blog-writer-project.md`           | `topics-*.md` output template (frontmatter table, candidate topics, appendix) |
| `.opencode/skills/*` (spec-* skills)     | SKILL.md frontmatter + section style as a format reference |

**Steps**:

1. Write YAML frontmatter (`name`, `description`) matching the opencode skill
   convention, description phrased so it triggers on "extract topics".
2. Document the 10-step workflow verbatim from the spec's Desired Outcome:
   1. **Resolve time window** — default last 7 days; accept overrides; compute
      Unix-ms bounds; derive the output filename from the ISO week of the
      window's **end** date.
   2. **Resolve tracked projects** — if `tracked-projects.txt` is present and
      has ≥1 non-comment/non-blank path line, use it as an allowlist; else
      auto-discover via
      `sqlite3 -readonly <db> "SELECT DISTINCT directory FROM session WHERE time_updated > <lo> AND time_updated <= <hi>"`
      and confirm the list via `question` before proceeding. Never refuse
      solely because the file is absent.
   3. **Per project git history** — `git -C <dir> log --since/--until` for short
      SHA, subject, timestamp; skip + note non-git/empty; warn + skip if the
      directory is gone.
   4. **Gather sessions** — query `session` filtered on `time_updated` and
      `directory`; collect `id` (short), `title`, `slug`, `agent`,
      `time_created`, `time_updated`; then pull `type='text'` part text
      (`json_extract(data,'$.text')`) for matched sessions, **capped per
      session** (bounded part count / character budget).
   5. **Correlate by timestamp** — relate commits and sessions close in time;
      be transparent about the links made.
   6. **Redact** — run the redaction filter over material destined for disk
      (quoted text) only; detect `client_secret`, `bearer`, `api_key`,
      `token`, and long hex/base64 secret-like strings; redact matches and
      mark the owning topic **Flagged**.
   7. **Synthesise candidate topics** — use the parent-spec template.
   8. **Write DRAFT** — `inputs/topics-YYYY-Www.md` (ISO week of window end)
      with `Status: DRAFT`; if that file already exists, ask via `question`
      whether to overwrite or rename before writing.
   9. **Ask a short question** — summarise counts (projects, sessions, commits,
      topics, flagged); never embed file contents in the `question`.
   10. **Finalise on approval** — `edit` `Status: DRAFT → FINAL`; on change
       requests edit the file directly and re-ask.
3. Add a **SQL constraints** subsection: every `sqlite3` call uses `-readonly`;
   queries **filter on `time_updated`** (bounded time window) — state plainly
   that this column is not indexed and a scan is acceptable given table size;
   do NOT create indexes. Include the verified schema note.
4. Add a **Redaction reference** subsection listing the patterns and the
   Flagged-note format, pointing at the helper delivered in Task 2.
5. Include the empty-result rule: still write a DRAFT stating "no topics".

**Tests**: Covered by Task 4 (asserts SKILL.md exists, is non-empty, mentions
each workflow anchor: allowlist/auto-discover, `sqlite3 -readonly`,
`time_updated`, redaction/Flagged, DRAFT/FINAL, ISO week).

**Acceptance criteria covered**: template match; correlate by timestamp;
redaction+Flagged; DRAFT-first + no embedded body; `-readonly`+`time_updated`;
substance from part text; ISO-week-of-end naming; overwrite prompt; zero-topics.

**Commit**: `feat(extract-topics): author the extraction workflow skill`

---

### Task 2: Add the redaction + timestamp-correlation helper `[M]`

**Goal**: Provide a small, testable script the skill invokes for the two
mechanical, security-critical operations (secret redaction and time-proximity
correlation), so behaviour is deterministic and unit-testable rather than
left to prose.

**Files**:

| File                                                    | Action | Description                                   |
|---------------------------------------------------------|--------|-----------------------------------------------|
| `.opencode/skills/extract-topics/scripts/redact.py`     | create | Reads text on stdin, redacts secret-like patterns, exits non-zero-flag semantics via a marker line |

**Reuse**:

| File                        | What to reuse                          |
|-----------------------------|----------------------------------------|
| `tests/scaffold_check.sh`   | `python3` availability is already assumed by the repo's test harness |

**Steps**:

1. Implement `redact.py` (stdin → stdout) that replaces matches of
   `client_secret`, `bearer <token>`, `api_key`, `token`, and long hex/base64
   runs with a `[REDACTED:<reason>]` marker, using conservative regexes.
2. Emit, on stderr or a trailing marker line, whether any redaction occurred
   (so the skill knows to attach a **Flagged** note to the owning topic).
3. Keep it dependency-free (Python stdlib only) — the repo has no manifest.
4. Reference this script from SKILL.md step 6 (update the Redaction reference
   subsection to name the exact invocation).

**Tests**: Task 4 pipes known-secret fixtures through `redact.py` and asserts
(a) each pattern is redacted, (b) the flag marker is emitted, (c) clean text
passes through unchanged and emits no flag.

**Acceptance criteria covered**: secret-like patterns redacted; topics carry a
Flagged note.

**Commit**: `feat(extract-topics): add redaction helper for session text`

---

### Task 3: Replace the topic-extractor stub with its full prompt `[S]`

**Goal**: Turn the step-01 placeholder agent into the real primary agent that
loads and follows the `extract-topics` skill, with anti-hijack hardening.

**Files**:

| File                                        | Action | Description                                     |
|---------------------------------------------|--------|-------------------------------------------------|
| `.opencode/agents/topic-extractor.md`       | modify | Replace stub body with role, invariants, anti-hijack rule, and skill load |

**Reuse**:

| File                                        | What to reuse                                  |
|---------------------------------------------|------------------------------------------------|
| `.opencode/agents/topic-extractor.md`       | Keep existing frontmatter (`mode: primary`, description) |
| `.opencode/opencode.json`                   | Permission boundary already defined; reference it, do not restate |
| `AGENTS.md`                                  | Project invariants wording to mirror |

**Steps**:

1. Preserve the frontmatter (`mode: primary`; refine `description` if needed).
2. Write the prompt body: role (read-only analyst), the DRAFT-first invariant,
   read-only DB access, scoped writes to `inputs/**`, and a **hard anti-hijack
   rule**: produces ONLY a topics file and NEVER writes an article even if
   asked — reframe such requests toward the blog-writer.
3. Instruct the agent to load the `extract-topics` skill.
4. Note that the permission boundary lives in `.opencode/opencode.json` (do not
   duplicate rules in prose).

**Tests**: Task 4 asserts the file still declares `mode: primary`, mentions the
`extract-topics` skill, contains an anti-hijack ("never" + "article") line, and
no longer contains the word "stub"/"placeholder".

**Acceptance criteria covered**: agent never writes outside `inputs/**` and
never writes an article; invocation drives the DRAFT topics workflow.

**Commit**: `feat(topic-extractor): replace stub with full agent prompt`

---

### Task 4: Add the extract-topics verification harness `[M]`

**Goal**: A `bash` test asserting every statically-checkable acceptance
criterion for this step, mirroring `tests/scaffold_check.sh`.

**Files**:

| File                               | Action | Description                                  |
|------------------------------------|--------|----------------------------------------------|
| `tests/extract_topics_check.sh`    | create | Static assertions for the skill, agent, and redaction helper |

**Reuse**:

| File                          | What to reuse                                          |
|-------------------------------|--------------------------------------------------------|
| `tests/scaffold_check.sh`     | `pass`/`fail`/`assert_file`/`assert_contains` helpers, `set -u`, root resolution, `python3` heredoc idiom |

**Steps**:

1. Copy the harness scaffolding (root resolution, helper functions) from
   `scaffold_check.sh`.
2. Assert SKILL.md exists, is non-empty, and contains each workflow anchor:
   `tracked-projects.txt`, auto-discover / `SELECT DISTINCT directory`,
   `sqlite3 -readonly`, `time_updated`, redaction keywords, `Flagged`,
   `Status: DRAFT` and `FINAL`, ISO-week naming, overwrite prompt.
3. Assert the agent file declares `mode: primary`, references `extract-topics`,
   carries the anti-hijack line, and dropped "stub"/"placeholder".
4. Assert `redact.py` exists; pipe secret fixtures through it and check
   redaction + flag marker; pipe clean text and check pass-through + no flag.
5. Assert the harness does NOT claim `time_updated` is indexed (guard against
   regressing the corrected wording) — i.e., SKILL.md must not contain
   "indexed time_updated" / "no full-table scan".
6. Exit non-zero on any failure.

**Tests**: This task *is* the test; run `bash tests/extract_topics_check.sh`.

**Acceptance criteria covered**: provides automated coverage of all
statically-verifiable criteria; the remainder are runtime-only (see
Verification).

**Commit**: `test(extract-topics): add verification harness for step 02`

---

**Task ordering**: Task 1 and Task 2 are largely independent but Task 1's step-6
text references Task 2's script, so do Task 2 alongside/just after Task 1 and
finalise the SKILL.md reference. Task 3 is independent (depends only on the
skill existing by name). Task 4 depends on Tasks 1–3 (it asserts their output).
Recommended order: 1 → 2 → 3 → 4.

## Edge Cases & Error Handling

- **`tracked-projects.txt` present with only comments**: treated as empty →
  auto-discover + confirm (Task 1, step 2).
- **Project dir deleted / non-git / no commits / no sessions**: warn or skip and
  note in appendix; never abort the whole run (Task 1, step 3–4).
- **opencode DB missing/locked**: surface a clear error; never fall back to
  write access (Task 1, SQL constraints).
- **Zero topics found**: still write a DRAFT stating the empty result
  (Task 1, step 5/8).
- **Secret-like content**: redacted in written material + topic Flagged
  (Task 1 step 6, Task 2).
- **Topics file for the week already exists**: prompt to overwrite/rename
  before writing (Task 1, step 8).
- **`time_updated` not indexed**: filter on it anyway (small table, read-only);
  do not claim it is indexed; do not add an index (Key Findings).

## Verification

1. Run `bash tests/extract_topics_check.sh` → all checks pass.
2. Run `bash tests/scaffold_check.sh` → step-01 checks still pass (no
   regression from editing the agent file).
3. **Runtime (manual, after restarting opencode)**: invoke `topic-extractor`
   with "extract topics from last week"; confirm it auto-discovers (or uses the
   allowlist), asks for project confirmation when auto-discovering, writes
   `inputs/topics-YYYY-Www.md` with `Status: DRAFT`, summarises via `question`
   without embedding the body, and flips to `FINAL` on approval.
4. **Runtime**: confirm all `sqlite3` calls in the transcript use `-readonly`,
   and that asking the agent to "write the article" is refused.
