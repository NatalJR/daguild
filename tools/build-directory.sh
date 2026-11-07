#!/bin/sh
# Builds the Claude Directory edition of daguild from the working tree: the plugin with no hooks,
# because the Directory refuses hooks of type command from a non-verified publisher.
# Usage: sh tools/build-directory.sh OUTDIR   (OUTDIR must be absent or an empty directory)
#
# - copied verbatim: .claude-plugin/marketplace.json, .claude-plugin/icon.png, LICENSE,
#   .gitattributes, agents/, skills/git/, skills/daguild/DAG.md, charter/TEMPLATE.md,
#   charter/SCHEMA.md. workflows/ is not shipped: the Directory validator holds workflow
#   JavaScript as scripts it cannot follow.
# - agents/: each shipped agents/<name>.md must pin in its frontmatter the model and effort that
#   are the defaults of <name>_model and <name>_effort in .claude-plugin/plugin.json (the render
#   hook may have rewritten the working-tree agents from a maintainer's options). The `skills`
#   frontmatter key (skill preloading) is dropped with its continuation lines; every other line is
#   kept byte for byte.
# - .claude-plugin/plugin.json: every userConfig member whose key ends in _model or _effort is
#   dropped (only the render hook applies them); git_handling stays (the git skill substitutes it);
#   every other line is kept byte for byte, bar the comma of the member that ends up last.
# - edition text edits (apply_edition_edits below): literal replacements in the copied files; each old
#   text must occur exactly once in its file.
# - skills/daguild/SKILL.md and README.md: the overlays under editions/directory/.
# - output-styles/daguild.md: editions/directory/output-style.md, a blank line, context/always-on.md,
#   a blank line, context/procedure.md, both parts rendered by hooks/session-context.sh with the
#   shipped switch defaults; procedure.md alone renders with git handling on, so the commit line
#   names the daguild git skill (which deactivates itself when the user's option is off) while
#   always-on.md lists no changed switch; HOME and the project directory point at a fresh empty
#   directory. The user selects the style as `daguild:daguild` (per project, or for every project
#   via outputStyle in ~/.claude/settings.json) (the Directory refuses force-for-plugin from a
#   non-verified publisher), and the harness does not substitute ${CLAUDE_PLUGIN_ROOT} inside an
#   output style, so the rendered plugin root followed by / becomes `<daguild>/`.
# A missing input, an agent pin that differs from its option default, an edit whose old text does
# not occur exactly once, an empty render, a render that keeps a {{ marker, the plugin root or a
# `## DaGuild switches changed` section, a plugin.json that still declares a model or effort
# option, lacks git_handling or has a comma
# before a closing } or ], or a tree that holds hooks/, a file declaring a command hook, or a
# frontmatter whose opener is not exactly ---, that holds a control character other than tab, whose
# top-level lines are not plain keys (a key's colon followed by whitespace or the line end), that lacks
# name or description, or that holds a key outside its kind's accepted list fails the build (exit 1;
# the tree is left for inspection).
# Helpers: tools/lib/build-tree.sh.
# Dependencies: sh, awk, cat, cp, mkdir, mktemp, mv, rm, find, grep, tr.
set -u

OVERLAY_DIR=editions/directory
RENDERER=hooks/session-context.sh
ROOT_PLACEHOLDER='<daguild>/'
RENDER_DIR=''
# The frontmatter keys the Directory accepts per file kind from a non-verified publisher (observed
# 2026-11-06); any other key is finding LOCAL_CODE_FRONTMATTER_KEY.
AGENT_FRONTMATTER_KEYS='name description tools model effort'
SKILL_FRONTMATTER_KEYS='name description argument-hint'
OUTPUT_STYLE_FRONTMATTER_KEYS='name description keep-coding-instructions'

fail() {
  printf 'build-directory: %s\n' "$1" >&2
  exit 1
}

