#!/usr/bin/env bash
# Shared helpers for codebase tasks.
#
# Source from .mise/tasks/* (task context):
#   # shellcheck source=../../lib/shell-files.sh
#   source "$MISE_CONFIG_ROOT/lib/shell-files.sh"
#
# MISE_CONFIG_ROOT is the right primitive here — mise dispatched the task, so
# it's set correctly. Do NOT source this file from test helpers or other lib
# files using $MISE_CONFIG_ROOT; see fold/notes/mise-gotchas.md. From a lib
# or test-helper context, self-locate via ${BASH_SOURCE[0]} instead.

# resolve_target <path>
#
# Resolve a caller-relative path to an absolute path. Uses CALLER_PWD
# (exported by the shiv shim) as the base for relative paths. Falls back
# to PWD when CALLER_PWD is unset (e.g., running tasks directly via mise
# inside the codebase repo itself).
#
# Absolute paths pass through unchanged.
resolve_target() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  elif [[ -n "${CALLER_PWD:-}" ]]; then
    printf '%s\n' "$CALLER_PWD/$path"
  else
    printf '%s\n' "$PWD/$path"
  fi
}

# discover_shell_files <target>
#
# Emit paths of shell files under <target>, one per line. A file is
# considered a shell file when it has:
#   - a .sh or .bash extension, OR
#   - no extension and a bash/sh shebang on the first line.
#
# The .git directory is pruned. Callers may pass <target> as the whole
# repo root, a subtree (e.g. .mise/tasks), or any path — discovery does
# not assume any particular project layout.
discover_shell_files() {
  local target="$1"

  # Files with .sh/.bash extension
  find "$target" \
    -type d -name .git -prune -o \
    -type f \( -name "*.sh" -o -name "*.bash" \) -print 2>/dev/null

  # Extension-less files with a bash/sh shebang
  find "$target" \
    -type d -name .git -prune -o \
    -type f ! -name "*.*" -print 2>/dev/null |
    while IFS= read -r f; do
      # Leading \b prevents 'sh' matching as a suffix of fish/zsh/csh/dash/ksh.
      if head -1 "$f" 2>/dev/null | grep -qE '^#!.*\b(bash|sh)\b'; then
        echo "$f"
      fi
    done
}
