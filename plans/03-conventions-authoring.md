# Plan: CONVENTIONS.md Authoring

| Field        | Value                                       |
|--------------|---------------------------------------------|
| **Title**    | CONVENTIONS.md Authoring                    |
| **Spec**     | specs/steps/03-conventions-authoring.md     |
| **Type**     | feature                                      |
| **Branch**   | feat/03-conventions-authoring               |
| **Created**  | 2026-07-23 09:20:00                         |
| **Status**   | IMPLEMENTED                                  |

## Context

Step 01 stubbed an all-placeholder `CONVENTIONS.md` so the blog-writer's
"missing conventions" guard has a target on a fresh clone. This step (3 of 5)
delivers a distinct, pristine `CONVENTIONS.template.md` reference and an
interactive `author-conventions` skill that interviews the user (one focused
`question` at a time) to fill `CONVENTIONS.md` in place with their real voice,
structure, bilingual EN→IT policy, restricted MDX vocabulary, frontmatter
rules, tag vocabulary (`{ id, label:{en,it} }`), taboos, and examples. The
canonical unfilled-placeholder marker is the HTML comment `<!-- TODO: ... -->`,
which step 04 uses to detect a still-empty conventions file.

## Branch Strategy

> **Before implementation, create a new branch from the repo's base
> branch.** The implementer auto-detects the base in this priority
> order: `develop` → `main` → `master` → `origin/HEAD`. This repo's
> current branch is `develop`, so that is the expected base. The branch
> name is `feat/03-conventions-authoring`.
>
> Reference command (the implementer adapts to the detected base):
>
> ```bash
> git checkout develop && git pull --ff-only && git checkout -b feat/03-conventions-authoring
> ```

Branch type mapping (this is a `feature`): `feat/<slug>`.

## Commit Strategy

All commits follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

Format: `<type>[(<scope>)]: <imperative description>`

One commit per task. Each task below maps to exactly one commit.

## Build & Test Commands

This project has no package manifest or build step. Tests are shell scripts
run directly with `bash`, following the step-01/02 pattern.

| Action | Command |
|--------|---------|
| Test (this step) | `bash tests/conventions_check.sh` |
| Test (step 02, regression) | `bash tests/extract_topics_check.sh` |
| Test (step 01, regression) | `bash tests/scaffold_check.sh` |

## Key Findings From Exploration

Recorded here so the implementer does not re-discover them:

- **Existing stub.** `CONVENTIONS.md` (from step 01) marks itself as a
  placeholder in prose ("PLACEHOLDER (stub)") and uses `_Placeholder — ..._`
  italic markers, **not** the `<!-- TODO: ... -->` comment this spec pins. It
  also has only 6 sections. This step must (a) switch to the canonical
  `<!-- TODO: ... -->` marker and (b) expand to the eight labelled sections the
  spec requires: `Voice & Tone`, `Article Structure`, `Bilingual Policy`,
  `MDX Conventions`, `Frontmatter Conventions`, `Tag Vocabulary`, `Taboos`,
  `Examples`.
- **Skill packaging pattern.** Skills live at `.opencode/skills/<name>/SKILL.md`
  with YAML frontmatter (`name`, `description` phrased to trigger on user
  intent), followed by a numbered `## Workflow`. See
  `.opencode/skills/extract-topics/SKILL.md` as the format reference.
- **Test harness idiom.** `tests/scaffold_check.sh` / `extract_topics_check.sh`
  use `set -u`, `SCRIPT_DIR`/`ROOT` resolution, `pass`/`fail`, `assert_file`,
  `assert_nonempty`, `assert_contains` (grep `-qF`), `assert_contains_ci`,
  `assert_absent`, and a `FAIL` accumulator with a 0/non-zero exit. Reuse this
  verbatim.
- **MDX + frontmatter source of truth.** The parent spec
  (`specs/blog-writer-project.md`) fixes the allowed component vocabulary
  (`<Lang value="en|it">`, `<TOCInline toc={props.toc} exclude="..." />`,
  `lang:filename` code fences, footnotes, `<video>`/`<source>`, images) and the
  bilingual frontmatter shape (`title`/`summary` per-language, `date`,
  `lastmod`, `tags` as `{ id, label:{en,it} }`, `draft`, `images`). Template and
  interview must stay consistent with it and invent nothing outside it.
- **Permissions already cover this step.** `blog-writer` may edit `drafts/**`,
  `inputs/**`, `published/**`; `topic-extractor` only `inputs/**`. **Neither
  agent can write `CONVENTIONS.md` / `CONVENTIONS.template.md` at the project
  root.** These files are authored by the human/implementer during setup, not
  by a runtime agent. No `opencode.json` change is needed in this step, and the
  plan must not assume a runtime agent writes them.

