---
name: author-conventions
description: Use when the user asks to create or update the project's writing conventions through a focused interview.
---

# Author Conventions

Interview the user and maintain the root `CONVENTIONS.md`. Never edit
`CONVENTIONS.template.md`; it is the pristine starter. Only the matching
bridge operation may persist the assembled conventions.

Delegate only to `conventions-writer`. The main chat owns every user question,
answer interpretation, conflict resolution, overwrite choice, and final review.
Never ask a custom agent to question the user. The custom agent only calls
`write_conventions` with content already assembled in the main chat.

## Placeholder and structure rules

The canonical unfilled marker is `<!-- TODO: ... -->`. A section is unfilled
when its only content is one or more such markers. A file whose eight sections
are all unfilled is placeholder-only and is not usable for article drafting.

Keep these headings in this order:

1. `Voice & Tone`
2. `Article Structure`
3. `Bilingual Policy`
4. `MDX Conventions`
5. `Frontmatter Conventions`
6. `Tag Vocabulary`
7. `Taboos`
8. `Examples`

## Workflow

### 1. Load or seed the document

Read `CONVENTIONS.md` and `CONVENTIONS.template.md`. If the root file is absent
or placeholder-only, use the template as the in-memory starting document. If
some sections contain real guidance, preserve it byte-for-byte unless the user
asks to revise that section. Do not persist a seed merely to ask questions.

Before the first persistence, ask once in the main chat for permission to
create and repeatedly update `CONVENTIONS.md` throughout this interview,
regardless of whether the root file already exists. That one approval covers
later persistence after each reviewed answer. Use `overwrite: false` for the
first write when the file is absent; after it exists, pass `overwrite: true`
only under that approval and while preserving every section outside the
current answer.

### 2. Interview one section at a time

Walk the eight sections in order and ask one focused question at a time. After
each answer, update the in-memory section, persist it through step 3, and only
then ask the next question. Cover:

- **Voice & Tone**: person, address, formality, humor, rhythm, vocabulary.
- **Article Structure**: intro, TOC, body, conclusion/footer, length, headings.
- **Bilingual Policy**: author English first, then translate EN→IT; tone and
  idiom parity; leave code identifiers, code strings, and comments unchanged
  unless the user explicitly says otherwise.
- **MDX Conventions**: `<Lang value="en|it">`,
  `<TOCInline toc={props.toc} exclude="..." />`, `lang:filename` code fences,
  footnotes, `<video>`/`<source>`, images, and standard markdown. No invented
  components.
- **Frontmatter Conventions**: bilingual title/summary, block-scalar summary,
  date/lastmod, images, tags, topic key, and draft rules.
- **Tag Vocabulary**: canonical entries in `{ id, label: { en, it } }` shape
  and guidance for reuse.
- **Taboos**: claims, tone, confidential names/URLs, credentials, and secrets.
- **Examples**: optional short exemplars in the user's voice.

If the user skips a section, retain its heading and TODO marker. If there is no
tag vocabulary, offer the template's starter set and record it only with the
user's acceptance. If answers conflict, surface one concise conflict question
in the main chat and record the resolution in every affected section.

### 3. Persist each reviewed answer

After each answer, assemble the complete updated document while preserving all
unmodified sections, then delegate `write_conventions` with that complete
content and the approved overwrite flag. The user's answer authorizes that
section's content; the create-and-repeated-update approval from step 1 is still
required before any persistence. Never delegate a partial section, invent
answers, or use a general file-writing tool. Return to step 2 after the write
succeeds.

### 4. Keep final review in the main chat

Ask a short final review question listing filled and intentionally unfilled
sections and pointing to `CONVENTIONS.md`. Never embed the file body or large
markdown in the question. Apply requested changes in memory, delegate the next
`write_conventions` with approved overwrite, and re-ask. The custom agent never
conducts the interview or final review.
