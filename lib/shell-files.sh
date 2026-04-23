#!/usr/bin/env bash
# Shared helpers for codebase tasks.
#
# Source into a task with:
#   # shellcheck source=../../lib/shell-files.sh
#   source "$MISE_CONFIG_ROOT/lib/shell-files.sh"

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