# The directory of this script, which locates tools/lib/.
script_directory() {
  script_dir=${0%/*}
  [ "$script_dir" != "$0" ] || script_dir=.
  printf '%s' "$script_dir"
}

. "$(script_directory)/lib/build-tree.sh"

# TEXT PART: succeeds when TEXT holds PART.
contains() {
  contains_rest=${1#*"$2"}
  [ "$contains_rest" != "$1" ]
}

copy_shipped_files() {
  copy_file .claude-plugin/marketplace.json
  copy_file .claude-plugin/icon.png
  copy_file LICENSE
  copy_file .gitattributes
  for shipped_dir in agents skills/git; do
    copy_directory "$shipped_dir"
  done
  copy_file skills/daguild/DAG.md
  copy_file charter/TEMPLATE.md
  copy_file charter/SCHEMA.md
}

copy_overlay_files() {
  copy_file skills/daguild/SKILL.md "$OVERLAY_DIR/skills/daguild/SKILL.md"
  [ -f "$OVERLAY_DIR/README.md" ] || fail "missing $OVERLAY_DIR/README.md, the edition's README"
  copy_file README.md "$OVERLAY_DIR/README.md"
}

# FILE: prints the frontmatter lines of FILE (between a first-line --- and the next ---), CR
# stripped.
frontmatter() {
  awk '
    { sub(/\r$/, "") }
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside { print }
  ' "$1"
}

# FILE KEY: prints the value of the top-level KEY in the frontmatter of FILE.
frontmatter_value() {
  frontmatter "$1" | awk -v key="$2" '
    index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      print value
      exit
    }
  '
}

# OPTION: prints the default of the userConfig member OPTION in the repository's plugin.json.
option_default() {
  awk -v key="\"$1\": {" '
    { sub(/\r$/, "") }
    index($0, key) { inside = 1; next }
    inside && /^    [}]/ { exit }
    inside && match($0, /"default": "[^"]*"/) { print substr($0, RSTART + 12, RLENGTH - 13); exit }
  ' .claude-plugin/plugin.json
}

# AGENT KEY: fails unless the frontmatter KEY of agents/AGENT.md under OUT equals the default of
# the AGENT_KEY option.
check_agent_pin() {
  pinned=$(frontmatter_value "$OUT/agents/$1.md" "$2")
  wanted=$(option_default "$1_$2")
  [ -n "$wanted" ] || fail "agent $1: plugin.json has no default for $1_$2"
  [ "$pinned" = "$wanted" ] || fail "agent $1: $2 [$pinned] differs from the $1_$2 default [$wanted]"
}

check_agent_pins() {
  for agent_file in "$OUT"/agents/*.md; do
    agent_name=${agent_file##*/}
    agent_name=${agent_name%.md}
    check_agent_pin "$agent_name" model
    check_agent_pin "$agent_name" effort
  done
}

# FILE KEY: succeeds when the frontmatter of FILE has the top-level KEY.
has_frontmatter_key() {
  frontmatter "$1" | grep -q -E "^$2[[:space:]]*:([[:space:]]|$)"
}

