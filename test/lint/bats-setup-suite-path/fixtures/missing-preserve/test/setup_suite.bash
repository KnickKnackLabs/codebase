setup_suite() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_DIR
  eval "$(cd "$REPO_DIR" && mise env)"
}
