#!/usr/bin/env bats
# Tests for codebase pre-commit

load ../test_helper

setup() {
  # Create a fresh git repo with mise.toml for each test
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  REPO_ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"
  cat > "$REPO/mise.toml" <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings", "gum-table"]

[_.codebase.scope]
gum-table = ".mise/tasks"
EOF
  # The pre-commit task resolves the target repo from CODEBASE_CALLER_PWD.
  export CODEBASE_CALLER_PWD="$REPO"
}

# ============================================================================
# Install — fresh repo
# ============================================================================

@test "install: creates dispatcher" {
  codebase pre-commit
  [ -f "$REPO/.git/hooks/pre-commit" ]
  grep -q "pre-commit.d" "$REPO/.git/hooks/pre-commit"
}

@test "install: creates pre-commit.d directory" {
  codebase pre-commit
  [ -d "$REPO/.git/hooks/pre-commit.d" ]
}

@test "install: creates codebase hook script" {
  codebase pre-commit
  [ -x "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

@test "install: hook delegates through the repository Mise environment" {
  codebase pre-commit
  grep -q 'exec mise -C "$REPO_ROOT" exec -- codebase lint "$REPO_ROOT"' \
    "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: hook does not bake configured rules or scopes" {
  cat > "$REPO/mise.toml" <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings", "gum-table"]

[_.codebase.scope]
gum-table = "custom/gum-path"
EOF
  codebase pre-commit
  grep -q 'exec mise -C "$REPO_ROOT" exec -- codebase lint "$REPO_ROOT"' \
    "$REPO/.git/hooks/pre-commit.d/codebase"
  ! grep -q 'lint:mise-settings' "$REPO/.git/hooks/pre-commit.d/codebase"
  ! grep -q 'custom/gum-path' "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: generated hook is syntactically valid bash" {
  codebase pre-commit
  bash -n "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: generated hook ignores stale ambient Codebase" {
  codebase pre-commit

  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  cat > "$bin/codebase" <<'EOF'
#!/usr/bin/env bash
touch "$AMBIENT_CODEBASE_RAN"
exit 99
EOF
  cat > "$bin/mise" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MISE_HOOK_ARGS"
while [[ "$1" != "--" ]]; do shift; done
shift
[[ "$1" == "codebase" ]]
shift
exec "$SELECTED_CODEBASE" "$@"
EOF
  cat > "$bin/selected-codebase" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CODEBASE_HOOK_ARGS"
EOF
  chmod +x "$bin/codebase" "$bin/mise" "$bin/selected-codebase"
  export AMBIENT_CODEBASE_RAN="$BATS_TEST_TMPDIR/ambient-codebase-ran"
  export MISE_HOOK_ARGS="$BATS_TEST_TMPDIR/mise-hook-args"
  export SELECTED_CODEBASE="$bin/selected-codebase"
  export CODEBASE_HOOK_ARGS="$BATS_TEST_TMPDIR/codebase-hook-args"

  run env PATH="$bin:/usr/bin:/bin" \
    bash -c 'cd "$1" && bash "$1/.git/hooks/pre-commit.d/codebase"' _ "$REPO"

  [ "$status" -eq 0 ]
  [ ! -e "$AMBIENT_CODEBASE_RAN" ]
  [ "$(sed -n '1p' "$MISE_HOOK_ARGS")" = "-C" ]
  [ "$(sed -n '2p' "$MISE_HOOK_ARGS")" = "$REPO_ROOT" ]
  [ "$(sed -n '3p' "$MISE_HOOK_ARGS")" = "exec" ]
  [ "$(sed -n '4p' "$MISE_HOOK_ARGS")" = "--" ]
  [ "$(sed -n '5p' "$MISE_HOOK_ARGS")" = "codebase" ]
  [ "$(sed -n '1p' "$CODEBASE_HOOK_ARGS")" = "lint" ]
  [ "$(sed -n '2p' "$CODEBASE_HOOK_ARGS")" = "$REPO_ROOT" ]
}

@test "install: generated hook fails clearly when Mise is unavailable" {
  codebase pre-commit

  run env PATH="/usr/bin:/bin" \
    bash -c 'cd "$1" && bash "$1/.git/hooks/pre-commit.d/codebase"' _ "$REPO"

  [ "$status" -ne 0 ]
  [[ "$output" == *"mise is required to run the repository-selected Codebase"* ]]
}

@test "install: generated hook preserves a missing declared Codebase failure" {
  codebase pre-commit

  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  cat > "$bin/codebase" <<'EOF'
#!/usr/bin/env bash
touch "$AMBIENT_CODEBASE_RAN"
exit 0
EOF
  cat > "$bin/mise" <<'EOF'
#!/usr/bin/env bash
echo "mise ERROR codebase is not installed" >&2
exit 42
EOF
  chmod +x "$bin/codebase" "$bin/mise"
  export AMBIENT_CODEBASE_RAN="$BATS_TEST_TMPDIR/ambient-codebase-ran"

  run env PATH="$bin:/usr/bin:/bin" \
    bash -c 'cd "$1" && bash "$1/.git/hooks/pre-commit.d/codebase"' _ "$REPO"

  [ "$status" -eq 42 ]
  [[ "$output" == *"codebase is not installed"* ]]
  [ ! -e "$AMBIENT_CODEBASE_RAN" ]
}

@test "install: dispatcher is executable" {
  codebase pre-commit
  [ -x "$REPO/.git/hooks/pre-commit" ]
}

# ============================================================================
# Install — existing dispatcher
# ============================================================================

@test "install: preserves existing dispatcher and other hooks" {
  mkdir -p "$REPO/.git/hooks/pre-commit.d"
  cat > "$REPO/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
set -eo pipefail
HOOK_DIR="$(dirname "$0")/pre-commit.d"
for hook in "$HOOK_DIR"/*; do
  [ -x "$hook" ] && "$hook" || exit $?
done
EOF
  chmod +x "$REPO/.git/hooks/pre-commit"
  echo '#!/usr/bin/env bash' > "$REPO/.git/hooks/pre-commit.d/other-hook"
  chmod +x "$REPO/.git/hooks/pre-commit.d/other-hook"

  codebase pre-commit

  [ -f "$REPO/.git/hooks/pre-commit.d/other-hook" ]
  [ -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

# ============================================================================
# Install — existing plain hook (not a dispatcher)
# ============================================================================

@test "install: errors when existing plain hook is not a dispatcher" {
  cat > "$REPO/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "custom hook"
EOF
  chmod +x "$REPO/.git/hooks/pre-commit"

  run codebase pre-commit
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a dispatcher"* ]]
}

# ============================================================================
# Idempotent
# ============================================================================

@test "install: running twice is safe" {
  codebase pre-commit
  run codebase pre-commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
  [ -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

# ============================================================================
# --check
# ============================================================================

@test "check: exits 0 when hook is current" {
  codebase pre-commit
  run codebase pre-commit --check
  [ "$status" -eq 0 ]
}

@test "check: exits 1 when hook is missing" {
  run codebase pre-commit --check
  [ "$status" -ne 0 ]
}

@test "check: exits 1 when hook is outdated" {
  codebase pre-commit
  # Tamper with the hook
  echo "# modified" >> "$REPO/.git/hooks/pre-commit.d/codebase"
  run codebase pre-commit --check
  [ "$status" -ne 0 ]
}

@test "check: makes no changes" {
  codebase pre-commit
  # Record state
  cp "$REPO/.git/hooks/pre-commit.d/codebase" "$BATS_TEST_TMPDIR/before"
  codebase pre-commit --check
  diff -q "$BATS_TEST_TMPDIR/before" "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "check: exits 1 when no config" {
  cat > "$REPO/mise.toml" <<'EOF'
[tools]
bats = "1.13.0"
EOF
  run codebase pre-commit --check
  [ "$status" -ne 0 ]
}

# ============================================================================
# --revert
# ============================================================================

@test "revert: removes codebase hook" {
  codebase pre-commit
  [ -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
  codebase pre-commit --revert
  [ ! -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

@test "revert: cleans up empty dispatcher" {
  codebase pre-commit
  codebase pre-commit --revert
  [ ! -f "$REPO/.git/hooks/pre-commit" ]
  [ ! -d "$REPO/.git/hooks/pre-commit.d" ]
}

@test "revert: preserves dispatcher when other hooks exist" {
  mkdir -p "$REPO/.git/hooks/pre-commit.d"
  echo '#!/usr/bin/env bash' > "$REPO/.git/hooks/pre-commit.d/other"
  chmod +x "$REPO/.git/hooks/pre-commit.d/other"

  codebase pre-commit
  codebase pre-commit --revert

  [ -f "$REPO/.git/hooks/pre-commit.d/other" ]
  [ ! -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

@test "revert: no-op when not installed" {
  run codebase pre-commit --revert
  [ "$status" -eq 0 ]
  [[ "$output" == *"No codebase hook"* ]]
}

# ============================================================================
# Scope
# ============================================================================

@test "scope: default scopes are delegated to aggregate lint" {
  cat > "$REPO/mise.toml" <<'EOF'
[settings]
quiet = true

[_.codebase]
lint = ["gum-table"]
EOF
  codebase pre-commit
  grep -q 'exec mise -C "$REPO_ROOT" exec -- codebase lint "$REPO_ROOT"' \
    "$REPO/.git/hooks/pre-commit.d/codebase"
  ! grep -q '.mise/tasks' "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "scope: overrides are delegated to aggregate lint" {
  cat > "$REPO/mise.toml" <<'EOF'
[settings]
quiet = true

[_.codebase]
lint = ["gum-table"]

[_.codebase.scope]
gum-table = "src/scripts"
EOF
  codebase pre-commit
  grep -q 'exec mise -C "$REPO_ROOT" exec -- codebase lint "$REPO_ROOT"' \
    "$REPO/.git/hooks/pre-commit.d/codebase"
  ! grep -q 'src/scripts' "$REPO/.git/hooks/pre-commit.d/codebase"
}

# ============================================================================
# Error handling
# ============================================================================

@test "error: fails outside git repo" {
  export CODEBASE_CALLER_PWD="$BATS_TEST_TMPDIR"
  run codebase pre-commit
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in a git repository"* ]]
}

@test "error: fails when no mise.toml" {
  rm "$REPO/mise.toml"
  run codebase pre-commit
  [ "$status" -ne 0 ]
  [[ "$output" == *"no mise.toml"* ]]
}

@test "error: fails when no lint rules configured" {
  cat > "$REPO/mise.toml" <<'EOF'
[tools]
bats = "1.13.0"
EOF
  run codebase pre-commit
  [ "$status" -ne 0 ]
  [[ "$output" == *"no lint rules"* ]]
}
