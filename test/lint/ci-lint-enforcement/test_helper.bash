setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  WORKFLOW="$REPO/.github/workflows/test.yml"
  mkdir -p "$(dirname "$WORKFLOW")"
  write_config
}

write_config() {
  cat > "$REPO/mise.toml" <<'TOML'
[_.codebase]
name = "fixture"
lint = ["mise-settings", "shellcheck"]
TOML
}

write_workflow() {
  cat > "$WORKFLOW"
}
