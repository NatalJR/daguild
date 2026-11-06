#!/bin/sh
# One-shot migration renaming the plugin from guild to daguild inside one git checkout: every
# tracked path holding a guild word is moved with git mv, then every tracked text file holding one
# is rewritten. It refuses the already-renamed plugin repository (its .claude-plugin/plugin.json
# declares the name daguild), whose README keeps the old word on purpose.
# Refuses, before any change, a checkout where git ls-files or git grep lists a quoted path name.
# Refuses, before any change, a run where a path the moves would create (a renamed directory or
# file) already exists.
# Refuses, before any change, a run whose touched paths (moves, rewrites) hold uncommitted changes:
# a path git diff HEAD or git ls-files --others (ignored files included) lists that equals a
# touched path or sits under a touched directory.
# Usage: sh tools/codemods/rename-to-daguild.sh REPO_ROOT
#
# Rules, case-sensitive, applied in this order; a boundary is any character outside [A-Za-z0-9]
# (underscore and punctuation included) or the start or end of the line:
# - R1: [Gg][Uu][Ii][Ll][Dd]: right after # or ^ becomes [Dd][Aa][Gg][Uu][Ii][Ll][Dd]:
# - R2: GUILD after a boundary and not followed by [A-Z0-9] becomes DAGUILD.
# - R3: Guild after a boundary and not followed by [a-z0-9] becomes DaGuild.
# - R4: guild after a boundary and not followed by [a-z0-9] becomes daguild (paths use R2 to R4).
# Each rule scans the line once, left to right, testing the boundaries against the original
# characters, so adjacent words sharing one boundary character are all rewritten; a rewritten
# word is preceded by a letter, so a second run on a consumer checkout changes nothing. Only
# tracked files are read; binary files and everything under tools/codemods/ (this script names the
# old word) are left alone. Contents go through a temp file copied back with cat, which keeps the
# file mode and every byte the rules do not rewrite: awk runs with BINMODE=3 because the awk of
# Git for Windows otherwise drops carriage returns (other awks hold it as an unused variable), and
# a final newline awk adds to a file that had none is trimmed.
# Prints one line per changed file and a final count; exits 0, or 1 on the first failure or on an
# interrupt (INT, TERM, HUP). A failure or interrupt after the first change reports on stderr that
# the checkout is partially migrated.
# Dependencies: sh, git, awk, grep, cat, cmp, mktemp, mv, rm, sort, tail.
set -u

EXCLUDED_PATHSPEC=':(exclude)tools/codemods/'
EXCLUDED_PATHS='^tools/codemods/'
WORK_DIR=''
CHANGED_LIST=''
CHANGE_PHASE=0

# rewrite replaces every OLD whose preceding character (empty at the line start) matches BEFORE
# and whose following character (empty at the line end) matches AFTER; rewrite_path_words applies
# R2 to R4.
REWRITE_FUNCTIONS='
  function at_boundary(previous, following, before, after) {
    return previous ~ before && following ~ after
  }
  function rewrite(text, old, new, before, after,   out, at, previous, character_before_rest) {
    out = ""
    while ((at = index(text, old)) > 0) {
      previous = at > 1 ? substr(text, at - 1, 1) : character_before_rest
      out = out substr(text, 1, at - 1)
      out = out (at_boundary(previous, substr(text, at + length(old), 1), before, after) ? new : old)
      character_before_rest = substr(old, length(old))
      text = substr(text, at + length(old))
    }
    return out text
  }
  function rewrite_path_words(text,   boundary) {
    boundary = "^[^A-Za-z0-9]?$"
    text = rewrite(text, "GUILD", "DAGUILD", boundary, "^[^A-Z0-9]?$")
    text = rewrite(text, "Guild", "DaGuild", boundary, "^[^a-z0-9]?$")
    return rewrite(text, "guild", "daguild", boundary, "^[^a-z0-9]?$")
  }
'

# Applies R2 to R4 when for_paths is 1, R1 to R4 otherwise.
REWRITE_PROGRAM="$REWRITE_FUNCTIONS"'
  {
    line = $0
    if (for_paths != 1)
      line = rewrite(line, "[Gg][Uu][Ii][Ll][Dd]:", "[Dd][Aa][Gg][Uu][Ii][Ll][Dd]:", "^[#^]$", "")
    print rewrite_path_words(line)
  }
