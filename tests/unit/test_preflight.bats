#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2119,SC2120
# test_preflight.bats - Unit tests for API preflight_check and validation paths

load '../helpers/test_helper.bash'

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"
    cd "$TEST_PROJECT" || return 1
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

create_docs() {
    local dir="${1:-$TEST_PROJECT}"
    mkdir -p "$dir"

    cat > "$dir/README.md" <<'EOF'
# README

This is a test README for APR preflight unit tests.
It is intentionally long enough to avoid size warnings.
EOF

    cat > "$dir/SPEC.md" <<'EOF'
# SPEC

This is a test spec for APR preflight unit tests.
It is intentionally long enough to avoid size warnings.
EOF

    cat > "$dir/IMPL.md" <<'EOF'
# IMPL

This is a test implementation doc for APR preflight unit tests.
It is intentionally long enough to avoid size warnings.
EOF
}

write_workflow_config() {
    local readme_path="$1"
    local spec_path="$2"
    local impl_path="${3:-}"

    mkdir -p ".apr/workflows"
    {
        echo "name: default"
        echo "description: Test workflow"
        echo "documents:"
        echo "  readme: $readme_path"
        echo "  spec: $spec_path"
        if [[ -n "$impl_path" ]]; then
            echo "  implementation: $impl_path"
        fi
        echo "api:"
        echo "  model: \"gpt-5.5\""
        echo "  reasoning_effort: high"
        echo "rounds:"
        echo "  output_dir: .apr/rounds/default"
    } > ".apr/workflows/default.yaml"
    echo "default_workflow: default" > ".apr/config.yaml"
}

create_path_without_api() {
    local mock_bin="$TEST_DIR/no_api_bin"
    mkdir -p "$mock_bin"
    ln -s "$(command -v jq)" "$mock_bin/jq"
    ln -s "$(command -v awk)" "$mock_bin/awk"
    ln -s "$(command -v date)" "$mock_bin/date"
    ln -s "$(command -v mktemp)" "$mock_bin/mktemp"
    ln -s "$(command -v mkdir)" "$mock_bin/mkdir"
    ln -s "$(command -v rm)" "$mock_bin/rm"
    ln -s "$(command -v cat)" "$mock_bin/cat"
    echo "$mock_bin"
}

assert_json_array_contains() {
    local json="$1"
    local path="$2"
    local expected="$3"

    if ! echo "$json" | jq -e --arg exp "$expected" "$path | index(\$exp)" > /dev/null; then
        log_test_error "Expected $path to include: $expected"
        fail "Expected $path to include: $expected"
    fi
}

@test "preflight_check: happy path returns 0" {
    create_docs
    setup_mock_api

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"Direct API ready"* ]]
}

@test "preflight_check: missing API key returns 1" {
    create_docs
    unset OPENAI_API_KEY 2>/dev/null || true

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"OPENAI_API_KEY is not set"* ]]
}

@test "preflight_check: README missing returns 1" {
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    setup_mock_api

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"README not found"* ]]
}

@test "preflight_check: Spec missing returns 1" {
    printf '%s\n' "# README" > "$TEST_PROJECT/README.md"
    setup_mock_api

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"Spec not found"* ]]
}

@test "preflight_check: impl missing returns warning (2)" {
    create_docs
    setup_mock_api

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/MISSING_IMPL.md"

    [[ "$CAPTURED_STATUS" -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *"Implementation not found"* ]]
}

@test "run_round: missing workflow config returns EXIT_CONFIG_ERROR" {
    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; run_round 1'

    [[ "$status" -eq 4 ]]
}

@test "run_round: missing required document returns EXIT_CONFIG_ERROR" {
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    write_workflow_config "$TEST_PROJECT/MISSING_README.md" "$TEST_PROJECT/SPEC.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; DRY_RUN=true; run_round 1' 2>&1

    [[ "$status" -eq 4 ]]
    [[ "$output" == *"Required file not found"* ]]
}

@test "run_round: include_impl with no implementation configured warns and continues" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; INCLUDE_IMPL=true; DRY_RUN=true; run_round 1' 2>&1

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Implementation document not configured; skipping"* ]]
    [[ "$output" == *"POST"* ]]
}

@test "run_round: existing output can cancel with prompt" {
    create_docs
    setup_mock_api
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    mkdir -p ".apr/rounds/default"
    printf '%s\n' "existing" > ".apr/rounds/default/round_1.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; SKIP_PREFLIGHT=true; can_prompt() { return 0; }; confirm() { return 1; }; run_round 1' 2>&1

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Cancelled."* ]]
}

@test "robot_validate: missing round number returns usage_error" {
    capture_streams robot_validate

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "usage_error"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Round number required"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=usage_error"* ]]
}

@test "robot_validate: not initialized returns not_configured" {
    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "not_configured"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Not initialized - run 'apr robot init'"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=not_configured"* ]]
}

@test "robot_validate: API missing populates errors" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    unset OPENAI_API_KEY 2>/dev/null || true

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "validation_failed"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Direct API not available: OPENAI_API_KEY is not set"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=validation_failed"* ]]
}

@test "robot_validate: previous round missing yields warnings but ok true" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    setup_mock_api

    capture_streams robot_validate 2

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "true"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.warnings" "Previous round 1 not found - starting fresh?"
    [[ -z "$CAPTURED_STDERR" ]]
}

@test "robot_validate: all valid returns ok true" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    setup_mock_api

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "true"
    assert_json_value "$CAPTURED_STDOUT" ".code" "ok"
    [[ -z "$CAPTURED_STDERR" ]]
}
