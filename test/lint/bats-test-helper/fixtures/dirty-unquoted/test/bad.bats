#!/usr/bin/env bats

@test "unquoted var + task path" {
  run $REPO_DIR/.mise/tasks/foo --flag
}

@test "bash + unquoted" {
  bash $REPO_DIR/.mise/tasks/lint/check
}
