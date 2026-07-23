# Step 01 — Project Scaffold & Permissions

| Field         | Value                                                  |
|---------------|--------------------------------------------------------|
| **Title**     | Project Scaffold & Permissions                         |
| **Type**      | feature                                                |
| **Scope**     | project skeleton + `.opencode/opencode.json`           |
| **Created**   | 2026-07-22 00:00:00                                    |
| **Status**    | IMPLEMENTED                                            |
| **Parent**    | specs/blog-writer-project.md                           |
| **Step**      | 1 of 5                                                 |

## Problem Statement

Everything in the Blog-Writer project rests on a correct directory layout and,
above all, a correct `.opencode/opencode.json`. This step lays down the
skeleton and encodes the safety-critical per-agent permissions and
`external_directory` allowances. If the permission ordering is wrong, the
agents can either be blocked from doing their job or — worse — allowed to write
where they must not.

## Desired Outcome

A fresh clone contains the full directory skeleton and a valid opencode config
that establishes the security boundaries for both agents (whose prompt/skill
bodies arrive in later steps).

### Files created

- `AGENTS.md` — top-level project context read by opencode: what the project
  is, that it only observes other projects, the two agents' roles, and the
  DRAFT-first + scoped-write invariants.
- `README.md` — how to use the project: prerequisites (`git`, `sqlite3`,
  the opencode DB path), how to invoke each agent, the optional
  `tracked-projects.txt` allowlist, where outputs land, and the reminder to
  restart opencode after config changes.
- `tracked-projects.txt` — created with an explanatory comment header only
  (no real paths); the file is an **optional allowlist**.
- `.opencode/opencode.json` — per-agent `permission` blocks + `external_directory`.
- `.opencode/agents/topic-extractor.md` and `.opencode/agents/blog-writer.md` —
  minimal valid **stubs** (frontmatter + a placeholder body). opencode
  auto-discovers file-based agents from this directory; their full prompt
  bodies are authored in steps 02/04. These stubs exist so the two agents
  are present and selectable after step 01.
- `inputs/.gitkeep`, `drafts/.gitkeep`, `published/.gitkeep`.
- `CONVENTIONS.md` — a valid **placeholder stub**, clearly marked as such, so
  a fresh clone validates and blog-writer's "missing conventions" guard finds
  a file. Step 03 replaces its content interactively; step 01 only creates the
  placeholder.

### opencode.json requirements

- Declares `"$schema": "https://opencode.ai/config.json"`.
- Defines a per-agent `permission` block for each of the two agents under the
  `agent` key: `agent.topic-extractor.permission` and
  `agent.blog-writer.permission`. The permission boundary lives **in
  `opencode.json`** (not in the `.md` files) so the safety-critical config is
  self-contained in this step. Do **not** put large inline prompts in the
  JSON — the agent prompt bodies live in the auto-discovered
  `.opencode/agents/*.md` files (see "Files created"). The JSON `agent` block
  and the `.md` files are separate mechanisms; the JSON does not reference the
  `.md` files.
- **topic-extractor permissions**:
  - `read`: allow anywhere.
  - `edit`: deny by default, allow only within `inputs/**`.
  - `bash`: broad rule first, then narrow: allow `git *`, allow
    `sqlite3 * -readonly *`, deny `git push*`, deny `git commit --amend*`,
    deny `rm -rf*`, and a conservative default for the rest.
- **blog-writer permissions**:
  - `read`: allow anywhere.
  - `edit`: deny by default, allow within `drafts/**`, `inputs/**`,
    `published/**`.
  - `bash`: same git/sqlite allow + destructive denies; additionally permit
    the specific move used for publishing (`mv drafts/* published/*` or
    equivalent), while keeping `rm -rf` denied.
- **external_directory** (applies to both agents): a broad allow of `~/**`
  plus the opencode DB directory so both agents can read source projects and
  the DB, followed by explicit denies of well-known sensitive paths:
  `~/.ssh/**`, `~/.aws/**`, `~/.gnupg/**`, `~/.config/**`, and `**/.env`.
  The broad allow is required because `tracked-projects.txt` is optional and
  auto-discovery may surface any project directory under the user's home; the
  deny list blocks the obvious secret stores while leaving discovery working.