'

# Prints the leading part of every input path up to its first component holding a guild word:
# a component the path rules change.
MOVE_SOURCES_PROGRAM="$REWRITE_FUNCTIONS"'
  function holds_guild_word(part) {
    return rewrite_path_words(part) != part
  }
  {
    count = split($0, parts, "/")
    prefix = parts[1]
    for (i = 1; i <= count && !holds_guild_word(parts[i]); i++) prefix = prefix "/" parts[i + 1]
    if (i <= count) print prefix
  }
'

# Prints, for every input path, each renamed leading part (directories and the path itself) that
# differs from the original leading part: every path the moves create.
RENAMED_PREFIXES_PROGRAM="$REWRITE_FUNCTIONS"'
  function add_component(part,   renamed_part) {
    renamed_part = rewrite_path_words(part)
    differs = differs || renamed_part != part
    renamed = renamed == "" ? renamed_part : renamed "/" renamed_part
    if (differs) print renamed
  }
  {
    renamed = ""
    differs = 0
    count = split($0, parts, "/")
    for (i = 1; i <= count; i++) add_component(parts[i])
  }
'

# Prints every input path equal to or under a line of the file touched.
DIRTY_PROGRAM='
  function is_at_or_under(path, root) {
    return path == root || index(path, root "/") == 1
  }
  function touches(path,   root, found) {
    found = 0
    for (root in roots) found = found || is_at_or_under(path, root)
    return found
  }
  BEGIN {
    while ((status = (getline root < touched)) > 0) roots[root] = 1
    if (status < 0) exit 2
  }
  touches($0) { print }
'

# Adds the partial-migration notice once the change phase has started.
report_partial_migration() {
  [ "$CHANGE_PHASE" -eq 1 ] || return 0
  printf 'rename-to-daguild: %s %s\n' 'the checkout is partially migrated; every path this run' \
    'touches had no uncommitted changes when it started, so git status shows only its changes there' >&2
}

fail() {
  printf 'rename-to-daguild: %s\n' "$1" >&2
  report_partial_migration
  exit 1
}

# Signal handler: removes the work directory and exits 1, warning about a partial migration.
interrupted() {
  rm -rf "$WORK_DIR"
  printf 'rename-to-daguild: %s\n' 'interrupted; the checkout may be partially migrated' >&2
  exit 1
}

# MESSAGE LIST: fails with MESSAGE followed by the lines of LIST when LIST is not empty.
refuse_when_listed() {
  [ -s "$2" ] || return 0
  printf 'rename-to-daguild: %s\n' "$1" >&2
  cat "$2" >&2
  exit 1
}

# PATH: succeeds when PATH exists, a dangling symbolic link included.
path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

# Prints the stdin lines naming a path that exists.
existing_paths() {
  while IFS= read -r listed_path; do
    ! path_exists "$listed_path" || printf '%s\n' "$listed_path"
  done
}

# FOR_PATHS: prints stdin with R2 to R4 applied when FOR_PATHS is 1, R1 to R4 otherwise.
rewrite_words() {
  LC_ALL=C awk -v BINMODE=3 -v for_paths="$1" "$REWRITE_PROGRAM"
}

# PATH: adds PATH to the changed-file list.
record_change() {
  printf '%s\n' "$1" >>"$CHANGED_LIST" || fail "cannot record $1"
}

# Writes every tracked path, one per line, to $WORK_DIR/tracked.
tracked_paths() {
  git -c core.quotePath=false ls-files >"$WORK_DIR/tracked" || fail 'cannot list tracked files'
}

# Writes every tracked path outside tools/codemods/, one per line, to $WORK_DIR/kept.
kept_paths() {
  tracked_paths
  LC_ALL=C grep -v -E -e "$EXCLUDED_PATHS" "$WORK_DIR/tracked" >"$WORK_DIR/kept"
  [ "$?" -le 1 ] || fail 'cannot filter the tracked files'
}

# Prints, once each, the leading part of every tracked path outside tools/codemods/ up to its
# first component holding a guild word: the files and directories one pass moves.
move_sources() {
  kept_paths
  LC_ALL=C awk "$MOVE_SOURCES_PROGRAM" "$WORK_DIR/kept" >"$WORK_DIR/prefixes" ||
    fail 'cannot find the paths to move'
  LC_ALL=C sort -u "$WORK_DIR/prefixes" || fail 'cannot sort the paths to move'
}

