# Step 05 — End-to-End Acceptance

| Field         | Value                                                  |
|---------------|--------------------------------------------------------|
| **Title**     | End-to-End Acceptance                                  |
| **Type**      | feature                                                |
| **Scope**     | integration verification of the whole project          |
| **Created**   | 2026-07-22 00:00:00                                    |
| **Status**    | IMPLEMENTED                                            |
| **Parent**    | specs/blog-writer-project.md                           |
| **Step**      | 5 of 5                                                 |

## Problem Statement

With scaffold, both agents, both skills, and `CONVENTIONS.md` in place, I need
a single pass that verifies the whole system satisfies every acceptance
criterion — including the security boundaries that must actively reject
disallowed actions.

## Desired Outcome

A documented, repeatable acceptance procedure (and, where feasible, automated
checks) that exercises the full workflow end to end and confirms every
guarantee in the parent spec.

### Scenarios to verify

1. **Fresh-clone readiness.** After filling `CONVENTIONS.md`, the project is
   usable with no other setup. `tracked-projects.txt` remains optional.
2. **Extractor DRAFT.** Invoke `topic-extractor` with "extract topics from
   last week". Assert `inputs/topics-YYYY-MM-DD.md` is created with
   `Status: DRAFT`, correct frontmatter table, candidate topics with correlated
   commit+session sources, and an appendix.
3. **Auto-discovery path.** With `tracked-projects.txt` absent, assert the
   extractor auto-discovers projects from the DB and confirms the list via
   `question` before writing.
4. **Allowlist path.** With `tracked-projects.txt` present, assert only listed
   projects appear.
5. **Redaction/flagging.** Seed a session (or fixture) containing a secret-like
   string; assert it is redacted and its topic carries a **Flagged** note.
6. **Topics finalise.** Approve via `question`; assert `Status` flips to
   `FINAL` and no file body was embedded in the question.
7. **Blog draft.** Invoke `blog-writer` with "write about topic 2". Assert it
   reads the right topic, reads `CONVENTIONS.md`, and creates
   `drafts/<slug>.mdx` with `draft: true`.
8. **Bilingual sequence.** Assert English is drafted/iterated first, then the
   Italian `<Lang value="it">` block and Italian frontmatter are added; final
   file has both `<Lang>` blocks and a valid bilingual frontmatter with
   `tags` in `{id,label:{en,it}}` shape.
9. **MDX vocabulary.** Assert only allowed components appear (`<Lang>`,
   `<TOCInline>`, `lang:filename` code fences, footnotes, `<video>`, images).
10. **Article finalise.** Approve; assert frontmatter `draft:` flips to
    `false`.
11. **Publish on command.** "publish <slug>"; assert the file moves to
    `published/<slug>.mdx` with `draft: false`; a publish for a nonexistent
    slug warns and does nothing.
12. **Missing conventions guard.** Remove/blank `CONVENTIONS.md`; assert
    blog-writer asks and refuses to draft.
13. **Permission boundaries (must reject).**
    - topic-extractor attempting to write outside `inputs/**` → rejected.
    - blog-writer attempting to write outside
      `drafts/**`/`inputs/**`/`published/**` → rejected.
    - blog-writer attempting to edit a source project → refused.
14. **Destructive/remote git denied (must reject).** `git push`,
    `git commit --amend`, `rm -rf` are denied for both agents.
15. **Read-only DB.** Assert all extractor DB access uses `sqlite3 -readonly`
    and filters on the indexed `time_updated` column (no full-table scans of
    `session`).

## Acceptance Criteria

- [ ] Every scenario 1–15 has a documented check with an observed PASS.
- [ ] Each parent-spec acceptance criterion maps to at least one scenario.
- [ ] Permission-boundary and destructive-command scenarios demonstrate an
      actual runtime rejection, not just intent.
- [ ] The procedure is repeatable on a fresh clone and documented in
      `README.md` (or a linked `docs/acceptance.md`).

## Edge Cases & Error Handling

- **Empty activity window**: extractor still writes a DRAFT stating the empty
  result; blog-writer can still take a free-text topic.
- **DB unavailable during test**: procedure notes the prerequisite and fails
  fast with a clear message.
- **Fixtures vs. live data**: prefer fixtures/temp copies for the redaction and
  auto-discovery checks to keep tests deterministic and avoid depending on the
  live DB contents.
- **Tracked project deleted from disk**: assert the extractor warns and skips
  that project rather than aborting the run.
- **Empty commit/session window for a project**: assert it is skipped silently
  and noted in the topics appendix.

## Dependencies & Constraints

- Requires Steps 01–04 complete.
- Uses `sqlite3 -readonly` throughout; never mutates the live opencode DB.

## Out of Scope

- New functionality (this step only verifies).
- Live deployment of published articles.

## Notes

- Where full automation is impractical (agent conversations), document a
  precise manual script with expected observations; automate the mechanical
  checks (file existence, frontmatter values, permission rejections, SQL
  read-only usage).