## Tasks

### Task 1: Author the `CONVENTIONS.template.md` starter template `[M]`

**Goal**: Create the distinct, pristine reference template with all eight
labelled sections, every field an unfilled `<!-- TODO: ... -->` placeholder.

**Files**:

| File                       | Action | Description                                            |
|----------------------------|--------|--------------------------------------------------------|
| `CONVENTIONS.template.md`  | create | Eight-section starter, all fields `<!-- TODO: ... -->` |

**Reuse**:

| File                             | What to reuse                                            |
|----------------------------------|----------------------------------------------------------|
| `specs/blog-writer-project.md`   | Allowed MDX vocabulary; bilingual frontmatter + tag shape |
| `CONVENTIONS.md` (step-01 stub)  | Section-heading intent (superset of its 6 sections)      |

**Steps**:

1. Write a short header noting this is the pristine template; `CONVENTIONS.md`
   is the file the blog-writer reads, and it is filled via the
   `author-conventions` interview.
2. Add the eight stable, labelled sections in this exact order:
   `Voice & Tone`, `Article Structure`, `Bilingual Policy`, `MDX Conventions`,
   `Frontmatter Conventions`, `Tag Vocabulary`, `Taboos`, `Examples`.
3. In each section, put one or more `<!-- TODO: ... -->` markers describing what
   belongs there (drawn from the spec's Interview coverage list). Use ONLY the
   `<!-- TODO: ... -->` comment marker — no `_Placeholder_` italics, no prose
   that a section is "filled".
4. In `MDX Conventions`, enumerate the allowed component vocabulary as guidance
   (matching the parent spec) so the writer never invents components.
5. In `Frontmatter Conventions`, show the bilingual frontmatter skeleton
   (per-language `title`/`summary`, `date`, `lastmod`, `tags`, `draft`,
   `images`) as guidance.
6. In `Tag Vocabulary`, seed a small starter set in the
   `{ id, label:{en,it} }` shape and mark it extensible (per edge case).

**Tests**: Covered by Task 3 (asserts the template exists, has all eight
sections, uses `<!-- TODO:` markers, names the allowed MDX components, and shows
the `{ id, label:{en,it} }` tag shape).

**Acceptance criteria covered**: starter template exists with all sections and
`<!-- TODO: ... -->` placeholders, valid on a fresh clone; documents MDX
vocabulary; tag vocabulary in the correct shape.

**Commit**: `feat(conventions): add CONVENTIONS.template.md starter template`

---

### Task 2: Author the `author-conventions` interview skill `[M]`

**Goal**: Encode the repeatable interactive interview that fills
`CONVENTIONS.md` section by section, one focused `question` at a time.

**Files**:

| File                                            | Action | Description                          |
|-------------------------------------------------|--------|--------------------------------------|
| `.opencode/skills/author-conventions/SKILL.md`  | create | Interview workflow across all areas  |

**Reuse**:

| File                                          | What to reuse                                    |
|-----------------------------------------------|--------------------------------------------------|
| `.opencode/skills/extract-topics/SKILL.md`    | SKILL.md frontmatter + numbered `## Workflow` style |
| `CONVENTIONS.template.md` (Task 1)            | Section order and the fields each question fills |
| `specs/blog-writer-project.md`                | MDX vocabulary + frontmatter/tag shape to encode |

**Steps**:

1. Write YAML frontmatter (`name: author-conventions`, `description` phrased to
   trigger on "author/fill/write my conventions", "set up CONVENTIONS.md").
2. Document the interview workflow: seed `CONVENTIONS.md` from
   `CONVENTIONS.template.md` if it is still all-placeholder, then walk the eight
   sections **in order**, asking **one focused `question` at a time** across all
   coverage areas from the spec (voice & tone; article structure incl.
   `<TOCInline>` and length bands; bilingual EN→IT policy incl. translation of
   code comments/strings default = no; MDX conventions; frontmatter conventions;
   tag vocabulary in `{ id, label:{en,it} }`; taboos + confidentiality; optional
   examples).
3. After each answer, `edit` the corresponding section of `CONVENTIONS.md`
   directly, replacing that section's `<!-- TODO: ... -->` markers with real
   content. Keep the labelled section even if the user skips it (leave a
   `<!-- TODO: ... -->` placeholder) so structure stays stable.
4. Encode the edge cases: user skips a section → keep heading + placeholder;
   no tag vocabulary yet → seed starter set, mark extensible; conflicting
   guidance across sections → surface via `question` and record the resolution.
5. State the DRAFT-first-style discipline: never embed large markdown in a
   `question`; the file on disk is the source of truth; confirm with a short
   summarising `question` at the end.
6. Note the canonical marker rule: a section counts as "unfilled" when it
   contains only `<!-- TODO: ... -->` markers, which is how step 04 detects a
   missing-conventions file.

**Tests**: Covered by Task 3 (asserts SKILL.md exists, is non-empty, names the
skill, references one-question-at-a-time interviewing, all eight section names,
EN→IT policy, the `<!-- TODO:` marker convention, and the tag shape).

**Acceptance criteria covered**: interactive interview via `question` one at a
time across all coverage areas; documents EN→IT policy and MDX vocabulary; tag
vocabulary shape; skip/seed/conflict edge cases.

**Commit**: `feat(conventions): add author-conventions interview skill`

---

### Task 3: Add the conventions verification harness `[M]`

**Goal**: A `bash` test asserting every statically-checkable acceptance
criterion for this step, mirroring `tests/extract_topics_check.sh`.

**Files**:

| File                            | Action | Description                                        |
|---------------------------------|--------|----------------------------------------------------|
| `tests/conventions_check.sh`    | create | Static assertions for the template and the skill   |

**Reuse**:

| File                                 | What to reuse                                             |
|--------------------------------------|-----------------------------------------------------------|
| `tests/extract_topics_check.sh`      | `set -u`, root resolution, `pass`/`fail`, `assert_*` helpers |

**Steps**:

1. Copy the harness scaffolding (root resolution, helper functions) from
   `extract_topics_check.sh`.
2. Assert `CONVENTIONS.template.md` exists, is non-empty, contains each of the
   eight section headings, uses the `<!-- TODO:` marker, names representative
   allowed MDX components (`<Lang`, `<TOCInline`, `lang:filename`), and shows the
   `label:` / `{ id, label:{en,it} }` tag shape (`id:` + `en:` + `it:`).
3. Assert `.opencode/skills/author-conventions/SKILL.md` exists, is non-empty,
   names the skill, mentions interviewing "one" focused question at a time,
   references all eight section names, the EN→IT bilingual policy, the
   `<!-- TODO:` marker convention, and the tag shape.
4. Guard the marker discipline: assert the template does NOT use the old
   `_Placeholder` italic marker (regression guard toward the canonical marker).
5. Exit non-zero on any failure (0/non-zero convention).

**Tests**: This task *is* the test; run `bash tests/conventions_check.sh`.

**Acceptance criteria covered**: automated coverage of all
statically-verifiable criteria; the interactive fill and step-04 detection are
runtime/cross-step (see Verification).

**Commit**: `test(conventions): add verification harness for step 03`

---

**Task ordering**: Task 2 references Task 1's template (section order, fields),
so do Task 1 first. Task 3 asserts the output of Tasks 1–2, so it comes last.
Recommended order: 1 → 2 → 3.

## Edge Cases & Error Handling

- **User skips a section**: keep the labelled heading with a `<!-- TODO: ... -->`
  placeholder rather than deleting it (Task 2, step 3–4).
- **No tag vocabulary yet**: seed a small starter set in the
  `{ id, label:{en,it} }` shape and mark it extensible (Task 1 step 6, Task 2
  step 4).
- **Conflicting guidance across sections**: surface via `question` and record
  the resolution (Task 2, step 4).
- **`CONVENTIONS.md` already partially filled**: the interview only replaces the
  `<!-- TODO: ... -->` markers, preserving existing real content (Task 2,
  step 2–3).
- **Marker consistency**: only `<!-- TODO: ... -->` counts as unfilled; the
  step-01 `_Placeholder_` style must not leak into the template (Task 3, step 4).

## Verification

1. Run `bash tests/conventions_check.sh` → all checks pass.
2. Run `bash tests/extract_topics_check.sh` and `bash tests/scaffold_check.sh`
   → no regression.
3. **Runtime (manual, after restarting opencode)**: invoke the
   `author-conventions` interview; confirm it asks one focused `question` at a
   time across all eight areas and fills `CONVENTIONS.md` in place, keeping any
   skipped section as a `<!-- TODO: ... -->` placeholder.
4. **Cross-step (step 04)**: confirm the blog-writer can treat a `CONVENTIONS.md`
   whose sections contain only `<!-- TODO: ... -->` markers as "missing
   conventions".
