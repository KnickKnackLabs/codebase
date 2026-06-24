setup_suite() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_DIR
  # codebase:ignore bats-setup-suite-path -- intentionally bypassing for test setup reasons
  eval "$(cd "$REPO_DIR" && mise env)"
}
