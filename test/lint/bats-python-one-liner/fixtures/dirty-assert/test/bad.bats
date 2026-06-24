#!/usr/bin/env bats

@test "parses frontmatter" {
  run mytool parse
  echo "$output" | python3 -c "import sys, json; data = json.load(sys.stdin); assert data['frontmatter'] == {}"
  [ "$status" -eq 0 ]
}