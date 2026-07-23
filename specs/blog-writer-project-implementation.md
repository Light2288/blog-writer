# Blog-Writer opencode Project — Implementation Guide

This is the master guide for building the Blog-Writer opencode project in a
spec-driven way. The overall feature is defined in
[`specs/blog-writer-project.md`](./blog-writer-project.md). Implementation is
decomposed into **five ordered steps**, each with its own spec-define document
in [`specs/steps/`](./steps/).

For each step you run the standard loop:

1. **spec-define** — refine `specs/steps/NN-<slug>.md` through dialogue and
   flip its Status to `DEFINED`.
2. **spec-plan** — produce `plans/NN-<slug>.md` from the defined spec.
3. **spec-implement** — write tests/red then code/green from the plan, staging
   changes.

Each step-spec is already drafted with `Status: DRAFT`. Drive it through your
normal spec flow before implementing.

## Prerequisites (verify once)

- `git` and `sqlite3` are on `PATH`.
- The opencode session DB exists at `~/.local/share/opencode/opencode.db`.
  Confirm read-only access:

  ```bash
  sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"
  ```

- opencode supports primary agents and skills (project-scoped under
  `.opencode/`).

## Step order and dependencies

| Step | Spec file | Depends on | Produces |
|------|-----------|------------|----------|
| 01 | `steps/01-project-scaffold-and-permissions.md` | — | Directory layout, `AGENTS.md`, `README.md`, `.gitkeep`s, `.opencode/opencode.json` (permissions + `external_directory`) |
| 02 | `steps/02-topic-extractor-agent-and-skill.md` | 01 | `topic-extractor` agent + `extract-topics` skill |
| 03 | `steps/03-conventions-authoring.md` | 01 | `CONVENTIONS.md` (interactive) + starter template |
| 04 | `steps/04-blog-writer-agent-and-skill.md` | 01, 03 | `blog-writer` agent + `write-blog-article` skill |
| 05 | `steps/05-end-to-end-acceptance.md` | 01–04 | Integration verification of all acceptance criteria |

Recommended execution order: **01 → 02 → 03 → 04 → 05**. Steps 02 and 03 are
independent of each other and can be done in either order once 01 is complete,
but 04 requires 03 (it reads `CONVENTIONS.md`).

## Step summaries

### Step 01 — Project scaffold & permissions

Lay down the project skeleton and the single most safety-critical file,
`.opencode/opencode.json`, which encodes per-agent permissions and
`external_directory` allowances. Everything else builds on this. Get the
permission ordering right here (opencode evaluates the **last** matching rule,
so broad rules first, narrow rules last).

### Step 02 — topic-extractor agent & extract-topics skill

The read-only analyst. Auto-discovers projects from the opencode DB (or uses
the optional `tracked-projects.txt` allowlist), git-logs each project and
queries sessions with `sqlite3 -readonly` over the indexed `time_updated`
column, correlates by timestamp, redacts secrets, and writes the DRAFT topics
file. Anti-hijack: never writes an article.

### Step 03 — CONVENTIONS.md authoring

An interactive interview that captures the user's voice, structure, taboos,
bilingual EN/IT preferences, MDX conventions, and tag vocabulary, then writes
`CONVENTIONS.md`. Also delivers a placeholder starter template so a fresh clone
has a valid file to edit.

### Step 04 — blog-writer agent & write-blog-article skill

The writer. Reads `CONVENTIONS.md` every run (refuses without it), takes a
topic from `inputs/topics-*.md` or free text, drafts the English body first and
iterates, then translates to Italian and assembles a single bilingual `.mdx`
in the target blog format with `draft: true`. Publishes on explicit command by
flipping `draft: false` and moving to `published/`. Anti-hijack: never edits
source projects, never commits/pushes.

### Step 05 — End-to-end acceptance

Exercises every acceptance criterion end to end: fresh-clone flow, extractor
DRAFT→FINAL, blog-writer draft from a topic, bilingual output, publish-on-
command, permission-boundary rejections, and destructive-command denials.

## After implementation

- Quit and restart opencode so the new `.opencode/opencode.json`, agents, and
  skills are loaded (config is not hot-reloaded).
- Invoke `topic-extractor` and `blog-writer` manually from inside the project.

## Cross-cutting invariants (apply to every step)

- **DRAFT-first, never embed large markdown in `question`.** Write the file,
  then ask a short summarising question.
- **Read-only DB access.** All `sqlite3` calls use `-readonly` and filter on
  the indexed `time_updated` column.
- **Scoped writes.** topic-extractor → `inputs/**`; blog-writer → `drafts/**`,
  `inputs/**`, `published/**`. The runtime must reject anything else.
- **No destructive/remote git.** `git push`, `git commit --amend`, `rm -rf`
  are denied for both agents.
- **Bilingual MDX format** is fixed by the target blog; the writer stays within
  the allowed component vocabulary.
