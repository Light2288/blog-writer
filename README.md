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
prompted, and restart Codex after changing `.codex/config.toml` or a repository
skill. Project trust is required before Codex loads the read-only configuration
and the project bridge. Node.js must be on the desktop app’s `PATH` as well.

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
| `.codex/`            | Codex read-only config and desktop MCP registration |
| `codex-bridge/`      | Local bounded MCP bridge used by the Codex main chat      |

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
   it flips the status table row from `DRAFT` to `FINAL`.

It never writes an article itself.

### blog-writer

Ask it to write about a topic, e.g. *"write about topic 2"* or a free-text
subject. It reads `CONVENTIONS.md`, drafts the **English body first** and
iterates with you, then translates to Italian and assembles a single
bilingual `drafts/<slug>.mdx` with frontmatter `draft: true` and a stable
`topic_key`. On your explicit *"publish &lt;slug&gt;"* command it flips
`draft: false`, preserves the original `date`, refreshes `lastmod`, moves the
file to `published/<slug>.mdx`, and records the `topic_key` in
`inputs/published-topics.md` so the topic-extractor won't resurface it. It
never edits source projects and never commits or pushes.

## Using Codex

### Direct desktop workflows

Open this repository as a trusted project, install the dependency above, and
restart Codex. In an ordinary project chat, use:

```text
Use extract-topics to find topics from last week.
Use author-conventions to update my writing conventions.
Use write-blog-article to draft topic 1 from inputs/topics-YYYY-MM-DD.md.
```

All three skills run directly in the same main chat. It owns project
confirmation, topic review, the conventions interview, English approval before
Italian translation, bilingual review, finalization, and explicit publication.
Use a concrete topics filename when selecting an article. Without one, the
writer reads the most recent `inputs/topics-*.md` and asks for clarification if
the file or numbered topic is missing.

Inspect the `blog_writer_bridge` tool catalog before the first workflow. The
project registration must expose exactly these nine operations:

```text
discover_projects, collect_activity, write_topic_draft, finalize_topics,
write_conventions, read_source_file, write_article_draft,
finalize_article, publish_article
```

Each skill calls only its own workflow operations. Tool availability does not
approve finalization, overwriting, or publication. Article finalization does not
publish. An explicit `publish <slug>` instruction moves the finalized article
and updates `inputs/published-topics.md` through the validated bridge handler.
Manual file moves do not update the ledger; no watcher reconciles them.

If tools are missing, partial, or unexpected, stop the workflow. Check Node.js
20+ on the app’s `PATH`, run `npm install --prefix codex-bridge`, trust the
project, and restart Codex. Inspect MCP startup errors and the catalog again.
A narrow catalog in an ordinary chat can indicate a launcher override or stale
session: open an ordinary project chat after restart. There is no custom-agent
fallback; shell and file tools cannot substitute for bridge history, source
fact checks, or mutations. No global Codex configuration changes are required.

### Command-scoped CLI compatibility

Install the bridge dependency, then run each reviewed workflow from the
repository:

```bash
npm install --prefix codex-bridge
./bin/blog-writer-codex topics "last week"
./bin/blog-writer-codex article "topic 2"
```

The topics command opens an interactive Codex session with only the `topic`
bridge profile. Confirm the discovered projects, review the resulting
topic list whose status table row is `DRAFT`, request any changes, and
explicitly approve its finalization before starting the article command. Topic
finalization does not start article writing.

The article command opens a separate interactive session with only the
`writer` profile. Review and approve the English draft first, then review the
bilingual DRAFT and explicitly approve finalization.
Article finalization does not publish. Publication remains a later, separate
`publish <slug>` command that preserves `date`, refreshes `lastmod`, moves the
article to `published/`, and updates the published-topic ledger.

The launcher may execute bridge code and repository skills from a linked
development worktree, but it resolves Git's primary checkout as the workflow
data root. Consequently `CONVENTIONS.md`, `tracked-projects.txt`, `inputs/`,
`drafts/`, and `published/` are always read from and written to the primary
Blog-Writer checkout, matching the OpenCode workflow.

The launcher uses the current configured model, `--no-daemon`, a read-only
sandbox, and one fixed invocation-scoped bridge profile. It never derives MCP
configuration from the supplied time window or subject. Missing `codex`,
Node.js, the bridge entrypoint, or installed bridge dependencies produces a
local prerequisite error. Invalid subcommands and a missing article subject
print usage before Codex starts. Model or service failures keep Codex's exit
status; the launcher never silently changes models.

The main session remains read-only for ordinary shell and filesystem access.
The project’s `desktop` bridge combines the three existing narrow profiles.
The launcher replaces the canonical server command and complete argument array
with the selected `topic` or `writer` profile; `conventions` remains available
as a one-operation profile. No narrow profile gains cross-workflow tools.
The bridge has no general shell tool, arbitrary-path file tool, or
caller-supplied project root.

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
bash tests/codex_scaffold_check.sh    # Codex skills, desktop routing, and read-only config
bash tests/codex_launcher_check.sh    # command validation and fixed MCP argv
npm test --prefix codex-bridge        # synthetic bridge unit/integration tests
bash tests/codex_acceptance_check.sh  # cross-runtime deterministic acceptance
```

The default suite is fully offline and deterministic: it uses temporary Git
repositories and synthetic rollout fixtures, never reads real Codex history,
and never invokes a model. The live Codex verifier is separate and opt-in:

```bash
CODEX_ACCEPTANCE_RUNTIME=1 bash tests/codex_live_check.sh
```

It consumes model calls. The app-server probe loads the actual trusted project
registration without MCP overrides and invokes all three skills on one parent
chat. It requires correlated catalogs, successful tool calls with exact
arguments, and exact fixture bytes. Separate topic and writer probes check
narrow CLI compatibility. The direct-write probe requires an actual sandbox
rejection. All probes use a temporary project, isolated `CODEX_HOME` and `HOME`,
and synthetic history. The default command reports `SKIP` and exits successfully.
Unavailable authentication or unsupported protocol evidence is reported as
`NEEDS_CONTEXT` (exit 2), not a pass; observed violations fail (exit 1).

These checks do not replace a **desktop restart and smoke test**. After restart,
confirm the nine tools in an ordinary project chat and perform a reviewed DRAFT
operation in a disposable fixture checkout. Neither static checks nor assistant
claims prove desktop success. The app-server fixture exercises transport and
persistence; the conversational approval sequence still needs a human review.

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

`.codex/config.toml` keeps the main Codex session read-only and registers
`blog_writer_bridge` with the fixed `desktop` profile. A fixed `/bin/sh`
bootstrap resolves the code root with `git rev-parse --show-toplevel`, then
executes Node.js. It works from nested folders and checkout paths containing
spaces; it does not expose a shell tool. MCP `cwd` is unset. Workflow data uses
the Git primary checkout even when bridge code runs from a linked worktree.
Trust and restart Codex after configuration changes so registration and skill
discovery are refreshed.
