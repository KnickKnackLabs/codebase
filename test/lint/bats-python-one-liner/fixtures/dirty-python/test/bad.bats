#!/usr/bin/env bats

@test "parses frontmatter with python" {
  run mytool parse
  echo "$output" | python -c "import sys, json; data = json.load(sys.stdin); assert data['frontmatter'] == {}"
  [ "$status" -eq 0 ]
}
