# Command-Scoped Codex Workflows

## Context

Blog-Writer currently expects the main Codex chat to delegate bounded topic,
conventions, and article operations to project custom agents. Each custom-agent
TOML file configures one local MCP bridge profile so the child sees only the
tools for its role.

The bridge profiles themselves work and advertise the correct isolated tool
catalogs. The current Codex Desktop and CLI runtimes, however, do not reliably
propagate the custom agent's `mcp_servers` configuration into the spawned
session. Desktop creates the child without the bridge tools. Non-interactive
CLI probes either omit the child or fail to materialize an ephemeral parent
thread. The workflow therefore stops before project discovery or article
persistence.

## Goal

Provide supported Codex commands that complete the existing review-driven
topic and article workflows without depending on custom-agent MCP propagation.
The commands must retain the project's privacy, least-privilege, DRAFT-first,
approval, and publication boundaries.

Success means a user can run:

```text
./bin/blog-writer-codex topics "last week"
./bin/blog-writer-codex article "topic 2"
```

The first command creates a reviewable topic DRAFT through the topic bridge
profile. After the existing review and finalization gate, the second creates a
reviewable bilingual article DRAFT through the writer profile. Publication
still requires a later explicit publish instruction.

## Non-goals

- Do not change OpenCode behavior or configuration.
- Do not expose all bridge profiles in the repository's global Codex config.
- Do not make topic extraction automatically start article writing.
- Do not bypass project confirmation, overwrite, review, finalization, or
  publication approvals.
- Do not remove the project custom agents; they remain available for runtimes
  that correctly support role-scoped MCP propagation.
- Do not add scheduling, automation, commits, pushes, or source-project writes.

## Selected approach

Add one repository launcher with two subcommands. Each subcommand starts a new
interactive Codex CLI session from the repository root, in a read-only sandbox,
with exactly one `blog_writer_bridge` MCP profile supplied as invocation-scoped
configuration:

- `topics` attaches the `topic` profile.
- `article` attaches the `writer` profile.

The launcher uses the current Codex CLI, does not select a model explicitly,
does not use ephemeral mode, and avoids the shared Desktop daemon. This keeps
model selection within the user's supported runtime configuration and prevents
stale daemon state from weakening invocation-scoped isolation.

The main Codex session owns the conversation and calls the attached narrow
bridge directly. Repository skills gain a command-scoped execution mode that
is active only when the expected exact bridge tool surface is callable in the
main session. Existing custom-agent delegation remains the fallback when the
main session does not have the matching profile.

## Command interface

### Topic extraction

```text
./bin/blog-writer-codex topics [time-window words...]
```

- With arguments, the words are passed as the requested time window.
- Without arguments, the prompt requests the skill's existing seven-day
  default.
- The command starts an interactive session so project confirmation, overwrite
  choices, DRAFT review, revisions, and final approval remain conversational.
- The prompt names `extract-topics`, identifies command-scoped mode, and forbids
  custom-agent delegation for that run.

### Article writing

```text
./bin/blog-writer-codex article <topic reference or free-text subject...>
```

- A subject is required. Missing input exits with usage text before Codex is
  launched.
- The prompt names `write-blog-article`, includes the subject, identifies
  command-scoped mode, and forbids custom-agent delegation for that run.
- English-first drafting, review, Italian translation, assembly, finalization,
  and explicit publication remain owned by the existing skill.

### Common launcher behavior

The launcher:

1. Resolves the repository root from its own location.
2. Validates that `codex`, `node`, the bridge entrypoint, and installed bridge
   dependencies are available.
3. Selects exactly one fixed profile from the recognized subcommand; callers
   cannot supply a profile name or arbitrary MCP command.
4. Starts Codex with the repository as its working directory, a read-only
   sandbox, no shared daemon, and invocation-scoped MCP configuration.
5. Propagates Codex's exit status and prints actionable prerequisite errors.

Unknown subcommands and missing required article input fail before model or MCP
startup.

## Skill behavior

`extract-topics` and `write-blog-article` each document two mutually exclusive
execution modes:

1. **Command-scoped mode:** the main session has the exact matching
   `blog_writer_bridge` profile because it was launched by the repository
   command. The main session performs the bridge operations while retaining
   all user questions and approval gates.
