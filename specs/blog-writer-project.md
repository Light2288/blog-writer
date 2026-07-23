# Blog-Writer opencode Project

| Field         | Value                                                  |
|---------------|--------------------------------------------------------|
| **Title**     | Blog-Writer opencode Project                           |
| **Type**      | feature                                                |
| **Scope**     | opencode project scaffold + two primary agents & skills |
| **Created**   | 2026-07-22 00:00:00                                    |
| **Updated**   | 2026-07-22 00:00:00                                    |
| **Status**    | DEFINED                                                |

## Problem Statement

I occasionally want to write blog articles drawing on what I've been working
on across multiple projects, but the raw material — git history and opencode
session transcripts — is scattered and easy to forget. I want a dedicated,
self-contained opencode project that observes my tracked projects, surfaces
candidate topics on demand, and helps me draft articles in my own voice. The
project houses the tools, conventions, and drafts; it is separate from the
projects it writes *about* and only ever observes them.

Articles are published to a Tailwind/Next.js MDX blog that is bilingual
(English + Italian), so drafts must match that blog's exact MDX file format.

## Desired Outcome

A new opencode project containing two manually-invoked primary agents and
their supporting skills:

1. **topic-extractor** — analyses recent activity across a set of tracked
   projects (git commit history + opencode session transcripts) and produces
   a candidate-topics file.
2. **blog-writer** — takes one of those candidate topics (or a free-text
   topic) plus the user's writing conventions, and drafts a bilingual MDX
   blog article, iterating with the user, and moving it to `published/` on
   explicit command.

There is no automation and no scheduled runs. Both agents are invoked
manually from inside this project when the user wants.

### Delivery

- Two opencode agents living inside this project's `.opencode/agents/`.
- Not standalone scripts. Not global agents.

### topic-extractor behaviour

- **Sources**: BOTH git commit history AND opencode session transcripts.
  Session transcripts are queried from `~/.local/share/opencode/opencode.db`
  via `sqlite3` in read-only mode. Commits and sessions are correlated by
  timestamp so they relate to one another.
- **Tracked projects (auto-discover + optional allowlist)**:
  - If `tracked-projects.txt` exists at the project root and is non-empty, it
    is treated as an **allowlist**: one directory path per line, and only
    those projects are considered.
  - If the file is missing or empty, the extractor **auto-discovers** the
    candidate project set from the opencode DB
    (`SELECT DISTINCT directory FROM session` within the time window), then
    presents the discovered list to the user via `question` for confirmation
    before extracting. The extractor does NOT refuse to run when the file is
    absent.
- **Time window**: default "last 7 days"; overridable per run.
- **Output**: a topics-candidates file at `inputs/topics-YYYY-Www.md`
  (ISO week numbering, e.g. `inputs/topics-2026-W28.md`).
- **DRAFT-first**: writes the topics file with `Status: DRAFT` first, then
  flips it to `FINAL` only on the user's explicit approval via `question`.

### blog-writer behaviour

- Reads the user's writing conventions from `CONVENTIONS.md` at the project
  root every conversation. If `CONVENTIONS.md` is missing, it asks the user
  via `question` and refuses to draft without at least a placeholder file.
- Takes a topic from the current `inputs/topics-*.md` file (e.g. "write about
  topic 2") or a free-text topic.
- May read anywhere to fact-check against source projects.
- **Bilingual workflow (EN first, then IT)**: drafts the full English body
  first and iterates with the user to their satisfaction, then translates to
  Italian and assembles a single `.mdx` file containing both `<Lang>` blocks.
- **Output**: an article draft at `drafts/<slug>.mdx` in the blog's exact MDX
  format (see below).
- **DRAFT-first**: the on-disk DRAFT marker is the MDX frontmatter field
  `draft: true`. The DRAFT-first *workflow* still applies: write the file with
  `draft: true`, ask a short `question` summarising it, and flip to
  `draft: false` only on the user's explicit approval.
- **Publish on command**: on the user's explicit instruction (e.g.
  "publish <slug>"), the blog-writer flips `draft: false` and moves
  `drafts/<slug>.mdx` to `published/<slug>.mdx`. It never auto-publishes.

### DRAFT-first pattern (both agents)

Both the topics file and the article file follow the DRAFT-first pattern used
by the spec-definer/planner/implementer skills: write the file to disk in its
draft state, then ask a short `question` summarising it. On explicit approval,
flip the draft marker to final. Never embed large markdown inside a `question`
tool call — it can cause request termination.

- Topics file draft marker: `Status: DRAFT` → `Status: FINAL`.
- Article draft marker: frontmatter `draft: true` → `draft: false`.

### Files this project should have

