---
name: daguild
description: >
  Force the daguild delegation walk on a task that looks trivial. The walk itself
  (classify, dispatch to daguild:investigator / daguild:builder / daguild:architect /
  daguild:reviewer / daguild:security / daguild:scribe, terminal tokens, review loop)
  is the session's default operating procedure, injected at session start, so
  ordinary coding requests never need this skill. Use only when the user types
  /daguild explicitly.
argument-hint: <task to force through the DAG>
---

Walk the `## Operating procedure (default mode)` already present in the session context for `$ARGUMENTS` (or the user's last request), starting at Step 1 with the inline shortcut disabled: the user invoked this skill to force delegation, so "answer inline" is not a valid route this time. `DAG.md` beside this file is binding as always.

When `## Operating procedure (default mode)` is absent from the session context (switch `procedure.default_mode` off), first Read `context/procedure.md` from the plugin root (two directories above this skill's directory) and walk it.
