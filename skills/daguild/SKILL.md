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

1. If this session's context does not contain the section "Operating procedure (default mode)", tell the user that the daguild procedure is off until they run `/output-style daguild:daguild` in this project (or set `"outputStyle": "daguild:daguild"` in `~/.claude/settings.json` for every project). Then do not read DAG.md or dispatch `daguild:*` agents for this request; handle the request directly only if the user says to proceed without daguild.
2. Read `${CLAUDE_PLUGIN_ROOT}/skills/daguild/DAG.md` if this session has not read it yet. Its node rules and anti-edges are binding.
3. A project without `.claude/daguild.md` can start from the charter template at `${CLAUDE_PLUGIN_ROOT}/charter/TEMPLATE.md`.
4. When this invocation carries a task, walk the operating procedure from the daguild output style for it, even if it looks trivial.
