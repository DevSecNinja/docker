#!/usr/bin/env bats

# Temporary: deliberate failure to demo the test-report action (#214). Reverted before review.
@test "report trial: deliberate failure" {
    run echo hello
    [ "$output" = "goodbye" ]
}
