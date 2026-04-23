#!/usr/bin/env bats

@test "deliberately bypasses mise for a good reason" {
  bash "$TASK"  # codebase:ignore — testing the raw script
}
