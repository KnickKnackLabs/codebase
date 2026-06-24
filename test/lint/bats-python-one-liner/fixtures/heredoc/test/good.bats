#!/usr/bin/env bats

@test "parses frontmatter with heredoc" {
  run mytool parse
  json_file="$BATS_TEST_TMPDIR/parse.json"
  printf '%s\n' "$output" > "$json_file"
  python3 - "$json_file" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
assert data["frontmatter"] == {}
assert data["frontmatter_present"] is False
assert data["diagnostics"] == []
PY
  [ "$status" -eq 0 ]
}