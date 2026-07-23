# Plan: Project Scaffold & Permissions

| Field        | Value                                             |
|--------------|---------------------------------------------------|
| **Title**    | Project Scaffold & Permissions                    |
| **Spec**     | specs/steps/01-project-scaffold-and-permissions.md |
| **Type**     | feature                                            |
| **Branch**   | feat/01-project-scaffold-and-permissions          |
| **Created**  | 2026-07-23 00:00:00                               |
| **Status**   | IMPLEMENTED                                       |

## Context

The Blog-Writer opencode project rests on a correct directory layout and a
safety-critical `.opencode/opencode.json` that encodes per-agent permissions
and `external_directory` allowances. This step (1 of 5) lays down the skeleton,
the two auto-discovered agent stubs, a placeholder `CONVENTIONS.md`, and the
permission boundary — getting the permission model right so later steps only
fill in agent/skill bodies.

## Branch Strategy

> **Before implementation, create a new branch from the repo's base
> branch.** The implementer auto-detects the base in this priority
> order: `develop` → `main` → `master` → `origin/HEAD`. For this repo the
> base is `develop`. The branch name is `feat/01-project-scaffold-and-permissions`.
>
> Reference command:
>
> ```bash
> git checkout develop && git pull --ff-only && git checkout -b feat/01-project-scaffold-and-permissions
> ```
>
> Note: the git repo and the project root are the same folder (the one that
> holds `specs/`). All paths below are relative to that project root.

Branch type mapping (this is a `feature`): `feat/<slug>`.

## Commit Strategy

All commits follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

Format: `<type>[(<scope>)]: <imperative description>`

One commit per task. Each task below maps to exactly one commit.

## Build & Test Commands

There is no application build/test toolchain (no `package.json`, `pyproject.toml`,
etc.). Verification is manual/CLI-based.

| Action        | Command |
|---------------|---------|
| Validate JSON | `python3 -m json.tool .opencode/opencode.json > /dev/null` |
| Prereq check  | `sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"` |
| Config load   | Restart opencode; confirm no `ConfigInvalidError` and both agents are selectable |

## Tasks

### Task 1: Create directory skeleton, `.gitkeep`s, and `tracked-projects.txt` `[S]`

**Goal**: Establish the on-disk directory layout for inputs, drafts, and
published outputs, plus the optional allowlist file.

**Files**:

| File                     | Action | Description                                    |
|--------------------------|--------|------------------------------------------------|
| `inputs/.gitkeep`        | create | Keep the `inputs/` dir tracked in git          |
| `drafts/.gitkeep`        | create | Keep the `drafts/` dir tracked in git          |
| `published/.gitkeep`     | create | Keep the `published/` dir tracked in git       |
| `tracked-projects.txt`   | create | Explanatory comment header only, no real paths |

**Steps**:

1. Create the three directories, each with an empty `.gitkeep`.
2. Create `tracked-projects.txt` with a comment header explaining it is an
   **optional allowlist** (one directory path per line; if absent/empty the
   extractor auto-discovers from the opencode DB and confirms via `question`).
   No real paths.

**Tests**:

- Confirm all three directories and `.gitkeep` files exist.
- Confirm `tracked-projects.txt` exists and contains only comment lines.

**Acceptance criteria covered**: "All directories and `.gitkeep` files exist."

**Commit**: `feat: add project directory skeleton and tracked-projects allowlist`

---

### Task 2: Add placeholder `CONVENTIONS.md` `[S]`

**Goal**: Provide a valid placeholder so a fresh clone validates and the
future blog-writer's "missing conventions" guard finds a file; real content
is authored interactively in step 03.

**Files**:

| File               | Action | Description                                            |
|--------------------|--------|--------------------------------------------------------|
| `CONVENTIONS.md`   | create | Clearly-marked placeholder stub with section headings  |

**Steps**:

1. Write a placeholder `CONVENTIONS.md` with a header explicitly marking it as
   a stub to be filled in during step 03. Include empty section headings for
   the topics step 03 will cover (voice/style, structure, taboos, bilingual
   EN/IT preferences, MDX conventions, tag vocabulary) so the shape is obvious.

**Tests**:

- Confirm `CONVENTIONS.md` exists at the project root and is non-empty.

**Acceptance criteria covered**: "A valid placeholder `CONVENTIONS.md` exists
at the project root."

**Commit**: `feat: add placeholder CONVENTIONS.md stub`

---

### Task 3: Add `AGENTS.md` and `README.md` `[M]`

**Goal**: Document the project context (for opencode) and the human-facing
usage guide.

**Files**:

| File          | Action | Description                                              |
|---------------|--------|----------------------------------------------------------|
| `AGENTS.md`   | create | Top-level project context read by opencode               |
| `README.md`   | create | How to use the project (prereqs, invocation, outputs)    |

**Steps**:

1. Write `AGENTS.md`: what the project is, that it only *observes* other
   projects (never edits them), the two agents' roles (topic-extractor,
   blog-writer), and the DRAFT-first + scoped-write invariants.
2. Write `README.md`: prerequisites (`git`, `sqlite3`, the opencode DB path),
   how to invoke each agent, the optional `tracked-projects.txt` allowlist,
   where outputs land (`inputs/`, `drafts/`, `published/`), the reminder to
   **restart opencode after config changes** (config is not hot-reloaded), and
   the escape hatch `OPENCODE_DISABLE_PROJECT_CONFIG=1` if the config fails to
   load.
3. Include in `README.md` the prereq verification command:
   `sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"`.

**Tests**:

- Confirm both files exist and describe the project, the two agents, and the
  invariants.
- Confirm `README.md` contains the DB prereq command and the restart reminder.

**Acceptance criteria covered**: "`sqlite3 -readonly ... .tables` succeeds
(prerequisite check documented in README)"; "`AGENTS.md` and `README.md`
describe the project, the two agents, and the invariants."

**Commit**: `docs: add AGENTS.md project context and README usage guide`

---

### Task 4: Add minimal agent stubs `.opencode/agents/{topic-extractor,blog-writer}.md` `[S]`

**Goal**: Create valid, auto-discoverable agent files so both agents are
present and selectable after step 01; full prompt bodies come in steps 02/04.

**Files**:

| File                                   | Action | Description                          |
|----------------------------------------|--------|--------------------------------------|
| `.opencode/agents/topic-extractor.md`  | create | Minimal valid stub (frontmatter + placeholder body) |
| `.opencode/agents/blog-writer.md`      | create | Minimal valid stub (frontmatter + placeholder body) |

**Reuse**:

| Reference                          | What to reuse                                  |
|------------------------------------|------------------------------------------------|
| opencode agent frontmatter format  | `mode: primary`, `description:` fields per opencode docs |

**Steps**:

1. Create `.opencode/agents/topic-extractor.md` with minimal frontmatter
   (`mode: primary`, a short `description`) and a placeholder body noting the
   real prompt is authored in step 02. Do **not** duplicate permissions here —
   the permission boundary lives in `opencode.json` (Task 5).
2. Create `.opencode/agents/blog-writer.md` similarly, noting step 04.

**Tests**:

- After opencode restart, confirm both agents are discovered and selectable.

**Acceptance criteria covered**: "`.opencode/agents/topic-extractor.md` and
`.opencode/agents/blog-writer.md` exist as valid stubs and both agents are
discovered/selectable when opencode starts."

**Commit**: `feat: add topic-extractor and blog-writer agent stubs`

---

### Task 5: Author `.opencode/opencode.json` with per-agent permissions and `external_directory` `[M]`

**Goal**: Encode the safety-critical permission boundary for both agents in a
schema-valid config.

**Files**:

| File                        | Action | Description                                  |
|-----------------------------|--------|----------------------------------------------|
| `.opencode/opencode.json`   | create | `$schema`, `agent.*.permission`, `external_directory` |

**Reuse**:

| Reference                              | What to reuse                              |
|----------------------------------------|--------------------------------------------|
| `https://opencode.ai/config.json`      | Confirmed shapes: `PermissionConfig`, `PermissionObjectConfig` (`{pattern: action}`), `external_directory` key, `AgentConfig.permission` |

**Steps**:

1. Declare `"$schema": "https://opencode.ai/config.json"`.
2. Under `agent`, add `topic-extractor` and `blog-writer` blocks, each with a
   `permission` object (no large inline prompts — bodies live in the `.md`
   stubs from Task 4):
   - **topic-extractor.permission**:
     - `read`: allow anywhere.
     - `edit`: deny by default, allow only `inputs/**`.
     - `bash`: allow `git *`, allow `sqlite3 * -readonly *`; deny `git push*`,
       `git commit --amend*`, `rm -rf*`; conservative default otherwise.
   - **blog-writer.permission**:
     - `read`: allow anywhere.
     - `edit`: deny by default, allow `drafts/**`, `inputs/**`, `published/**`.
     - `bash`: same git/sqlite allow + destructive denies; additionally permit
       the publishing move (`mv drafts/* published/*` or equivalent); keep
       `rm -rf` denied.
3. Add `external_directory` (applies to both agents as needed): broad allow of
   `~/**` plus the opencode DB directory; explicit denies of `~/.ssh/**`,
   `~/.aws/**`, `~/.gnupg/**`, `~/.config/**`, `**/.env`.
