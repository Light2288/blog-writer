# Blog-Writer

A self-contained OpenCode and Codex project that helps you turn recent work —
spread across several other projects — into bilingual (English + Italian) blog
articles for a Tailwind/Next.js MDX blog. It **only observes** the projects it
writes about; it never modifies them. Both runtimes are manually invoked; no
automation or scheduled run is installed.

The shared editorial workflow has two roles:

- **topic-extractor** — a read-only analyst that surfaces candidate topics
  from recent Git history and local runtime transcripts.
- **blog-writer** — drafts a bilingual MDX article from a chosen topic,
  iterating with you, and publishes it on explicit command.

## Prerequisites

Both runtimes need **git**. OpenCode also needs **sqlite3** and its session
database at `~/.local/share/opencode/opencode.db`.

Verify read-only access to the database before first use:

```bash
sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"
```

If that lists tables (including `session`), you're ready. If the file does
not exist, open OpenCode at least once so the database is created, or adjust
your setup so the DB lives at that path.

Codex needs Node.js 20+ and npm. Install the pinned local MCP bridge dependency
after cloning:

```bash
npm install --prefix codex-bridge
```

Open the repository in Codex CLI or Codex desktop, trust the project when
prompted, and restart Codex after changing `.codex/config.toml`, a custom-agent
file, or a repository skill. Project trust is required before Codex loads the
read-only configuration and role-scoped MCP servers.

## Directory layout

| Path                 | Purpose                                             |
|----------------------|-----------------------------------------------------|
| `inputs/`            | Candidate-topic files (`topics-YYYY-MM-DD.md`) + the `published-topics.md` ledger |
| `drafts/`            | Article drafts (`<slug>.mdx`, `draft: true`)        |
| `published/`         | Published articles (moved here on your command)     |
| `CONVENTIONS.md`     | Your writing style/voice (authored in step 03)      |
| `tracked-projects.txt` | Optional allowlist of project directories         |
| `.opencode/`         | OpenCode agents, skills, and permission config      |
| `.agents/skills/`    | Codex repository skills                            |
| `.codex/`            | Codex read-only config and role-scoped custom agents |
| `codex-bridge/`      | Local profiled MCP bridge used by Codex agents      |

## Using OpenCode

Invoke each agent manually from inside this project (there is no automation
or scheduling).

### topic-extractor

Ask it to extract topics, e.g. *"extract topics from last week"*. It:

1. Determines which projects to consider (see the allowlist below).
2. Reads Git commit history and OpenCode session transcripts
   (`sqlite3 -readonly`, filtered on the `time_updated` column),
   correlates them by timestamp, and redacts obvious secrets.
