#!/usr/bin/env bats
# Tests for lint:variadic-args rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Pass paths
# ============================================================================

@test "variadic-args: passes on task using xargs pattern (correct)" {
  run codebase lint:variadic-args "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "variadic-args: passes on task with no variadic directives (no false positives)" {
  run codebase lint:variadic-args "$FIXTURES/no-variadic"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-variadic"* ]]
}

@test "variadic-args: passes on target with no .mise/tasks/ (nothing to check)" {
  run codebase lint:variadic-args "$FIXTURES/no-tasks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-tasks"* ]]
  [[ "$output" == *"no .mise/tasks/ files found"* ]]
}

@test "variadic-args: does NOT flag read -ra on non-variadic var (no false positive)" {
  # no-variadic fixture has a read -ra on $usage_name which is NOT declared
  # with var=#true. The rule should not flag it.
  run codebase lint:variadic-args "$FIXTURES/no-variadic"
  [ "$status" -eq 0 ]
  [[ "$output" != *"read -ra"* ]]
}

# ============================================================================
# Failure modes
# ============================================================================

@test "variadic-args: flags eval ARGS=(\${usage_args:-}) as ERROR" {
  run codebase lint:variadic-args "$FIXTURES/dirty-eval"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-eval"* ]]
  [[ "$output" == *"ERROR: eval is a shell injection vector"* ]]
}

@test "variadic-args: flags read -ra <<< \"\$usage_query\" as WARN" {
  run codebase lint:variadic-args "$FIXTURES/dirty-read-ra"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-read-ra"* ]]
  [[ "$output" == *"WARN: read -ra loses quoting"* ]]
}

@test "variadic-args: flags eval on variadic flag (not just positional arg)" {
  # dirty-read-ra uses a flag --query with var=#true, not a positional arg
  run codebase lint:variadic-args "$FIXTURES/dirty-read-ra"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage_query"* ]]
}

@test "variadic-args: reports correct line numbers" {
  run codebase lint:variadic-args "$FIXTURES/dirty-eval"
  [ "$status" -ne 0 ]
  # The eval is on line 6 of the fixture
  [[ "$output" == *"my-task:6"* ]]
}

@test "variadic-args: only flags variadic-var consumption, not non-variadic" {
  # mixed fixture has --exclude variadic used correctly (xargs pattern)
  # and --query variadic used with read -ra. Only the read -ra should be flagged.
  run codebase lint:variadic-args "$FIXTURES/mixed"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 dangerous variadic-arg consumption"* ]]
  [[ "$output" == *"usage_query"* ]]
  [[ "$output" != *"usage_exclude"* ]]
}

@test "variadic-args: handles mix of clean and dirty tasks in one target" {
  run codebase lint:variadic-args "$FIXTURES/multi-task"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 dangerous variadic-arg consumption"* ]]
  [[ "$output" == *"dirty-task"* ]]
  [[ "$output" != *"clean-task"* ]]
}

# ============================================================================
# Ignore mechanisms
# ============================================================================

@test "variadic-args: respects inline # codebase:ignore — reason" {
  run codebase lint:variadic-args "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"ignored-inline"* ]]
}

@test "variadic-args: respects file-level codebase:ignore in mise.toml" {
  run codebase lint:variadic-args "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-file"* ]]
}

# ============================================================================
# Multi-target
# ============================================================================

@test "variadic-args: checks multiple targets and reports each" {
  run codebase lint:variadic-args "$FIXTURES/clean" "$FIXTURES/dirty-eval"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"dirty-eval"* ]]
}

@test "variadic-args: exit code is the number of failing targets" {
  run codebase lint:variadic-args "$FIXTURES/dirty-eval" "$FIXTURES/dirty-read-ra"
  [ "$status" -eq 2 ]
}

# ============================================================================
# Error paths
# ============================================================================

@test "variadic-args: fails when target does not exist" {
  run codebase lint:variadic-args "$FIXTURES/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "variadic-args: fails when no targets given" {
  run codebase lint:variadic-args
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]
  [[ "$output" == *"<targets>"* ]]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "variadic-args: does NOT flag eval/read -ra on non-variadic env vars" {
  # no-variadic fixture has read -ra on $usage_name which is not variadic
  run codebase lint:variadic-args "$FIXTURES/no-variadic"
  [ "$status" -eq 0 ]
}

@test "variadic-args: handles usage_args positional arg variadic" {
  # Test that positional args with var=#true are also checked
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/foo" <<'EOF'
#!/usr/bin/env bash
#USAGE arg "[args]..." var=#true help="Args"
set -euo pipefail
read -ra ARGS <<< "$usage_args"
echo "${ARGS[@]}"
EOF

  run codebase lint:variadic-args "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"read -ra"* ]]
  [[ "$output" == *"usage_args"* ]]
  rm -rf "$tmp"
}

@test "variadic-args: passes on file with variadic arg used via xargs (correct pattern)" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/foo" <<'EOF'
#!/usr/bin/env bash
#USAGE flag "--name <name>" var=#true help="Names"
set -euo pipefail

NAMES=()
if [ -n "${usage_name:-}" ]; then
  while IFS= read -r name; do
    NAMES+=("$name")
  done < <(printf '%s' "$usage_name" | xargs printf '%s\n')
fi
EOF

  run codebase lint:variadic-args "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -rf "$tmp"
}

# ============================================================================
# Relative path resolution (regression: codebase#24)
# ============================================================================

@test "variadic-args: relative path resolves against CODEBASE_CALLER_PWD, not codebase install dir" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'EOF'
#!/usr/bin/env bash
#USAGE arg "[args]..." var=#true help="Args"
set -euo pipefail
eval "ARGS=(${usage_args:-})"
EOF

  CODEBASE_CALLER_PWD="$tmp" run codebase lint:variadic-args .
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"eval"* ]]
  rm -rf "$tmp"
}