4. Order/structure the `{pattern: action}` rules per the precedence confirmed
   in Task 6. Validate the JSON parses.

**Tests**:

- `python3 -m json.tool .opencode/opencode.json` succeeds (valid JSON).
- Restart opencode: no `ConfigInvalidError`.
- Inspect each `edit` and `bash` block to confirm allow and deny entries are
  present as specified.

**Acceptance criteria covered**: config valid + opencode starts without
`ConfigInvalidError`; per-agent permission blocks in `opencode.json`;
topic-extractor `edit` allows `inputs/**` only; blog-writer `edit` allows
`drafts/**`, `inputs/**`, `published/**` only; both agents' `bash` allow/deny
lists; `external_directory` allow `~/**`+DB and denies the sensitive set.

**Commit**: `feat: add opencode.json with per-agent permissions and external_directory`

---

### Task 6: Empirically confirm opencode permission rule-precedence and finalise ordering `[M]`

**Goal**: Verify how opencode resolves multiple matching patterns within a
`{pattern: action}` object, then arrange `opencode.json` so the deny rules are
genuinely effective — the safety boundary depends on this.

**Files**:

| File                        | Action | Description                                          |
|-----------------------------|--------|------------------------------------------------------|
| `.opencode/opencode.json`   | modify | Reorder/restructure rules per confirmed precedence   |
| `README.md`                 | modify | Document the confirmed precedence semantics briefly  |

**Steps**:

1. Empirically determine opencode's precedence for the pattern-object form
   (candidate models: last-match-wins, most-specific-match, deny-overrides).
   Use a controlled check — e.g. a temporary agent/config with a known
   allow+deny pair on an overlapping path, then observe which wins at runtime
   — and/or opencode docs/source. Record the finding.
2. If the confirmed rule is **not** last-match-wins, restructure the rules in
   `opencode.json` (from Task 5) so each deny actually overrides the broad
   allow it must beat (e.g. reorder, or split into more specific patterns).
3. Verify the boundary holds by exercising representative cases: a denied edit
   outside the allowed dirs is rejected; a denied `git push`/`rm -rf` is
   rejected; an allowed `inputs/**` edit and `git log`/`sqlite3 -readonly`
   succeed.
4. Add a short note to `README.md` documenting the confirmed precedence rule so
   future edits stay safe.

**Tests**:

- Document the precedence finding (in the plan/impl notes and README).
- Confirm both the allow side and the deny side behave as intended for each
  agent (edit scope, `git push`, `git commit --amend`, `rm -rf`,
  `external_directory` sensitive denies).

**Acceptance criteria covered**: "opencode's permission rule-precedence
semantics have been empirically confirmed ... and the ordering/structure is
arranged so the deny rules are actually effective"; the allow/deny assertion
criteria for `edit`, `bash`, and `external_directory`.

**Commit**: `fix: confirm permission precedence and harden opencode.json ordering`

---

**Task ordering**: Tasks 1–4 are independent of each other and can be done in
any order. Task 5 depends on Task 4 (agent stubs must exist so the `agent`
blocks correspond to real agents). Task 6 depends on Task 5 (it verifies and
adjusts the config authored there) and on Task 3 (it appends the precedence
note to `README.md`). Recommended order: 1 → 2 → 3 → 4 → 5 → 6.

## Edge Cases & Error Handling

- **opencode DB not found**: README documents the expected path and the
  verification command; runtime error handling is added in steps 02/04. (Task 3)
- **Permission rule ordering mistake**: covered by explicit allow-and-deny
  checks and the precedence-verification task; do not trust ordering without
  confirming opencode's actual semantics. (Tasks 5, 6)
- **Config fails to load**: README points at `OPENCODE_DISABLE_PROJECT_CONFIG=1`
  so the user can edit from inside opencode. (Task 3)

## Verification

1. `sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"` succeeds.
2. `python3 -m json.tool .opencode/opencode.json > /dev/null` succeeds.
3. Restart opencode; confirm no `ConfigInvalidError` and both `topic-extractor`
   and `blog-writer` are selectable.
4. Confirm directory skeleton, `.gitkeep`s, `tracked-projects.txt`,
   `CONVENTIONS.md` placeholder, `AGENTS.md`, and `README.md` all exist.
5. Confirm the permission boundary behaves correctly (allow + deny sides) for
   both agents: scoped `edit`, `git`/`sqlite3 -readonly` allowed, destructive
   git and `rm -rf` denied, `external_directory` allows `~/**`+DB and denies
   the sensitive set — under the empirically-confirmed precedence rule.
