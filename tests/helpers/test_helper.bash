#!/usr/bin/env bash
# test_helper.bash - Common setup/teardown and utilities for APR tests
#
# This file is sourced by all BATS test files.
# It provides:
#   - Test environment setup/teardown
#   - APR function loading for unit tests
#   - Common fixtures and paths
#   - Custom assertions for APR-specific testing

# Strict mode for helper functions
set -euo pipefail

# =============================================================================
# Path Configuration
# =============================================================================

# Get the directory containing this helper
HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$HELPERS_DIR")"
PROJECT_ROOT="$(dirname "$TESTS_DIR")"

# BATS libraries
BATS_LIB_DIR="$TESTS_DIR/lib"

# Load BATS helper libraries
load "$BATS_LIB_DIR/bats-support/load"
load "$BATS_LIB_DIR/bats-assert/load"

# Load our custom helpers
# shellcheck disable=SC1091  # Test helper paths are resolved at runtime.
source "$HELPERS_DIR/logging.bash"
# shellcheck disable=SC1091  # Test helper paths are resolved at runtime.
source "$HELPERS_DIR/assertions.bash"

# Fixtures directory
# shellcheck disable=SC2034  # Used by test files
FIXTURES_DIR="$TESTS_DIR/fixtures"

# APR script path
APR_SCRIPT="$PROJECT_ROOT/apr"

# =============================================================================
# Test Environment Setup/Teardown
# =============================================================================

# setup_test_environment - Create isolated temp directory for test
# Sets TEST_DIR, TEST_HOME, and configures XDG paths
setup_test_environment() {
    # Create unique temp directory for this test
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apr_test.XXXXXX")"
    export TEST_DIR

    # Save real home for tests that need access to installed tools
    export REAL_HOME="${HOME}"

    # Create isolated home directory
    TEST_HOME="$TEST_DIR/home"
    mkdir -p "$TEST_HOME"
    export HOME="$TEST_HOME"

    # Configure XDG paths to use test directory
    export XDG_DATA_HOME="$TEST_DIR/data"
    export XDG_CACHE_HOME="$TEST_DIR/cache"
    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

    # Create a test project directory
    TEST_PROJECT="$TEST_DIR/project"
    mkdir -p "$TEST_PROJECT"
    export TEST_PROJECT

    # Initialize as git repo (many APR features expect git)
    (cd "$TEST_PROJECT" && git init -q)

    # Disable colors and gum for deterministic output
    export NO_COLOR=1
    export APR_NO_GUM=1
    export CI=true

    # Disable update checks (unset, not =0, because script checks for empty)
    unset APR_CHECK_UPDATES 2>/dev/null || true

    # Log test setup
    log_test_step "setup" "Created test environment at $TEST_DIR"
}

# teardown_test_environment - Clean up test directory
teardown_test_environment() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        # Log before cleanup
        log_test_step "teardown" "Cleaning up $TEST_DIR"

        # Remove test directory
        rm -rf "$TEST_DIR"
    fi
}

