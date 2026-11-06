#!/bin/sh
# Output-tree helpers shared by tools/build-release.sh and tools/build-directory.sh, sourced by
# both. The sourcing script defines fail MESSAGE (prints MESSAGE with its own prefix, exits 1);
# prepare_output sets OUT, which the copy helpers write under.

# DIR: succeeds when DIR has no entry, hidden ones included.
directory_is_empty() {
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    if [ -e "$entry" ] || [ -L "$entry" ]; then
      return 1
    fi
  done
  return 0
}

# DIR: creates DIR when absent (it must otherwise be an empty directory); sets OUT to its
# absolute path.
prepare_output() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    [ -d "$1" ] && directory_is_empty "$1" || fail "$1 exists and is not an empty directory"
  fi
  mkdir -p "$1" || fail "cannot create $1"
  OUT=$(CDPATH='' cd -- "$1" && pwd) || fail "cannot enter $1"
}

# PATH: creates the parent directory of PATH under OUT.
make_parent() {
  target_dir=${1%/*}
  [ "$target_dir" = "$1" ] || mkdir -p "$OUT/$target_dir" || fail "cannot create $OUT/$target_dir"
}

# PATH [SOURCE]: copies SOURCE (default: PATH) to PATH under OUT.
copy_file() {
  source_path=${2:-$1}
  [ -f "$source_path" ] || fail "missing shipped file $source_path"
  make_parent "$1"
  cp "$source_path" "$OUT/$1" || fail "cannot copy $source_path"
}

# DIR: copies the repository directory DIR to the same relative path under OUT.
copy_directory() {
  [ -d "$1" ] || fail "missing shipped directory $1"
  make_parent "$1"
  cp -R "$1" "$OUT/$1" || fail "cannot copy $1"
}
