# AGENTS.md — Blog-Writer Project Context

This file is read by opencode as top-level project context. It tells any
agent working in this repository what the project is and the invariants it
must respect.

## What this project is

Blog-Writer is a self-contained opencode project that helps the user turn
recent work — scattered across multiple other projects — into blog articles.
It **only ever observes** the projects it writes about; it never modifies
them. This repository houses the tools, conventions, and drafts, and is
separate from the source projects.

Articles are published to a Tailwind/Next.js MDX blog that is bilingual
(English + Italian), so drafts must match that blog's exact MDX file format.

There is no automation and no scheduled runs. Both agents are invoked
manually from inside this project when the user wants.

## The two agents

- **topic-extractor** (read-only analyst): analyses recent activity across a
  set of tracked projects — git commit history plus opencode session
  transcripts from `~/.local/share/opencode/opencode.db` (queried with
  `sqlite3 -readonly`) — correlates them by timestamp, redacts obvious
  secrets, and writes a DRAFT candidate-topics file to
  `inputs/topics-YYYY-MM-DD.md`. It **never writes an article**, even if asked.

- **blog-writer** (the writer): reads `CONVENTIONS.md` every run (and refuses
  to draft without at least a placeholder), takes a topic from the current
  `inputs/topics-*.md` file or free text, drafts the **English body first**
  and iterates, then translates to Italian and assembles a single bilingual
  `.mdx` file in `drafts/` with frontmatter `draft: true`. On the user's
  explicit command it flips `draft: false` and moves the file to
  `published/`. It **never edits source projects** and **never commits or
  pushes**.

## Invariants (both agents)

- **DRAFT-first.** Write the file to disk in its draft state
  (`Status: DRAFT` for topics; frontmatter `draft: true` for articles), then
  ask a short summarising `question`. Flip to final only on explicit user
  approval. **Never embed large markdown inside a `question` call** — it can
  terminate the request.
- **Scoped writes.** The runtime enforces write scopes:
  - `topic-extractor` may write only within `inputs/**`.
  - `blog-writer` may write only within `drafts/**`, `inputs/**`,
    `published/**`.
- **Read-only DB access.** All `sqlite3` calls use `-readonly` and filter on
  the indexed `time_updated` column.
- **No destructive or remote git.** `git push`, `git commit --amend`, and
  `rm -rf` are denied for both agents.
- **Fixed MDX vocabulary.** The writer stays within the target blog's allowed
  component set and never invents components outside it.

See `README.md` for how to run the project and `CONVENTIONS.md` for the
writing style (authored in step 03).