- `AGENTS.md` — top-level project context read by opencode.
- `CONVENTIONS.md` — the user's writing style, structure, voice, and taboos,
  including bilingual (EN/IT) and MDX conventions. Delivered as a starter
  template with placeholders, authored interactively (see step 03).
- `tracked-projects.txt` — optional plain list of directories, one per line
  (allowlist). May be absent; the extractor falls back to auto-discovery.
- `.opencode/opencode.json` — permissions overrides for the two agents and
  `external_directory` allowances for the tracked projects.
- `.opencode/agents/topic-extractor.md`
- `.opencode/agents/blog-writer.md`
- `.opencode/skills/extract-topics/SKILL.md`
- `.opencode/skills/write-blog-article/SKILL.md`
- `inputs/.gitkeep`
- `drafts/.gitkeep`
- `published/.gitkeep`
- `README.md` — how to use the project.

### topics-*.md output structure

Rough template (the `extract-topics` skill may refine):

```text
# Topic candidates — Week 2026-W28

| Field       | Value                            |
|-------------|----------------------------------|
| Window      | 2026-07-01 to 2026-07-07         |
| Projects    | app-scrutatore, certflow, blog   |
| Sessions    | 12 (see appendix)                |
| Commits     | 34 (see appendix)                |
| Status      | DRAFT                            |

## Candidate topics

### Topic 1: <catchy working title>
- **Why interesting**: <1-2 sentences>
- **Sources**:
  - Sessions: <session-id-short>, <session-id-short>
  - Commits: <project>@<sha-short>, ...
- **Estimated depth**: short / medium / long
- **Angle**: <how to approach it — retrospective, tutorial, opinion,
  deep-dive, etc.>
- **Flagged**: <only present if sensitive content was detected — describe why>

### Topic 2: ...

## Appendix: raw sources
- <bulleted list of sessions with titles>
- <bulleted list of commits with subjects>
```

### article-<slug>.mdx output structure

Bilingual MDX matching the target blog's format exactly: YAML frontmatter with
per-language `title` and `summary`, `date`, `lastmod`, a `tags` list where each
tag is `{ id, label: { en, it } }`, a `draft` boolean, and an `images` list;
followed by the body split into `<Lang value="en">` and `<Lang value="it">`
blocks.

```text
---
title:
  en: <English title>
  it: <Italian title>

summary:
  en: >
    <English summary, multi-line block scalar>
  it: >
    <Italian summary, multi-line block scalar>

date: <YYYY-MM-DD>
lastmod: <YYYY-MM-DD>

tags:
  - id: <kebab-id>
    label:
      en: <English label>
      it: <Italian label>
  - id: <kebab-id>
    label:
      en: <English label>
      it: <Italian label>

draft: true
images:
  - <path or empty list>
---

<Lang value="en">

<English article body per CONVENTIONS.md>

</Lang>

<Lang value="it">

<Italian article body — translation of the English body>

</Lang>
```