# Standard BATS setup/teardown hooks
setup() {
    setup_test_environment
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# APR Function Loading (for Unit Tests)
# =============================================================================

# APR functions loaded flag
_APR_FUNCTIONS_LOADED=false

# load_apr_functions - Source APR script to access internal functions
# This allows unit testing of individual functions without running the full script
load_apr_functions() {
    if [[ "$_APR_FUNCTIONS_LOADED" == "true" ]]; then
        return 0
    fi

    # We need to source apr but prevent it from running main()
    # APR uses 'main "$@"' at the end, so we need to intercept

    # Create a modified version that doesn't call main
    local apr_functions="$TEST_DIR/apr_functions.bash"

    # Extract everything except the final main call
    sed '/^main "\$@"$/d' "$APR_SCRIPT" > "$apr_functions"

    # Source the functions
    # shellcheck disable=SC1090
    source "$apr_functions"

    _APR_FUNCTIONS_LOADED=true
    log_test_step "load" "Loaded APR functions from $APR_SCRIPT"
}

# =============================================================================
# Test Fixture Helpers
# =============================================================================

# setup_test_workflow - Create a complete test workflow configuration
# Usage: setup_test_workflow [workflow_name]
setup_test_workflow() {
    local workflow="${1:-default}"

    cd "$TEST_PROJECT" || return 1

    # Create sample documents
    cat > README.md << 'EOF'
# Test Project

This is a test project for APR testing.

## Features
- Feature 1
- Feature 2
EOF

    cat > SPECIFICATION.md << 'EOF'
# Specification

## Overview
This is the specification document.

## Requirements
1. Requirement A
2. Requirement B
EOF

    cat > IMPLEMENTATION.md << 'EOF'
# Implementation

## Architecture
Description of the implementation.
EOF

    # Create .apr directory structure
    mkdir -p ".apr/workflows" ".apr/rounds/$workflow" ".apr/templates"

    # Create config.yaml
    cat > .apr/config.yaml << EOF
default_workflow: $workflow
EOF

    # Create workflow config
    cat > ".apr/workflows/${workflow}.yaml" << EOF
name: $workflow
description: Test workflow for $workflow

documents:
  readme: README.md
  spec: SPECIFICATION.md
  implementation: IMPLEMENTATION.md

api:
  model: "gpt-5.5"
  reasoning_effort: high

rounds:
  output_dir: .apr/rounds/$workflow

template: |
  First, read the attached README.md.

  Now read the attached SPECIFICATION.md.

  Please analyze and provide feedback.

template_with_impl: |
  First, read the attached README.md.

  Now read the attached SPECIFICATION.md.

  And the attached IMPLEMENTATION.md.

  Please analyze and provide feedback.
EOF

    log_test_step "fixture" "Created test workflow '$workflow' in $TEST_PROJECT"
}

# create_mock_round - Create a mock round output file
# Usage: create_mock_round <round_number> [workflow] [content]
create_mock_round() {
    local round="$1"
    local workflow="${2:-default}"
    local content="${3:-}"

    local rounds_dir="$TEST_PROJECT/.apr/rounds/$workflow"
    mkdir -p "$rounds_dir"

    local round_file="$rounds_dir/round_${round}.md"

    if [[ -z "$content" ]]; then
        content="# Round $round Analysis

## Summary
This is the analysis for round $round.

## Recommendations
1. First recommendation
2. Second recommendation

## Conclusion
Round $round complete.
"
    fi

    echo "$content" > "$round_file"
    log_test_step "fixture" "Created mock round $round at $round_file"
}

# setup_test_metrics - Create test metrics file for a workflow
# Usage: setup_test_metrics [workflow]
setup_test_metrics() {
    local workflow="${1:-default}"
    local metrics_dir="$TEST_PROJECT/.apr/analytics/$workflow"
    mkdir -p "$metrics_dir"

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$metrics_dir/metrics.json" << EOF
{
  "schema_version": "1.0.0",
  "workflow": "$workflow",
  "created_at": "$ts",
  "updated_at": "$ts",
  "rounds": [
    {
      "round": 1,
      "timestamp": "$ts",
      "size_bytes": 1024,
      "word_count": 150,
      "section_count": 3
    }
  ],
  "convergence": {
    "detected": false,
    "confidence": 0.0,
    "estimated_rounds_remaining": null,
    "signals": {}
  }
}
EOF
    log_test_step "fixture" "Created test metrics for workflow '$workflow'"
}

# =============================================================================
# Stream Capture Utilities
# =============================================================================

# capture_streams - Run a command and capture stdout/stderr separately
# Usage: capture_streams command [args...]
# Sets: CAPTURED_STDOUT, CAPTURED_STDERR, CAPTURED_STATUS
capture_streams() {
    local stdout_file stderr_file
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"

    # Don't let Bats' ERR trap (and our helper's `set -e`) turn a non-zero exit
    # into an immediate test failure. We intentionally capture failures.
    # shellcheck disable=SC2034  # Used by callers
    CAPTURED_STATUS=0
    # shellcheck disable=SC2034  # Used by callers
    "$@" > "$stdout_file" 2> "$stderr_file" || CAPTURED_STATUS=$?

    # shellcheck disable=SC2034  # Used by callers
    CAPTURED_STDOUT="$(cat "$stdout_file")"
    # shellcheck disable=SC2034  # Used by callers
    CAPTURED_STDERR="$(cat "$stderr_file")"

    rm -f "$stdout_file" "$stderr_file"
}

# =============================================================================
# Mock Responses API (for tests that do not call the real API)
# =============================================================================

# setup_mock_api - Create a mock curl command for API-backed tests
setup_mock_api() {
    local mock_curl="$TEST_DIR/bin/curl"
    mkdir -p "$(dirname "$mock_curl")"
    export OPENAI_API_KEY="test-openai-key"
    export OPENAI_BASE_URL="https://mock.openai.test/v1"
    export APR_API_POLL_INTERVAL="${APR_API_POLL_INTERVAL:-1}"
    export APR_API_MAX_POLL_SECONDS="${APR_API_MAX_POLL_SECONDS:-5}"

    cat > "$mock_curl" << 'EOF'
#!/usr/bin/env bash
# Mock curl for APR Responses API testing.
method="GET"
url=""
write_status=false
data_arg=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -X)
            method="${2:-GET}"
            shift 2
            ;;
        -w)
            write_status=true
            shift 2
            ;;
        --data-binary)
            data_arg="${2:-}"
            shift 2
            ;;
        -H|--connect-timeout|--max-time)
            shift 2
            ;;
        http://*|https://*)
            url="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

