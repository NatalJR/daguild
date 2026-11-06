---
name: daguild
description: >
  Loads the daguild delegation graph (node rules, dispatch modes, anti-edges) and
  the plugin's paths. Invoke once per session before the first dispatch to a
  daguild:* agent, or when the user types /daguild <task> to force the delegation
  walk on a request that looks trivial.
argument-hint: <task to force through the DAG>
---

The daguild plugin's directory, written `<daguild>/` in the daguild output style, is `${CLAUDE_PLUGIN_ROOT}/`.

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/daguild/DAG.md` if this session has not read it yet. Its node rules and anti-edges are binding.
2. A project without `.claude/daguild.md` can start from the charter template at `${CLAUDE_PLUGIN_ROOT}/charter/TEMPLATE.md`.
3. When this invocation carries a task, walk the operating procedure from the daguild output style for it, even if it looks trivial.
