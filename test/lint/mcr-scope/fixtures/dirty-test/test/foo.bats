#!/usr/bin/env bats
# Bad: test file references MCR directly.
@test "smoke" {
  [ -d "$MISE_CONFIG_ROOT" ]
}
