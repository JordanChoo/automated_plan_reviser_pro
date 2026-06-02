#!/usr/bin/env bash
# logging.bash - Detailed test logging infrastructure for APR tests
#
# Provides comprehensive logging for debugging test failures.
# Each test logs: inputs, expected output, actual output, pass/fail status.

# =============================================================================
# Configuration
# =============================================================================

# Log directory (set during test setup)
TEST_LOG_DIR="${TEST_LOG_DIR:-}"

# Current test log file
TEST_LOG_FILE="${TEST_LOG_FILE:-}"

# Verbosity level (0=quiet, 1=normal, 2=verbose, 3=debug)
TEST_VERBOSITY="${TEST_VERBOSITY:-1}"

# =============================================================================
# Log File Management
# =============================================================================

# init_test_logging - Initialize logging for a test run
# Usage: init_test_logging [log_dir]
init_test_logging() {
    local log_dir="${1:-${TMPDIR:-/tmp}/apr_test_logs}"
    TEST_LOG_DIR="$log_dir"
    mkdir -p "$TEST_LOG_DIR"

    # Create log file with timestamp
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    TEST_LOG_FILE="$TEST_LOG_DIR/test_run_${timestamp}.log"

    # Write header
    {
        echo "========================================"
        echo "APR Test Run: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================"
        echo ""
    } >> "$TEST_LOG_FILE"
}

# get_log_file - Get current log file path, initializing if needed
get_log_file() {
    if [[ -z "$TEST_LOG_FILE" || ! -f "$TEST_LOG_FILE" ]]; then
        init_test_logging "${TEST_LOG_DIR:-${TMPDIR:-/tmp}/apr_test_logs}"
    fi
    echo "$TEST_LOG_FILE"
}

# =============================================================================
# Core Logging Functions
# =============================================================================

# log_raw - Write raw message to log file
# Usage: log_raw "message"
log_raw() {
    local log_file
    log_file="$(get_log_file)"
    echo "$*" >> "$log_file"
}

# log_timestamp - Write timestamped message to log file
# Usage: log_timestamp "message"
log_timestamp() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
    log_raw "[$timestamp] $*"
}

# =============================================================================
# Test-Oriented Logging
# =============================================================================

# log_test_start - Log the start of a test
# Usage: log_test_start "test_name"
log_test_start() {
    local test_name="$1"
    log_raw ""
    log_raw "----------------------------------------"
    log_timestamp "TEST START: $test_name"
    log_raw "----------------------------------------"
}

# log_test_end - Log the end of a test
# Usage: log_test_end "test_name" "pass|fail" [reason]
log_test_end() {
    local test_name="$1"
    local status="$2"
    local reason="${3:-}"

    log_raw "----------------------------------------"
    if [[ "$status" == "pass" ]]; then
        log_timestamp "TEST PASS: $test_name"
    else
        log_timestamp "TEST FAIL: $test_name"
        if [[ -n "$reason" ]]; then
            log_raw "  Reason: $reason"
        fi
    fi
    log_raw "----------------------------------------"
    log_raw ""
}

# log_test_step - Log a step within a test
# Usage: log_test_step "step_type" "message"
log_test_step() {
    local step_type="$1"
    local message="$2"

    case "$step_type" in
        setup)    log_timestamp "  [SETUP] $message" ;;
        teardown) log_timestamp "  [TEARDOWN] $message" ;;
        action)   log_timestamp "  [ACTION] $message" ;;
        check)    log_timestamp "  [CHECK] $message" ;;
        fixture)  log_timestamp "  [FIXTURE] $message" ;;
        load)     log_timestamp "  [LOAD] $message" ;;
        mock)     log_timestamp "  [MOCK] $message" ;;
        *)        log_timestamp "  [$step_type] $message" ;;
    esac
}

# log_test_input - Log test inputs
# Usage: log_test_input "description" "value"
log_test_input() {
    local description="$1"
    local value="$2"

    log_raw "  INPUT: $description"
    log_raw "    $value"
}

# log_test_expected - Log expected output
# Usage: log_test_expected "description" "value"
log_test_expected() {
    local description="$1"
    local value="$2"

    log_raw "  EXPECTED: $description"
    log_raw "    $value"
}

# log_test_actual - Log actual output
# Usage: log_test_actual "description" "value"
log_test_actual() {
    local description="$1"
    local value="$2"

    log_raw "  ACTUAL: $description"
    log_raw "    $value"
}

# log_test_output - Log command output (multi-line safe)
# Usage: log_test_output "$output"
log_test_output() {
    local output="$1"

    log_raw "  OUTPUT:"
    while IFS= read -r line; do
        printf '    %s\n' "$line"
    done <<< "$output" >> "$(get_log_file)"
}

# log_test_error - Log an error
# Usage: log_test_error "message"
log_test_error() {
    local message="$1"
    log_timestamp "  [ERROR] $message"
}

# log_test_warning - Log a warning
# Usage: log_test_warning "message"
log_test_warning() {
    local message="$1"
    log_timestamp "  [WARNING] $message"
}

# =============================================================================
# Command Logging
# =============================================================================

# log_command - Log a command and its result
# Usage: log_command "command" "exit_status" "output"
log_command() {
    local command="$1"
    local exit_status="$2"
    local output="$3"

    log_raw "  COMMAND: $command"
    log_raw "  EXIT: $exit_status"
    if [[ -n "$output" ]]; then
        log_raw "  OUTPUT:"
        local output_head
        output_head=$(printf '%s\n' "$output" | head -50)
        while IFS= read -r line; do
            printf '    %s\n' "$line"
        done <<< "$output_head" >> "$(get_log_file)"
        local line_count
        line_count=$(echo "$output" | wc -l)
        if (( line_count > 50 )); then
            log_raw "    ... ($(( line_count - 50 )) more lines)"
        fi
    fi
}

# =============================================================================
# Diff Logging
# =============================================================================

# log_diff - Log a diff between expected and actual
# Usage: log_diff "expected" "actual"
log_diff() {
    local expected="$1"
    local actual="$2"

    log_raw "  DIFF (expected vs actual):"
    diff -u <(echo "$expected") <(echo "$actual") 2>/dev/null | sed 's/^/    /' >> "$(get_log_file)" || true
}

# =============================================================================
# Summary Logging
# =============================================================================

# log_summary - Write test run summary
# Usage: log_summary passed failed skipped total
log_summary() {
    local passed="${1:-0}"
    local failed="${2:-0}"
    local skipped="${3:-0}"
    local total="${4:-0}"

    log_raw ""
    log_raw "========================================"
    log_raw "TEST SUMMARY"
    log_raw "========================================"
    log_timestamp "Completed"
    log_raw "  Total:   $total"
    log_raw "  Passed:  $passed"
    log_raw "  Failed:  $failed"
    log_raw "  Skipped: $skipped"
    log_raw "========================================"

    # Also print to stderr for visibility
    if (( TEST_VERBOSITY >= 1 )); then
        echo "" >&2
        echo "Test log written to: $(get_log_file)" >&2
    fi
}

# =============================================================================
# Console Output (for verbose mode)
# =============================================================================

# log_console - Print to console if verbosity allows
# Usage: log_console level "message"
log_console() {
    local level="$1"
    local message="$2"

    if (( TEST_VERBOSITY >= level )); then
        echo "$message" >&2
    fi
}
