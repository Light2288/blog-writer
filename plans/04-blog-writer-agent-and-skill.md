# Plan: blog-writer Agent & write-blog-article Skill

| Field        | Value                                              |
|--------------|----------------------------------------------------|
| **Title**    | blog-writer Agent & write-blog-article Skill       |
| **Spec**     | specs/steps/04-blog-writer-agent-and-skill.md      |
| **Type**     | feature                                             |
| **Branch**   | feat/04-blog-writer-agent-and-skill                |
| **Created**  | 2026-07-23 11:30:00                                |
| **Status**   | IMPLEMENTED                                        |

## Context

Step 01 laid down the scaffold, including a `blog-writer` **stub** agent and
the permission boundary in `.opencode/opencode.json`. Step 03 delivered the
`author-conventions` interview and the canonical `<!-- TODO: -->` placeholder
marker used to fill `CONVENTIONS.md`. This step (4 of 5) replaces the stub with
the real primary agent and authors the `write-blog-article` skill it loads:
read `CONVENTIONS.md` (refuse on a missing/all-placeholder file), resolve a
topic from `inputs/topics-*.md` or free text, draft the English body first and
iterate, translate to Italian, assemble a single bilingual `drafts/<slug>.mdx`
with `draft: true`, and publish on explicit command by flipping `draft: false`
and moving the file to `published/`. Anti-hijack: never edits source projects,
never commits or pushes.

## Branch Strategy

