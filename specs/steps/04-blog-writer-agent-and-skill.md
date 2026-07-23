# Step 04 — blog-writer Agent & write-blog-article Skill

| Field         | Value                                                  |
|---------------|--------------------------------------------------------|
| **Title**     | blog-writer Agent & write-blog-article Skill           |
| **Type**      | feature                                                |
| **Scope**     | `.opencode/agents/blog-writer.md` + `.opencode/skills/write-blog-article/SKILL.md` |
| **Created**   | 2026-07-22 00:00:00                                    |
| **Status**    | IMPLEMENTED                                            |
| **Parent**    | specs/blog-writer-project.md                           |
| **Step**      | 4 of 5                                                 |

## Problem Statement

I need a writer agent that turns a chosen topic into a publish-ready bilingual
MDX article in my voice, matching my blog's exact file format, iterating with
me, and moving the file to `published/` only when I say so.

## Desired Outcome

A primary agent `blog-writer` backed by a `write-blog-article` skill that
drafts `drafts/<slug>.mdx`, iterates, and publishes on command.

### Agent (`.opencode/agents/blog-writer.md`)

- `mode: primary`.
- Frontmatter permissions per step 01 (read anywhere; edit `drafts/**`,
  `inputs/**`, `published/**`; bash git/sqlite allow + publish move; destructive
  deny).
- Prompt body: role, invariants, and hard anti-hijack rules — produces ONLY
  articles in `drafts/` (moved to `published/` on explicit command), NEVER
  edits source projects, NEVER commits or pushes.
- Loads the `write-blog-article` skill.

### Skill (`.opencode/skills/write-blog-article/SKILL.md`)

Workflow:

1. **Load conventions.** Read `CONVENTIONS.md`. If missing, or if it is still
   an all-placeholder template, ask the user via `question` and refuse to draft
   until at least a real placeholder file exists.
2. **Resolve the topic.**
   - "write about topic N" → read the current/most-recent `inputs/topics-*.md`,
     select topic N, carry over its title, angle, depth, and sources.
   - Free-text topic → use as-is.
3. **Derive a slug** (kebab-case) and target path `drafts/<slug>.mdx`.
4. **Draft English first.** Write the article body in English per
   `CONVENTIONS.md` (structure, voice, taboos), using ONLY the allowed MDX
   vocabulary: `<Lang value="en">`, `<TOCInline toc={props.toc} .../>`, code
   fences with `lang:filename`, footnotes, `<video>`, images, standard
   markdown. Assemble the frontmatter with `draft: true`, per-language
   `title`/`summary` (English filled, Italian placeholder for now), `date`,
   `lastmod`, `tags`, and `images`. Tag `id` and `label:{en,it}` values are
   drawn from the tag vocabulary authored in `CONVENTIONS.md` (Step 03), not
   invented ad hoc.
5. **Iterate on English.** Write to disk, then ask a short `question`
   (summary + word count + file path — never embed the body). Apply requested
   changes by editing the file directly. Repeat until the user approves the
   English body.
6. **Translate to Italian.** Produce the Italian `title`/`summary` and a full
   `<Lang value="it">` body that faithfully translates the approved English,
   honouring the bilingual policy in `CONVENTIONS.md` (e.g. don't translate
   code identifiers/strings). Assemble the single `.mdx` with both `<Lang>`
   blocks.
7. **Confirm the assembled bilingual draft.** Short `question` again; iterate
   as needed. The file stays `draft: true`.
8. **Finalise on approval.** On explicit approval, `edit` frontmatter
   `draft: true → false`.
9. **Publish on command.** On explicit "publish <slug>": ensure
   `draft: false`, then move `drafts/<slug>.mdx` → `published/<slug>.mdx`
   using only the permitted file tools or a permitted `mv` (per the Step 01
   permissions — never a destructive command). Never auto-publish. If no
   draft exists for the slug, warn and do nothing.

### Output format (must match exactly)

Bilingual MDX with the frontmatter and `<Lang>` structure defined in the parent
spec's "article-<slug>.mdx output structure" section. `draft:` is the on-disk
DRAFT marker (no separate Status table).

## Acceptance Criteria

- [ ] "write about topic 2" reads the correct topic from `inputs/topics-*.md`,
      reads `CONVENTIONS.md`, and creates `drafts/<slug>.mdx` with
      `draft: true`.
- [ ] The English body is drafted and iterated to approval before Italian is
      produced.
- [ ] The final `.mdx` contains both `<Lang value="en">` and
      `<Lang value="it">` blocks and a bilingual frontmatter (`title`,
      `summary`, `tags` with `{id,label:{en,it}}`, `date`, `lastmod`, `draft`,
      `images`).
- [ ] Only the allowed MDX component vocabulary is used.
- [ ] Approval flips frontmatter `draft:` to `false`; the body is never
      embedded in a `question`.
- [ ] "publish <slug>" moves the file from `drafts/` to `published/` with
      `draft: false`.
- [ ] Missing/placeholder `CONVENTIONS.md` causes the agent to ask and refuse
      to draft.
- [ ] The agent never writes outside `drafts/**`, `inputs/**`, `published/**`,
      never edits source projects, never commits/pushes.

## Edge Cases & Error Handling

- **`CONVENTIONS.md` missing or all-placeholder**: ask via `question`, refuse
  to draft.
- **Referenced topic number out of range / no topics file**: ask the user to
  clarify or supply a free-text topic.
- **Italian requested before English approved**: finish and confirm English
  first, then translate.
- **Publish requested for a slug with no draft**: warn, do nothing.
- **Slug collision with an existing draft/published file**: ask before
  overwriting.
- **User asks the writer to edit a source project or to commit/push**: refuse
  per anti-hijack rules.
- **Editing an already-published or previously-dated article**: refresh
  `lastmod` to the edit date (leave the original `date` unchanged).

## Dependencies & Constraints

- Requires Step 01 (permissions) and Step 03 (`CONVENTIONS.md`).
- Consumes `inputs/topics-*.md` produced by Step 02 (but also accepts
  free-text topics, so Step 02 is not strictly required to draft).
- Output must match the target Tailwind/Next.js MDX blog format.

## Out of Scope

- Generating the topics file (step 02).
- Deploying `published/` articles to a live site.
- Languages beyond EN/IT.

## Notes

- Keep every `question` short; the article body can be many KB.
- Word count in any summary is computed from the English body unless the user
  asks otherwise.
