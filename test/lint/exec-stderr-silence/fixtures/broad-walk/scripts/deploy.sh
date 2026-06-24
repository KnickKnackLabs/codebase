#!/usr/bin/env bash
# Not under .mise/tasks/ — broad walk must still find this.
set -euo pipefail
if ! exec 3<>"$remote_path" 2>/dev/null; then
  echo "probe failed" >&2
  exit 1
fi