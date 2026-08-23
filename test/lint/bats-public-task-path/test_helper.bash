setup() {
  TARGET="$BATS_TEST_TMPDIR/fixture repo"
  mkdir -p "$TARGET/test"
  cat > "$TARGET/mise.toml" <<'TOML'
[_.codebase]
name = "fixture"
TOML
}

write_bats() {
  local raw="$TARGET/test/example.bats.raw"
  cat > "$raw"
  awk '
    /^bats_test_function / { print "@test \"fixture\" {"; next }
    { print }
  ' "$raw" > "$TARGET/test/example.bats"
  rm "$raw"
}
