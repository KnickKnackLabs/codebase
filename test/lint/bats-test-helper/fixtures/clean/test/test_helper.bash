#!/usr/bin/env bash
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mytool() {
  ( cd "$REPO_DIR" && mise run -q "$@" )
}
export -f mytool