> **Before implementation, create a new branch from the repo's base
> branch.** The implementer auto-detects the base in this priority
> order: `develop` → `main` → `master` → `origin/HEAD`. This repo's
> current branch is `develop`, so that is the expected base. The branch
> name is `feat/04-blog-writer-agent-and-skill`.
>
> Reference command (the implementer adapts to the detected base):
>
> ```bash
> git checkout develop && git pull --ff-only && git checkout -b feat/04-blog-writer-agent-and-skill
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
`tests/conventions_check.sh`).

| Action | Command |
|--------|---------|
| Test (this step) | `bash tests/blog_writer_check.sh` |
| Test (step 03, regression) | `bash tests/conventions_check.sh` |
| Test (step 02, regression) | `bash tests/extract_topics_check.sh` |
| Test (step 01, regression) | `bash tests/scaffold_check.sh` |

## Key Findings From Exploration

Recorded here so the implementer does not re-discover them:

- **Permissions already support this step.** `.opencode/opencode.json` already
  grants `blog-writer`: `read` anywhere; `edit` of `drafts/**`, `inputs/**`,
  `published/**`; `bash` `git *`, `sqlite3 ... -readonly ...`, and
  `mv drafts/* published/*`; and denies `git push` / `git commit --amend` /
  `rm -rf`. **No config change is needed** in this step.
- **The agent file is a stub, not new.** `.opencode/agents/blog-writer.md`
  exists with correct frontmatter (`mode: primary`, description) and a stub
  body pointing at "step 04". This step **modifies** it (mirroring how Step 02
  replaced the topic-extractor stub), preserving/refining the frontmatter.
- **"Missing conventions" signal.** Step 03's canonical placeholder marker is
  `<!-- TODO:`. The blog-writer's guard must treat `CONVENTIONS.md` as
  missing/placeholder when the file is absent OR every section still carries a
  `<!-- TODO:` marker (no real content). The live `CONVENTIONS.md` is currently
  still an all-placeholder stub (using the legacy `_Placeholder_` style), so
  the guard must also tolerate that — key point: refuse to draft unless real
  content exists.
- **Sibling skill/agent style to mirror.** `.opencode/skills/extract-topics/SKILL.md`
  (YAML frontmatter `name`/`description`, numbered workflow, constraint
  subsections) and `.opencode/agents/topic-extractor.md` (role / Invariants /
  Anti-hijack rule sections) are the format references. Keep the new files
  consistent with them.
- **Output format is fully specified.** The bilingual MDX frontmatter +
  `<Lang>` block structure and the allowed component vocabulary are defined in
  `specs/blog-writer-project.md` under "article-<slug>.mdx output structure".
  Reproduce it in the skill verbatim; do not invent components.
- **Tag vocabulary source.** Tag `id` and `label:{en,it}` values come from the
  Tag Vocabulary section authored in `CONVENTIONS.md` (Step 03), not invented
  ad hoc.
- **Test style.** Shell harness with `pass`/`fail`/`assert_file`/
  `assert_nonempty`/`assert_contains`/`assert_contains_ci`/`assert_absent`
  helpers, `set -u`, `SCRIPT_DIR`/`ROOT` resolution, exit non-zero on any
  failure. Copy this scaffolding from `tests/conventions_check.sh`.

## Tasks

### Task 1: Author the `write-blog-article` skill workflow `[M]`

**Goal**: Create the skill document encoding the full nine-step
draft→iterate→translate→publish workflow the agent follows.

**Files**:

| File                                              | Action | Description                        |
|---------------------------------------------------|--------|------------------------------------|
| `.opencode/skills/write-blog-article/SKILL.md`    | create | Full authoring + publish workflow  |

**Reuse**:

| File                                              | What to reuse                                                        |
|---------------------------------------------------|----------------------------------------------------------------------|
| `specs/blog-writer-project.md`                    | The `article-<slug>.mdx` output structure + allowed MDX vocabulary   |
| `.opencode/skills/extract-topics/SKILL.md`        | Frontmatter (`name`/`description`) + numbered-workflow section style |
| `CONVENTIONS.md`                                  | The section names to read (Voice, Structure, Bilingual, MDX, Tag Vocabulary, Taboos) |

**Steps**:

1. Write YAML frontmatter (`name: write-blog-article`, `description` phrased to
   trigger on "write about topic N" / "draft an article" / "publish <slug>").
2. Document the workflow verbatim from the spec's Desired Outcome:
   1. **Load conventions** — read `CONVENTIONS.md`; if absent OR still
      all-placeholder (every section carries only a `<!-- TODO:` / legacy
      `_Placeholder_` marker, no real content), ask via `question` and **refuse
      to draft** until real content exists.
   2. **Resolve the topic** — "write about topic N" → read the current/
      most-recent `inputs/topics-*.md`, select topic N, carry over its title,
      angle, depth, and sources; free-text topic → use as-is.
   3. **Derive a slug** (kebab-case) and target path `drafts/<slug>.mdx`.
   4. **Draft English first** — write the body in English per `CONVENTIONS.md`
      using ONLY the allowed MDX vocabulary; assemble frontmatter with
      `draft: true`, per-language `title`/`summary` (English filled, Italian
      placeholder), `date`, `lastmod`, `tags` (id + label:{en,it} drawn from
      the CONVENTIONS.md Tag Vocabulary, not invented), and `images`.
   5. **Iterate on English** — write to disk, ask a short `question` (summary +
      word count + file path, never the body); edit the file directly; repeat
      until approved.
   6. **Translate to Italian** — produce Italian `title`/`summary` and a full
      `<Lang value="it">` body faithfully translating the approved English,
      honouring the bilingual policy (don't translate code identifiers/strings);
      assemble the single `.mdx` with both `<Lang>` blocks.
   7. **Confirm the assembled bilingual draft** — short `question`; iterate as
      needed; the file stays `draft: true`.
   8. **Finalise on approval** — `edit` frontmatter `draft: true → false`.
   9. **Publish on command** — on explicit "publish <slug>": ensure
      `draft: false`, then move `drafts/<slug>.mdx` → `published/<slug>.mdx`
      using only the permitted file tools or the permitted
      `mv drafts/* published/*` (never a destructive command); never
      auto-publish; if no draft exists for the slug, warn and do nothing.
3. Add an **Output format** subsection reproducing the bilingual frontmatter +
   `<Lang>` structure and the allowed component vocabulary from the parent
   spec, stating `draft:` is the on-disk DRAFT marker (no Status table).
4. Add a **DRAFT-first discipline** note: never embed the article body (or
   large markdown) in a `question`; the file on disk is the source of truth.
5. Include the edge-case rules inline: Italian-before-English → finish English
   first; slug collision → ask before overwriting; publish with no draft →
   warn, do nothing; editing an already-published/previously-dated article →
   refresh `lastmod` (leave `date` unchanged).

**Tests**: Covered by Task 3 (asserts SKILL.md exists, is non-empty, and
mentions each workflow anchor: conventions guard, topic resolution, English-
first, `draft: true`, `<Lang value="en">`/`<Lang value="it">`, allowed
vocabulary, publish move, no-embed rule).

**Acceptance criteria covered**: topic-resolution + `draft: true` draft;
English-first-then-Italian; bilingual frontmatter/blocks; allowed vocabulary;
approval flips `draft:`; publish move; missing/placeholder conventions guard;
no body in `question`.

**Commit**: `feat(write-blog-article): author the article authoring skill`

---

### Task 2: Replace the blog-writer stub with its full prompt `[S]`

**Goal**: Turn the step-01 placeholder agent into the real primary agent that
loads and follows the `write-blog-article` skill, with anti-hijack hardening.

**Files**:

| File                                   | Action | Description                                                        |
|----------------------------------------|--------|--------------------------------------------------------------------|
| `.opencode/agents/blog-writer.md`      | modify | Replace stub body with role, invariants, anti-hijack rule, skill load |

**Reuse**:

| File                                   | What to reuse                                                       |
|----------------------------------------|---------------------------------------------------------------------|
| `.opencode/agents/blog-writer.md`      | Keep existing frontmatter (`mode: primary`, description; refine if needed) |
| `.opencode/agents/topic-extractor.md`  | Role / Invariants / Anti-hijack-rule section structure to mirror    |
| `.opencode/opencode.json`              | Permission boundary already defined; reference it, do not restate   |
| `AGENTS.md`                            | Project invariant wording to mirror                                 |

**Steps**:

1. Preserve the frontmatter (`mode: primary`; refine `description` if needed).
2. Write the prompt body: role (the writer), then Invariants — reads
   `CONVENTIONS.md` every run and refuses without real content, DRAFT-first via
   the `draft:` marker, scoped writes to `drafts/**`/`inputs/**`/`published/**`,
   English-first bilingual workflow, publish only on explicit command.
3. Add a **hard anti-hijack rule**: produces ONLY articles in `drafts/` (moved
   to `published/` on explicit command); NEVER edits source projects; NEVER
   commits or pushes — reframe such requests and decline.
4. Instruct the agent to load the `write-blog-article` skill.
5. Note that the permission boundary lives in `.opencode/opencode.json` (do not
   duplicate rules in prose).

**Tests**: Task 3 asserts the file declares `mode: primary`, references the
`write-blog-article` skill, carries anti-hijack lines (never edit source
projects / never commit / never push), and no longer contains
"stub"/"placeholder".

**Acceptance criteria covered**: agent never writes outside the three dirs,
never edits source projects, never commits/pushes; invocation drives the
authoring workflow.

**Commit**: `feat(blog-writer): replace stub with full agent prompt`

---

### Task 3: Add the blog-writer verification harness `[M]`

**Goal**: A `bash` test asserting every statically-checkable acceptance
criterion for this step, mirroring the existing harnesses.

**Files**:

| File                            | Action | Description                                          |
|---------------------------------|--------|------------------------------------------------------|
| `tests/blog_writer_check.sh`    | create | Static assertions for the skill and the agent file   |

**Reuse**:

| File                          | What to reuse                                                                 |
|-------------------------------|-------------------------------------------------------------------------------|
| `tests/conventions_check.sh`  | `set -u`, `SCRIPT_DIR`/`ROOT` resolution, `pass`/`fail`/`assert_*` helpers, exit-code idiom |

**Steps**:

1. Copy the harness scaffolding (root resolution, helper functions) from
   `tests/conventions_check.sh`.
2. Assert `.opencode/skills/write-blog-article/SKILL.md` exists, is non-empty,
   and contains each workflow anchor: `CONVENTIONS.md`, a refuse/placeholder
   guard, topic resolution (`topics-`), English-first, `draft: true`,
   `<Lang value="en"`, `<Lang value="it"`, `<TOCInline`, `lang:filename`,
   `publish`, `published/`, and a "never embed" / no-body-in-question note.
3. Assert the agent file `.opencode/agents/blog-writer.md` declares
   `mode: primary`, references `write-blog-article`, carries anti-hijack lines
   (case-insensitive "never" + "source"/"commit"/"push"), and dropped
   "stub"/"placeholder" (`assert_absent`).
4. Assert the skill names the allowed vocabulary and the tag shape
   (`label:` / `en:` / `it:`), tying tags to the CONVENTIONS vocabulary.
5. Exit non-zero on any failure.

**Tests**: This task *is* the test; run `bash tests/blog_writer_check.sh`.

**Acceptance criteria covered**: automated coverage of all statically-
verifiable criteria; the remainder are runtime-only (see Verification).

**Commit**: `test(blog-writer): add verification harness for step 04`

---

**Task ordering**: Task 1 (skill) and Task 2 (agent) are largely independent;
Task 2 references the skill by name, so author Task 1 first. Task 3 depends on
Tasks 1–2 (it asserts their output). Recommended order: 1 → 2 → 3.

## Edge Cases & Error Handling

- **`CONVENTIONS.md` missing or all-placeholder**: ask via `question`, refuse
  to draft (Task 1, step 1; Task 2 invariant).
- **Referenced topic number out of range / no topics file**: ask the user to
  clarify or supply a free-text topic (Task 1, step 2).
- **Italian requested before English approved**: finish and confirm English
  first, then translate (Task 1, steps 5–6).
- **Publish requested for a slug with no draft**: warn, do nothing (Task 1,
  step 9).
- **Slug collision with an existing draft/published file**: ask before
  overwriting (Task 1, step 3/9).
- **Editing an already-published/previously-dated article**: refresh `lastmod`,
  leave `date` unchanged (Task 1, step 5).
- **User asks the writer to edit a source project or to commit/push**: refuse
  per anti-hijack rules (Task 2, step 3).

## Verification

1. Run `bash tests/blog_writer_check.sh` → all checks pass.
2. Run `bash tests/conventions_check.sh`, `bash tests/extract_topics_check.sh`,
   and `bash tests/scaffold_check.sh` → prior steps still pass (no regression
   from editing the agent file).
3. **Runtime (manual, after restarting opencode)**: with a real (non-
   placeholder) `CONVENTIONS.md`, invoke `blog-writer` with "write about
   topic N"; confirm it reads the topic + conventions, drafts
   `drafts/<slug>.mdx` with `draft: true`, iterates on the English body via a
   short `question` (no embedded body), then produces the Italian `<Lang>`
   block in the same file.
4. **Runtime**: approve the draft → confirm `draft:` flips to `false`; issue
   "publish <slug>" → confirm the file moves to `published/<slug>.mdx`.
5. **Runtime**: with an all-placeholder `CONVENTIONS.md`, confirm the agent
   asks and refuses to draft; confirm asking it to edit a source project or to
   commit/push is refused.
