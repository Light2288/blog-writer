# Step 02 — topic-extractor Agent & extract-topics Skill

| Field         | Value                                                  |
|---------------|--------------------------------------------------------|
| **Title**     | topic-extractor Agent & extract-topics Skill           |
| **Type**      | feature                                                |
| **Scope**     | `.opencode/agents/topic-extractor.md` + `.opencode/skills/extract-topics/SKILL.md` |
| **Created**   | 2026-07-22 00:00:00                                    |
| **Status**    | DRAFT                                                  |
| **Parent**    | specs/blog-writer-project.md                           |
| **Step**      | 2 of 5                                                 |

## Problem Statement

I need a read-only analyst agent that turns my recent activity across projects
into a reviewed list of candidate blog topics, correlating what I committed
with what I discussed in opencode sessions, without leaking secrets.

## Desired Outcome

A primary agent `topic-extractor` backed by an `extract-topics` skill that,
when invoked (e.g. "extract topics from last week"), produces a DRAFT topics
file at `inputs/topics-YYYY-Www.md` and drives it to FINAL on approval.

### Agent (`.opencode/agents/topic-extractor.md`)

- `mode: primary`.
- Frontmatter permissions consistent with step 01 (read anywhere; edit only
  `inputs/**`; bash git/sqlite allow, destructive deny).
- Prompt body: role, invariants, and a hard anti-hijack rule — it produces
  ONLY a topics file and NEVER writes an article, even if asked.
- Loads the `extract-topics` skill.

### Skill (`.opencode/skills/extract-topics/SKILL.md`)

Workflow:

1. **Resolve time window.** Default last 7 days; accept overrides ("last
   month", explicit dates). Compute the window as Unix-ms bounds for the DB
   query.
2. **Resolve tracked projects.**
   - If `tracked-projects.txt` exists and is non-empty → use it as an
     allowlist (one directory per line; ignore blank lines and `#` comments).
   - Else → auto-discover via
     `sqlite3 -readonly <db> "SELECT DISTINCT directory FROM session WHERE time_updated > <lo> AND time_updated <= <hi>"`,
     then present the discovered list to the user via `question` for
     confirmation before proceeding. Never refuse solely because the file is
     absent.
3. **Per project, gather git history.** `git -C <dir> log` filtered to the
   window (`--since`/`--until`), collecting short SHA, subject, timestamp. If
   the directory is not a git repo or has no commits in the window, skip and
   note in the appendix. If the directory no longer exists on disk, warn and
   skip.
4. **Gather sessions.** Query `session` filtered on the indexed `time_updated`
   column and `directory`, collecting `id` (short), `title`, `slug`, `agent`,
   `time_created`, `time_updated`. Read only. For candidate topic sourcing,
   optionally pull message/part text from `message.data`/`part.data` for the
   matched sessions.
5. **Correlate by timestamp.** Relate commits and sessions that fall close
   together in time so a topic can cite both.
6. **Redact.** Before writing anything, run the redaction filter over any
   session-derived text: detect `client_secret`, `bearer`, `api_key`,
   `token`, and long hex/base64 strings that look like secrets. Redact matches
   in any quoted material, and mark the owning topic with a **Flagged** note
   describing why.
7. **Synthesise candidate topics** using the template in the parent spec
   (title, why interesting, sources = sessions + commits, estimated depth,
   angle, optional Flagged note) plus the appendix of raw sources.
8. **Write DRAFT.** Write `inputs/topics-YYYY-Www.md` (ISO week) with
   `Status: DRAFT`.
9. **Ask a short question.** Summarise counts (projects, sessions, commits,
   topic count, any flagged) and point at the file. Never embed the file
   contents in the `question` call.
10. **Finalise on approval.** On explicit approval, `edit` the `Status` row
    `DRAFT → FINAL`. On change requests, edit the file directly and re-ask.

### SQL constraints

- Every `sqlite3` invocation uses `-readonly`.
- Window filters use the indexed `time_updated` column; no full-table scans.
- Verified schema: `session(id, project_id, directory, title, slug, agent,
  model, time_created, time_updated, ...)`, `message(id, session_id, data,
  time_created, ...)`, `part(id, message_id, session_id, data, ...)`.

## Acceptance Criteria

- [ ] Invoking with "extract topics from last week" produces
      `inputs/topics-YYYY-Www.md` with `Status: DRAFT`.
- [ ] With `tracked-projects.txt` present and non-empty, only listed projects
      are considered.
- [ ] With `tracked-projects.txt` absent/empty, projects are auto-discovered
      from the DB and confirmed via `question` before extraction.
- [ ] The topics file matches the parent spec's template (frontmatter table,
      candidate topics with sources, appendix).
- [ ] Commits and sessions are correlated by timestamp within each topic's
      Sources.
- [ ] Secret-like patterns are redacted and their topics carry a Flagged note.
- [ ] Approval via `question` flips `Status` to `FINAL`; the file body is
      never embedded in the question.
- [ ] All DB access uses `sqlite3 -readonly` and filters on `time_updated`.
- [ ] The agent never writes outside `inputs/**` and never writes an article.

## Edge Cases & Error Handling

- **No commits in window for a project**: skip silently, note in appendix.
- **No sessions in window for a project**: skip silently, note in appendix.
- **Project directory deleted from disk**: warn, skip.
- **Non-git tracked directory**: skip git gathering, still use sessions.
- **opencode DB missing/locked**: surface a clear error; do not fall back to
  write access.
- **Zero topics found**: still write a DRAFT file stating the empty result
  rather than silently doing nothing.
- **Sensitive keyword detected**: Flagged note added; user decides in review.

## Dependencies & Constraints

- Requires Step 01 (permissions, scaffold).
- Requires `git` and `sqlite3` on PATH and the opencode DB present.

## Out of Scope

- Writing any article (that is the blog-writer's job, step 04).
- Editing source projects.

## Notes

- Correlation is heuristic (time proximity); the skill should be transparent
  about which commits/sessions it linked.
- Keep the redaction regexes conservative but note that review + the
  allowlist gate are the real safety net.