2. **Custom-agent mode:** the main session lacks the matching bridge profile,
   so it delegates bounded operations to the existing custom agent exactly as
   today.

Command-scoped mode must reject or stop if cross-role bridge tools are visible.
It must not use shell or general filesystem writes as a substitute for bridge
operations. The skill's source-reading and mutation boundaries remain
unchanged.

The launcher prompt selects command-scoped mode explicitly. Merely seeing an
MCP-looking tool is insufficient; the expected profile tools must be present
and no bridge tool from another role may be present.

## Data flow

### Topics

```text
user command
  -> interactive Codex main session
  -> extract-topics skill
  -> topic-profile bridge operations
  -> project confirmation and synthesis in chat
  -> inputs/topics-YYYY-MM-DD.md with Status: DRAFT
  -> explicit approval
  -> marker-only FINAL transition
```

### Article

```text
user command
  -> interactive Codex main session
  -> write-blog-article skill
  -> writer-profile bridge operations
  -> English DRAFT review
  -> Italian translation and bilingual DRAFT review
  -> drafts/<slug>.mdx with draft: true
  -> explicit finalization approval
  -> later, separate explicit publish instruction
  -> published/<slug>.mdx and published-topic ledger update
```

Topic finalization does not trigger article creation. Article finalization does
not trigger publication.

## Security and privacy boundaries

- The repository `.codex/config.toml` remains read-only and contains no global
  privileged bridge registration.
- Each command exposes one fixed profile only. Topic and writer tools never
  coexist in one launcher-created session.
- The main shell remains read-only; all intended writes pass through the fixed,
  profiled bridge operations.
- The topic profile retains bounded, redacted history and confirmed-project
  rules. Source projects remain read-only.
- The writer profile retains fixed Blog-Writer output paths and has no general
  shell, arbitrary file, Git mutation, commit, or push tool.
- User-provided topic or time-window text is prompt data only. It cannot alter
  the MCP command, profile, server path, or Codex configuration arguments.

## Error handling

- Missing `codex`, Node.js, bridge dependencies, or bridge entrypoint: fail
  locally with a concise prerequisite message.
- Unsupported subcommand or missing article subject: print usage and exit
  non-zero without launching Codex.
- Bridge startup or tool-catalog mismatch: stop the workflow and report the
  missing or unexpected tools; never fall back to shell writes or unbounded
  history access.
- Existing output target: preserve the skill's explicit overwrite question.
- Missing or placeholder-only conventions: preserve the article skill's refusal
  to draft.
- Codex model or service error: propagate the failed command status; do not
  silently switch models.

## Verification

Offline verification will cover:

- launcher usage and argument validation;
- exact fixed MCP command/profile arguments for each subcommand using a fake
  `codex` executable that records invocation arguments;
- rejection of unknown subcommands and missing article subjects before launch;
- unchanged exact bridge tool catalogs and cross-role isolation;
- skill text and acceptance checks for both execution modes;
- the bridge CLI starting when its entrypoint is reached through a filesystem
  alias;
- the full existing deterministic test suite.

The opt-in live verifier will add command-scoped probes in an isolated fixture
and `CODEX_HOME`. Each probe requires structured evidence that the main session
called the expected profile tool with exact fixture arguments, produced the
fixture effect, and could not call a cross-role bridge tool. The existing
custom-agent live probe remains diagnostic for upstream runtime support but is
not the acceptance gate for the command-scoped workflow.

## Documentation

The README and acceptance guide will:

- present the command-scoped launcher as the reliable Codex path;
- retain the ordinary Desktop/custom-agent instructions as conditional on a
  runtime that propagates custom-agent MCP configuration;
- show the topic-review-article sequence and its separate approvals;
- document prerequisites, command examples, failure messages, and opt-in live
  verification;
- continue to describe OpenCode independently and unchanged.

## Compatibility and migration

No existing drafts, topics, published articles, conventions, ledgers, bridge
formats, or OpenCode files change. Existing custom-agent files remain valid.
The launcher is additive, and removing it later does not require data
migration. Once local Codex runtimes reliably propagate custom-agent MCP
configuration, the project may make delegation the primary path again without
changing content formats or bridge handlers.
