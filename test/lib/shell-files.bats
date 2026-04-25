#!/usr/bin/env bats
# Tests for lib/shell-files.sh helpers

setup() {
  # Self-locate via BATS_TEST_DIRNAME (reliable in .bats files).
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_DIR/lib/shell-files.sh"
}

# ============================================================================
# resolve_target
# ============================================================================

@test "resolve_target: absolute path passes through unchanged" {
  result=$(resolve_target "/some/absolute/path")
  [ "$result" = "/some/absolute/path" ]
}

@test "resolve_target: relative path resolves against CALLER_PWD" {
  CALLER_PWD="/home/user/project" result=$(resolve_target ".mise/tasks")
  [ "$result" = "/home/user/project/.mise/tasks" ]
}

@test "resolve_target: relative path resolves against PWD when CALLER_PWD unset" {
  unset CALLER_PWD
  local expected="$PWD/.mise/tasks"
  result=$(resolve_target ".mise/tasks")
  [ "$result" = "$expected" ]
}

@test "resolve_target: bare directory name resolves correctly" {
  CALLER_PWD="/tmp/test-repo" result=$(resolve_target "lib")
  [ "$result" = "/tmp/test-repo/lib" ]
}

@test "resolve_target: dot resolves to CALLER_PWD" {
  CALLER_PWD="/tmp/test-repo" result=$(resolve_target ".")
  [ "$result" = "/tmp/test-repo/." ]
}
