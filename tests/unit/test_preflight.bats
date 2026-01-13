#!/usr/bin/env bats
# test_preflight.bats - Unit tests for APR preflight/validation helpers
#
# Tests:
#   - preflight_check success path
#   - missing/readability failures
#   - implementation warning path
#   - oracle missing failure

load '../helpers/test_helper'

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"

    export NO_COLOR=1
    export APR_NO_GUM=1
    export GUM_AVAILABLE=false
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

create_basic_docs() {
    cd "$TEST_PROJECT" || return 1
    cat > README.md << 'DOC'
# README
Test readme.
DOC
    cat > SPECIFICATION.md << 'DOC'
# Spec
Test spec.
DOC
}

@test "preflight_check succeeds with valid files and oracle" {
    setup_mock_oracle
    create_basic_docs

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPECIFICATION.md"

    [[ $CAPTURED_STATUS -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"All pre-flight checks passed"* ]]
}

@test "preflight_check fails when README missing" {
    setup_mock_oracle
    cd "$TEST_PROJECT" || return 1
    cat > SPECIFICATION.md << 'DOC'
# Spec
DOC

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPECIFICATION.md"

    [[ $CAPTURED_STATUS -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"README not found"* ]]
}

@test "preflight_check fails when spec missing" {
    setup_mock_oracle
    cd "$TEST_PROJECT" || return 1
    cat > README.md << 'DOC'
# README
DOC

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPECIFICATION.md"

    [[ $CAPTURED_STATUS -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"Spec not found"* ]]
}

@test "preflight_check warns when implementation missing" {
    setup_mock_oracle
    create_basic_docs

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPECIFICATION.md" "$TEST_PROJECT/IMPLEMENTATION.md"

    [[ $CAPTURED_STATUS -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *"Implementation not found"* ]]
    [[ "$CAPTURED_STDERR" == *"Pre-flight completed with warnings"* ]]
}

@test "preflight_check fails when oracle missing" {
    create_basic_docs

    check_oracle() {
        return 1
    }

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPECIFICATION.md"

    [[ $CAPTURED_STATUS -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"Oracle not available"* ]]

    unset -f check_oracle
}

@test "preflight_check fails when README not readable" {
    setup_mock_oracle
    create_basic_docs
    chmod 000 "$TEST_PROJECT/README.md"

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPECIFICATION.md"

    [[ $CAPTURED_STATUS -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"README not readable"* ]]
}