# SOURCE TARGET: prints one line per tracked file now under TARGET, moved from under SOURCE.
report_moves() {
  git -c core.quotePath=false --literal-pathspecs ls-files -- "$2" >"$WORK_DIR/moved" ||
    fail "cannot list $2"
  while IFS= read -r moved_file; do
    printf 'moved: %s -> %s\n' "$1${moved_file#"$2"}" "$moved_file"
    record_change "$moved_file"
  done <"$WORK_DIR/moved"
}

# SOURCE: prints the renamed SOURCE.
renamed_path() {
  printf '%s\n' "$1" >"$WORK_DIR/source" || fail "cannot rename $1"
  rewrite_words 1 <"$WORK_DIR/source" || fail "cannot rename $1"
}

# SOURCE TARGET: fails when TARGET already exists, since git mv would nest SOURCE inside it.
# Backstop only: refuse_existing_targets checks every target before the first move.
refuse_existing_target() {
  path_exists "$2" || return 0
  fail "cannot move $1 to $2: $2 already exists"
}

# SOURCE: moves SOURCE to its renamed path; fails (status 1) when SOURCE is already gone.
move_path() {
  path_exists "$1" || return 1
  target=$(renamed_path "$1") || exit 1
  refuse_existing_target "$1" "$target"
  git mv -- "$1" "$target" || fail "cannot move $1 to $target"
  report_moves "$1" "$target"
}

# One pass of moves; succeeds when it moved something.
move_pass() {
  move_sources >"$WORK_DIR/sources" || fail 'cannot list the paths to move'
  pass_moved=1
  while IFS= read -r move_source; do
    move_path "$move_source" && pass_moved=0
  done <"$WORK_DIR/sources"
  return "$pass_moved"
}

# Repeats passes until none moves anything: a moved directory may still hold a guild component.
move_paths() {
  while move_pass; do :; done
}

# FILE: succeeds when the last byte of FILE is a newline.
ends_with_newline() {
  [ -z "$(tail -c 1 -- "$1")" ]
}

# ORIGINAL REWRITTEN: drops the final newline awk may add to REWRITTEN when ORIGINAL has none.
keep_missing_final_newline() {
  if ends_with_newline "$1" || ! ends_with_newline "$2"; then
    return 0
  fi
  printf '%s' "$(cat "$2")" >"$2.trimmed" || fail "cannot trim $1"
  mv "$2.trimmed" "$2" || fail "cannot trim $1"
}

# FILE: writes FILE through the rules to $WORK_DIR/rewritten; succeeds when that changes FILE.
rewrites_file() {
  rewritten="$WORK_DIR/rewritten"
  rewrite_words 0 <"$1" >"$rewritten" || fail "cannot rewrite $1"
  keep_missing_final_newline "$1" "$rewritten"
  ! cmp -s -- "$1" "$rewritten"
}

# FILE: rewrites FILE through a temp file when a rule changes it.
rewrite_file() {
  rewrites_file "$1" || return 0
  cat "$WORK_DIR/rewritten" >"$1" || fail "cannot write $1"
  printf 'rewritten: %s\n' "$1"
  record_change "$1"
}

# Prints the tracked text files outside tools/codemods/ that may hold a word to rewrite.
candidate_files() {
  git -c core.quotePath=false grep -l -I -i -F -e guild -e '[Gg][Uu][Ii][Ll][Dd]:' \
    -- . "$EXCLUDED_PATHSPEC"
  [ "$?" -le 1 ] || fail 'cannot search the tracked files'
}

# Prints how many recorded paths still exist: a path moved twice leaves a stale first record.
count_changed_files() {
  LC_ALL=C sort -u "$CHANGED_LIST" >"$WORK_DIR/changed_sorted" ||
    fail 'cannot sort the changed files'
  existing_paths <"$WORK_DIR/changed_sorted" >"$WORK_DIR/existing" ||
    fail 'cannot list the changed files'
  awk 'END { print NR }' "$WORK_DIR/existing" || fail 'cannot count the changed files'
}

# Succeeds when the current directory is the already-renamed plugin repository itself.
is_renamed_plugin() {
  [ -f .claude-plugin/plugin.json ] &&
    LC_ALL=C grep -q -E -e '"name"[[:space:]]*:[[:space:]]*"daguild"' .claude-plugin/plugin.json
}