**Allowed MDX components** (restricted to the target blog's vocabulary):
`<Lang value="en|it">`, `<TOCInline toc={props.toc} exclude="..." />`, fenced
code blocks using the `lang:filename` info-string convention (e.g.
```` ```ts:contentlayer.config.ts ````), footnotes (`[^1]` and their
definitions), `<video>` with `<source>`, images via markdown or the `images`
frontmatter, and standard markdown. The writer must NOT invent components
outside this set.

### Permissions

- **topic-extractor**:
  - Read anywhere (needed to `git log` tracked projects and read the opencode
    DB).
  - Write and edit only inside `inputs/**` (within this project).
- **blog-writer**:
  - Read anywhere (may need to fact-check by reading source projects).
  - Write and edit only inside `drafts/**`, `inputs/**`, and `published/**`.
- **Both**:
  - `bash` allowed with `git *` and `sqlite3 * -readonly *` permitted.
  - Destructive commands (`git push`, `git commit --amend`, `rm -rf`) denied.

### Anti-hijack rules (both agents)

Same hardening as the spec-definer/planner:

- `topic-extractor` produces only a topics file; it never writes an article
  itself even if asked.
- `blog-writer` produces only articles in `drafts/` (and moves them to
  `published/` on explicit command); it never edits source projects, and never
  commits or pushes.

### Sensitive information handling

Session transcripts may contain secrets or private data. The `extract-topics`
skill must include a redaction step:

- Automatic filter for obvious patterns: `client_secret`, `bearer`, `api_key`,
  `token`, and long hex/base64 strings that look like secrets.
- Any topic whose sources contained a match is marked with a **Flagged** note
  in the DRAFT topics file; the user decides whether to keep it.
- User approval of the DRAFT topics file before it becomes FINAL.
- The `tracked-projects.txt` allowlist is the primary gate — sensitive
  projects can be excluded by using the allowlist instead of auto-discovery.

## Acceptance Criteria

- [ ] A fresh clone of the project works after the user edits `CONVENTIONS.md`;
      editing `tracked-projects.txt` is optional (auto-discovery otherwise).
- [ ] Running `topic-extractor` with the prompt "extract topics from last
      week" produces `inputs/topics-YYYY-Www.md` with `Status: DRAFT`.
- [ ] When `tracked-projects.txt` is absent, the extractor auto-discovers
      projects from the DB and confirms the list via `question` before writing.
- [ ] The user can approve or request changes via the `question` tool;
      approving flips the topics file `Status` to `FINAL`.
- [ ] Running `blog-writer` with "write about topic 2" reads the correct
      topic from the input file, reads `CONVENTIONS.md`, and drafts
      `drafts/<slug>.mdx` in the bilingual MDX format with `draft: true`.
- [ ] The blog-writer drafts the English body first, iterates, then produces
      the Italian translation in the same `.mdx`.
- [ ] On the user's explicit "publish <slug>" instruction, the blog-writer
      flips `draft: false` and moves the file to `published/<slug>.mdx`.
- [ ] The `topic-extractor` cannot write outside `inputs/**`; the runtime
      rejects such writes.
- [ ] The `blog-writer` cannot write outside `drafts/**`, `inputs/**`, and
      `published/**`; the runtime rejects such writes.
- [ ] Neither agent runs `git push`, `git commit --amend`, or any destructive
      command.
- [ ] The topics file follows the DRAFT-first pattern; large markdown is never
      embedded in a `question` call.
- [ ] The article file follows the DRAFT-first pattern via the frontmatter
      `draft:` field.
- [ ] Sensitive-keyword detection flags matching topics with a "Flagged" note
      in the DRAFT topics file.
- [ ] Generated articles use only the allowed MDX component vocabulary.

## Edge Cases & Error Handling

- **Tracked project has no commits in the window**: skip silently, note it in
  the appendix.
- **opencode DB has no sessions in the window for a project**: same — skip
  silently, note in the appendix.
- **`CONVENTIONS.md` missing**: `blog-writer` asks the user via `question` and
  refuses to draft without at least a placeholder file.
- **`tracked-projects.txt` missing or empty**: `topic-extractor` falls back to
  auto-discovery from the DB and confirms the discovered project list via
  `question` before extracting (it does NOT refuse to run).
- **A tracked project has been deleted from disk**: warn, then skip that
  project.
- **Sensitive keyword detected in draft topics**: mark the topic with a
  "Flagged" note; the user decides whether to keep it.
- **Italian translation requested before the English body is approved**: the
  blog-writer completes and confirms the English body first, then translates.
- **Publish requested for a slug that has no draft**: warn and do nothing.

## Dependencies & Constraints

- Runs as an opencode project; requires opencode with primary-agent and skill
  support.
- Requires `git` and `sqlite3` available on the host.
- Reads the opencode session database at
  `~/.local/share/opencode/opencode.db`. Verified schema: sessions live in the
  `session` table with columns including `directory`, `title`, `slug`,
  `agent`, `model`, `time_created`, `time_updated` (indexed, Unix ms). Message
  and part content (for redaction) live in `message.data` and `part.data`
  (JSON).
- The extractor's SQL queries must use `sqlite3 -readonly` to avoid contending
  with a running opencode session.
- Time-window queries should use the indexed `time_updated` column, not scan
  the full session table.
- `.opencode/opencode.json` must grant `external_directory` allowances for the
  tracked projects so the agents can read them.
- Article output must match the target Tailwind/Next.js MDX blog format
  (bilingual frontmatter + `<Lang>` blocks + restricted component set).

## Out of Scope

- Automated scheduling (no cron, no launchd, no systemd).
- Publishing to a live blog / CMS / GitHub Pages (moving a file to
  `published/` on command is in scope; deploying it is not).
- Languages beyond English and Italian.
- Analytics or engagement tracking.
- A dedicated review agent (the `blog-writer` handles its own iteration).
- Rich media authoring beyond referencing images/`<video>` in the allowed MDX
  vocabulary.
- Series / multi-part articles as a first-class concept.

## Notes

- The DRAFT-first pattern is essential — the topics and article files can be
  many KB of markdown, and embedding them inside a `question` tool call has
  been shown to cause request termination. Always write the file, then ask a
  short question with just a summary.
- The `topics-YYYY-Www.md` naming uses ISO week numbering (e.g.
  `topics-2026-W28.md`).
- This project's directory is not itself a git repo by default; the agents do
  not require it to be one.
- Implementation is decomposed into five spec-driven steps. See
  `specs/blog-writer-project-implementation.md` for the master guide and
  `specs/steps/01..05-*.md` for the per-step specs.
