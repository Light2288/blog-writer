---
name: extract-topics
description: Use when the user asks to extract, surface, or find candidate blog topics from recent Codex and Git activity.
---

# Extract Topics

Coordinate a reviewable candidate-topic extraction from recent Codex and Git
activity. Source projects and Codex history are always read-only. The only
output is `inputs/topics-YYYY-MM-DD.md`, written with `Status: DRAFT` and
changed to `FINAL` only after explicit user approval.

Delegate only to `topic-extractor`. The main chat owns every user question,
project confirmation, overwrite choice, review, and approval. Never ask a custom agent to question the user. Give the custom agent bounded operations;
it returns concise structured results and never owns the conversation.

## Workflow

Follow these ten steps in order.

### 1. Resolve the time window

Default to the last 7 days and accept natural-language or explicit-date
overrides. Convert the result to Unix-millisecond bounds `(lo, hi]`.

Use the run's local date for `inputs/topics-YYYY-MM-DD.md`. Record the resolved
window, the ISO week containing the window end, and a local
`Generated: YYYY-MM-DD HH:MM` value inside the file. Never derive the filename
from the window or ISO week.

### 2. Resolve tracked projects

Read `tracked-projects.txt`:

- If it has non-comment, non-blank lines, normalize and deduplicate those paths
  and use them as the allowlist. Resolve relative entries against the Blog-Writer project root, then pass only absolute paths to the bridge.
- Otherwise delegate `discover_projects` with `lo` and `hi` to
  `topic-extractor`. In the main chat, show only the discovered directory list
  and bridge warnings, then ask the user to confirm or edit the list. Do not
  collect activity until a non-empty discovered list is confirmed. An explicit
  user choice of an empty list ends with a normal empty DRAFT.

Missing or unsupported Codex history is an error. Do not silently fall back to
Git-only evidence. Missing, inactive, or non-Git confirmed projects may be
skipped only when their bounded bridge warning is carried forward.

### 3. Gather normalized activity

Delegate `collect_activity` with `(lo, hi]` and the exact confirmed project
paths. Depend only on the returned normalized activity records:
`source`, `project_dir`, `timestamp`, `kind`, `id`, `title`, `text`, and
`metadata`. Do not read rollout JSON, an internal Codex database, or an
OpenCode database directly.

Preserve the returned `warnings` and `stats`. The bridge already bounds and
redacts Codex prose before returning it.

### 4. Separate sessions and commits

Treat records with `source: codex` / `kind: session` as session evidence and
records with `source: git` / `kind: commit` as commit evidence. Use only the
bounded `text`, titles, identifiers, timestamps, and metadata returned by the
bridge. Count each class from the bridge result rather than estimating it.

### 5. Correlate by project and timestamp

Relate sessions and commits that occur close together within the same project.
Correlation is heuristic. Every candidate's Sources must list the exact short
session IDs and `<project>@<short-sha>` commits actually used.

### 5b. Exclude already-published topics

Read `inputs/published-topics.md` when present and scan `published/*.mdx`
frontmatter for `topic_key`. Exclude a candidate when either source contains
its normalized topic key; drafts never exclude it. Derive `topic_key` by
lowercasing the working title, converting runs of non-alphanumeric characters
to `-`, and trimming repeated/edge hyphens. Keep possible near-duplicates but
flag the overlap for review. Record every exclusion in the excluded appendix.

### 6. Carry redaction flags and warnings

Never try to reverse or replace bridge redaction. When a session record has
`metadata.redacted: true`, add a **Flagged** note to every candidate that uses
it and name only its safe `metadata.redaction_reasons`. When metadata reports
truncation, say so in the raw-sources appendix.

Carry every bridge warning into `Appendix: bridge warnings`; preserve its safe
code/message and safe file or project context. Never include raw malformed
records or secret-like source text in the appendix or review question.

### 7. Synthesize and score candidates

For every candidate include a working title, topic key, why it is interesting,
Sources, estimated depth, angle, optional Flagged note, and this Evaluation:

| Dimension | Score |
|---|---:|
| Reader appeal | 0-10 |
| Technical depth | 0-10 |
| Storytelling | 0-10 |
| Uniqueness | 0-10 |
| Publishability | 0-10 |
| **Overall** | **average, one decimal** |

Lower Publishability for flagged or confidentiality-constrained material.
Sort descending by Overall, then Reader appeal, then editorial judgment.

### 8. Persist the DRAFT

Compose the complete file using the format below, with exactly one
`Status: DRAFT`. If today's target already exists, the main chat asks whether
to overwrite it; pass `overwrite: true` only after that explicit choice.
Delegate `write_topic_draft` with the run date, full content, and approved
overwrite flag. Even when no candidate remains, write the normal DRAFT with a
plain "No new candidate topics found in this window" result and appendices.

### 9. Ask a short review question

In the main chat, summarize only the project, session, commit, candidate, and
flagged counts; mention warning/exclusion counts and point to the file. Never
embed the file body or large markdown in a question. On requested changes,
recompose the file, delegate `write_topic_draft` with the user's overwrite
approval, and ask again.

### 10. Finalize on approval

Only after explicit user approval, delegate `finalize_topics` for the run date.
This is the only finalization path and changes only the status marker. Report
the resulting path. Without approval, leave `Status: DRAFT` untouched.

## Topics file format

```text
# Topic candidates — 2026-07-26 (ISO week 2026-W30)

| Field       | Value                      |
|-------------|----------------------------|
| Window      | 2026-07-20 to 2026-07-26   |
| ISO week    | 2026-W30                   |
| Generated   | 2026-07-26 14:30           |
| Projects    | app, library               |
| Sessions    | 12 (see appendix)          |
| Commits     | 34 (see appendix)          |
| Status      | DRAFT                      |

> Evaluation legend: Reader appeal, Technical depth, Storytelling,
> Uniqueness, and Publishability are scored 0-10. Overall is their average.

## Candidate topics

### Topic 1: <working title>
- **Topic key**: <kebab-case-key>
- **Why interesting**: <one or two sentences>
- **Sources**:
  - Sessions: <short-id>, ...
  - Commits: <project>@<short-sha>, ...
- **Estimated depth**: short / medium / long
- **Angle**: retrospective / tutorial / opinion / deep-dive / ...
- **Evaluation**: <five-row table plus Overall>
- **Flagged**: <only for bridge-redacted or constrained evidence>

## Appendix: raw sources
- <bounded session and commit references; note truncation>

## Appendix: bridge warnings
- <safe warning code and message, or "None">

## Appendix: excluded (already published)
- <topic-key> — <reason/source, or "None">
```