3. Skips any topic you have **already published** an article about (matched by
   `topic_key` via the `inputs/published-topics.md` ledger and published
   articles' frontmatter), so re-running it does not resurface finished work.
   Drafts do not count — only published articles.
4. Scores each candidate across five dimensions (Reader appeal, Technical depth,
   Storytelling, Uniqueness, Publishability), orders them by the resulting
   Overall score, and writes a DRAFT topics file to `inputs/topics-YYYY-MM-DD.md`
   (named by the run date — so same-week re-runs don't collide — with the ISO
   week, window, and a `Generated:` timestamp recorded inside). On your approval
   it flips `Status: DRAFT` to `Status: FINAL`.

It never writes an article itself.

### blog-writer

Ask it to write about a topic, e.g. *"write about topic 2"* or a free-text
subject. It reads `CONVENTIONS.md`, drafts the **English body first** and
iterates with you, then translates to Italian and assembles a single
bilingual `drafts/<slug>.mdx` with frontmatter `draft: true` and a stable
`topic_key`. On your explicit *"publish &lt;slug&gt;"* command it flips
`draft: false`, moves the file to `published/<slug>.mdx`, and records the
`topic_key` in `inputs/published-topics.md` so the topic-extractor won't
resurface it. It never edits source projects and never commits or pushes.

## Using Codex

Start a trusted Codex chat in this repository and invoke the repository skills
in ordinary language. For example:

- “Use `extract-topics` to find topics from last week.”
- “Use `write-blog-article` to write about topic 2.”
- “Use `author-conventions` to help me complete the writing conventions.”

The main chat owns project confirmation, review questions, and every approval.
It delegates bounded work to `topic-extractor`, `blog-writer`, or
`conventions-writer`. The main session and custom agents are read-only; all
intended writes pass through one local MCP bridge whose `topic`, `writer`, and
`conventions` profiles expose different fixed tool lists. The bridge has no
general shell tool, arbitrary-path file tool, or caller-supplied project root.

Codex topic extraction reads supported local rollout JSONL below
`~/.codex/sessions/**/*.jsonl` through a bounded adapter and combines it with
read-only Git history. That location and record shape are adapter details, not
a stable public database contract. The bridge never modifies local history,
and internal Codex SQLite is not supported. ChatGPT web history and hosted
account history are out of scope.

## The optional `tracked-projects.txt` allowlist

Editing `tracked-projects.txt` is **optional**:

- **Present and non-empty** (has at least one path line): it is an
  allowlist — only those project directories are considered.
- **Absent or comment-only**: the topic-extractor auto-discovers candidate
  projects from the active runtime history and confirms the list with you
  before extracting.

Use the allowlist to exclude sensitive projects.

## Acceptance testing

A single, repeatable end-to-end acceptance procedure lives in
[`docs/acceptance.md`](docs/acceptance.md). It maps every acceptance criterion
to a check, distinguishing automated mechanical checks from the manual
agent-conversation script.

Run the whole mechanical suite from the project root:

```bash
bash tests/run_all.sh
```

Or run individual verifiers:

```bash
bash tests/scaffold_check.sh          # step 01 scaffold + permissions structure
bash tests/extract_topics_check.sh    # step 02 topic-extractor + extract-topics
bash tests/conventions_check.sh       # step 03 conventions template + interview
bash tests/blog_writer_check.sh       # step 04 blog-writer + write-blog-article
bash tests/acceptance_check.sh        # step 05 system-wide static + coverage
bash tests/permission_check.sh        # step 05 permission/destructive-command denial
bash tests/redaction_check.sh         # step 05 deterministic redaction/flagging
bash tests/codex_scaffold_check.sh    # Codex skills, agents, and read-only config
npm test --prefix codex-bridge        # synthetic bridge unit/integration tests
bash tests/codex_acceptance_check.sh  # cross-runtime deterministic acceptance
```

The default suite is fully offline and deterministic: it uses temporary Git
repositories and synthetic rollout fixtures, never reads real Codex history,
and never invokes a model. The live Codex verifier is separate and opt-in:

```bash
CODEX_ACCEPTANCE_RUNTIME=1 bash tests/codex_live_check.sh
```

It consumes model calls. Its write and boundary probes run only in a temporary
fixture project with an isolated `CODEX_HOME`; the default command without the
environment variable reports `SKIP` and exits successfully.

The permission-boundary and destructive-command scenarios can additionally be
proven against the live runtime (opt-in, consumes model calls):

```bash
ACCEPTANCE_RUNTIME=1 bash tests/permission_check.sh
```

## OpenCode configuration and permissions

The permission boundary for both agents lives in
`.opencode/opencode.json`:

- Both agents may **read** anywhere (to inspect source projects and the DB).
- `topic-extractor` may **edit** only within `inputs/**`.
- `blog-writer` may **edit** only within `drafts/**`, `inputs/**`, and
  `published/**`.
- Both may run `git *` and `sqlite3 * -readonly *`; `git push`,
  `git commit --amend`, and `rm -rf` are **denied**.
- `external_directory` allows reading under your home directory and the
  OpenCode DB directory, while denying well-known secret stores
  (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.config`, and any `.env`).

### Restart after config changes

OpenCode's configuration is validated strictly and is **not hot-reloaded**.
After editing `.opencode/opencode.json` (or the agent files), **quit and
restart OpenCode** so the changes take effect.

### If the config fails to load

If OpenCode reports a `ConfigInvalidError` and you need to edit the config
from inside OpenCode, start it with the project config disabled:

```bash
OPENCODE_DISABLE_PROJECT_CONFIG=1 opencode
```

Fix `.opencode/opencode.json`, then restart normally.

### How permission rules are resolved (precedence)

The OpenCode permission boundary depends on how OpenCode resolves multiple
matching patterns within a single `{pattern: action}` object. Per the official
OpenCode documentation, **rules are evaluated by pattern match, with the
last matching rule winning**. The recommended layout — which
`.opencode/opencode.json` follows — puts the catch-all `"*"` (and `"**"`)
rule **first** and more specific rules **after** it. Additional facts that
shape this config:

- Wildcards are simple: `*` matches zero or more of any character (including
  path separators) and `?` matches exactly one; everything else is literal.
- `~` / `$HOME` at the start of a pattern expands to your home directory.
- Agent permissions are merged with the global config, and agent rules take
  precedence.
- `external_directory` covers any tool touching paths outside the project.
  Entries there inherit workspace defaults (so `read` stays allowed unless
  denied); the explicit denies above block the sensitive stores.

Because ordering is significant, keep the catch-all deny/ask rules first and
the narrow allow/deny rules last when editing `.opencode/opencode.json`.

## Codex configuration and permissions

`.codex/config.toml` keeps the main Codex session read-only and enables custom
agents without registering privileged bridge tools globally. Each file under
`.codex/agents/` starts exactly one bridge profile and also uses a read-only
sandbox. Trust and restart Codex after configuration changes so discovery and
the MCP registrations are refreshed.
