#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # BATS runs each test in an isolated shell.
# test_install.bats - Integration tests for install.sh
#
# Tests installer behavior with mocked network downloads.

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    log_test_start "${BATS_TEST_NAME}"
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Mock curl (no network)
# =============================================================================

setup_mock_curl() {
    local mock_bin="$TEST_DIR/bin"
    mkdir -p "$mock_bin"

    cat > "$mock_bin/curl" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

out=""
url=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            out="$2"
            shift 2
            ;;
        *)
            url="$1"
            shift
            ;;
    esac
done

if [[ -z "$url" ]]; then
    exit 1
fi

if [[ -n "${out:-}" ]]; then
    if [[ "$url" == *"apr.sha256"* ]]; then
        cp "$APR_TEST_REMOTE_SHA" "$out"
    else
        cp "$APR_TEST_REMOTE_APR" "$out"
    fi
else
    if [[ "$url" == *"apr.sha256"* ]]; then
        cat "$APR_TEST_REMOTE_SHA"
    else
        cat "$APR_TEST_REMOTE_APR"
    fi
fi
EOF

    chmod +x "$mock_bin/curl"

    # Ensure curl is found before system binaries
    export PATH="$mock_bin:$PATH"
}

setup_mock_curl_without_hash_tools() {
    local mock_bin="$TEST_DIR/no_hash_bin"
    mkdir -p "$mock_bin"

    cat > "$mock_bin/curl" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

out=""
url=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            out="$2"
            shift 2
            ;;
        *)
            url="$1"
            shift
            ;;
    esac
done

if [[ -z "$url" ]]; then
    exit 1
fi

if [[ -n "${out:-}" ]]; then
    if [[ "$url" == *"apr.sha256"* ]]; then
        cp "$APR_TEST_REMOTE_SHA" "$out"
    else
        cp "$APR_TEST_REMOTE_APR" "$out"
    fi
else
    if [[ "$url" == *"apr.sha256"* ]]; then
        cat "$APR_TEST_REMOTE_SHA"
    else
        cat "$APR_TEST_REMOTE_APR"
    fi
fi
EOF

    chmod +x "$mock_bin/curl"

    local tool
    for tool in awk basename bash cat chmod cp cut date dirname env grep head mkdir mktemp mv rm sleep tr uname; do
        ln -s "$(command -v "$tool")" "$mock_bin/$tool"
    done

    export PATH="$mock_bin"
}

# =============================================================================
# Tests
# =============================================================================

@test "install.sh: installs APR to DEST with APR_SKIP_VERIFY" {
    local remote_apr="$TEST_DIR/remote_apr"
    local remote_sha="$TEST_DIR/remote_apr.sha256"
    cp "$APR_SCRIPT" "$remote_apr"
    echo "dummy" > "$remote_sha"

    export APR_TEST_REMOTE_APR="$remote_apr"
    export APR_TEST_REMOTE_SHA="$remote_sha"
    setup_mock_curl

    local dest_dir="$TEST_DIR/install/bin"

    run env \
        DEST="$dest_dir" \
        APR_NO_DEPS=1 \
        APR_SKIP_VERIFY=1 \
        APR_SKIP_INSTALLER_CHECK=1 \
        NO_COLOR=1 \
        bash "$PROJECT_ROOT/install.sh"

    log_test_output "$output"

    assert_success
    assert_file_exists "$dest_dir/apr"
    [[ -x "$dest_dir/apr" ]]
}

@test "install.sh: verifies checksum when available" {
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        skip "No sha256sum or shasum available"
    fi

    local remote_apr="$TEST_DIR/remote_apr"
    local remote_sha="$TEST_DIR/remote_apr.sha256"
    cp "$APR_SCRIPT" "$remote_apr"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$remote_apr" | awk '{print $1}' > "$remote_sha"
    else
        shasum -a 256 "$remote_apr" | awk '{print $1}' > "$remote_sha"
    fi

    export APR_TEST_REMOTE_APR="$remote_apr"
    export APR_TEST_REMOTE_SHA="$remote_sha"
    setup_mock_curl

    local dest_dir="$TEST_DIR/install_checksum/bin"

    run env \
        DEST="$dest_dir" \
        APR_NO_DEPS=1 \
        APR_SKIP_INSTALLER_CHECK=1 \
        NO_COLOR=1 \
        bash "$PROJECT_ROOT/install.sh"

    log_test_output "$output"

    assert_success
    assert_file_exists "$dest_dir/apr"
}

@test "install.sh: fails when checksum exists but no hash tool is available" {
    local original_path="$PATH"
    local remote_apr="$TEST_DIR/remote_apr"
    local remote_sha="$TEST_DIR/remote_apr.sha256"
    cp "$APR_SCRIPT" "$remote_apr"
    printf '%064d\n' 0 > "$remote_sha"

    export APR_TEST_REMOTE_APR="$remote_apr"
    export APR_TEST_REMOTE_SHA="$remote_sha"
    setup_mock_curl_without_hash_tools

    local dest_dir="$TEST_DIR/install_no_hash/bin"

    run env \
        DEST="$dest_dir" \
        APR_NO_DEPS=1 \
        APR_SKIP_INSTALLER_CHECK=1 \
        NO_COLOR=1 \
        bash "$PROJECT_ROOT/install.sh"

    PATH="$original_path"
    export PATH

    log_test_output "$output"

    assert_failure
    [[ "$output" == *"Cannot verify checksum"* ]]
    [[ ! -f "$dest_dir/apr" ]]
}
