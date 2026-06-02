#!/usr/bin/env bats
# test_run.bats - Integration tests for APR run command
#
# Tests the run command against the direct OpenAI Responses API backend using a
# deterministic curl mock.

load '../helpers/test_helper'

setup() {
    setup_test_environment
    log_test_start "${BATS_TEST_NAME}"

    cd "$TEST_PROJECT" || return 1
    setup_mock_api
    setup_test_workflow "default"
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Dry Run Tests
# =============================================================================

@test "run --dry-run: previews direct Responses API request" {
    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"

    assert_success
    [[ "$output" == *"POST https://mock.openai.test/v1/responses"* ]]
    [[ "$output" == *"model: gpt-5.5"* ]]
    [[ "$output" == *"reasoning.effort: high"* ]]
    [[ "$output" == *"background: true"* ]]
    [[ "$output" == *"store: true"* ]]
}

@test "run --dry-run: includes slug and output file" {
    run "$APR_SCRIPT" run 5 --dry-run

    log_test_output "$output"

    assert_success
    [[ "$output" == *"metadata.apr_slug: apr-default-round-5"* ]]
    [[ "$output" == *"output_file: .apr/rounds/default/round_5.md"* ]]
}

@test "run --dry-run --include-impl: uses implementation slug suffix" {
    run "$APR_SCRIPT" run 1 --dry-run --include-impl

    log_test_output "$output"

    assert_success
    [[ "$output" == *"apr-default-round-1-with-impl"* ]]
}

@test "shorthand: apr <number> works like apr run <number>" {
    run "$APR_SCRIPT" 1 --dry-run

    log_test_output "$output"

    assert_success
    [[ "$output" == *"POST https://mock.openai.test/v1/responses"* ]]
    [[ "$output" == *"apr-default-round-1"* ]]
}

# =============================================================================
# Render Mode Tests
# =============================================================================

@test "run --render: outputs API review bundle" {
    run "$APR_SCRIPT" run 1 --render

    log_test_output "$output"

    assert_success
    [[ "$output" == *"APR DIRECT API REVIEW BUNDLE"* ]]
    [[ "$output" == *"# Test Project"* ]]
    [[ "$output" == *"# Specification"* ]]
    [[ "$output" == *"Please analyze and provide feedback."* ]]
}

@test "run --render --include-impl: includes implementation document" {
    run "$APR_SCRIPT" run 1 --render --include-impl

    log_test_output "$output"

    assert_success
    [[ "$output" == *"# Implementation"* ]]
    [[ "$output" == *"IMPLEMENTATION.md"* ]]
}

@test "run --render --copy: copies rendered API bundle when clipboard tool exists" {
    {
        printf '#!/usr/bin/env bash\n'
        printf 'cat > "${TEST_DIR}/clipboard.txt"\n'
    } > "$TEST_DIR/bin/pbcopy"
    chmod +x "$TEST_DIR/bin/pbcopy"

    capture_streams "$APR_SCRIPT" run 1 --render --copy

    log_test_actual "exit code" "$CAPTURED_STATUS"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ -z "$CAPTURED_STDOUT" ]]
    assert_file_contains "$TEST_DIR/clipboard.txt" "APR DIRECT API REVIEW BUNDLE"
    assert_file_contains "$TEST_DIR/clipboard.txt" "# Test Project"
}

# =============================================================================
# Round Number Validation Tests
# =============================================================================

@test "run: rejects non-numeric round" {
    run "$APR_SCRIPT" run abc --dry-run

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    assert_failure
}

@test "run: rejects negative round" {
    run "$APR_SCRIPT" run -1 --dry-run

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    assert_failure
}

@test "run: accepts large round number" {
    run "$APR_SCRIPT" run 999 --dry-run

    log_test_output "$output"

    assert_success
    [[ "$output" == *"apr-default-round-999"* ]]
}

# =============================================================================
# Workflow Selection Tests
# =============================================================================

@test "run: -w selects workflow" {
    setup_test_workflow "secondary"

    run "$APR_SCRIPT" run 1 --dry-run -w secondary

    log_test_output "$output"

    assert_success
    [[ "$output" == *"apr-secondary-round-1"* ]]
}

@test "run: --workflow selects workflow" {
    setup_test_workflow "another"

    run "$APR_SCRIPT" run 1 --dry-run --workflow another

    log_test_output "$output"

    assert_success
    [[ "$output" == *"apr-another-round-1"* ]]
}

