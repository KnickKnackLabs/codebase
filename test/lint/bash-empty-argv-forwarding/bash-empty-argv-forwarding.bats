#!/usr/bin/env bats
# Tests for lint:bash-empty-argv-forwarding rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Detection
# ============================================================================

@test "bash-empty-argv-forwarding: passes on a clean codebase" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "bash-empty-argv-forwarding: flags '\"$@\"' under nounset" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty"* ]]
  [[ "$output" == *'"$@"'* ]]
}

@test "bash-empty-argv-forwarding: does not flag '\"$@\"' in files without nounset" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/no-nounset"
  [ "$status" -eq 0 ]
}

@test "bash-empty-argv-forwarding: does not flag 'for arg in \"$@\"' (safe context)" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/safe-context"
  [ "$status" -eq 0 ]
}

@test "bash-empty-argv-forwarding: does not flag already-safe '${@+\"$@\"}'" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/already-safe"
  [ "$status" -eq 0 ]
}

@test "bash-empty-argv-forwarding: flags across exec, mise run, and piped forms" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/exec-wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec other "$@"
EOF
  cat > "$tmp/.mise/tasks/mise-wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mise run child "$@"
EOF

  run codebase lint:bash-empty-argv-forwarding "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exec other"* ]]
  [[ "$output" == *"mise run child"* ]]
  rm -rf "$tmp"
}

@test "bash-empty-argv-forwarding: fail output includes the hint" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Use ${@+"$@"}'* ]]
}

@test "bash-empty-argv-forwarding: fail output names the violating file" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"delegate"* ]]
}

# ============================================================================
# Ignore directives
# ============================================================================

@test "bash-empty-argv-forwarding: inline '# codebase:ignore — reason' skips the line" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"ignored-inline"* ]]
}

@test "bash-empty-argv-forwarding: 'codebase:ignore' in mise.toml skips the whole target" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-file"* ]]
}

# ============================================================================
# Scope / discovery
# ============================================================================

@test "bash-empty-argv-forwarding: walks the whole target — finds hits outside .mise/tasks" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/broad-walk"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts/deploy.sh"* ]]
  [[ "$output" == *"bin/tool"* ]]
}

@test "bash-empty-argv-forwarding: works on a codebase with no mise.toml" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/no-toml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-toml"* ]]
}

@test "bash-empty-argv-forwarding: passes on a codebase with no shell files" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/no-shell-files"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-shell-files"* ]]
  [[ "$output" == *"no shell files"* ]]
}

@test "bash-empty-argv-forwarding: discovery skips non-bash shebangs (fish, zsh)" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/installer" <<'EOF'
#!/usr/bin/env fish
set -u
some_command "$@"
EOF
  # fish is not a bash/sh shebang, so discover_shell_files should skip it.
  run codebase lint:bash-empty-argv-forwarding "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -rf "$tmp"
}

@test "bash-empty-argv-forwarding: discovery prunes .git/ (hooks are ignored)" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.git/hooks" "$tmp/.mise/tasks"
  cat > "$tmp/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec hook "$@"
EOF
  cat > "$tmp/.mise/tasks/greet" <<'EOF'
#!/usr/bin/env bash
echo hi
EOF

  run codebase lint:bash-empty-argv-forwarding "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  # One shell file scanned (the greet task), zero from .git
  [[ "$output" == *"1 file(s) clean"* ]]
  rm -rf "$tmp"
}

# ============================================================================
# Comment handling
# ============================================================================

@test "bash-empty-argv-forwarding: does not flag '\"$@\"' inside a full-line comment" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Note: some_command "$@" — not really executed
echo ok
EOF
  run codebase lint:bash-empty-argv-forwarding "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -rf "$tmp"
}

# ============================================================================
# Multi-target
# ============================================================================

@test "bash-empty-argv-forwarding: checks multiple targets and reports each" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/clean" "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"dirty"* ]]
}

@test "bash-empty-argv-forwarding: exit code is the number of failing targets" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/dirty" "$FIXTURES/broad-walk"
  [ "$status" -eq 2 ]
}

# ============================================================================
# Error paths
# ============================================================================

@test "bash-empty-argv-forwarding: fails when target does not exist" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURES/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "bash-empty-argv-forwarding: fails when no targets given" {
  run codebase lint:bash-empty-argv-forwarding
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]
  [[ "$output" == *"<targets>"* ]]
}

# ============================================================================
# Relative path resolution
# ============================================================================

@test "bash-empty-argv-forwarding: relative path resolves against CODEBASE_CALLER_PWD" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
some_command "$@"
EOF

  CODEBASE_CALLER_PWD="$tmp" run codebase lint:bash-empty-argv-forwarding .mise/tasks
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *'"$@"'* ]]
  rm -rf "$tmp"
}

# ============================================================================
# Explicit braces detection
# ============================================================================

@test "bash-empty-argv-forwarding: flags '\"\${@}\"' (explicit braces) under nounset" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
some_command "${@}"
EOF

  run codebase lint:bash-empty-argv-forwarding "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *'"${@}"'* ]]
  rm -rf "$tmp"
}

@test "bash-empty-argv-forwarding: flags '\"\${@}\"' in redirect context" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
some_command "${@}" > /tmp/output
EOF

  run codebase lint:bash-empty-argv-forwarding "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *'"${@}"'* ]]
  rm -rf "$tmp"
}

@test "bash-empty-argv-forwarding: does not flag local array assignment from '\"$@\"'" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
local args=("$@")
for arg in "${args[@]}"; do
  echo "$arg"
done
EOF

  run codebase lint:bash-empty-argv-forwarding "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -rf "$tmp"
}