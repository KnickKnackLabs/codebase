#!/usr/bin/env bats
# Tests for codebase pre-commit

setup() {
  CODEBASE_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TASK="$CODEBASE_DIR/.mise/tasks/pre-commit"

  # Create a fresh git repo with mise.toml for each test
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  cat > "$REPO/mise.toml" <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings", "gum-table"]

[_.codebase.scope]
gum-table = ".mise/tasks"
EOF
}

run_pre_commit() {
  local revert="false" check="false"
  for arg in "$@"; do
    case "$arg" in
      --revert) revert="true" ;;
      --check) check="true" ;;
    esac
  done
  CALLER_PWD="$REPO" usage_revert="$revert" usage_check="$check" bash "$TASK"
}

# ============================================================================
# Install — fresh repo
# ============================================================================

@test "install: creates dispatcher" {
  run_pre_commit
  [ -f "$REPO/.git/hooks/pre-commit" ]
  grep -q "pre-commit.d" "$REPO/.git/hooks/pre-commit"
}

@test "install: creates pre-commit.d directory" {
  run_pre_commit
  [ -d "$REPO/.git/hooks/pre-commit.d" ]
}

@test "install: creates codebase hook script" {
  run_pre_commit
  [ -x "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

@test "install: hook contains configured rules" {
  run_pre_commit
  grep -q "mise-settings" "$REPO/.git/hooks/pre-commit.d/codebase"
  grep -q "gum-table" "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: hook contains scope mappings" {
  run_pre_commit
  grep -q '.mise/tasks' "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: dispatcher is executable" {
  run_pre_commit
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

  run_pre_commit

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

  run bash -c "CALLER_PWD='$REPO' bash '$TASK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a dispatcher"* ]]
}

# ============================================================================
# Idempotent
# ============================================================================

@test "install: running twice is safe" {
  run_pre_commit
  run run_pre_commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
  [ -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

# ============================================================================
# --check
# ============================================================================

@test "check: exits 0 when hook is current" {
  run_pre_commit
  run bash -c "cd '$REPO' && bash '$TASK' --check"
  [ "$status" -eq 0 ]
}

@test "check: exits 1 when hook is missing" {
  run run_pre_commit --check
  [ "$status" -ne 0 ]
}

@test "check: exits 1 when hook is outdated" {
  run_pre_commit
  # Tamper with the hook
  echo "# modified" >> "$REPO/.git/hooks/pre-commit.d/codebase"
  run run_pre_commit --check
  [ "$status" -ne 0 ]
}

@test "check: makes no changes" {
  run_pre_commit
  # Record state
  cp "$REPO/.git/hooks/pre-commit.d/codebase" "$BATS_TEST_TMPDIR/before"
  run bash -c "cd '$REPO' && bash '$TASK' --check"
  diff -q "$BATS_TEST_TMPDIR/before" "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "check: exits 1 when no config" {
  cat > "$REPO/mise.toml" <<'EOF'
[tools]
bats = "1.13.0"
EOF
  run run_pre_commit --check
  [ "$status" -ne 0 ]
}

# ============================================================================
# --revert
# ============================================================================

@test "revert: removes codebase hook" {
  run_pre_commit
  [ -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
  run_pre_commit --revert
  [ ! -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

@test "revert: cleans up empty dispatcher" {
  run_pre_commit
  run_pre_commit --revert
  [ ! -f "$REPO/.git/hooks/pre-commit" ]
  [ ! -d "$REPO/.git/hooks/pre-commit.d" ]
}

@test "revert: preserves dispatcher when other hooks exist" {
  mkdir -p "$REPO/.git/hooks/pre-commit.d"
  echo '#!/usr/bin/env bash' > "$REPO/.git/hooks/pre-commit.d/other"
  chmod +x "$REPO/.git/hooks/pre-commit.d/other"

  run_pre_commit
  run_pre_commit --revert

  [ -f "$REPO/.git/hooks/pre-commit.d/other" ]
  [ ! -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

@test "revert: no-op when not installed" {
  run run_pre_commit --revert
  [ "$status" -eq 0 ]
  [[ "$output" == *"No codebase hook"* ]]
}

# ============================================================================
# Scope
# ============================================================================

@test "scope: uses default when no override" {
  cat > "$REPO/mise.toml" <<'EOF'
[settings]
quiet = true

[_.codebase]
lint = ["gum-table"]
EOF
  run_pre_commit
  grep -q '.mise/tasks' "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "scope: override takes precedence" {
  cat > "$REPO/mise.toml" <<'EOF'
[settings]
quiet = true

[_.codebase]
lint = ["gum-table"]

[_.codebase.scope]
gum-table = "src/scripts"
EOF
  run_pre_commit
  grep -q 'src/scripts' "$REPO/.git/hooks/pre-commit.d/codebase"
}

# ============================================================================
# Error handling
# ============================================================================

@test "error: fails outside git repo" {
  run bash -c "CALLER_PWD='$BATS_TEST_TMPDIR' bash '$TASK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in a git repository"* ]]
}

@test "error: fails when no mise.toml" {
  rm "$REPO/mise.toml"
  run bash -c "CALLER_PWD='$REPO' bash '$TASK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no mise.toml"* ]]
}

@test "error: fails when no lint rules configured" {
  cat > "$REPO/mise.toml" <<'EOF'
[tools]
bats = "1.13.0"
EOF
  run bash -c "CALLER_PWD='$REPO' bash '$TASK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no lint rules"* ]]
}