- **Rule precedence — verify, don't assume.** The whole boundary depends on
  how opencode resolves multiple matching patterns within a single
  `{pattern: action}` object. The draft assumes **last-match-wins** (broad
  rules first, narrow/deny rules last). Because JSON object key ordering is
  not formally guaranteed by every parser and the deny list is
  safety-critical, the implementer must **empirically confirm** the actual
  precedence semantics before relying on ordering. If opencode uses a
  different rule (e.g. most-specific-match or deny-overrides-allow), the
  config must be restructured so the denies are genuinely effective.

## Acceptance Criteria

- [ ] `sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"`
      succeeds (prerequisite check documented in README).
- [ ] All directories and `.gitkeep` files exist.
- [ ] `.opencode/agents/topic-extractor.md` and
      `.opencode/agents/blog-writer.md` exist as valid stubs and both agents
      are discovered/selectable when opencode starts.
- [ ] A valid placeholder `CONVENTIONS.md` exists at the project root.
- [ ] `.opencode/opencode.json` is valid against
      `https://opencode.ai/config.json` and opencode starts without a
      `ConfigInvalidError`.
- [ ] Per-agent `permission` blocks are defined in `opencode.json` (not only in
      the agent `.md` files), and no large inline prompt is embedded in the JSON.
- [ ] `topic-extractor`'s `edit` permission allows `inputs/**` and denies
      everything else.
- [ ] `blog-writer`'s `edit` permission allows `drafts/**`, `inputs/**`,
      `published/**` and denies everything else.
- [ ] For both agents, `bash` allows `git *` and `sqlite3 * -readonly *` and
      denies `git push`, `git commit --amend`, and `rm -rf`.
- [ ] `external_directory` allows reading under `~/**` and the opencode DB
      directory, AND denies `~/.ssh/**`, `~/.aws/**`, `~/.gnupg/**`,
      `~/.config/**`, and `**/.env` (both the allow and each deny are asserted).
- [ ] opencode's permission rule-precedence semantics have been empirically
      confirmed (documented in the plan/implementation), and the `opencode.json`
      ordering/structure is arranged so the deny rules are actually effective
      under the confirmed semantics.
- [ ] `AGENTS.md` and `README.md` describe the project, the two agents, and the
      invariants.

## Edge Cases & Error Handling

- **opencode DB not found**: README documents the expected path and how to
  verify; agents surface a clear error at runtime (handled in steps 02/04).
- **Permission rule ordering mistake**: covered by explicit acceptance tests
  that assert both the allow and the deny sides, plus the precedence-
  verification criterion above (do not trust ordering without confirming
  opencode's actual semantics).
- **Config fails to load**: README points at the env-var escape hatches
  (`OPENCODE_DISABLE_PROJECT_CONFIG=1`) so the user can edit from inside
  opencode.

## Dependencies & Constraints

- opencode config is validated strictly and is not hot-reloaded; restart is
  required after changes.
- If unsure of any config field shape, fetch and consult
  `https://opencode.ai/config.json` rather than guessing.
- Agent prompt bodies and skill bodies are filled in by later steps; this step
  creates minimal valid agent `.md` stubs so both agents are discovered.
- Verified during spec-define: the opencode DB exists at
  `~/.local/share/opencode/opencode.db` and `sqlite3 -readonly ... ".tables"`
  succeeds, listing a `session` table (among others).
- opencode auto-discovers file-based agents from `.opencode/agents/*.md`; the
  `agent` block in `opencode.json` is a separate mechanism and does not
  reference those files. Per the confirmed config schema, `AgentConfig` has no
  file-path/reference field.

## Out of Scope

- Agent prompts and skill logic (steps 02–04).
- `CONVENTIONS.md` **content** — step 01 creates only the placeholder stub;
  the interactive authoring happens in step 03.
- End-to-end behaviour verification (step 05).

## Notes

- Keep the `bash` deny list explicit and precedence-aware (confirm opencode's
  actual matching semantics rather than assuming last-match-wins).
- Per-agent `permission` blocks live in `opencode.json`; agent prompt bodies
  live in the auto-discovered `.opencode/agents/*.md` files. Do not put large
  inline prompts in the JSON.
