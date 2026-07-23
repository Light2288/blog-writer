# Blog-Writer

A self-contained opencode project that helps you turn recent work — spread
across several other projects — into bilingual (English + Italian) blog
articles for a Tailwind/Next.js MDX blog. It **only observes** the projects
it writes about; it never modifies them.

Two manually-invoked primary agents live here:

- **topic-extractor** — a read-only analyst that surfaces candidate topics
  from your recent git history and opencode session transcripts.
- **blog-writer** — drafts a bilingual MDX article from a chosen topic,
  iterating with you, and publishes it on explicit command.

## Prerequisites

- **git** on your `PATH`.
- **sqlite3** on your `PATH`.
- The opencode session database at `~/.local/share/opencode/opencode.db`.

Verify read-only access to the database before first use:

```bash
sqlite3 -readonly ~/.local/share/opencode/opencode.db ".tables"
```

If that lists tables (including `session`), you're ready. If the file does
not exist, open opencode at least once so the database is created, or adjust
your setup so the DB lives at that path.

## Directory layout

| Path                 | Purpose                                             |
|----------------------|-----------------------------------------------------|
| `inputs/`            | Candidate-topic files (`topics-YYYY-Www.md`)        |
| `drafts/`            | Article drafts (`<slug>.mdx`, `draft: true`)        |
| `published/`         | Published articles (moved here on your command)     |
| `CONVENTIONS.md`     | Your writing style/voice (authored in step 03)      |
| `tracked-projects.txt` | Optional allowlist of project directories         |
| `.opencode/`         | Agents and the permission config (`opencode.json`)  |

## Using the agents

Invoke each agent manually from inside this project (there is no automation
or scheduling).

### topic-extractor

Ask it to extract topics, e.g. *"extract topics from last week"*. It:

1. Determines which projects to consider (see the allowlist below).
2. Reads git commit history and opencode session transcripts
   (`sqlite3 -readonly`, filtered on the indexed `time_updated` column),
   correlates them by timestamp, and redacts obvious secrets.
3. Writes a DRAFT topics file to `inputs/topics-YYYY-Www.md` (ISO week
   numbering) and asks you to review it. On your approval it flips
   `Status: DRAFT` to `Status: FINAL`.

It never writes an article itself.

### blog-writer

Ask it to write about a topic, e.g. *"write about topic 2"* or a free-text
subject. It reads `CONVENTIONS.md`, drafts the **English body first** and
iterates with you, then translates to Italian and assembles a single
bilingual `drafts/<slug>.mdx` with frontmatter `draft: true`. On your
explicit *"publish &lt;slug&gt;"* command it flips `draft: false` and moves the
file to `published/<slug>.mdx`. It never edits source projects and never
commits or pushes.

## The optional `tracked-projects.txt` allowlist

Editing `tracked-projects.txt` is **optional**:

- **Present and non-empty** (has at least one path line): it is an
  allowlist — only those project directories are considered.
- **Absent or comment-only**: the topic-extractor auto-discovers candidate
  projects from the opencode DB and confirms the list with you before
  extracting.

Use the allowlist to exclude sensitive projects.

## Configuration and permissions

The permission boundary for both agents lives in
`.opencode/opencode.json`:

- Both agents may **read** anywhere (to inspect source projects and the DB).
- `topic-extractor` may **edit** only within `inputs/**`.
- `blog-writer` may **edit** only within `drafts/**`, `inputs/**`, and
  `published/**`.
- Both may run `git *` and `sqlite3 * -readonly *`; `git push`,
  `git commit --amend`, and `rm -rf` are **denied**.
- `external_directory` allows reading under your home directory and the
  opencode DB directory, while denying well-known secret stores
  (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.config`, and any `.env`).

### Restart after config changes

opencode's configuration is validated strictly and is **not hot-reloaded**.
After editing `.opencode/opencode.json` (or the agent files), **quit and
restart opencode** so the changes take effect.

### If the config fails to load

If opencode reports a `ConfigInvalidError` and you need to edit the config
from inside opencode, start it with the project config disabled:

```bash
OPENCODE_DISABLE_PROJECT_CONFIG=1 opencode
```

Fix `.opencode/opencode.json`, then restart normally.

### How permission rules are resolved (precedence)

The permission boundary depends on how opencode resolves multiple matching
patterns within a single `{pattern: action}` object. Per the official
opencode documentation, **rules are evaluated by pattern match, with the
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
