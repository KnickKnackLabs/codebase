#!/usr/bin/env bats
# Tests for lint:bash-empty-array-expansions rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Detection
# ============================================================================

@test "bash-empty-array-expansions: passes on a clean codebase" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "bash-empty-array-expansions: flags '\"${args[@]}\"' under nounset" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty"* ]]
  [[ "$output" == *'"${arch_args[@]}"'* ]]
}

@test "bash-empty-array-expansions: flags '\"${args[*]}\"' under nounset" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/dirty-star"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-star"* ]]
  [[ "$output" == *'"${all_flags[*]}"'* ]]
}

@test "bash-empty-array-expansions: flags multiple array expansions in one file" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/dirty-multiple"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-multiple"* ]]
  [[ "$output" == *'"${names[@]}"'* ]]
  [[ "$output" == *'"${paths[@]}"'* ]]
  [[ "$output" == *'"${flags[*]}"'* ]]
}

@test "bash-empty-array-expansions: does not flag '\"${args[@]}\"' in files without nounset" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/no-nounset"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Safe contexts
# ============================================================================

@test "bash-empty-array-expansions: does not flag 'for item in \"\${items[@]}\"'" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/safe-context"
  [ "$status" -eq 0 ]
}

@test "bash-empty-array-expansions: does not flag 'local arr=(\"\${items[@]}\")'" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/safe-context-local"
  [ "$status" -eq 0 ]
}

@test "bash-empty-array-expansions: does not flag already-safe '\${arr[@]+\"\${arr[@]}\"}" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/already-safe"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Ignore mechanisms
# ============================================================================

@test "bash-empty-array-expansions: respects inline ignore" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
}

@test "bash-empty-array-expansions: respects file-level ignore via mise.toml" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "bash-empty-array-expansions: handles missing mise.toml gracefully" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/no-toml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-toml"* ]]
}

@test "bash-empty-array-expansions: finds hits outside .mise/tasks in broad walk" {
  run codebase lint:bash-empty-array-expansions "$FIXTURES/broad-walk"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lib/helper.sh"* ]]
}

# ============================================================================
# Dynamic test: various variable names
# ============================================================================

@test "bash-empty-array-expansions: flags different variable names" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "${names[@]}"
echo "${paths[@]}"
echo "${flags[*]}"
SCRIPT

  run codebase lint:bash-empty-array-expansions "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"names"* ]]
  [[ "$output" == *"paths"* ]]
  [[ "$output" == *"flags"* ]]
  rm -rf "$tmp"
}

@test "bash-empty-array-expansions: flags in redirect context" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
some_command "${args[@]}" > /tmp/output
SCRIPT

  run codebase lint:bash-empty-array-expansions "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *'"${args[@]}"'* ]]
  rm -rf "$tmp"
}

@test "bash-empty-array-expansions: does not flag local array assignment then for loop (combined safe)" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
local args=("$@")
for arg in "${args[@]}"; do
  echo "$arg"
done
SCRIPT

  run codebase lint:bash-empty-array-expansions "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -rf "$tmp"
}