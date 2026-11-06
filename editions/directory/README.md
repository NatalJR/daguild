# daguild

daguild is a delegation crew of six specialist agents (investigator, builder, architect, reviewer, security and scribe) and the operating procedure that routes every coding request through them. Project knowledge never lives in the plugin. It lives in a per-project charter file that every agent reads first, so the same crew works in any repository.

This is the Claude Directory edition: it has no hooks and runs no scripts. The full edition, with hooks, lives in the same GitHub repository, linked at the end of this page.

To install the full edition manually, run `claude plugin marketplace add NatalJR/daguild`, then `/plugin install daguild@daguild` inside Claude Code. Install exactly one edition: both register the same `daguild:*` agents and skills, so uninstall this one first.

## How this edition works

- **Output style:** an output style named `daguild`, applied automatically while the plugin is enabled. It carries the reply style, the universal code rules and the operating procedure, and Claude Code sends it with every request. While the plugin is enabled it replaces any output style you selected; disable the plugin to return to yours.
- **The `daguild` skill:** loads the delegation graph and gives the plugin's paths. `/daguild <task>` forces the full walk on a request that looks trivial.
- **The `git` skill:** conventional commits, one commit per logical change, no AI attribution, and no pushes without an explicit request. The git handling option shapes it.
- **Charter template:** a project plugs in through `.claude/daguild.md`, copied from the template the `daguild` skill points to.

## Install

Install from the Claude Directory in Claude Code (`/plugin`). Then copy the charter template into your project as `.claude/daguild.md` and fill in every section.

Claude Code only: output styles and agents do not load in Claude chat.

## Configuration

One plugin option: git handling, off by default. It is asked at install and changed later in `/config`.

Agents run on pinned models and efforts:

- **investigator:** haiku, medium
- **builder:** opus, medium
- **architect:** opus, high
- **reviewer:** opus, high
- **security:** fable, high
- **scribe:** sonnet, medium

## Differences from the full edition

- No per-prompt reminder. The output style is sent with every request instead.
- No `daguild.conf` switches. The procedure ships with every switch at its default.
- No git guard blocking AI attribution, skipped commit checks or forced pushes.
- No emoji scan of written files.
- No receipt check on subagent reports.
- No per-agent model and effort options.
- No workflows. `/daguild:cleanup-audit` and `/daguild:review-wave` ship only in the full edition.

The rules behind those checks still reach Claude as instructions. Nothing enforces them.

## What the plugin runs, reads and writes

- **Runs:** nothing. No hooks, no scripts, no MCP servers, no package launcher.
- **Reads:** nothing on its own. The agents and skills read files only through Claude Code's tools, under your permission settings.
- **Writes:** nothing on its own. The same rule applies.
- **Sends:** nothing. No network access of any kind and no telemetry.
- **Personal data:** none read or stored.

License: MIT. The full documentation, with the delegation graph and every feature of the full edition, is in the [repository README](https://github.com/NatalJR/daguild#readme).
