#!/usr/bin/env bats
# Tests for codebase pre-commit

load ../test_helper

setup() {
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
  # The pre-commit task resolves the target repo from CALLER_PWD.
  export CALLER_PWD="$REPO"
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

@test "install: hook contains configured rules" {
  codebase pre-commit
  grep -q "mise-settings" "$REPO/.git/hooks/pre-commit.d/codebase"
  grep -q "gum-table" "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: hook honors user scope overrides" {
  # Override gum-table's default (.mise/tasks) with a non-default value.
  # Verifies the user override is actually applied, not masked by the default.
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
  grep -q 'custom/gum-path' "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: generated hook is syntactically valid bash" {
  codebase pre-commit
  bash -n "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: generated hook runs end-to-end against a clean repo" {
  # Full smoke test: install the hook, actually execute it. Catches
  # generation bugs the grep-based tests can't.
  #
  # Uses mise-settings (expects quiet=true + task_output="interleave"
  # in the target's mise.toml) as the only lint rule; our fixture
  # mise.toml satisfies it, so the hook should exit 0.
  cat > "$REPO/mise.toml" <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings"]
EOF
  codebase pre-commit

  # Git always invokes hooks from the repo root. Simulate that —
  # the hook reads REPO_ROOT via 'git rev-parse --show-toplevel'.
  run bash -c "cd '$REPO' && bash '$REPO/.git/hooks/pre-commit.d/codebase'"
  [ "$status" -eq 0 ]
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

@test "scope: uses default when no override" {
  cat > "$REPO/mise.toml" <<'EOF'
[settings]
quiet = true

[_.codebase]
lint = ["gum-table"]
EOF
  codebase pre-commit
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
  codebase pre-commit
  grep -q 'src/scripts' "$REPO/.git/hooks/pre-commit.d/codebase"
}

# ============================================================================
# Error handling
# ============================================================================

@test "error: fails outside git repo" {
  export CALLER_PWD="$BATS_TEST_TMPDIR"
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
