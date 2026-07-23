# Writing Conventions — Starter Template

<!--
  This is the PRISTINE starter template. Do not edit it in place.

  The file the `blog-writer` agent actually reads every run is
  `CONVENTIONS.md` at the project root. On a fresh clone that file starts as
  an all-placeholder stub; you fill it in by running the `author-conventions`
  interview skill (which asks one focused question at a time and writes your
  answers into `CONVENTIONS.md`, seeding it from this template when needed).

  Placeholder convention: every unfilled field is a single canonical HTML
  comment of the form `<!-- TODO: ... -->`. The comment renders invisibly, so
  a partially-filled CONVENTIONS.md never leaks placeholder text into a
  preview, and it is trivial to grep. A section counts as "unfilled" when its
  only content is one or more `<!-- TODO: ... -->` markers; the blog-writer
  treats a CONVENTIONS.md whose sections are all unfilled as "missing
  conventions" and refuses to draft.

  Keep the eight section headings below stable and in this order — the
  blog-writer references them by name.
-->

## Voice & Tone

<!-- TODO: First vs third person. Do you write as "I"? Do you address the
     reader as "you"? -->
<!-- TODO: Formality register (casual, conversational, professional, academic). -->
<!-- TODO: Humour — how much, what kind, any that is off-limits. -->
<!-- TODO: Sentence rhythm and vocabulary preferences; words/phrases you favour. -->

## Article Structure

<!-- TODO: Default article skeleton (e.g. intro -> TOC -> body sections ->
     conclusion -> support/licence footer). -->
<!-- TODO: When to include a <TOCInline toc={props.toc} exclude="..." />. -->
<!-- TODO: Typical length bands — short / medium / long, and roughly what each
     means in words or sections. -->
<!-- TODO: Heading levels and how deep you nest them. -->

## Bilingual Policy

<!-- TODO: English is authored first, then translated to Italian — confirm and
     note any exceptions. -->
<!-- TODO: Tone parity expectations between EN and IT (same register, or does
     IT lean more/less formal?). -->
<!-- TODO: How idioms and technical terms are handled in translation. -->
<!-- TODO: Whether code comments/strings are translated (default: no — leave
     code as-is). -->

## MDX Conventions

<!-- TODO: Confirm the allowed component vocabulary and any per-component
     preferences. The writer must NOT invent components outside this set: -->
<!-- TODO: - <Lang value="en"> / <Lang value="it"> blocks wrapping each
     language's body. -->
<!-- TODO: - <TOCInline toc={props.toc} exclude="..." /> for the table of
     contents. -->
<!-- TODO: - Fenced code blocks using the `lang:filename` info-string
     convention (e.g. ```ts:contentlayer.config.ts). -->
<!-- TODO: - Footnotes ([^1] references and their definitions). -->
<!-- TODO: - <video> with nested <source>. -->
<!-- TODO: - Images via markdown or the frontmatter `images` list. -->
<!-- TODO: Code-fence info-string style preferences (always name the file?). -->
<!-- TODO: Footnote style preferences. -->

## Frontmatter Conventions

<!-- TODO: How to write `summary` (length, and the block-scalar `>` style). -->
<!-- TODO: `date` and `lastmod` rules (when each is set/updated). -->
<!-- TODO: `images` defaults (empty list, or a default hero image?). -->
<!-- TODO: `draft` handling (starts true; flipped to false only on publish). -->

<!--
  Reference frontmatter skeleton (matches the target blog exactly):

  ---
  title:
    en: <English title>
    it: <Italian title>
  summary:
    en: >
      <English summary>
    it: >
      <Italian summary>
  date: <YYYY-MM-DD>
  lastmod: <YYYY-MM-DD>
  tags:
    - id: <kebab-id>
      label:
        en: <English label>
        it: <Italian label>
  draft: true
  images:
    - <path or empty list>
  ---
-->

## Tag Vocabulary

<!-- TODO: Curate your canonical tag set. Each tag uses the
     { id, label:{en,it} } shape shown below. Reuse existing tags before
     inventing new ones; this set is extensible — add tags as your topics
     grow. -->

Starter set (edit freely):

```yaml
tags:
  - id: engineering
    label:
      en: Engineering
      it: Ingegneria
  - id: retrospective
    label:
      en: Retrospective
      it: Retrospettiva
  - id: tutorial
    label:
      en: Tutorial
      it: Tutorial
```

## Taboos

<!-- TODO: Words, phrases, claims, or tone to avoid. -->
<!-- TODO: Formatting you dislike. -->
<!-- TODO: Confidentiality rules — never reveal client names, secrets,
     internal URLs, credentials, or private project details. -->

## Examples

<!-- TODO: Optionally capture one or two short exemplar snippets in your own
     voice for the writer to anchor on. Leave as a placeholder if you prefer
     the writer to rely on the sections above. -->
