#!/usr/bin/env bats
load test_helper

@test "short harmless print" {
  run mytool version
  result="$(python3 -c 'print("hello")')"
  [ "$result" = "hello" ]
}