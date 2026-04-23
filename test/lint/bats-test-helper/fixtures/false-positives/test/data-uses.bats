#!/usr/bin/env bats

@test "reads a task file as data — should NOT be flagged" {
  run grep -q 'set -euo pipefail' "$MISE_CONFIG_ROOT/.mise/tasks/foo"
  [ "$status" -eq 0 ]
}

@test "writes a task fixture — should NOT be flagged" {
  mkdir -p "$repo/.mise/tasks"
  cat > "$repo/.mise/tasks/synthetic" <<'TASK'
#!/usr/bin/env bash
echo hi
TASK
  chmod +x "$repo/.mise/tasks/synthetic"
}

@test "passes a task-path as an argument to a tool — should NOT be flagged" {
  run codebase scan -e '.mise/tasks/ci/*' .
}

@test "run some other command — should NOT be flagged" {
  run some_wrapper list --json
}
