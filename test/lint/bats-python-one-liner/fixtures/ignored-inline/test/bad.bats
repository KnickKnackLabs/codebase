#!/usr/bin/env bats

@test "parses frontmatter with inline ignore" {
  run mytool parse
  echo "$output" | python3 -c "import sys, json; data = json.load(sys.stdin); assert data['frontmatter'] == {}"  # codebase:ignore bats-python-one-liner — intentional inline assertion for a trivial check
  [ "$status" -eq 0 ]
}