rewrite_files() {
  candidate_files >"$WORK_DIR/candidates"
  while IFS= read -r text_file; do
    rewrite_file "$text_file"
  done <"$WORK_DIR/candidates"
}

# Fails when git lists a tracked or candidate path quoted, which line reading would misread.
refuse_quoted_paths() {
  tracked_paths
  candidate_files >"$WORK_DIR/candidates"
  LC_ALL=C grep -h -E -e '^"' "$WORK_DIR/tracked" "$WORK_DIR/candidates" >"$WORK_DIR/quoted"
  [ "$?" -le 1 ] || fail 'cannot check the listed paths'
  refuse_when_listed 'git lists these paths quoted; rename them first:' "$WORK_DIR/quoted"
}

# Fails, before any move, when a path the moves would create already exists.
refuse_existing_targets() {
  kept_paths
  LC_ALL=C awk "$RENAMED_PREFIXES_PROGRAM" "$WORK_DIR/kept" >"$WORK_DIR/renamed" ||
    fail 'cannot rename the tracked paths'
  LC_ALL=C sort -u "$WORK_DIR/renamed" >"$WORK_DIR/targets" || fail 'cannot sort the renamed paths'
  existing_paths <"$WORK_DIR/targets" >"$WORK_DIR/existing_targets" ||
    fail 'cannot check the renamed paths'
  refuse_when_listed 'these renamed paths already exist; move them away first:' \
    "$WORK_DIR/existing_targets"
}

# FILE: adds FILE to $WORK_DIR/touched when a rule changes it.
touch_when_rewritten() {
  rewrites_file "$1" || return 0
  printf '%s\n' "$1" >>"$WORK_DIR/touched" || fail "cannot record $1"
}

# Writes every path the run will move or rewrite, on the original names, to $WORK_DIR/touched.
touched_paths() {
  move_sources >"$WORK_DIR/touched" || fail 'cannot list the paths to move'
  candidate_files >"$WORK_DIR/candidates"
  while IFS= read -r text_file; do
    touch_when_rewritten "$text_file"
  done <"$WORK_DIR/candidates"
}

# Writes the paths with staged or unstaged changes against HEAD to $WORK_DIR/uncommitted and the
# untracked paths, ignored ones included, to $WORK_DIR/untracked.
uncommitted_paths() {
  git -c core.quotePath=false diff --name-only --no-renames HEAD -- >"$WORK_DIR/uncommitted" ||
    fail 'cannot list the uncommitted changes'
  git -c core.quotePath=false ls-files --others >"$WORK_DIR/untracked" ||
    fail 'cannot list the untracked files'
}

# Fails when an uncommitted or untracked path equals or sits under a path the run will touch.
refuse_dirty_touched_paths() {
  touched_paths
  uncommitted_paths
  LC_ALL=C awk -v touched="$WORK_DIR/touched" "$DIRTY_PROGRAM" \
    "$WORK_DIR/uncommitted" "$WORK_DIR/untracked" >"$WORK_DIR/dirty" ||
    fail 'cannot compare the uncommitted paths with the touched paths'
  refuse_when_listed 'commit, stash or move away these uncommitted paths this run touches:' \
    "$WORK_DIR/dirty"
}

[ "$#" -eq 1 ] && [ -n "$1" ] || fail 'usage: sh tools/codemods/rename-to-daguild.sh REPO_ROOT'
root=$(git -C "$1" rev-parse --show-toplevel) || fail "$1 is not inside a git checkout"
cd -- "$root" || fail "cannot enter $root"
is_renamed_plugin &&
  fail "$root is the renamed daguild plugin itself; this one-shot migration is for guild checkouts"
WORK_DIR=$(mktemp -d) || fail 'cannot create a temporary directory'
trap 'rm -rf "$WORK_DIR"' EXIT
trap interrupted INT TERM HUP
CHANGED_LIST="$WORK_DIR/changed"
: >"$CHANGED_LIST" || fail 'cannot create the changed-file list'
refuse_quoted_paths
refuse_existing_targets
refuse_dirty_touched_paths
CHANGE_PHASE=1
move_paths
rewrite_files
CHANGE_PHASE=0
changed_count=$(count_changed_files) || exit 1
printf 'changed files: %s\n' "$changed_count"
