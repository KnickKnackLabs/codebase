#!/usr/bin/env bats

@test "runs foo" {
  bash "$REPO_DIR/.mise/tasks/foo" --flag
}
