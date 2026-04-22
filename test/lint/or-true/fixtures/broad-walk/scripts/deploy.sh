#!/usr/bin/env bash
# Not under .mise/tasks or lib/ — broad walk must still find this.
set -euo pipefail
curl -sSf https://example.com || true
