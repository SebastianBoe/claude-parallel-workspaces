#!/usr/bin/env bash
# symlink-memories.sh — replace one or more Claude Code project memory directories with
# symlinks to a single canonical one, so several workspaces share one memory store.
#
# This is the *mechanical* half of the memory-sharing step (see ../README.md, "Merge and
# symlink memory"). Run it only AFTER you've asked Claude to merge any memories that exist in
# one workspace's store but not another's into the canonical directory — this script does not
# merge content, it only backs up and swaps directories, so anything left only in a
# non-canonical directory at the time you run this is preserved in its backup but stops being
# read by that workspace from then on.
#
# Usage:
#   symlink-memories.sh <canonical-memory-dir> <other-memory-dir> [<other-memory-dir> ...]
#
# Example (three sibling workspaces, workspace 0's memory chosen as canonical):
#   symlink-memories.sh \
#     ~/.claude/projects/-home-you-r-0/memory \
#     ~/.claude/projects/-home-you-r-1/memory \
#     ~/.claude/projects/-home-you-r-2/memory
#
# Find your own project memory directories with:
#   ls -d ~/.claude/projects/*/memory
# (one per distinct working directory Claude Code has been run from; the directory-name
# encoding of the path is an internal detail that can change between Claude Code versions —
# match by eyeballing which one corresponds to which workspace, don't hardcode the naming
# scheme into other tooling.)
set -euo pipefail

[[ $# -ge 2 ]] || {
  echo "usage: $0 <canonical-memory-dir> <other-memory-dir> [<other-memory-dir> ...]" >&2
  exit 2
}

canonical=$1; shift
[[ -d "$canonical" ]] || { echo "symlink-memories: canonical dir not found: $canonical" >&2; exit 1; }
canonical=$(realpath "$canonical")

for other in "$@"; do
  if [[ -L "$other" ]]; then
    target=$(realpath "$other" 2>/dev/null || true)
    if [[ "$target" == "$canonical" ]]; then
      echo "already linked, skipping: $other"
    else
      echo "symlink-memories: $other is already a symlink to something else ($target) — skipping, resolve by hand" >&2
    fi
    continue
  fi

  if [[ -d "$other" ]]; then
    backup="${other}.pre-merge-backup"
    if [[ -e "$backup" ]]; then
      backup="${other}.pre-merge-backup-$$"
    fi
    mv "$other" "$backup"
    echo "backed up $other -> $backup"
  elif [[ -e "$other" ]]; then
    echo "symlink-memories: $other exists and is not a directory — skipping" >&2
    continue
  fi

  ln -s "$(realpath --relative-to="$(dirname "$other")" "$canonical")" "$other"
  echo "linked $other -> $canonical"
done

echo "Done. Verify with: ls -la \$(dirname \"$1\")"
