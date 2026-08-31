# Plan: Add Parenthetical Style Convention

| Field           | Value                                                |
|-----------------|------------------------------------------------------|
| **Title**       | Add Parenthetical Style Convention                   |
| **Spec**        | specs/add-parenthetical-style-convention.md          |
| **Type**        | chore                                                |
| **Branch**      | chore/add-parenthetical-style-convention             |
| **Implementer** | spec-implementer-lite                                |
| **Created**     | 2026-08-31 22:56:40                                  |
| **Status**      | IMPLEMENTED                                          |

## Context

The live writing conventions do not yet describe the intended use of parentheses in English and Italian prose. This documentation-only change adds that guidance to the existing voice rules while preserving the current conventions, workflow, templates, tests, and articles.

The architecture map (`docs/architecture/map.md`) is missing, so no map context was used; normal repository exploration established the relevant files and consumers instead. No Accepted or Proposed ADRs were found, and no unresolved architectural decision affects this change.

## Branch Strategy

> **Before implementation, create a new branch from the repo's base
> branch.** The implementer auto-detects the base in this priority
> order: `develop` → `main` → `master` → `origin/HEAD`. The branch
> name is `chore/add-parenthetical-style-convention`.
>
> Reference command (the implementer adapts to the detected base):
>
> ```bash
> git checkout <base> && git pull --ff-only && git checkout -b chore/add-parenthetical-style-convention
> ```
>
> If the repo is not a git workspace, branch creation is skipped and
> noted in the implementation report.

## Commit Strategy

All commits follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

Format: `<type>[(<scope>)]: <imperative description>`

One commit maps to the single task below.

## Recommended Implementer

**Recommendation**: `spec-implementer-lite`

The work is a mechanical, low-risk edit to one Markdown file. The insertion point and existing bullet style are clear, and the task requires no design decision, runtime logic, sensitive domain work, or new validation machinery.

Run with `/implement-lite` for `spec-implementer-lite`.

## Build & Test Commands

| Action | Command |
|--------|---------|
| Test   | `bash tests/run_all.sh` |

The repository has no build step. Its individual convention and writer checks are available as `bash tests/conventions_check.sh` and `bash tests/blog_writer_check.sh`; no existing check validates the live file's parenthetical wording, and the spec excludes adding one.

## Tasks

### Task 1: Add the parenthetical voice rule `[S | risk: none]`

**Goal**: Add one concise convention governing natural parenthetical usage in English and Italian article bodies and rare, purposeful title usage.

**Risk rationale**: No security, data, concurrency, migration, or other material implementation risk applies to a local documentation-only edit. Readability and scope concerns are controlled by explicit wording and diff verification.

**Files**:

| File             | Action | Description |
|------------------|--------|-------------|
| `CONVENTIONS.md` | modify | Add the parenthetical-style guidance under `## Voice & Tone`. |

**Reuse**:

| File | What to reuse |
|------|---------------|
| `CONVENTIONS.md` | Reuse the concise bold-label bullet format and place the rule after the humour guidance and before `**Rhythm**`. Match the existing moderation language and voice. |
| `.opencode/skills/write-blog-article/SKILL.md` | Rely on the existing behavior that reads `CONVENTIONS.md` on every run; do not duplicate the rule in the skill. |
| `.opencode/skills/author-conventions/SKILL.md` | Preserve the established distinction between the live conventions and pristine `CONVENTIONS.template.md`; do not modify the template. |

**Steps**:

1. In `CONVENTIONS.md`, locate `## Voice & Tone` and insert a single concise bullet after the existing humour and self-deprecation guidance and before `**Rhythm**`.
2. State that parentheses should be used naturally and fairly often in both English and Italian article bodies for brief ironic comments, qualifications, and self-deprecating afterthoughts.
3. Qualify the guidance so it is not a mechanical quota: prohibit stacked parenthetical asides, keep the main point outside parentheses, and prefer rewriting or omitting an aside when clarity suffers.
4. State that parentheses may appear in titles only rarely, purposefully, and when they do not make the title cumbersome.
5. Preserve every existing heading and rule; leave `CONVENTIONS.template.md`, agents, skills, tests, drafts, published articles, workflow files, and MDX behavior unchanged.

**Tests**:

- Inspect the diff to confirm that only `CONVENTIONS.md` changed and that all existing content remains intact.
- Review the added bullet against all five acceptance criteria and the four edge cases in `specs/add-parenthetical-style-convention.md`.
- Run `bash tests/run_all.sh` as repository regression validation (no parenthetical-specific automated test is added).

**Acceptance criteria covered**: All five criteria: explicit bilingual guidance; natural and fairly frequent usage with the three named purposes; no stacking or buried main point; article-body priority and rare purposeful title use; consistency with existing tone, structure, and formatting.

**Commit**: `chore(conventions): add parenthetical style guidance`

---

**Task ordering**: There is one independent task.

## Edge Cases & Error Handling

- **An aside would obscure the sentence**: Require the main clause to stand on its own and direct the writer to rewrite or omit the aside (Task 1).
- **Several parenthetical asides would be adjacent or nested**: Explicitly prohibit stacking and favor plain prose or sentence restructuring (Task 1).
- **A title could use parentheses**: Permit them only rarely when they add clear value without making the title cumbersome (Task 1).
- **English and Italian require different placement**: Preserve natural grammar in each language rather than requiring mechanically identical punctuation (Task 1).
- **“Fairly often” could imply a quota**: Frame frequency as natural stylistic guidance, not a per-sentence or per-paragraph requirement (Task 1).

## Verification

1. Run `git diff -- CONVENTIONS.md` and verify the only content change is one convention bullet in `## Voice & Tone` after the humour guidance and before `**Rhythm**`.
2. Confirm the bullet explicitly covers both languages, article bodies, all three intended parenthetical uses, clarity, anti-stacking, and rare purposeful title usage.
3. Run `git status --short` and confirm no implementation files other than `CONVENTIONS.md` were changed (spec and plan status files are workflow artifacts).
4. Run `bash tests/run_all.sh` and confirm the existing repository checks pass.
5. Confirm no automated parenthetical lint, article rewrite, template update, agent/skill duplication, workflow change, or MDX change was introduced.
