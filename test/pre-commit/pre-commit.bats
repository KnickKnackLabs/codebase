#!/usr/bin/env bats
# Tests for codebase pre-commit install/uninstall

setup() {
  CODEBASE_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  INSTALL="$CODEBASE_DIR/.mise/tasks/pre-commit/install"
  UNINSTALL="$CODEBASE_DIR/.mise/tasks/pre-commit/uninstall"

  # Create a fresh git repo with mise.toml for each test
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  cat > "$REPO/mise.toml" <<'EOF'
[tools]
bats = "1.13.0"

[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings", "gum-table"]
EOF
}

run_install() {
  usage_target="$REPO" bash "$INSTALL"
}

run_uninstall() {
  usage_target="$REPO" bash "$UNINSTALL"
}

# ============================================================================
# Install — fresh repo (no existing hooks)
# ============================================================================

@test "install: creates dispatcher" {
  run_install
  [ -f "$REPO/.git/hooks/pre-commit" ]
  grep -q "pre-commit.d" "$REPO/.git/hooks/pre-commit"
}

@test "install: creates pre-commit.d directory" {
  run_install
  [ -d "$REPO/.git/hooks/pre-commit.d" ]
}

@test "install: creates codebase hook script" {
  run_install
  [ -x "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

@test "install: hook contains configured rules" {
  run_install
  grep -q "mise-settings" "$REPO/.git/hooks/pre-commit.d/codebase"
  grep -q "gum-table" "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: dispatcher is executable" {
  run_install
  [ -x "$REPO/.git/hooks/pre-commit" ]
}

# ============================================================================
# Install — existing dispatcher (e.g. den with obfuscation hook)
# ============================================================================

@test "install: preserves existing dispatcher" {
  # Set up existing dispatcher + another hook
  mkdir -p "$REPO/.git/hooks/pre-commit.d"
  cat > "$REPO/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
# Pre-commit dispatcher — runs all executable scripts in pre-commit.d/
set -eo pipefail
HOOK_DIR="$(dirname "$0")/pre-commit.d"
for hook in "$HOOK_DIR"/*; do
  [ -x "$hook" ] && "$hook" || exit $?
done
EOF
  chmod +x "$REPO/.git/hooks/pre-commit"
  echo '#!/usr/bin/env bash' > "$REPO/.git/hooks/pre-commit.d/other-hook"
  echo 'echo other' >> "$REPO/.git/hooks/pre-commit.d/other-hook"
  chmod +x "$REPO/.git/hooks/pre-commit.d/other-hook"

  run_install

  # Other hook should still be there
  [ -f "$REPO/.git/hooks/pre-commit.d/other-hook" ]
  # Codebase hook should be added
  [ -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

# ============================================================================
# Install — existing plain hook (not a dispatcher)
# ============================================================================

@test "install: errors when existing plain hook is not a dispatcher" {
  cat > "$REPO/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "I am a custom hook"
EOF
  chmod +x "$REPO/.git/hooks/pre-commit"

  run bash -c "usage_target='$REPO' bash '$INSTALL'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a dispatcher"* ]]
}

# ============================================================================
# Install — idempotent
# ============================================================================

@test "install: running twice is safe" {
  run_install
  run_install
  # Should still work, only one codebase hook
  [ -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
  count=$(ls "$REPO/.git/hooks/pre-commit.d/" | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

# ============================================================================
# Install — error cases
# ============================================================================

@test "install: fails on non-git directory" {
  run bash -c "usage_target='$BATS_TEST_TMPDIR' bash '$INSTALL'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a git repository"* ]]
}

@test "install: fails when no mise.toml" {
  rm "$REPO/mise.toml"
  run bash -c "usage_target='$REPO' bash '$INSTALL'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no mise.toml"* ]]
}

@test "install: fails when no lint rules configured" {
  cat > "$REPO/mise.toml" <<'EOF'
[tools]
bats = "1.13.0"
EOF
  run bash -c "usage_target='$REPO' bash '$INSTALL'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no lint rules"* ]]
}

# ============================================================================
# Uninstall
# ============================================================================

@test "uninstall: removes codebase hook" {
  run_install
  [ -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
  run_uninstall
  [ ! -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

@test "uninstall: cleans up empty dispatcher" {
  run_install
  run_uninstall
  [ ! -f "$REPO/.git/hooks/pre-commit" ]
  [ ! -d "$REPO/.git/hooks/pre-commit.d" ]
}

@test "uninstall: preserves dispatcher when other hooks exist" {
  # Install dispatcher with another hook first
  mkdir -p "$REPO/.git/hooks/pre-commit.d"
  echo '#!/usr/bin/env bash' > "$REPO/.git/hooks/pre-commit.d/other"
  chmod +x "$REPO/.git/hooks/pre-commit.d/other"

  run_install
  run_uninstall

  # Dispatcher and other hook should remain
  [ -f "$REPO/.git/hooks/pre-commit" ]
  [ -f "$REPO/.git/hooks/pre-commit.d/other" ]
  # Codebase hook should be gone
  [ ! -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

@test "uninstall: no-op when not installed" {
  run run_uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"No codebase hook"* ]]
}

@test "uninstall: fails on non-git directory" {
  run bash -c "usage_target='$BATS_TEST_TMPDIR' bash '$UNINSTALL'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a git repository"* ]]
}
