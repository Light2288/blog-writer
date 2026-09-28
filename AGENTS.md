# AGENTS.md — Blog-Writer Project Context

Blog-Writer turns recent work across other projects into reviewed bilingual
blog articles. It observes source projects and local runtime history but never
modifies those sources. This repository contains the workflows, conventions,
candidate topics, drafts, and publication staging files.

Articles target a Tailwind/Next.js MDX blog in English and Italian. Both the
OpenCode and Codex runtimes are invoked manually; there is no automation or
scheduled run.

## Shared workflow invariants

- **DRAFT-first.** Persist `Status: DRAFT` for topics or `draft: true` for an
  article before asking a short review question. Finalize only after explicit
  approval. Never embed a file body or large markdown in a question.
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

- `extract-topics` coordinates topic discovery, project confirmation,
  synthesis, DRAFT review, and final approval; it delegates only bounded
  history and topic operations to the `topic-extractor` custom agent.
- `author-conventions` conducts the focused interview and final review in the
  main chat; it delegates only persistence to `conventions-writer`.
- `write-blog-article` owns topic resolution, English-first writing,
  translation, and every approval gate in the main chat; it delegates only
  bounded fact checks and article mutations to `blog-writer`.

The main Codex session and all three custom agents run with a read-only
sandbox. `.codex/config.toml` enables multi-agent behavior but intentionally
registers no privileged MCP bridge. Each standalone file under
`.codex/agents/` registers exactly one `node codex-bridge/src/server.mjs
--profile <role>` server and may use only that matching profile. Custom agents
never question the user; they return concise structured results to the main
chat.

All intended Codex writes pass through narrow bridge operations. Never add a
general shell, arbitrary file tool, caller-supplied project root, or cross-role
profile access.

See `README.md` for runtime invocation and verification, and
`CONVENTIONS.md` for the actual writing style.