# FILE KEY: prints FILE without the top-level frontmatter KEY and its continuation lines (indented,
# `- ` items, # comments or blank); every other line is printed as read.
without_frontmatter_key() {
  awk -v key="$2" '
    { line = $0; sub(/\r$/, "", line) }
    NR == 1 && line == "---" { inside = 1; print; next }
    inside && line == "---" { inside = 0 }
    inside && dropping && line ~ /^([ \t]|- |#|$)/ { next }
    { dropping = 0 }
    inside && index(line, key) == 1 && substr(line, length(key) + 1) ~ /^[ \t]*:([ \t]|$)/ { dropping = 1; next }
    { print }
  ' "$1"
}

# FILE KEY: removes the top-level KEY from the frontmatter of FILE through a temporary file in the
# same directory, rewriting FILE in place so it keeps its mode; FILE is left untouched when it
# lacks KEY.
drop_frontmatter_key() {
  has_frontmatter_key "$1" "$2" || return 0
  dropped=$(mktemp "$1.XXXXXX") || fail "cannot create a temporary file next to $1"
  without_frontmatter_key "$1" "$2" >"$dropped" || { rm -f "$dropped"; fail "cannot drop $2 from $1"; }
  cat "$dropped" >"$1" || { rm -f "$dropped"; fail "cannot rewrite $1"; }
  rm -f "$dropped" || fail "cannot remove $dropped"
}

# The Directory refuses skill preloading from a non-verified publisher: the shipped agents lose
# their skills key and invoke those skills through the Skill tool.
drop_agent_skill_preloads() {
  for agent_file in "$OUT"/agents/*.md; do
    drop_frontmatter_key "$agent_file" skills
  done
}

# FILE OLD NEW: replaces the one occurrence of OLD in FILE under OUT with NEW, both literal; fails
# unless OLD occurs exactly once.
replace_once() {
  edited="$OUT/$1"
  [ -f "$edited" ] || fail "missing edited file $1"
  OLD_TEXT=$2 NEW_TEXT=$3 awk '
    BEGIN { old = ENVIRON["OLD_TEXT"]; replacement = ENVIRON["NEW_TEXT"] }
    {
      rest = $0
      replaced = ""
      while ((at = index(rest, old)) > 0) {
        found++
        replaced = replaced substr(rest, 1, at - 1) replacement
        rest = substr(rest, at + length(old))
      }
      lines[NR] = replaced rest
    }
    END {
      if (found != 1) exit 1
      for (i = 1; i <= NR; i++) print lines[i]
    }
  ' "$edited" >"$edited.edited" || { rm -f "$edited.edited"; fail "[$2] does not occur exactly once in $1"; }
  mv "$edited.edited" "$edited" || fail "cannot rewrite $1"
}

# The edition's text edits, one per line: file, old text, new text.
apply_edition_edits() {
  replace_once skills/daguild/DAG.md 'injected into every session (`context/procedure.md`)' \
    'carried into every session by the daguild output style once selected (`/output-style daguild:daguild`)'
  replace_once skills/daguild/DAG.md ' (user-adjustable through the plugin options)' ''
  replace_once skills/daguild/DAG.md \
    ' Workflow scripts follow the same rule: no `effort` on `daguild:*` agents; a value only on the default workflow agent.' ''
  replace_once .claude-plugin/plugin.json \
    "Let daguild handle git: a generic git skill plus a guard hook that denies AI attribution, --no-verify and forced pushes. Off: your project's own git conventions apply." \
    "Let daguild handle git through its generic git skill. Off: your project's own git conventions apply."
}

# Fails when a line of the shipped plugin.json ending in a comma is directly followed by a line
# whose first non-blank character is } or ].
check_manifest_shape() {
  dangling_comma=$(awk '
    { sub(/\r$/, "") }
    previous_comma && /^[ \t]*[]}]/ { print FNR; exit }
    { previous_comma = $0 ~ /,$/ }
  ' "$OUT/.claude-plugin/plugin.json") || fail 'cannot read the shipped plugin.json'
  [ -z "$dangling_comma" ] || fail "plugin.json line $dangling_comma closes right after a trailing comma"
}

# Prints .claude-plugin/plugin.json without the userConfig members (at a four-space indent) whose
# key ends in _model or _effort; the last kept member's closing line loses its comma, the others
# keep one.
strip_agent_options() {
  awk '
    function bare(text) { sub(/\r$/, "", text); return text }
    # TEXT with its trailing comma present when WANTED, absent otherwise; a CR stays last.
    function with_comma(text, wanted,   cr) {
      cr = text ~ /\r$/ ? "\r" : ""
      sub(/\r$/, "", text)
      sub(/,$/, "", text)
      return text (wanted ? "," : "") cr
    }
    function member_key(text) {
      match(text, /"[^"]+"/)
      return substr(text, RSTART + 1, RLENGTH - 2)
    }
    function buffer(text) { buffered[++buffered_count] = text }
    function flush(   i) {
      for (i = 1; i <= buffered_count; i++) {
        if (i in closes) print with_comma(buffered[i], i != last_close)
        else print buffered[i]
      }
    }
    function start_member(text) {
      dropping = member_key(text) ~ /_(model|effort)$/
      state = "member"
      if (!dropping) buffer(text)
    }
    function member_line(text) {
      if (!dropping) buffer(text)
      if (bare(text) !~ /^    [}],?$/) return
      if (!dropping) { closes[buffered_count] = 1; last_close = buffered_count }
      state = "config"
    }
    function config_line(text) {
      if (bare(text) ~ /^  [}]/) { flush(); print text; state = "outside" }
      else if (bare(text) ~ /^    "[^"]+": [{]$/) start_member(text)
      else buffer(text)
    }
    BEGIN { state = "outside" }
    state == "member" { member_line($0); next }
    state == "config" { config_line($0); next }
    { print }
    bare($0) ~ /^  "userConfig": [{]$/ { state = "config" }
  ' .claude-plugin/plugin.json
}

write_plugin_manifest() {
  manifest="$OUT/.claude-plugin/plugin.json"
  [ -f .claude-plugin/plugin.json ] || fail 'missing shipped file .claude-plugin/plugin.json'
  make_parent .claude-plugin/plugin.json
  strip_agent_options >"$manifest" || fail 'cannot write .claude-plugin/plugin.json'
  ! grep -q -E '_(model|effort)"' "$manifest" || fail 'plugin.json still declares a model or effort option'
  grep -q -F '"git_handling"' "$manifest" || fail 'plugin.json lacks git_handling'
}

# Prints stdin with every ROOT_FORWARD followed by / replaced by ROOT_PLACEHOLDER.
replace_root() {
  DAGUILD_ROOT="$ROOT_FORWARD/" DAGUILD_PLACEHOLDER=$ROOT_PLACEHOLDER awk '
    BEGIN { root = ENVIRON["DAGUILD_ROOT"]; placeholder = ENVIRON["DAGUILD_PLACEHOLDER"] }
    {
      rest = $0
      replaced = ""
      while ((at = index(rest, root)) > 0) {
        replaced = replaced substr(rest, 1, at - 1) placeholder
        rest = substr(rest, at + length(root))
      }
      print replaced rest
    }
  '
}

# PART GIT_HANDLING: runs the renderer on PART with the shipped defaults and
# CLAUDE_PLUGIN_OPTION_GIT_HANDLING set to GIT_HANDLING (unset when empty); sets RENDERED.
run_renderer() {
  RENDERED=$(
    unset CLAUDE_PLUGIN_OPTION_GIT_HANDLING
    [ -z "$2" ] || export CLAUDE_PLUGIN_OPTION_GIT_HANDLING="$2"
    CLAUDE_PLUGIN_ROOT=$REPO_ROOT HOME=$RENDER_DIR CLAUDE_PROJECT_DIR=$RENDER_DIR \
      sh "$REPO_ROOT/$RENDERER" "$1"
  )
}

# PART GIT_HANDLING: prints context PART rendered, the plugin root written as ROOT_PLACEHOLDER.
render_part() {
  run_renderer "$1" "$2"
  [ -n "$RENDERED" ] || fail "rendering $1 printed nothing"
  placed=$(printf '%s\n' "$RENDERED" | replace_root) || fail "cannot replace the plugin root in $1"
  ! contains "$placed" '{{' || fail "rendered $1 keeps a {{ marker"
  ! contains "$placed" "$ROOT_FORWARD" || fail "rendered $1 still names the plugin root $ROOT_FORWARD"
  ! contains "$placed" '## DaGuild switches changed' || fail "rendered $1 lists changed switches"
  printf '%s\n' "$placed"
}

make_render_dir() {
  RENDER_DIR=$(mktemp -d) || fail 'cannot create a temporary directory'
  trap 'rm -rf "$RENDER_DIR"' EXIT
}

write_output_style() {
  header="$OVERLAY_DIR/output-style.md"
  [ -f "$header" ] || fail "missing $header"
  make_parent output-styles/daguild.md
  make_render_dir
  {
    cat "$header" || fail "cannot read $header"
    printf '\n'
    render_part context/always-on.md ''
    printf '\n'
    render_part context/procedure.md true
  } >"$OUT/output-styles/daguild.md"
}

# KEYS KEY: succeeds when the space-separated KEYS holds KEY.
listed() {
  case " $1 " in *" $2 "*) return 0 ;; esac
  return 1
}

# FILE: prints the top-level keys of the frontmatter of FILE, one per line.
frontmatter_keys() {
  frontmatter "$1" | grep -E '^[A-Za-z0-9_-]+[[:space:]]*:([[:space:]]|$)' | awk -F: '{ key = $1; sub(/[ \t]+$/, "", key); print key }'
}

# FILE: succeeds when line 1 of FILE, CR stripped, starts with a UTF-8 byte order mark or starts
# with --- without being exactly ---.
has_malformed_frontmatter_opener() {
  LC_ALL=C awk '
    NR == 1 { sub(/\r$/, ""); malformed = index($0, "\357\273\277") == 1 || (index($0, "---") == 1 && $0 != "---"); exit }
    END { exit !malformed }
  ' "$1"
}

# FILE: prints the first frontmatter line of FILE that does not start with a space and is neither
# blank, a # comment, a `- ` item nor a plain key (a line starting with a tab is reported).
first_unplain_frontmatter_line() {
  frontmatter "$1" | awk '
    /^$/ || /^ / || /^#/ || /^- / || /^[A-Za-z0-9_-]+[[:space:]]*:([[:space:]]|$)/ { next }
    { print; exit }
  '
}

# FILE: succeeds when the frontmatter of FILE, trailing CRs stripped, holds a control character
# other than tab.
frontmatter_has_control_character() {
  frontmatter "$1" | tr -d '\t\n' | LC_ALL=C grep -q '[[:cntrl:]]'
}

# FILE: fails unless FILE opens with exactly --- and its frontmatter holds no control character but
# tab and is plain top-level keys that include name and description.
check_frontmatter_shape() {
  ! has_malformed_frontmatter_opener "$1" || fail "$1: frontmatter opener is not exactly --- (LOCAL_CODE_FRONTMATTER_KEY)"
  ! frontmatter_has_control_character "$1" ||
    fail "$1: frontmatter holds a control character (LOCAL_CODE_FRONTMATTER_KEY)"
  unplain_line=$(first_unplain_frontmatter_line "$1")
  [ -z "$unplain_line" ] || fail "$1: frontmatter line $unplain_line is not a plain key (LOCAL_CODE_FRONTMATTER_KEY)"
  for required_key in name description; do
    has_frontmatter_key "$1" "$required_key" ||
      fail "$1: frontmatter lacks $required_key or is not recognized (LOCAL_CODE_FRONTMATTER_KEY)"
  done
}

# FILE ACCEPTED: fails when the frontmatter of FILE is not plain keys with name and description or a
# top-level frontmatter key of FILE is not in the space-separated ACCEPTED.
check_frontmatter_keys() {
  check_frontmatter_shape "$1"
  for frontmatter_key in $(frontmatter_keys "$1"); do
    listed "$2" "$frontmatter_key" ||
      fail "$1: frontmatter key $frontmatter_key is outside the Directory's accepted list (LOCAL_CODE_FRONTMATTER_KEY)"
  done
}

# ACCEPTED FILE...: checks every FILE that exists against the space-separated ACCEPTED keys.
check_kind_frontmatter_keys() {
  accepted_keys=$1
  shift
  for shipped_file in "$@"; do
    [ -f "$shipped_file" ] || continue
    check_frontmatter_keys "$shipped_file" "$accepted_keys"
  done
}

check_accepted_frontmatter_keys() {
  check_kind_frontmatter_keys "$AGENT_FRONTMATTER_KEYS" "$OUT"/agents/*.md
  check_kind_frontmatter_keys "$SKILL_FRONTMATTER_KEYS" "$OUT"/skills/*/SKILL.md
  check_kind_frontmatter_keys "$OUTPUT_STYLE_FRONTMATTER_KEYS" "$OUT"/output-styles/*.md
}

check_no_hooks() {
  [ ! -e "$OUT/hooks" ] || fail 'the tree holds hooks/'
  command_hooks=$(find "$OUT" -type f -exec grep -l -E '"type"[[:space:]]*:[[:space:]]*"command"' {} +)
  [ -z "$command_hooks" ] || fail "files declare a command hook: $command_hooks"
  check_accepted_frontmatter_keys
}

[ "$#" -eq 1 ] && [ -n "$1" ] || fail 'usage: sh tools/build-directory.sh OUTDIR'
prepare_output "$1"
REPO_ROOT=$(CDPATH='' cd -- "$(script_directory)/.." && pwd) || fail 'cannot locate the repository'
cd "$REPO_ROOT" || fail "cannot enter $REPO_ROOT"
ROOT_FORWARD=$(printf '%s' "$REPO_ROOT" | tr '\\' '/')
copy_shipped_files
check_agent_pins
drop_agent_skill_preloads
write_plugin_manifest
copy_overlay_files
apply_edition_edits
check_manifest_shape
write_output_style
check_no_hooks
printf 'files: %s\n' "$(find "$OUT" -type f | awk 'END { print NR }')"
