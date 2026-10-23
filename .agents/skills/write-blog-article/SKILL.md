---
name: write-blog-article
description: Use when the user asks to draft, revise, finalize, or publish a bilingual blog article.
---

# Write Blog Article

Coordinate a bilingual English/Italian MDX article in the user's voice. The
main chat authors and reviews all prose. The only output is one
`<workflow-root>/drafts/<slug>.mdx` with `draft: true`, finalized and published
only through explicit approval gates.

The main chat owns every user question, topic/slug choice, English review,
bilingual review, overwrite choice, finalization approval, and publication
command. All workflow operations run directly in this chat.

## Execution modes

Resolve the complete canonical bridge catalog before any workflow operation.
Choose command-scoped mode only when explicitly selected by the launcher;
otherwise choose desktop mode.

### Desktop mode

Use this mode in an ordinary project chat. The canonical `blog_writer_bridge`
must expose exactly these nine operations:

`discover_projects`, `collect_activity`, `write_topic_draft`, `finalize_topics`,
`write_conventions`, `read_source_file`, `write_article_draft`,
`finalize_article`, `publish_article`.

Known operations for other workflows are valid members of this desktop catalog.
Call only this skill's matching operations, directly from the main chat.
Unrelated MCP servers are outside this catalog check.

### Command-scoped mode

Require the exact four-tool writer catalog: `read_source_file`,
`write_article_draft`, `finalize_article`, and `publish_article`. Reject every
other bridge operation, including the wider desktop catalog, before any call.
Call the matching operations directly from the main chat.

Missing, partial, or unexpected bridge catalogs stop the workflow before any
bridge call. Report missing or unexpected operations and applicable setup:
Node.js 20+, Git, `npm install --prefix codex-bridge`, project trust, and a Codex
restart so project MCP configuration is loaded. Do not silently switch modes.
Never use shell or general filesystem tools to replace a bridge mutation,
history operation, or bounded source fact-check. There is no custom-agent
fallback. Tool availability never grants overwrite, finalization, or publication
approval.

## Workflow data root

Resolve one absolute workflow data root before reading any Blog-Writer-owned
artifact. In command-scoped mode, use the trusted workflow root supplied by
the launcher. Otherwise run
`git rev-parse --path-format=absolute --git-common-dir`, require the returned
directory name to be `.git`, and use its parent directory. In a linked
worktree this is the primary checkout, not the current code worktree.

Root every reference to `CONVENTIONS.md`, `inputs/`, `drafts/`, and
`published/` at this workflow root. Use absolute paths for shell reads and
review links. The bridge independently applies the same root to every
mutation. Never substitute the current working directory when it differs from
the workflow root.

## Workflow

Follow these nine steps in order.

### 1. Load and validate conventions

Read `<workflow-root>/CONVENTIONS.md` every run. It is missing when absent or
placeholder-only: it contains no real writing guidance, including a single
`<!-- TODO: ... -->` or legacy `_Placeholder_` marker, or incomplete sections
containing only such markers. If missing, ask in the
main chat for the user to run `author-conventions` and refuse to draft. Never
invent voice, structure, tag vocabulary, taboos, or bilingual policy.

### 2. Resolve the topic and sources

- For "write about topic N", read the most recent
  `<workflow-root>/inputs/topics-*.md`, select Topic N, and preserve its title,
  topic key, angle, depth, and exact sources.
- For a free-text request, use the user's topic and derive its topic key.
- If the numbered topic or file is missing, ask the user to clarify.

For fact-checks outside this repository, establish the confirmed tracked
project allowlist in the main chat, then run individual bounded
`read_source_file` requests with the exact absolute path and confirmed project
list. Surface `truncated: true`; never imply unreturned text was checked. Do
not access SQLite, rollout files, arbitrary paths, or source files directly.

### 3. Derive slug and target

