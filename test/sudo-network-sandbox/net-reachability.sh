#!/bin/bash

set -e

# Optional: Import test library bundled with the devcontainer CLI
# See https://github.com/devcontainers/cli/blob/HEAD/docs/features/test.md#dev-container-features-test-lib
# Provides the 'check' and 'reportResults' commands.
source dev-container-features-test-lib

check "captive.apple.com is reachable" curl -s -f -o /dev/null --max-time 10 --connect-timeout 5 https://captive.apple.com
check "httpbin.org is reachable" curl -s -f -o /dev/null --max-time 10 --connect-timeout 5 https://httpbin.org
check "example.com is unreachable" bash -c "! curl -s -f -o /dev/null --max-time 10 --connect-timeout 5 https://example.com"

reportResults
