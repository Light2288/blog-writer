# Codex Desktop Workflows

**Slug:** `codex-desktop-workflows`
**Type:** feature
**Status:** APPROVED
**Provenance:** User request in this conversation to make all existing Blog-Writer operations available directly in Codex desktop; `AGENTS.md`; `docs/superpowers/specs/2026-09-28-codex-chatgpt-support-design.md`; `docs/superpowers/specs/2026-09-28-command-scoped-codex-workflows-design.md`.

## Problem

The user wants to extract topics, maintain writing conventions, and write,
review, finalize, and publish bilingual articles from an ordinary Codex desktop
chat in this project. These workflows currently stop when their custom agents
do not receive the configured bridge tools. Repeating a prompt or changing the
requested time window does not supply those missing capabilities.

## Current Behavior

- The project configuration enables custom agents but does not register the
  bridge in the parent session.
- Each of the three custom-agent files declares its own MCP bridge profile.
  Current official Codex documentation says that agent-local `mcp_servers`
  settings do not override the parent session; the server must be configured
  in the parent session instead.
- Topic extraction and article writing support a command-scoped path through
  the CLI launcher, with exactly four tools for the selected workflow.
  Ordinary chats fall back to custom-agent delegation. Conventions persistence
  also depends on a custom agent.
- The bridge already implements nine bounded operations across its topic,
  conventions, and writer profiles. Existing handlers enforce source-project
  allowlists, file paths, generated-file limits, and publication validation.
- `publish_article` moves a finalized draft into `published/` and updates
  `inputs/published-topics.md`, avoiding duplicate topic-key entries. A manual
  file move does not update that ledger.

## Desired Outcome

After installing the existing bridge dependencies, trusting the project, and
restarting Codex, the user can invoke any existing workflow in the same desktop
chat without launching a separate CLI session or changing bridge profiles.

Examples include:

- "Use extract-topics to find topics from last week."
- "Use author-conventions to update my writing conventions."
- "Use write-blog-article to draft topic 1 from this extracted topics file."
- Requests to revise a draft, approve English, translate to Italian, approve
  the bilingual article, finalize it, or explicitly publish its slug.

The main chat retains the conversation and every existing review and approval
gate. Making publication tools available does not authorize publication.

## Selected Design

### One project-registered desktop bridge

Add one fixed `desktop` profile to the existing bridge and register it as
`blog_writer_bridge` in the project's `.codex/config.toml`. Its exact catalog is
the union of the existing operations:

| Workflow | Operations |
|---|---|
| Topics | `discover_projects`, `collect_activity`, `write_topic_draft`, `finalize_topics` |
| Conventions | `write_conventions` |
| Articles | `read_source_file`, `write_article_draft`, `finalize_article`, `publish_article` |

Reuse the existing handlers and tool argument schemas. The desktop profile
adds a supported registration surface, not a general-purpose file or command
interface. Its registration is project-scoped; the update must not edit the
user's global Codex configuration, credentials, or model preferences.

Bridge startup must resolve the code location reliably when the desktop app's
working directory differs from the repository root. Configuration must remain
portable across checkout locations. Workflow artifacts continue to resolve
through the Git common directory to the primary checkout, including when code
runs from a linked worktree.

### Direct execution by all three skills

Update `extract-topics`, `author-conventions`, and `write-blog-article` to call
their matching bridge operations directly from the main session. Ordinary
desktop invocation selects desktop mode when the canonical bridge exposes
exactly the nine-operation catalog. The presence of the other workflows'
known tools in desktop mode must not cause a skill to reject that valid
catalog. Each active skill still uses only its own operations.

An explicit launcher-selected command mode continues to require the selected
workflow's exact narrow catalog. Missing tools, unexpected bridge operations,
or a mismatched catalog stop the workflow with a concise explanation and
relevant setup or restart guidance. There is no custom-agent or shell fallback
for bridge history access, fact checks, or mutations.

Preserve the existing topic review and scoring workflow, incremental
conventions interview, English-first article review, translation, bilingual
review, finalization, overwrite approvals, and explicit publication command.

### Remove the obsolete custom-agent dependency

Remove the three project custom-agent definitions and the skills' delegation
paths. Update project instructions and verification contracts so they no longer
require agent-local MCP registration or claim agent-specific MCP isolation.
Remove project configuration settings that exist only to support those agents.

The main session remains read-only for ordinary shell and filesystem access.
All intended workflow mutations continue through the bounded bridge tools.

### Preserve CLI compatibility and publication behavior

Keep the existing `topics` and `article` launcher interfaces. Their invocation
configuration overrides the same canonical bridge registration with the
existing topic or writer profile, so command-scoped sessions retain their
narrow catalogs even after the desktop profile becomes the project default.

Keep the conventions-only bridge profile available. Existing narrow profiles
must not gain operations from other workflows.

Publication remains an explicit operation that moves the requested finalized
article and updates its ledger together. Preserve the existing metadata,
duplicate prevention, collision checks, and rollback behavior. Do not add a
folder watcher or manual-move reconciliation command.

## Acceptance Criteria

- **AC-01 — Desktop registration:** A trusted ordinary desktop project chat,
  after restart and with dependencies installed, receives exactly the nine
  desktop bridge operations without the launcher or a custom agent. All three
  skills can select direct desktop execution in the same chat.
- **AC-02 — Topic workflow:** Topic extraction preserves project confirmation,
  bounded normalized activity, redaction flags and warnings, published-topic
  exclusion, scoring, DRAFT persistence, overwrite approval, and explicit
  marker-only finalization.
- **AC-03 — Conventions workflow:** Conventions can be created and updated
  directly through `write_conventions`, preserving the focused interview,
  incremental persistence approval, unaffected sections, and final review.
