#!/usr/bin/env bats
# Tests for lint:usage-flag-naming rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Clean cases — should pass
# ============================================================================

@test "usage-flag-naming: passes on clean task (flag/placeholder match)" {
  run codebase lint:usage-flag-naming "$FIXTURES/clean-match"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "usage-flag-naming: passes on boolean flag (no placeholder)" {
  run codebase lint:usage-flag-naming "$FIXTURES/clean-boolean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "usage-flag-naming: passes on short-only flag (no long name)" {
  run codebase lint:usage-flag-naming "$FIXTURES/clean-short-only"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "usage-flag-naming: passes on multi-flag task when all match" {
  run codebase lint:usage-flag-naming "$FIXTURES/multi-flag"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "usage-flag-naming: passes on target with no .mise/tasks directory" {
  run codebase lint:usage-flag-naming "$FIXTURES/no-tasks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ============================================================================
# Dirty cases — should fail
# ============================================================================

@test "usage-flag-naming: flags mismatched flag/placeholder" {
  run codebase lint:usage-flag-naming "$FIXTURES/dirty-mismatch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-mismatch"* ]]
  # --exclude (usage_exclude) vs <excludes> (usage_excludes)
  [[ "$output" == *"--exclude"* ]]
  [[ "$output" == *"usage_exclude"* ]]
  [[ "$output" == *"excludes"* ]]
  [[ "$output" == *"usage_excludes"* ]]
}

@test "usage-flag-naming: flags multi-word placeholder mismatch" {
  run codebase lint:usage-flag-naming "$FIXTURES/dirty-multi-word"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-multi-word"* ]]
  # --search-path (usage_search_path) vs <search-paths> (usage_search_paths)
  [[ "$output" == *"search-path"* ]]
  [[ "$output" == *"usage_search_path"* ]]
  [[ "$output" == *"search-paths"* ]]
  [[ "$output" == *"usage_search_paths"* ]]
}

# ============================================================================
# Mixed cases
# ============================================================================

@test "usage-flag-naming: flags only dirty tasks in mixed target" {
  run codebase lint:usage-flag-naming "$FIXTURES/mixed"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"mixed"* ]]
  # Only the bad task should be flagged, good task should not appear in findings
  [[ "$output" == *".mise/tasks/bad"* ]]
  [[ "$output" != *".mise/tasks/good"* ]]
}

# ============================================================================
# Ignore mechanisms
# ============================================================================

@test "usage-flag-naming: respects inline codebase:ignore" {
  run codebase lint:usage-flag-naming "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "usage-flag-naming: respects file-level codebase:ignore in mise.toml" {
  run codebase lint:usage-flag-naming "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
}

# ============================================================================
# Output format
# ============================================================================

@test "usage-flag-naming: output includes task file path and line number" {
  run codebase lint:usage-flag-naming "$FIXTURES/dirty-mismatch"
  [ "$status" -ne 0 ]
  [[ "$output" == *".mise/tasks/scan:"* ]]
  [[ "$output" == *"2:"* ]]  # line 2 has the #USAGE flag directive (line 1 is shebang)
}

@test "usage-flag-naming: output includes hint for fix" {
  run codebase lint:usage-flag-naming "$FIXTURES/dirty-mismatch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"hint"* ]]
  [[ "$output" == *"mise"* ]]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "usage-flag-naming: handles empty target directory" {
  run codebase lint:usage-flag-naming "$FIXTURES/no-tasks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "usage-flag-naming: does not self-flag on own fixtures tree" {
  # When scanning the codebase repo with this rule, the rule's own fixture
  # directories contain intentional mismatches under .mise/tasks/. The fd
  # --exclude fixtures flag skips subdirectories named fixtures/ within the
  # tasks tree, so self-hosting should pass clean. This test verifies that
  # behavior by scanning the entire fixtures tree. Note: this passes because
  # fd --exclude fixtures skips the actual dirty fixture content; if it ever
  # fails, the exclusion mechanism broke.
  run codebase lint:usage-flag-naming "$FIXTURES"
  [ "$status" -eq 0 ]
}

@test "usage-flag-naming: does NOT flag matching hyphens (file-path → file_path)" {
  # --file-path <file-path> should match: both normalize to usage_file_path.
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.mise/tasks"
  cat > "$tmpdir/.mise/tasks/hyphen-match" << 'TASK'
#!/usr/bin/env bash
#USAGE flag "--file-path <file-path>" help="File path"
echo "hyphen match"
TASK

  run codebase lint:usage-flag-naming "$tmpdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -rf "$tmpdir"
}

@test "usage-flag-naming: does NOT flag matching plural (exclude → exclude)" {
  # --exclude <exclude> should match: both normalize to usage_exclude.
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.mise/tasks"
  cat > "$tmpdir/.mise/tasks/plural-match" << 'TASK'
#!/usr/bin/env bash
#USAGE flag "--exclude <exclude>" help="Patterns to exclude"
echo "plural match"
TASK

  run codebase lint:usage-flag-naming "$tmpdir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -rf "$tmpdir"
}