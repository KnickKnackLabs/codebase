#!/usr/bin/env bats
# Integration smoke tests: every task that takes target paths correctly
# resolves relative paths against CALLER_PWD. Regression coverage for
# codebase#24 — each task has its own copy of the resolution loop, so a
# regression in any one isn't caught by tests on the others.
#
# Shape: create a tmpdir with content appropriate for the rule, set
# CALLER_PWD to the tmpdir, pass a relative path, assert the task
# finds the content (not "target does not exist").

load ../test_helper

# --- Helpers ---------------------------------------------------------------

# Create a tmpdir with a single shell task file.
# Usage: make_task_dir [body]
# Returns the tmpdir path via stdout.
make_task_dir() {
  local body="${1:-echo ok}"
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<EOF
#!/usr/bin/env bash
$body
EOF
  echo "$tmp"
}

# Create a tmpdir with a mise.toml containing required settings.
make_settings_dir() {
  local tmp
  tmp=$(mktemp -d)
  cat > "$tmp/mise.toml" <<'EOF'
[settings]
quiet = true
task_output = "interleave"
EOF
  echo "$tmp"
}

# Create a tmpdir with a BATS test file.
make_test_dir() {
  local body="${1:-run notes list}"
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/test"
  cat > "$tmp/test/example.bats" <<EOF
#!/usr/bin/env bats
@test "example" {
  $body
}
EOF
  echo "$tmp"
}

# --- lint:shellcheck -------------------------------------------------------

@test "shellcheck: relative path resolves against CALLER_PWD" {
  local tmp
  tmp=$(make_task_dir "echo hello")

  CALLER_PWD="$tmp" run codebase lint:shellcheck .mise/tasks
  # shellcheck may warn but shouldn't error on "target does not exist"
  [[ "$output" != *"does not exist"* ]]
  rm -rf "$tmp"
}

# --- lint:bats-test-helper -------------------------------------------------

@test "bats-test-helper: relative path resolves against CALLER_PWD" {
  local tmp
  tmp=$(make_test_dir 'run notes list')

  CALLER_PWD="$tmp" run codebase lint:bats-test-helper test
  [[ "$output" != *"does not exist"* ]]
  rm -rf "$tmp"
}

# --- lint:bats-test-task ---------------------------------------------------

@test "bats-test-task: relative path resolves against CALLER_PWD" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  # A minimal test task with the canonical shape.
  cat > "$tmp/.mise/tasks/test" <<'EOF'
#!/usr/bin/env bash
#MISE description="Run tests"
#USAGE arg "[args]..." var=#true help="Test args"
#USAGE example "mise run test" header="Run all"
set -euo pipefail
bats test/
EOF

  CALLER_PWD="$tmp" run codebase lint:bats-test-task .
  [[ "$output" != *"does not exist"* ]]
  rm -rf "$tmp"
}

# --- lint:mcr-scope --------------------------------------------------------

@test "mcr-scope: relative path resolves against CALLER_PWD" {
  local tmp
  tmp=$(make_test_dir 'echo ok')

  CALLER_PWD="$tmp" run codebase lint:mcr-scope test
  [[ "$output" != *"does not exist"* ]]
  rm -rf "$tmp"
}

# --- lint:mise-settings ----------------------------------------------------

@test "mise-settings: relative path resolves against CALLER_PWD" {
  local tmp
  tmp=$(mktemp -d)
  # Create a subdir to use as the relative target.
  mkdir -p "$tmp/project"
  cat > "$tmp/project/mise.toml" <<'EOF'
[settings]
quiet = true
task_output = "interleave"
EOF

  CALLER_PWD="$tmp" run codebase lint:mise-settings project
  [[ "$output" != *"does not exist"* ]]
  [[ "$output" == *"OK"* ]] || [[ "$output" == *"FAIL"* ]]
  rm -rf "$tmp"
}

# --- scan ------------------------------------------------------------------

@test "scan: relative path resolves against CALLER_PWD" {
  local tmp
  tmp=$(make_task_dir 'mise run test')

  CALLER_PWD="$tmp" run codebase scan -p 'mise run $$$' .mise/tasks
  # May or may not find matches, but shouldn't error on path resolution.
  [[ "$output" != *"does not exist"* ]]
  rm -rf "$tmp"
}

# --- migrate/task-pattern --------------------------------------------------

@test "task-pattern: relative path resolves against CALLER_PWD" {
  local tmp
  tmp=$(make_task_dir 'mise run test')

  CALLER_PWD="$tmp" run codebase migrate:task-pattern .mise/tasks
  [[ "$output" != *"does not exist"* ]]
  rm -rf "$tmp"
}
