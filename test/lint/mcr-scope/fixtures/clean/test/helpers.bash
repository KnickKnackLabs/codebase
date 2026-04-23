#!/usr/bin/env bash
# Clean helper — uses BATS_TEST_DIRNAME per convention.
REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export REPO_DIR
