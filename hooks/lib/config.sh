# DaGuild switch table (sourced by the daguild hooks; POSIX sh).
# Sources, later wins: <plugin root>/config/defaults.conf, ~/.claude/daguild.conf,
# <project>/.claude/daguild.conf. Missing files are skipped silently.
# Grammar per line: blank or `#` comment ignored; otherwise `name = value`, optional spaces
# around `=`, names matching ^[a-z][a-z0-9_.]*$, values on|off|true|false|yes|no in any case.
# Any other line (inline comments included) is ignored silently. The defaults file declares the
# known switches; a switch the defaults file does not declare is ignored in the user and project
# files and reads as on. Lines are only matched against that grammar, never expanded or executed.
# git.handling is not a conf switch: a line for it is ignored in every file, the defaults file
# included. The plugin option CLAUDE_PLUGIN_OPTION_GIT_HANDLING (install prompt or /config) is
# its only source: true|1|on|yes in any case is on, any other value is off, unset reads as off.
# The defaults file is read from ${CLAUDE_PLUGIN_ROOT} only; when it is unset no defaults file is
# read (the hooks exit before sourcing this file in that case). The release build compiles the
# defaults in: it replaces that read with one declare line per defaults file entry.
# The Claude Directory validator cannot read `case` statements, so every match below is a `[ ]`
# test on a parameter expansion.
set -u

DAGUILD_SWITCHES=''
DAGUILD_DEFAULTS=''
_DAGUILD_NL='
'
_DAGUILD_CR=$(printf '\r')

