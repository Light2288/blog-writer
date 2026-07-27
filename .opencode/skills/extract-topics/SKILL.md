---
name: extract-topics
description: >-
  Use when the topic-extractor agent is asked to extract, surface, or find
  candidate blog topics from recent activity (e.g. "extract topics from last
  week"). Analyses git history and opencode session transcripts across tracked
  projects, correlates them by timestamp, redacts secrets, and writes a DRAFT
  topics file to inputs/topics-YYYY-MM-DD.md.
---

# Extract Topics

Turn recent activity across the user's projects — git commits plus opencode
session transcripts — into a reviewed list of candidate blog topics. The output
is a single DRAFT file at `inputs/topics-YYYY-MM-DD.md` that is flipped to FINAL
only on the user's explicit approval.

This skill is **read-only** with respect to every source: it only ever observes
the tracked projects and the opencode database. It writes exclusively inside
`inputs/**`, and it **never writes an article** — that is the blog-writer's job.

## Workflow

Follow these ten steps in order.

### 1. Resolve the time window

Default to the **last 7 days**. Accept overrides from the user's phrasing:
"last month", "last two weeks", explicit dates ("from 2026-07-01 to
2026-07-15"), etc.

Compute the window as an inclusive pair of Unix-**millisecond** bounds
`(lo, hi]` for the database query (opencode stores timestamps in ms).

Derive the output filename from the **date the extraction is run** (today's
local date): `inputs/topics-YYYY-MM-DD.md` (e.g. `topics-2026-07-24.md`). This
gives every run its own file, so running twice in the same ISO week does not
collide. Record the resolved window and the ISO week that contains the window's
end date **inside** the file (in the header table and a `Generated:` line), not
in the filename.

### 2. Resolve tracked projects (allowlist or auto-discover)

Read `tracked-projects.txt` at the project root:

- **Present and non-empty** — i.e. it has at least one line that is not blank
  and not a `#` comment — treat it as an **allowlist**: consider only those
  directories (one path per line; ignore blank lines and `#` comments).
- **Absent, or only comments/blank lines** — **auto-discover** the candidate
  set from the opencode DB, then present the discovered list to the user via
  the `question` tool and wait for confirmation before extracting.

  ```bash
  sqlite3 -readonly "$OPENCODE_DB" \
    "SELECT DISTINCT directory FROM session
     WHERE time_updated > <lo> AND time_updated <= <hi>"
  ```

Never refuse to run solely because `tracked-projects.txt` is absent — the
allowlist is optional and auto-discovery is the documented fallback. The
allowlist is nonetheless the primary privacy gate: sensitive projects can be
excluded by listing only the ones you want.

`$OPENCODE_DB` is `~/.local/share/opencode/opencode.db`.

### 3. Gather git history per project

For each resolved project directory, collect commits inside the window:

```bash
git -C <dir> log --since="<lo-as-date>" --until="<hi-as-date>" \
  --pretty=format:'%h%x09%ct%x09%s'
```

Collect the short SHA, commit timestamp, and subject.

- If the directory **is not a git repo** or has **no commits** in the window,
  skip its git gathering and note it in the appendix.
- If the directory **no longer exists on disk**, warn the user and skip it.

### 4. Gather sessions (and their text)

Query the `session` table filtered on the `time_updated` column and the
project `directory`:

```bash
sqlite3 -readonly "$OPENCODE_DB" \
  "SELECT id, title, slug, agent, time_created, time_updated
   FROM session
   WHERE directory = '<dir>'
     AND time_updated > <lo> AND time_updated <= <hi>"
```

Collect a short `id`, `title`, `slug`, `agent`, `time_created`, and
`time_updated` for each session.

For **topic substance** (the material that makes a topic more than a title),
pull the prose text from the matched sessions' parts. Human/agent prose lives
in `part` rows whose data has `type = 'text'`:

```bash
sqlite3 -readonly "$OPENCODE_DB" \
  "SELECT json_extract(data,'\$.text')
   FROM part
   WHERE session_id = '<session-id>'
     AND json_extract(data,'\$.type') = 'text'
   ORDER BY time_created
   LIMIT <n>"
```

**Cap the volume per session** — use a bounded part count and/or a character
budget (e.g. the first N text parts, truncated to a few thousand characters
total) so context stays manageable. Do not slurp entire long sessions.

### 5. Correlate by timestamp

Relate commits and sessions that fall close together in time within the same
project, so a topic can cite both. Correlation is heuristic (time proximity);
**be transparent** in each topic's Sources about exactly which commits and
sessions you linked.

### 5b. Exclude already-published topics

Before synthesising, drop any candidate the user has **already published an
article about**, so re-running the extractor next day/week does not resurface
finished work. Only **published** articles exclude a topic — drafts do **not**
(an abandoned draft may legitimately resurface).

Two exclusion sources (a candidate is excluded if it matches **either**):

1. **The ledger** `inputs/published-topics.md` — a running list the
   `blog-writer` appends to on every publish. Each entry records the
   `topic_key`, the published article slug, and the date. Read it if present:

   ```bash
   [ -f inputs/published-topics.md ] && cat inputs/published-topics.md
   ```

2. **Published article frontmatter** — as a fallback (e.g. the ledger was lost),
   scan `published/*.mdx` for a `topic_key:` field:

   ```bash
   grep -h '^topic_key:' published/*.mdx 2>/dev/null | sed 's/^topic_key:[[:space:]]*//'
   ```

**Matching.** Compute each candidate's `topic_key` (see below) and exclude it if
that key appears in either source. As a secondary safety net, also skip a
candidate whose derived key is a near-duplicate of a published one (same key
after normalising). When in doubt, keep the topic but add a short note that it
*may* overlap a published article, and let the user decide in review.

**`topic_key` derivation (shared with `write-blog-article`).** Kebab-case the
topic's working title: lowercase, spaces → `-`, strip punctuation, collapse
repeats. This must match the article slug the writer derives from the same
title, so the two skills agree without extra bookkeeping.

Record what you excluded in the file's **Excluded** appendix section (topic key
+ why), so the user can see nothing was silently dropped.

### 6. Redact secrets

Before writing **anything to disk**, run the redaction filter over every piece
of session-derived text that will appear in the file (quoted material). Only
material destined for the topics file needs redaction — internal-only reasoning
is never written and is out of scope.

Pipe such text through the helper:

```bash
printf '%s' "<quoted-text>" | python3 .opencode/skills/extract-topics/scripts/redact.py
```

`redact.py` replaces matches with `[REDACTED:<reason>]` on stdout and writes
`FLAG` to stderr when any redaction occurred. It detects `client_secret`,
`bearer` tokens, `api_key`, `token`, and long hex/base64 strings that look like
secrets. Keep the regexes conservative — the DRAFT review and the
`tracked-projects.txt` allowlist are the real safety net.

Any topic whose sources produced a redaction (a `FLAG`) must carry a
**Flagged** note describing why, so the user can decide in review whether to
keep it.

### 7. Synthesise candidate topics

Produce the topics using the template below (from the parent spec): a working
title, why it is interesting, Sources (sessions + commits), estimated depth,
angle, an **Evaluation** block, and an optional **Flagged** note — plus an
appendix listing the raw sources.

**Evaluation (always included).** Score every topic across these **five
dimensions**, each `0-10`, and compute the **Overall** as their average
(rounded to one decimal). This is the extractor's subjective opinion, meant to
help the user triage during review — not a hard gate.

- **Reader appeal** — how many readers would genuinely want to read it.
- **Technical depth** — how much substantive engineering there is to unpack.
- **Storytelling** — how well it fits the user's first-person, ironic narrative
  voice (see `CONVENTIONS.md`).
- **Uniqueness** — how fresh/differentiated it is versus what already exists.
- **Publishability** — how easy it is to write safely and well; **lower this
  score when a topic is Flagged** or otherwise constrained by confidentiality
  (Taboos), since that adds friction/risk.

Render the evaluation as a compact markdown table per topic (dimension | score),
followed by the **Overall** row. Add a short legend near the top of the file
explaining the dimensions.

**Ordering.** Sort the candidate topics **from the highest Overall score to the
lowest** before writing the file (ties broken by Reader appeal, then by the
extractor's judgement). The numbering (Topic 1, Topic 2, ...) follows this
sorted order, so "write about topic 1" always refers to the highest-rated
candidate.

### 8. Write the DRAFT file

Write `inputs/topics-YYYY-MM-DD.md` (the run date, per step 1) with
`Status: DRAFT`. Include a **`Generated:`** row in the header table recording the
exact date and time the file was produced (`YYYY-MM-DD HH:MM`, local time), plus
the resolved `Window` and the `ISO week` of the window end, so the chronology and
scope are clear from inside the file.

- If a topics file for **today's date** already exists (you already ran the
  extractor today), ask the user via `question` whether to **overwrite** it or
  use a different name, before writing. Never clobber silently.
- If **no topics** were found (or every candidate was excluded as
  already-published), still write a DRAFT file that plainly states the result
  (e.g. "No new candidate topics found in this window") rather than silently
  doing nothing.

### 9. Ask a short question

Call `question` with a **short** summary only: counts of projects, sessions,
commits, candidate topics, and how many are flagged, plus a pointer to the
file. **Never embed the file body (or any large markdown) inside a `question`
call** — it can terminate the request. The file on disk is the source of truth
during review.

### 10. Finalise on approval

- On explicit approval, use `edit` to flip the `Status` row from
  `DRAFT` to `FINAL`.
- On change requests, edit the file directly and re-ask (back to step 9).

## SQL constraints

- **Every** `sqlite3` invocation uses `-readonly`. Never fall back to
  write access, even if the DB appears missing or locked — surface a clear
  error instead.
- Window queries **filter on the `time_updated` column** to bound the result
  to the requested window. Note: `time_updated` is **not** indexed in the
  opencode schema, so this filter performs a table scan; that is acceptable
  because the `session` table is small. Do **not** create an index — the
  database is accessed strictly read-only.
- Verified schema (Unix-ms timestamps):
  `session(id, project_id, parent_id, slug, directory, title, agent, model,
  time_created, time_updated, path, ...)`,
  `message(id, session_id, time_created, time_updated, data)`,
  `part(id, message_id, session_id, time_created, time_updated, data)`.
  Prose text is in `part` rows with `json_extract(data,'$.type') = 'text'` at
  `json_extract(data,'$.text')`.

## Redaction reference

- Helper: `.opencode/skills/extract-topics/scripts/redact.py` (stdlib only).
- Input on stdin, redacted text on stdout, `FLAG` on stderr when redactions
  occurred.
- Patterns: `client_secret`, `bearer <token>`, `api_key`, `token`, long
  hex (≥32) and base64 (≥32) runs. Matches become `[REDACTED:<reason>]`.
- Any topic sourced from flagged text gets a **Flagged** note.

## Topics file template

```text
# Topic candidates — 2026-07-26 (ISO week 2026-W30)

| Field       | Value                            |
|-------------|----------------------------------|
| Window      | 2026-07-20 to 2026-07-26         |
| ISO week    | 2026-W30                         |
| Generated   | 2026-07-26 14:30                 |
| Projects    | app-scrutatore, certflow, blog   |
| Sessions    | 12 (see appendix)                |
| Commits     | 34 (see appendix)                |
| Status      | DRAFT                            |

> **Evaluation legend.** Each topic is scored 0-10 across five dimensions and
> the **Overall** is their average (the extractor's subjective opinion, to aid
> triage — not a hard gate). Dimensions: **Reader appeal** (would readers want
> it), **Technical depth** (substance to unpack), **Storytelling** (fit with the
> first-person, ironic voice in `CONVENTIONS.md`), **Uniqueness** (freshness vs.
> what exists), **Publishability** (ease of writing it safely — lowered when a
> topic is Flagged / confidentiality-constrained). Topics are ordered from
> highest to lowest Overall.

## Candidate topics

### Topic 1: <catchy working title>
- **Topic key**: <kebab-case-key derived from the title>
- **Why interesting**: <1-2 sentences>
- **Sources**:
  - Sessions: <session-id-short>, <session-id-short>
  - Commits: <project>@<sha-short>, ...
- **Estimated depth**: short / medium / long
- **Angle**: <retrospective, tutorial, opinion, deep-dive, etc.>
- **Evaluation**:

  | Dimension       | Score |
  |-----------------|-------|
  | Reader appeal   | <0-10> |
  | Technical depth | <0-10> |
  | Storytelling    | <0-10> |
  | Uniqueness      | <0-10> |
  | Publishability  | <0-10> |
  | **Overall**     | **<avg>** |

- **Flagged**: <only if secret-like content was detected — describe why>

### Topic 2: ...
(topics appear in descending Overall-score order)

## Appendix: raw sources
- <bulleted list of sessions with titles>
- <bulleted list of commits with subjects>

## Appendix: excluded (already published)
- <topic-key> — matched published article <slug> (<source: ledger|frontmatter>)
- (empty if nothing was excluded)
```
