#!/bin/bash

set -e

# Optional: Import test library bundled with the devcontainer CLI
# See https://github.com/devcontainers/cli/blob/HEAD/docs/features/test.md#dev-container-features-test-lib
# Provides the 'check' and 'reportResults' commands.
source dev-container-features-test-lib

check "sudo ls" bash -c "! sudo ls && echo FAIL | grep FAIL"
check "sudo cat" bash -c "! sudo cat tempfile && echo FAIL | grep FAIL"
check "sudo iptables" bash -c "! sudo iptables -t nat -L && echo FAIL | grep FAIL"

reportResults