Derive a canonical kebab-case slug from the working title: lowercase, replace
runs of non-alphanumeric characters with `-`, collapse repeats, trim edges.
Use `<workflow-root>/drafts/<slug>.mdx`. Carry a selected candidate's
`topic_key`; otherwise use the same derivation as the slug. If the slug already
exists in `<workflow-root>/drafts/`, ask before overwriting and pass
`overwrite: true` only after that explicit choice.

If `<workflow-root>/published/<slug>.mdx` already exists, stop safely before
drafting or finalizing. Published-slug replacement is unsupported. Ask the
user to choose a new slug or handle replacement outside this workflow. Never
bypass the bridge or imply that draft overwrite
approval can replace a published article.

### 4. Draft the English body first

Author the English body first, following every applicable convention and
taboo. Assemble the single MDX file with:

- `draft: true`;
- stable `topic_key`;
- bilingual title/summary with a clearly temporary Italian placeholder;
- creation `date` and `lastmod` set to today's local `YYYY-MM-DD` date;
- tags drawn only from the controlled `CONVENTIONS.md` vocabulary in
  `{ id, label: { en, it } }` shape; and
- an images list.

Include the complete English `<Lang value="en">` block and an explicit
temporary Italian `<Lang value="it">` placeholder. Run
`write_article_draft` with the complete content and approved overwrite flag.

### 5. Iterate on English

In the main chat, ask a short review question containing only a one-line
summary, English word count, and file path. Never embed the article body or
large markdown in a question. Apply requested English changes, reassemble the
whole DRAFT, and run `write_article_draft` with overwrite approval. Repeat
until the user explicitly approves the English body.

If Italian is requested early, complete this English approval gate first.

### 6. Translate approved English to Italian

Translate the approved English title, summary, and body according to the
bilingual policy. Preserve code identifiers, strings, comments, and protected
technical terms. Replace the placeholder with the complete
`<Lang value="it">` block, keep `<Lang value="en">` unchanged, retain
`draft: true`, and run `write_article_draft` again.

### 7. Review the bilingual DRAFT

Ask a short main-chat review question with the path and compact summary, never
the body. Iterate by reassembling and running `write_article_draft` with the
whole file. It remains
`draft: true` throughout review.

### 8. Finalize only on approval

After explicit bilingual approval, run `finalize_article` for the slug.
This marker-only operation changes `draft: true` to `draft: false` while the
file remains under `drafts/`. Without approval, do nothing.

### 9. Publish only on explicit command

Only an explicit `publish <slug>` (or equivalent) authorizes publication. If
the bilingual review is incomplete, ask for completion rather than publishing.
If the reviewed draft is still `draft: true`, first run
`finalize_article` only when the publish command clearly confirms final
approval. Then run `publish_article` with the slug and today's local
`YYYY-MM-DD` publication date.

The bridge preserves the original `date`, refreshes `lastmod`, moves only a
finalized file to `<workflow-root>/published/<slug>.mdx`, and idempotently
records `topic_key | slug | publication date` in
`<workflow-root>/inputs/published-topics.md`. Never auto-publish and never
simulate these mutations with shell or file tools.

## Required MDX format

```text
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
topic_key: <kebab-case-key>
tags:
  - id: <controlled-id>
    label:
      en: <English label>
      it: <Italian label>
draft: true
images: []
---

<Lang value="en">

<English body>

</Lang>

<Lang value="it">

<Italian translation>

</Lang>
```

Allowed MDX vocabulary is limited to `<Lang value="en|it">`,
`<TOCInline toc={props.toc} exclude="..." />`, fenced code blocks with the
`lang:filename` info-string convention, footnotes, `<video>` with `<source>`,
markdown images or frontmatter images, and standard markdown. Never invent components outside this set.

When editing a previously dated draft, preserve `date` and refresh `lastmod` to
the edit date. Existing published articles cannot be edited or replaced by this
workflow. A missing draft, invalid marker, or bridge failure is reported safely
and leaves the workflow uncompleted.