@test "run: fails for non-existent workflow" {
    run "$APR_SCRIPT" run 1 --dry-run -w nonexistent

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    assert_failure
    [[ "$output" == *"Workflow 'nonexistent' not found"* ]]
}

# =============================================================================
# Preflight and API Execution Tests
# =============================================================================

@test "run --wait: polls API and writes completed round output" {
    capture_streams "$APR_SCRIPT" run 1 --wait

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"Direct API ready"* ]]
    [[ "$CAPTURED_STDERR" == *"Review complete!"* ]]
    assert_file_exists ".apr/rounds/default/round_1.md"
    assert_file_contains ".apr/rounds/default/round_1.md" "Mock API review"
    assert_file_exists ".apr/api_sessions/apr-default-round-1.json"
    assert_file_exists ".apr/logs/api_apr-default-round-1.json"
}

@test "run: background mode creates stored API session" {
    capture_streams "$APR_SCRIPT" run 1

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"API review queued in background"* ]]
    assert_file_exists ".apr/api_sessions/apr-default-round-1.json"
    assert_json_value "$(cat .apr/api_sessions/apr-default-round-1.json)" ".response_id" "resp_mock_apr_default_round_1"
    assert_json_value "$(cat .apr/api_sessions/apr-default-round-1.json)" ".status" "in_progress"
}

@test "run: rejects concurrent background run for same round" {
    capture_streams "$APR_SCRIPT" run 1
    log_test_actual "first exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 0 ]]

    capture_streams "$APR_SCRIPT" run 1
    log_test_actual "second exit code" "$CAPTURED_STATUS"
    log_test_actual "second stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 12 ]]
    [[ "$CAPTURED_STDERR" == *"API session is already active"* ]]
}

@test "run: --no-preflight still validates required files" {
    mv README.md README.md.missing

    run "$APR_SCRIPT" run 1 --dry-run --no-preflight

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    assert_failure
    [[ "$output" == *"Required file not found: README.md"* ]]
}

@test "run: preflight fails when required file missing" {
    mv README.md README.md.missing

    capture_streams "$APR_SCRIPT" run 1 --wait

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 4 ]]
    [[ "$CAPTURED_STDERR" == *"Pre-flight failed: README not found"* ]]
}

@test "run: existing output file warns and proceeds when non-interactive" {
    mkdir -p .apr/rounds/default
    printf '%s\n' "existing output" > .apr/rounds/default/round_1.md

    capture_streams "$APR_SCRIPT" run 1 --wait

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"Round 1 output already exists"* ]]
    assert_file_contains ".apr/rounds/default/round_1.md" "Mock API review"
}

@test "run: API create failure returns network error" {
    export MOCK_API_HTTP_CODE=500
    export MOCK_API_ERROR="forced failure"

    capture_streams "$APR_SCRIPT" run 1

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 10 ]]
    [[ "$CAPTURED_STDERR" == *"API request failed: forced failure"* ]]
}

@test "run: missing API key fails before API execution" {
    unset OPENAI_API_KEY

    capture_streams "$APR_SCRIPT" run 1

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 4 ]]
    [[ "$CAPTURED_STDERR" == *"OPENAI_API_KEY is not set"* ]]
}

# =============================================================================
# Prompt Assembly Tests
# =============================================================================

@test "run: render keeps API bundle sections and fences stable" {
    create_mock_round 1 "default" "# Round 1 Content

Previous analysis here."

    run "$APR_SCRIPT" run 2 --render

    log_test_output "$output"

    assert_success
    [[ "$output" == *"## README (README.md)"* ]]
    [[ "$output" == *"## SPECIFICATION (SPECIFICATION.md)"* ]]
    [[ "$output" == *"## REVIEW INSTRUCTIONS"* ]]
    [[ "$output" == *"~~~~markdown"* ]]
}

@test "run: quiet dry-run still shows request preview" {
    run "$APR_SCRIPT" run 1 --dry-run --quiet

    log_test_output "$output"

    assert_success
    [[ "$output" == *"POST https://mock.openai.test/v1/responses"* ]]
}

@test "run: verbose dry-run includes additional detail" {
    run "$APR_SCRIPT" run 1 --dry-run --verbose

    log_test_output "$output"

    assert_success
    [[ "$output" == *"prompt_chars:"* ]]
    [[ ${#output} -gt 100 ]]
}

@test "run: provides helpful message on workflow config error" {
    mv .apr/workflows/default.yaml .apr/workflows/default.yaml.missing

    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    assert_failure
    [[ "$output" == *"Workflow 'default' not found"* ]]
}
