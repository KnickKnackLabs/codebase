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

# Install — fresh repo

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

@test "install: hook delegates to aggregate lint" {
  codebase pre-commit
  grep -q 'exec codebase lint "$REPO_ROOT"' "$REPO/.git/hooks/pre-commit.d/codebase"
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
  grep -q 'exec codebase lint "$REPO_ROOT"' "$REPO/.git/hooks/pre-commit.d/codebase"
  ! grep -q 'lint:mise-settings' "$REPO/.git/hooks/pre-commit.d/codebase"
  ! grep -q 'custom/gum-path' "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: generated hook is syntactically valid bash" {
  codebase pre-commit
  bash -n "$REPO/.git/hooks/pre-commit.d/codebase"
}

@test "install: generated hook delegates to codebase lint for repo root" {
  codebase pre-commit

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/codebase" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CODEBASE_HOOK_ARGS"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/codebase"
  export CODEBASE_HOOK_ARGS="$BATS_TEST_TMPDIR/hook-args"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  # Git always invokes hooks from the repo root. Simulate that —
  # the hook reads REPO_ROOT via 'git rev-parse --show-toplevel'.
  run bash -c 'cd "$1" && bash "$1/.git/hooks/pre-commit.d/codebase"' _ "$REPO"
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$CODEBASE_HOOK_ARGS")" = "lint" ]
  [ "$(sed -n '2p' "$CODEBASE_HOOK_ARGS")" = "$REPO_ROOT" ]
}

@test "install: dispatcher is executable" {
  codebase pre-commit
  [ -x "$REPO/.git/hooks/pre-commit" ]
}

# Install — existing dispatcher

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

# Install — existing plain hook (not a dispatcher)

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

# Idempotent

@test "install: running twice is safe" {
  codebase pre-commit
  run codebase pre-commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
  [ -f "$REPO/.git/hooks/pre-commit.d/codebase" ]
}

# --check

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

# --revert

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

# Scope

@test "scope: default scopes are delegated to aggregate lint" {
  cat > "$REPO/mise.toml" <<'EOF'
[settings]
quiet = true

[_.codebase]
lint = ["gum-table"]
EOF
  codebase pre-commit
  grep -q 'exec codebase lint "$REPO_ROOT"' "$REPO/.git/hooks/pre-commit.d/codebase"
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
  grep -q 'exec codebase lint "$REPO_ROOT"' "$REPO/.git/hooks/pre-commit.d/codebase"
  ! grep -q 'src/scripts' "$REPO/.git/hooks/pre-commit.d/codebase"
}

# Error handling

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