# Builds DAGUILD_SWITCHES: newline-separated name=on / name=off entries, one per switch.
# DAGUILD_DEFAULTS keeps the same table as declared by the defaults file alone.
daguild_config_load() {
  DAGUILD_SWITCHES=''
  # Release build anchor: the only code line naming the defaults file, replaced by generated
  # declare lines. Rewriting it or adding a second such line breaks the release build.
  [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || _daguild_config_read "${CLAUDE_PLUGIN_ROOT}/config/defaults.conf" declare
  DAGUILD_DEFAULTS=$DAGUILD_SWITCHES
  [ -z "${HOME:-}" ] || _daguild_config_read "$HOME/.claude/daguild.conf" override
  [ -z "${CLAUDE_PROJECT_DIR:-}" ] || _daguild_config_read "$CLAUDE_PROJECT_DIR/.claude/daguild.conf" override
  _daguild_option_apply
  return 0
}

# Returns 0 when switch NAME is on, 1 when off. A switch with no entry takes its built-in default.
daguild_switch() {
  _daguild_table_value "$DAGUILD_SWITCHES" "$1" || _daguild_builtin_default "$1"
  [ "$_daguild_value" = on ]
}

# Prints the name=on / name=off entries whose value differs from the shipped default, sorted by
# name, space separated; nothing when every switch holds its default.
daguild_changed_switches() {
  _daguild_changed=$(_daguild_changed_entries | LC_ALL=C sort -t '=' -k 1,1 | tr '\n' ' ')
  [ -z "$_daguild_changed" ] || printf '%s\n' "${_daguild_changed% }"
  return 0
}

_daguild_changed_entries() {
  printf '%s\n' "$DAGUILD_SWITCHES" | while IFS= read -r _daguild_entry; do
    [ -n "$_daguild_entry" ] || continue
    _daguild_default_value "${_daguild_entry%%=*}"
    [ "${_daguild_entry#*=}" = "$_daguild_value" ] || printf '%s\n' "$_daguild_entry"
  done
}

# Sets _daguild_value to NAME's shipped default: the defaults file entry, else the built-in one.
_daguild_default_value() {
  _daguild_table_value "$DAGUILD_DEFAULTS" "$1" || _daguild_builtin_default "$1"
}

# TABLE NAME: sets _daguild_value to NAME's state in TABLE; returns 1 when TABLE has no entry.
_daguild_table_value() {
  if _daguild_table_has "$1" "$2=on"; then
    _daguild_value=on
  elif _daguild_table_has "$1" "$2=off"; then
    _daguild_value=off
  else
    return 1
  fi
}

# TABLE ENTRY: succeeds when ENTRY is one whole line of TABLE.
_daguild_table_has() {
  _daguild_lines="$_DAGUILD_NL$1$_DAGUILD_NL"
  _daguild_rest=${_daguild_lines#*"$_DAGUILD_NL$2$_DAGUILD_NL"}
  [ "$_daguild_rest" != "$_daguild_lines" ]
}

# Built-in defaults for a switch no defaults file declares: git.handling is opt-in, the rest on.
_daguild_builtin_default() {
  _daguild_value=on
  [ "$1" != git.handling ] || _daguild_value=off
}

# FILE MODE: applies every valid line; MODE declare accepts new switches, override only known ones.
_daguild_config_read() {
  [ -f "$1" ] && [ -r "$1" ] || return 0
  _daguild_config_mode=$2
  while IFS= read -r _daguild_config_line || [ -n "$_daguild_config_line" ]; do
    _daguild_config_apply "$_daguild_config_line"
  done <"$1"
}

_daguild_config_apply() {
  _daguild_config_parse "$1" || return 0
  # git.handling comes from the plugin option only.
  [ "$_daguild_name" != git.handling ] || return 0
  _daguild_switch_known "$_daguild_name" || [ "$_daguild_config_mode" = declare ] || return 0
  _daguild_switch_store "$_daguild_name" "$_daguild_state"
}

# Sets _daguild_name and _daguild_state from a `name = value` line; returns 1 for any other line.
_daguild_config_parse() {
  _daguild_text=${1%"$_DAGUILD_CR"}
  [ "${_daguild_text#*=}" != "$_daguild_text" ] || return 1
  _daguild_trim "${_daguild_text%%=*}"
  _daguild_name=$_daguild_trimmed
  _daguild_trim "${_daguild_text#*=}"
  _daguild_is_name "$_daguild_name" && _daguild_parse_state "$_daguild_trimmed"
}

# Sets _daguild_trimmed to TEXT without its leading and trailing whitespace runs.
# Two steps per side: the directory validator cannot follow a parameter expansion nested in another.
_daguild_trim() {
  _daguild_lead=${1%%[![:space:]]*}
  _daguild_trimmed=${1#"$_daguild_lead"}
  _daguild_tail=${_daguild_trimmed##*[![:space:]]}
  _daguild_trimmed=${_daguild_trimmed%"$_daguild_tail"}
}

# Succeeds when NAME starts with a lowercase letter and holds only [a-z0-9_.].
_daguild_is_name() {
  [ "${1#[a-z]}" != "$1" ] || return 1
  [ "${1%%[!a-z0-9_.]*}" = "$1" ]
}

_daguild_parse_state() {
  if _daguild_is_on_word "$1"; then
    _daguild_state=on
  elif _daguild_is_off_word "$1"; then
    _daguild_state=off
  else
    return 1
  fi
}

# Succeeds when WORD is on, true or yes in any case.
_daguild_is_on_word() {
  [ -n "$1" ] || return 1
  [ -z "${1#[Oo][Nn]}" ] || [ -z "${1#[Tt][Rr][Uu][Ee]}" ] || [ -z "${1#[Yy][Ee][Ss]}" ]
}

# Succeeds when WORD is off, false or no in any case.
_daguild_is_off_word() {
  [ -n "$1" ] || return 1
  [ -z "${1#[Oo][Ff][Ff]}" ] || [ -z "${1#[Ff][Aa][Ll][Ss][Ee]}" ] || [ -z "${1#[Nn][Oo]}" ]
}

# Maps the git handling plugin option, when set, onto git.handling: 1 or an on word is on.
_daguild_option_apply() {
  [ -n "${CLAUDE_PLUGIN_OPTION_GIT_HANDLING+set}" ] || return 0
  _daguild_option=$CLAUDE_PLUGIN_OPTION_GIT_HANDLING
  if [ "$_daguild_option" = 1 ] || _daguild_is_on_word "$_daguild_option"; then
    _daguild_switch_store git.handling on
  else
    _daguild_switch_store git.handling off
  fi
}

_daguild_switch_known() {
  _daguild_lines="$_DAGUILD_NL$DAGUILD_SWITCHES$_DAGUILD_NL"
  _daguild_rest=${_daguild_lines#*"$_DAGUILD_NL$1="}
  [ "$_daguild_rest" != "$_daguild_lines" ]
}

_daguild_switch_store() {
  if _daguild_switch_known "$1"; then
    _daguild_switch_replace "$1" "$2"
  elif [ -z "$DAGUILD_SWITCHES" ]; then
    DAGUILD_SWITCHES="$1=$2"
  else
    DAGUILD_SWITCHES="$DAGUILD_SWITCHES$_DAGUILD_NL$1=$2"
  fi
}

# Rewrites the existing entry for NAME in place, keeping the table order.
_daguild_switch_replace() {
  _daguild_table="$_DAGUILD_NL$DAGUILD_SWITCHES$_DAGUILD_NL"
  _daguild_before=${_daguild_table%%"$_DAGUILD_NL$1="*}
  _daguild_after=${_daguild_table#*"$_DAGUILD_NL$1="}
  _daguild_after=${_daguild_after#*"$_DAGUILD_NL"}
  _daguild_table="$_daguild_before$_DAGUILD_NL$1=$2$_DAGUILD_NL$_daguild_after"
  _daguild_table=${_daguild_table#"$_DAGUILD_NL"}
  DAGUILD_SWITCHES=${_daguild_table%"$_DAGUILD_NL"}
}
