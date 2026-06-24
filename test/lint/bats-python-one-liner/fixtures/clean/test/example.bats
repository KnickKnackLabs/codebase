#!/usr/bin/env bats
load test_helper

@test "parses frontmatter with heredoc" {
  run mytool parse
  json_file="$BATS_TEST_TMPDIR/parse.json"
  printf '%s\n' "$output" > "$json_file"
  python3 - "$json_file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["frontmatter"] == {}
PY
  [ "$status" -eq 0 ]
}
