# AGENTS.md — Blog-Writer Project Context

Blog-Writer turns recent work across other projects into reviewed bilingual
blog articles. It observes source projects and local runtime history but never
modifies those sources. This repository contains the workflows, conventions,
candidate topics, drafts, and publication staging files.

Articles target a Tailwind/Next.js MDX blog in English and Italian. Both the
OpenCode and Codex runtimes are invoked manually; there is no automation or
scheduled run.

## Shared workflow invariants

- **DRAFT-first.** Persist a topic table row with `Status` set to `DRAFT`, or
  `draft: true` for an article, before asking a short review question. Finalize
  only after explicit approval. Never embed a file body or large markdown in a
  question.
- **Real conventions required.** `CONVENTIONS.md` is invalid when missing or
  placeholder-only. Refuse to draft until it contains real guidance; a single
  placeholder is not sufficient.
- **Source projects are read-only.** Fact-check and activity collection may
  observe confirmed source projects but never edit, commit, or push them.
- **Stable shared formats.** Both runtimes use `inputs/topics-YYYY-MM-DD.md`,
  `inputs/published-topics.md`, `drafts/*.mdx`, `published/*.mdx`, stable topic
  keys, English-first authoring, and the same bilingual frontmatter.
- **Fixed MDX vocabulary.** Use only the components documented in
  `CONVENTIONS.md`; never invent a component.
- **Explicit publication.** Final approval does not publish. Move a finalized
  article and update its ledger only on an explicit publish command.

## OpenCode runtime

OpenCode loads project configuration from `.opencode/`:

- **topic-extractor** reads Git history plus OpenCode sessions from
  `~/.local/share/opencode/opencode.db` using `sqlite3 -readonly`, redacts
  obvious secrets, and writes only `inputs/**`. Its queries bound the window
  with `session.time_updated`; that column is **not indexed** in the verified
  schema, so the read-only query may scan the small session table.
- **blog-writer** reads conventions every run, authors English before Italian,
  writes only `drafts/**`, `inputs/**`, and `published/**`, and never commits or
  pushes.
- The supporting OpenCode skills live under `.opencode/skills/`; OpenCode's
  scoped permissions and command denials remain defined in
  `.opencode/opencode.json`.

Do not change OpenCode behavior when working on the Codex path.

## Codex runtime

Codex loads three repository skills from `.agents/skills/`:

- `extract-topics` owns discovery, project confirmation, synthesis, DRAFT
  review, and final approval; it calls bounded topic operations directly.
- `author-conventions` owns the interview and final review; it persists approved
  changes directly through `write_conventions`.
- `write-blog-article` owns topic resolution, source fact checks, English-first
  writing, translation, and every approval gate; it calls bounded article
  operations directly.

All three skills run in the main chat. `.codex/config.toml` keeps ordinary shell
and filesystem access read-only and registers one fixed `desktop` bridge with
exactly nine operations: `discover_projects`, `collect_activity`,
`write_topic_draft`, `finalize_topics`, `write_conventions`, `read_source_file`,
`write_article_draft`, `finalize_article`, and `publish_article`.
The fixed startup bootstrap finds the code root through Git; MCP `cwd` is unset.
There are no project custom-agent definitions or delegation fallback.

Explicit launcher command mode replaces that registration with exactly the
selected narrow `topic` or `writer` catalog. The `conventions`-only profile
remains available. Validate the selected catalog before any bridge operation;
ignore unrelated MCP servers. Missing, partial, unexpected, or mismatched
catalogs require dependency/trust/restart guidance, never a shell substitute.

When Codex code runs from a linked worktree, that worktree is only the code
root. Resolve the Git common directory and use its primary checkout as the
workflow data root for `CONVENTIONS.md`, `tracked-projects.txt`, `inputs/`,
`drafts/`, and `published/`.

All intended Codex writes pass through bounded bridge operations. Explicit
publication updates the ledger; manual file moves do not. Never add a
general shell, arbitrary file tool, caller-supplied project root, or cross-role
access in a narrow profile.

See `README.md` for runtime invocation and verification, and
`CONVENTIONS.md` for the actual writing style.
