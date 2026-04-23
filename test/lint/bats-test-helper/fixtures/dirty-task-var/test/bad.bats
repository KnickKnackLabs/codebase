#!/usr/bin/env bats

setup() {
  TASK="$REPO_DIR/.mise/tasks/foo"
}

@test "runs foo" {
  bash "$TASK"
}
