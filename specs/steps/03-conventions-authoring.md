# Step 03 — CONVENTIONS.md Authoring

| Field         | Value                                                  |
|---------------|--------------------------------------------------------|
| **Title**     | CONVENTIONS.md Authoring                               |
| **Type**      | feature                                                |
| **Scope**     | `CONVENTIONS.md` + `CONVENTIONS.template.md`           |
| **Created**   | 2026-07-22 00:00:00                                    |
| **Status**    | IMPLEMENTED                                            |
| **Parent**    | specs/blog-writer-project.md                           |
| **Step**      | 3 of 5                                                 |

## Problem Statement

The blog-writer can only match my voice if my conventions are written down.
I don't have them articulated yet and want help producing a comprehensive
`CONVENTIONS.md`. A fresh clone also needs a valid placeholder so the
blog-writer's "missing conventions" guard behaves predictably.

## Desired Outcome

Two artefacts:

1. A **starter template** at `CONVENTIONS.template.md` (a distinct, pristine
   reference file) with all sections present and every field an unfilled
   placeholder — enough structure that a fresh clone has a valid file to copy
   from, and enough that the blog-writer can detect "unfilled placeholder" vs
   "real content". This template is delivered by this step and is not modified
   by the interview.
2. A completed `CONVENTIONS.md` at the project root, produced through an
   **interactive interview** that captures my actual preferences. Step 01
   (scaffold) stubs an all-placeholder `CONVENTIONS.md` so the blog-writer's
   "missing conventions" guard has a target on a fresh clone; this step fills
   it in place via the interview (seeding it from `CONVENTIONS.template.md`
   when needed).

### Interview coverage

The authoring process (a guided dialogue, using the `question` tool one focused
question at a time) should elicit and record:

- **Voice & tone** — first vs third person, formality, humour, use of "I",
  reader address ("you").
- **Structure** — default article skeleton (intro, TOC, body sections,
  conclusion, support/licence footer as in the sample), typical length bands
  (short/medium/long), when to use a `<TOCInline>`.
- **Bilingual policy (EN/IT)** — English is authored first then translated;
  tone parity expectations; how idioms/technical terms are handled; whether
  code comments/strings are translated (default: no).
- **MDX conventions** — allowed component vocabulary (`<Lang>`, `<TOCInline>`,
  code fences with `lang:filename`, footnotes, `<video>`, images); code-fence
  info-string style; footnote style; heading levels.
- **Frontmatter conventions** — how to write `summary` (length, block scalar),
  `date`/`lastmod` rules, `images` defaults, `draft` handling.
- **Tag vocabulary** — the canonical `tags` set (each `{ id, label:{en,it} }`),
  and guidance for choosing/reusing tags.
- **Taboos** — words, claims, tone, or content to avoid; confidentiality rules
  (never reveal client names, secrets, internal URLs, etc.).
- **Examples** — optionally capture one or two exemplar snippets in the user's
  voice for the writer to anchor on.

### CONVENTIONS.md structure

Organise the file into stable, labelled sections matching the interview
coverage above so the blog-writer can reference them deterministically:
`Voice & Tone`, `Article Structure`, `Bilingual Policy`, `MDX Conventions`,
`Frontmatter Conventions`, `Tag Vocabulary`, `Taboos`, `Examples`.

Placeholders use a single canonical marker — the HTML comment
`<!-- TODO: ... -->` — so the blog-writer can distinguish an unfilled template
from real conventions. The comment form is chosen deliberately: it renders
invisibly, so a partially-filled `CONVENTIONS.md` never leaks placeholder text
into a preview, and it is trivial to grep. A section is considered "unfilled"
when its only content is one or more `<!-- TODO: ... -->` markers.

## Acceptance Criteria

- [ ] A starter `CONVENTIONS.template.md` exists as a distinct, pristine
      reference with all sections present and every field an unfilled
      `<!-- TODO: ... -->` placeholder; valid on a fresh clone.
- [ ] The authoring flow interviews the user via `question` (one focused
      question at a time) across all coverage areas.
- [ ] The resulting `CONVENTIONS.md` contains real content in each section
      (or explicit, intentional placeholders the user chose to keep).
- [ ] The file documents the bilingual EN→IT policy and the allowed MDX
      component vocabulary consistent with the parent spec.
- [ ] The tag vocabulary section lists tags in the `{ id, label:{en,it} }`
      shape used by the article frontmatter.
- [ ] The blog-writer (step 04) can detect a `CONVENTIONS.md` whose sections
      contain only `<!-- TODO: ... -->` markers and treat it as "missing
      conventions".

## Edge Cases & Error Handling

- **User skips a section**: keep the labelled section with a placeholder rather
  than deleting it, so structure stays stable.
- **User has no tag vocabulary yet**: seed with a small starter set and mark it
  extensible.
- **Conflicting guidance across sections**: surface the conflict via
  `question` and record the resolution.

## Dependencies & Constraints

- Requires Step 01 (project scaffold), which stubs an all-placeholder
  `CONVENTIONS.md` at the project root. This step fills that file in place and
  additionally delivers the distinct `CONVENTIONS.template.md` reference.
- `CONVENTIONS.md` and `CONVENTIONS.template.md` both live at the project root
  (`CONVENTIONS.md` is read by blog-writer every run).
- The canonical placeholder marker is the HTML comment `<!-- TODO: ... -->`;
  step 04's "missing conventions" detection depends on it.

## Out of Scope

- The blog-writer's use of the conventions (step 04).
- Enforcing the conventions programmatically (they are guidance for the
  writer, not a linter).

## Notes

- Mirror the sample article's overall shape (intro → TOC → sections →
  conclusion → support/licence) as the default structure unless the user
  prefers otherwise.
- Keep section headings stable; the writer references them by name.