- **AC-04 — Article workflow:** Articles can be fact-checked, drafted, revised,
  translated, finalized, and explicitly published through the main session.
  English approval precedes Italian translation; bilingual review and explicit
  publication authorization remain required. Finalization alone does not
  publish an article.
- **AC-05 — Publication ledger:** Publishing an approved finalized article
  moves it into `published/` and records its topic key, slug, and publication
  date in `inputs/published-topics.md` without duplicate topic-key entries.
  Manual file moves remain outside ledger bookkeeping. Publication failures
  retain the existing rollback and error-reporting guarantees.
- **AC-06 — Boundaries:** Existing source allowlists, redaction, path checks,
  generated-file limits, symlink protections, overwrite checks, and published
  slug collision checks remain enforced. No arbitrary shell, file-access, or
  caller-supplied project-root tool is introduced. Source projects and runtime
  history remain read-only.
- **AC-07 — Compatibility and roots:** Existing CLI commands retain their
  narrow catalogs and exit behavior, the conventions-only profile remains
  available, OpenCode behavior is unchanged, and linked worktrees continue
  reading and writing workflow data in the primary checkout.
- **AC-08 — Actionable failures:** Missing, partial, or unexpected bridge
  catalogs produce clear errors and applicable prerequisite or restart
  guidance. No skill silently delegates to an unsupported custom agent,
  reads raw history directly, or simulates bridge mutations with file tools.
- **AC-09 — Verification and documentation:** Automated fixture checks cover
  the desktop catalog and all three workflow families, while narrow-profile
  isolation checks remain. The opt-in runtime verifier exercises direct
  parent-session desktop configuration across multiple workflows and requires
  correlated tool calls and file effects. Documentation distinguishes those
  checks from a manual desktop restart and smoke test; neither static checks
  nor assistant claims alone establish desktop success.

## Edge Cases and Failure Modes

- Missing Node.js, bridge dependencies, project trust, or server initialization
  must be reported as setup failures; an empty tool catalog is not successful
  initialization of a workflow.
- A partial desktop catalog or additional unknown bridge operation is invalid.
  Unrelated MCP servers outside the Blog-Writer bridge are not part of its
  catalog validation.
- An explicitly selected narrow CLI mode must not silently accept the wider
  desktop catalog.
- Existing topic files and article drafts require overwrite approval. Existing
  published slugs remain protected from replacement.
- Missing or placeholder-only conventions still prevent article drafting.
- Missing or unsupported history remains an error; extraction must not silently
  switch to Git-only evidence.
- Source-project selection and approval are not inferred merely from a bridge
  tool being available.
- Restarting or resuming a chat does not itself authorize finalization,
  overwriting, or publication.

## Constraints

- Preserve existing shared artifact formats and real writing conventions.
- Do not change OpenCode configuration, skills, or behavior.
- Add no schedules, background watchers, source-project mutations, or global
  Codex settings.
- Retain the existing bridge handlers' validation and bounded access; expose
  only the fixed desktop union and the existing narrow profiles.
- Keep user-facing questions, prose authoring, translation, and approval gates
  in the main chat.
- Historical approved specifications remain historical inputs. Update current
  runtime instructions, architecture documentation, and acceptance guidance to
  describe the new supported behavior.

## Out of Scope

- Automatic ledger updates after manual file moves or a reconciliation command.
- Editing or replacing already-published articles through this workflow.
- Deploying articles to the live blog or changing its application.
- New article formats, MDX components, topic scoring rules, or history sources.
- Automatic topic-to-article transitions or unattended publication.
- Changes to topic-file selection rules, batch article authoring, or article
  content as part of this project update.

## Verification and Rollout

Extend bridge unit and SDK integration coverage for the exact desktop catalog,
handler reuse, safe failures, and representative topic, conventions, and
article operations against temporary fixture data. Retain the existing path,
history, redaction, publication, and narrow-profile regression coverage.

Update static scaffold, acceptance, and launcher checks to verify parent
registration, direct skill routing, removal of custom-agent dependencies, and
CLI overrides of the desktop default. Extend the opt-in live verifier to load
the trusted project's desktop configuration and prove direct main-session
operations from multiple workflows in one session. Live probes must use
isolated workflow data and synthetic history rather than real articles or
the user's history.

Update setup instructions with dependency installation, project trust, restart,
tool-catalog inspection, supported prompts, and actionable troubleshooting.
After implementation, a desktop restart and smoke test must confirm actual
desktop tool availability. Report any unavailable live verification explicitly
instead of treating offline tests as proof of desktop support.

No migration or modification of existing conventions, topics, drafts, or
published articles is required for the configuration update.

## Notes and Approval Sequence

The user selected one desktop bridge, direct main-chat execution with removal
of the three project custom agents, and preservation of publish-command ledger
bookkeeping without manual-move reconciliation.

Official documentation consulted during discovery:

- [Custom agents inherit parent MCP configuration](https://learn.chatgpt.com/docs/agent-configuration/subagents).
- [Project-scoped MCP configuration and restart](https://learn.chatgpt.com/docs/extend/mcp?surface=app).
- [Project configuration and relative paths](https://learn.chatgpt.com/docs/config-file/config-advanced).

This specification remains DRAFT until explicit approval of the written file.
Only after that approval may the implementation plan be created. The plan
requires separate explicit approval before updating `main`, creating the
implementation branch, or changing product files. Work directly in the
existing checkout; do not create a worktree unless requested. Keep the spec
and plan uncommitted until the implementation branch exists, then implement,
verify, and commit there. Do not push or merge unless requested.
