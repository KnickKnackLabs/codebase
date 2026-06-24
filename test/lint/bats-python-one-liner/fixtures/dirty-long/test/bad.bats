#!/usr/bin/env bats

@test "complex transformation" {
  run mytool transform
  result="$(python3 -c "import sys; data = [l.strip().split(',') for l in sys.stdin]; assert all(len(d) > 2 for d in data)")"
  [ -n "$result" ]
}