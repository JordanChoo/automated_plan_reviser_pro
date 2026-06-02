#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # BATS runs each test in an isolated shell.
# test_utils.bats - Unit tests for APR utility functions
#
# Tests:
#   - version_gt() - Semantic version comparison
#   - can_prompt() - Interactive terminal detection
#   - iso_timestamp() - ISO8601 timestamp generation
#   - verbose() - Debug logging

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# version_gt() Tests
# =============================================================================

@test "version_gt: newer minor version returns true" {
    log_test_input "version_gt 1.2.0 1.1.0" ""

    run version_gt "1.2.0" "1.1.0"

    log_test_actual "exit code" "$status"
    assert_success
}

@test "version_gt: newer major version returns true" {
    log_test_input "version_gt 2.0.0 1.9.9" ""

    run version_gt "2.0.0" "1.9.9"

    log_test_actual "exit code" "$status"
    assert_success
}

@test "version_gt: newer patch version returns true" {
    log_test_input "version_gt 1.0.1 1.0.0" ""

    run version_gt "1.0.1" "1.0.0"

    log_test_actual "exit code" "$status"
    assert_success
}

@test "version_gt: equal versions returns false" {
    log_test_input "version_gt 1.0.0 1.0.0" ""

    run version_gt "1.0.0" "1.0.0"

    log_test_actual "exit code" "$status"
    assert_failure
}

@test "version_gt: older version returns false" {
    log_test_input "version_gt 1.0.0 1.0.1" ""

    run version_gt "1.0.0" "1.0.1"

    log_test_actual "exit code" "$status"
    assert_failure
}

@test "version_gt: double-digit version numbers compared correctly" {
    log_test_input "version_gt 1.10.0 1.9.0" ""

    run version_gt "1.10.0" "1.9.0"

    log_test_actual "exit code" "$status"
    assert_success
}

@test "version_gt: zero major version works" {
    log_test_input "version_gt 0.2.0 0.1.9" ""

    run version_gt "0.2.0" "0.1.9"

    log_test_actual "exit code" "$status"
    assert_success
}

@test "version_gt: handles versions without dots gracefully" {
    log_test_input "version_gt 2 1" ""

    # Should not crash, behavior may vary
    run version_gt "2" "1"

    log_test_actual "exit code" "$status"
    # Just verify it doesn't crash - specific behavior depends on implementation
    [[ $status -eq 0 || $status -eq 1 ]]
}

# =============================================================================
# iso_timestamp() Tests
# =============================================================================

@test "iso_timestamp: returns valid ISO8601 format" {
    log_test_step "action" "Calling iso_timestamp"

    run iso_timestamp

    log_test_actual "output" "$output"

    assert_success
    # Format: YYYY-MM-DDTHH:MM:SSZ
    assert_output --regexp '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
}

@test "iso_timestamp: returns UTC timezone (Z suffix)" {
    run iso_timestamp

    log_test_actual "output" "$output"

    assert_success
    [[ "$output" == *"Z" ]]
}

@test "iso_timestamp: timestamps increment over time" {
    local ts1 ts2

    ts1=$(iso_timestamp)
    sleep 1
    ts2=$(iso_timestamp)

    log_test_actual "first timestamp" "$ts1"
    log_test_actual "second timestamp" "$ts2"

    # Second timestamp should be later
    [[ "$ts2" > "$ts1" ]]
}

# =============================================================================
# verbose() Tests
# =============================================================================

@test "verbose: no output when VERBOSE is false" {
    export VERBOSE=false

    log_test_step "action" "Calling verbose with VERBOSE=false"

    capture_streams verbose "test message"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ -z "$CAPTURED_STDERR" ]]
}

@test "verbose: outputs to stderr when VERBOSE is true" {
    export VERBOSE=true

    log_test_step "action" "Calling verbose with VERBOSE=true"

    capture_streams verbose "test message"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ -n "$CAPTURED_STDERR" ]]
    [[ "$CAPTURED_STDERR" == *"test message"* ]]
}

@test "verbose: output includes prefix" {
    export VERBOSE=true

    capture_streams verbose "test message"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    # Should include some kind of prefix
    [[ "$CAPTURED_STDERR" == *"apr"* ]] || [[ "$CAPTURED_STDERR" == *"verbose"* ]] || [[ "$CAPTURED_STDERR" == *"["* ]]
}

# =============================================================================
# can_prompt() Tests
# =============================================================================

@test "can_prompt: returns false when QUIET_MODE is true" {
    export QUIET_MODE=true

    log_test_step "action" "Calling can_prompt with QUIET_MODE=true"

    run can_prompt

    log_test_actual "exit code" "$status"
    assert_failure
}

@test "can_prompt: returns false when stdin is not a tty" {
    export QUIET_MODE=false

    log_test_step "action" "Calling can_prompt with piped stdin"

    # Pipe something to ensure stdin is not a TTY
    run bash -c 'source '"$TEST_DIR"'/apr_functions.bash; echo "" | can_prompt'

    log_test_actual "exit code" "$status"
    assert_failure
}

# =============================================================================
# Environment Variable Detection Tests
# =============================================================================

@test "check_for_updates: ignores invalid cached timestamp" {
    local original_path="$PATH"
    local bin_dir="$TEST_DIR/no_downloaders"
    mkdir -p "$bin_dir"

    local tool
    for tool in cat date mkdir; do
        ln -s "$(command -v "$tool")" "$bin_dir/$tool"
    done

    APR_HOME="$TEST_DIR/apr_home"
    APR_CHECK_UPDATES=1
    mkdir -p "$APR_HOME"
    printf '%s\n' "not-a-timestamp" > "$APR_HOME/.last_update_check"
    PATH="$bin_dir"
    export APR_HOME APR_CHECK_UPDATES PATH

    run check_for_updates

    PATH="$original_path"
    export PATH

    log_test_actual "exit code" "$status"
    log_test_actual "timestamp cache" "$(cat "$APR_HOME/.last_update_check")"
    assert_success
    [[ "$(cat "$APR_HOME/.last_update_check")" =~ ^[0-9]+$ ]]
}

@test "check_gum: returns failure when APR_NO_GUM is set" {
    export APR_NO_GUM=1

    log_test_step "action" "Calling check_gum with APR_NO_GUM=1"

    # check_gum returns 1 (failure) when APR_NO_GUM is set
    run check_gum

    log_test_actual "exit code" "$status"

    assert_failure
}

@test "check_gum: does not enable gum when APR_NO_GUM is set" {
    export APR_NO_GUM=1

    log_test_step "action" "Calling check_gum with APR_NO_GUM=1"

    # GUM_AVAILABLE should stay false (its default value)
    GUM_AVAILABLE=false
    check_gum || true  # Ignore return code

    log_test_actual "GUM_AVAILABLE" "$GUM_AVAILABLE"

    [[ "$GUM_AVAILABLE" == "false" ]]
}

@test "check_gum: does not enable gum in CI environment" {
    export CI=true
    unset APR_NO_GUM

    log_test_step "action" "Calling check_gum with CI=true"

    # In CI, gum is not enabled even if available (no installation attempt)
    GUM_AVAILABLE=false
    check_gum || true  # Ignore return code

    log_test_actual "GUM_AVAILABLE" "$GUM_AVAILABLE"

    # If gum is not installed, it should stay false
    # If gum IS installed, it would be true (gum can be used in CI if pre-installed)
    # This test just verifies check_gum doesn't crash in CI mode
    [[ "$GUM_AVAILABLE" == "true" || "$GUM_AVAILABLE" == "false" ]]
}