payload=""
if [[ "$method" == "POST" ]]; then
    if [[ "$data_arg" == "@-" ]]; then
        payload=$(cat)
    elif [[ -n "$data_arg" ]]; then
        payload="$data_arg"
    fi
fi

mock_output_text() {
    local id="$1"
    {
        printf 'Mock API review output for %s.\n\n' "$id"
        for i in $(seq 1 80); do
            printf 'Recommendation %02d: tighten the specification, validate assumptions, and keep the implementation aligned with the plan.\n' "$i"
        done
        printf '\nComplete.\n'
    }
}

http_code="${MOCK_API_HTTP_CODE:-200}"
if [[ ! "$http_code" =~ ^2 ]]; then
    body=$(jq -nc --arg msg "${MOCK_API_ERROR:-mock api error}" '{error:{message:$msg}}')
elif [[ "$method" == "POST" ]]; then
    slug=$(printf '%s' "$payload" | jq -r '.metadata.apr_slug // "apr-mock-round-1"' 2>/dev/null || echo "apr-mock-round-1")
    response_id="resp_mock_${slug//[^A-Za-z0-9_]/_}"
    status="${MOCK_API_CREATE_STATUS:-in_progress}"
    if [[ "$status" == "completed" ]]; then
        text=$(mock_output_text "$response_id")
        body=$(jq -nc --arg id "$response_id" --arg status "$status" --arg text "$text" \
            '{id:$id, object:"response", status:$status, output_text:$text, output:[{type:"message", content:[{type:"output_text", text:$text}]}]}')
    else
        body=$(jq -nc --arg id "$response_id" --arg status "$status" '{id:$id, object:"response", status:$status}')
    fi
else
    response_id="${url##*/}"
    status="${MOCK_API_GET_STATUS:-completed}"
    if [[ "$status" == "completed" ]]; then
        text=$(mock_output_text "$response_id")
        body=$(jq -nc --arg id "$response_id" --arg status "$status" --arg text "$text" \
            '{id:$id, object:"response", status:$status, output_text:$text, output:[{type:"message", content:[{type:"output_text", text:$text}]}]}')
    else
        body=$(jq -nc --arg id "$response_id" --arg status "$status" '{id:$id, object:"response", status:$status}')
    fi
fi

printf '%s' "$body"
if [[ "$write_status" == "true" ]]; then
    printf '\n%s' "$http_code"
fi
EOF
    chmod +x "$mock_curl"

    # Add to PATH
    export PATH="$TEST_DIR/bin:$PATH"

    log_test_step "mock" "Created mock API curl at $mock_curl"
}

# =============================================================================
# Utility Functions
# =============================================================================

# skip_if_no_gum - Skip test if gum is required but not available
skip_if_no_gum() {
    if ! command -v gum &>/dev/null; then
        skip "gum not available"
    fi
}

# get_apr_version - Get APR version from VERSION file or script
get_apr_version() {
    if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
        cat "$PROJECT_ROOT/VERSION"
    else
        "$APR_SCRIPT" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
    fi
}
