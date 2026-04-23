#!/usr/bin/env bats
load test_helper

@test "does a thing" {
  run mytool list --json
  [ "$status" -eq 0 ]
}
