---
name: write-blog-article
description: >-
  Use when the blog-writer agent is asked to draft, write, or publish a blog
  article (e.g. "write about topic 2", "draft an article on X", "publish
  <slug>"). Reads CONVENTIONS.md, resolves a topic from inputs/topics-*.md or
  free text, drafts the English body first and iterates, translates to Italian,
  and assembles a single bilingual drafts/<slug>.mdx with draft: true. Flips
  draft: false and moves the file to published/ on explicit command.
---

# Write Blog Article

Turn a chosen topic into a publish-ready **bilingual** (English + Italian) MDX
article in the user's voice, matching the target Tailwind/Next.js blog's exact
file format. The output is a single file at `drafts/<slug>.mdx` that carries the
on-disk DRAFT marker `draft: true` in its frontmatter; it is flipped to
`draft: false` and moved to `published/<slug>.mdx` only on the user's explicit
command.

This skill writes **only** inside `drafts/**`, `inputs/**`, and `published/**`.
It **never edits source projects** and **never commits or pushes** — those are
hard anti-hijack rules enforced by the agent and the permission boundary in
`.opencode/opencode.json`.

## Workflow

Follow these nine steps in order.

### 1. Load conventions

Read `CONVENTIONS.md` at the project root **every run**. It defines the user's
voice, article structure, bilingual (EN→IT) policy, allowed MDX vocabulary,
frontmatter rules, and the controlled tag vocabulary.

Treat the conventions as **missing** when either:

- the file is absent; or
- it is still an all-placeholder template — every section carries only a
  placeholder marker (the canonical `<!-- TODO:` marker from the
  `author-conventions` skill, or the legacy `_Placeholder_` style) with no real
  content.

If the conventions are missing, ask the user via `question` to author them
(point them at the `author-conventions` skill) and **refuse to draft** until at
least a real, non-placeholder `CONVENTIONS.md` exists. Do not invent a voice or
tag vocabulary of your own.

### 2. Resolve the topic

- **"write about topic N"** → read the current / most-recent
  `inputs/topics-*.md` file, select topic N, and carry over its working title,
  angle, estimated depth, and sources. If the file is absent or N is out of
  range, ask the user to clarify or to supply a free-text topic.
- **Free-text topic** → use the user's description as-is.

You may read anywhere (including the source projects and the opencode session
DB via `sqlite3 -readonly`) to fact-check, but you never modify them.

### 3. Derive a slug and target path

Derive a kebab-case `<slug>` from the working title and set the target path
`drafts/<slug>.mdx`. If a draft or published file already exists for that slug,
**ask before overwriting** — never clobber silently.

When the topic came from an `inputs/topics-*.md` file, carry over its
**`topic_key`** (the topics file records one per topic). Otherwise derive the
`topic_key` from the working title with the **same** kebab-case rule as the slug
(lowercase, spaces → `-`, strip punctuation, collapse repeats), so a free-text
topic still gets a stable key. This key is what the `extract-topics` skill uses
to avoid resurfacing already-published topics.

### 4. Draft the English body first

Write the article body in English following `CONVENTIONS.md` (structure, voice,
taboos), using **only** the allowed MDX component vocabulary (see
[Output format](#output-format)). Assemble the frontmatter with:

- `draft: true` — the on-disk DRAFT marker (there is no separate Status table).
- `topic_key` — the stable kebab-case key from step 3, so published articles are
  traceable back to their topic (used by `extract-topics` for exclusion).
- per-language `title` and `summary` — English filled in; Italian left as a
  short placeholder for now.
- `date` and `lastmod` — today's date.
- `tags` — each `{ id, label: { en, it } }`, with `id` and label values **drawn
  from the Tag Vocabulary in `CONVENTIONS.md`**, not invented ad hoc.
- `images` — a list (may be empty).

### 5. Iterate on the English body

Write the file to disk, then call `question` with a **short** summary only:
a one-line description, the English **word count**, and the file path. **Never
embed the article body (or any large markdown) inside a `question`** — it can
terminate the request. Apply requested changes by editing the file directly.
Repeat until the user approves the English body.

If the user asks for the Italian translation before the English body is
approved, finish and confirm the English body first, then translate.

### 6. Translate to Italian

Produce the Italian `title`/`summary` and a full `<Lang value="it">` body that
faithfully translates the approved English, honouring the bilingual policy in
`CONVENTIONS.md` (e.g. do not translate code identifiers, code strings, or
terms the conventions say to leave in English). Assemble the single `.mdx` so
it contains both the `<Lang value="en">` and `<Lang value="it">` blocks.

### 7. Confirm the assembled bilingual draft

Call `question` again with a short summary (again, never the body). Iterate as
needed by editing the file directly. The file stays `draft: true` throughout.

### 8. Finalise on approval

On the user's explicit approval, use `edit` to flip the frontmatter
`draft: true` → `draft: false`. The file remains in `drafts/` until an explicit
publish command.

### 9. Publish on command

On an explicit instruction like **"publish <slug>"**:

- ensure the frontmatter is `draft: false` (flip it if needed); then
- move `drafts/<slug>.mdx` → `published/<slug>.mdx` using only the permitted
  file tools or the permitted `mv drafts/* published/*` command — **never a
  destructive command**; then
- **record the topic in the ledger** so `extract-topics` stops resurfacing it.
  Append one line to `inputs/published-topics.md` (create the file with a
  heading if it does not exist), in the form:

  ```text
  - <topic_key> | <slug> | published 2026-07-26
  ```

  Use the article's `topic_key` from its frontmatter and today's date. If a line
  for that `topic_key` already exists, do not duplicate it. This ledger lives in
  `inputs/**`, which the blog-writer is permitted to write.

Never auto-publish. If no draft exists for the requested slug, warn the user
and do nothing.

## Output format

Bilingual MDX matching the target blog's format exactly: YAML frontmatter with
per-language `title` and `summary`, `date`, `lastmod`, a `tags` list where each
tag is `{ id, label: { en, it } }`, a `draft` boolean, a `topic_key` string, and
an `images` list; followed by the body split into `<Lang value="en">` and
`<Lang value="it">` blocks.

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

topic_key: <kebab-case-key matching the topic / article slug>

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
frontmatter, and standard markdown. **Never invent components outside this
set.**

## DRAFT-first discipline

- The article draft marker is the frontmatter field `draft: true` → `draft:
  false`. Write the file to disk in its draft state, then ask a short
  summarising `question`; flip to `draft: false` only on explicit approval.
- **Never embed** the article body — or any large markdown — inside a
  `question` tool call. The file on disk is the source of truth during review;
  the `question` carries only a summary, word count, and the file path.
- Word count in any summary is computed from the English body unless the user
  asks otherwise.

## Edge cases

- **`CONVENTIONS.md` missing or all-placeholder** — ask via `question`, refuse
  to draft (step 1).
- **Referenced topic number out of range / no topics file** — ask the user to
  clarify or supply a free-text topic (step 2).
- **Slug collision with an existing draft/published file** — ask before
  overwriting (step 3).
- **Italian requested before the English body is approved** — finish and
  confirm the English body first, then translate (steps 5–6).
- **Editing an already-published or previously-dated article** — refresh
  `lastmod` to the edit date and leave the original `date` unchanged.
- **Publish requested for a slug with no draft** — warn and do nothing
  (step 9).
- **User asks the writer to edit a source project or to commit/push** — refuse
  per the anti-hijack rules.
