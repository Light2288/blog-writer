---
name: author-conventions
description: >-
  Use when the user wants to author, fill in, set up, or update their writing
  conventions — e.g. "fill in CONVENTIONS.md", "author my conventions", "set up
  the blog conventions", "interview me for my writing style". Runs an
  interactive interview, asking one focused question at a time, and writes the
  answers into CONVENTIONS.md at the project root (seeding it from
  CONVENTIONS.template.md when it is still all-placeholder).
---

# Author Conventions

Fill in the user's writing conventions through an interactive interview. The
output is `CONVENTIONS.md` at the project root — the file the `blog-writer`
agent reads every run. This skill captures the user's real voice, structure,
bilingual policy, MDX vocabulary, frontmatter rules, tag vocabulary, taboos,
and optional examples, and writes them into stable, labelled sections the
writer can reference by name.

The pristine reference is `CONVENTIONS.template.md`. Never edit the template;
it stays all-placeholder so a fresh clone always has a clean starting point.

## Placeholder convention

Every unfilled field is a single canonical HTML comment: `<!-- TODO: ... -->`.
It renders invisibly (so a half-filled file never leaks placeholder text into a
preview) and is trivial to grep. A section counts as **unfilled** when its only
content is one or more `<!-- TODO: ... -->` markers. The blog-writer treats a
`CONVENTIONS.md` whose sections are all unfilled as "missing conventions" and
refuses to draft — so the interview's job is to replace those markers with real
content.

Keep the eight section headings stable and in this order; the writer references
them by name:

1. `Voice & Tone`
2. `Article Structure`
3. `Bilingual Policy`
4. `MDX Conventions`
5. `Frontmatter Conventions`
6. `Tag Vocabulary`
7. `Taboos`
8. `Examples`

## Workflow

### 1. Seed CONVENTIONS.md

Read `CONVENTIONS.md`. If it does not exist, or every section is unfilled (only
`<!-- TODO: ... -->` markers, e.g. the step-01 stub), seed it from
`CONVENTIONS.template.md` so the eight labelled sections and their
`<!-- TODO: ... -->` prompts are in place. If it already has real content in
some sections, preserve that content and only work on the sections the user
wants to (re)author.

### 2. Interview one section at a time

Walk the eight sections **in order**. For each section, ask **one focused
`question` at a time** — never bundle multiple areas into a single question.
Prefer several small questions over one long one. After each answer, move to
step 3 before asking the next question.

Cover these areas (the `<!-- TODO: ... -->` prompts in each section list the
specifics):

- **Voice & Tone** — first vs third person, use of "I", whether to address the
  reader as "you", formality register, humour, sentence rhythm and vocabulary
  preferences.
- **Article Structure** — the default skeleton (intro → TOC → body →
  conclusion → support/licence footer), when to use a
  `<TOCInline toc={props.toc} exclude="..." />`, typical length bands
  (short/medium/long), heading levels.
- **Bilingual Policy** — English is authored first, then translated to Italian;
  tone parity expectations; how idioms and technical terms are handled; whether
  code comments/strings are translated (default: **no**, leave code as-is).
- **MDX Conventions** — confirm the allowed component vocabulary and any
  per-component preferences: `<Lang value="en|it">`,
  `<TOCInline toc={props.toc} exclude="..." />`, fenced code blocks using the
  `lang:filename` info-string convention, footnotes, `<video>`/`<source>`,
  images; code-fence info-string style; footnote style. The writer must never
  invent components outside this set.
- **Frontmatter Conventions** — how to write `summary` (length, `>` block
  scalar), `date`/`lastmod` rules, `images` defaults, `draft` handling.
- **Tag Vocabulary** — the canonical tag set, each in the
  `{ id, label:{en,it} }` shape, plus guidance for choosing/reusing tags.
- **Taboos** — words, claims, tone, or content to avoid; confidentiality rules
  (never reveal client names, secrets, internal URLs, credentials).
- **Examples** — optionally one or two short exemplar snippets in the user's
  voice for the writer to anchor on.

### 3. Write each answer into the section

After each answer, use `edit` to replace that section's `<!-- TODO: ... -->`
markers in `CONVENTIONS.md` with the user's real content. Edit incrementally,
one section at a time — do not rewrite the whole file at once.

Edge cases:

- **User skips a section**: keep the labelled heading and leave a
  `<!-- TODO: ... -->` placeholder rather than deleting the section, so the
  structure stays stable.
- **No tag vocabulary yet**: seed the starter set from the template (in the
  `{ id, label:{en,it} }` shape) and note that it is extensible.
- **Conflicting guidance across sections**: surface the conflict via a
  `question` and record the resolution in the affected sections.

### 4. Confirm with a short question

When the sections are filled, call `question` with a **short** summary only —
which sections were filled, which were intentionally left as placeholders, and
a pointer to `CONVENTIONS.md`. **Never embed the file body (or any large
markdown) inside a `question` call** — it can terminate the request. The file
on disk is the source of truth during review.

On change requests, `edit` the affected section directly and re-ask.

## Notes

- `CONVENTIONS.md` and `CONVENTIONS.template.md` live at the project root.
  They are authored during project setup, not written by a runtime agent under
  scoped-write permissions.
- Consistency with the parent spec is mandatory: the MDX vocabulary and the
  bilingual frontmatter + tag shape must match the target blog exactly.
