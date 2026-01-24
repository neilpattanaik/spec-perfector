#!/usr/bin/env bats
# test_preflight.bats - Unit tests for preflight_check and validation paths

# Load test helpers
load '../helpers/test_helper.bash'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"
    cd "$TEST_PROJECT"
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Helper Functions
# =============================================================================

create_docs() {
    local dir="${1:-$TEST_PROJECT}"
    mkdir -p "$dir"

    # Keep fixtures comfortably above preflight "suspiciously small" thresholds.
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

    log_test_step "fixture" "Created test docs in $dir"
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
        echo "oracle:"
        echo "  model: \"5.2 Thinking\""
        echo "rounds:"
        echo "  output_dir: .apr/rounds/default"
    } > ".apr/workflows/default.yaml"

    echo "default_workflow: default" > ".apr/config.yaml"
}

create_oracle_version_fail() {
    local mock_bin="$TEST_DIR/mock_oracle_fail"
    mkdir -p "$mock_bin"

    cat > "$mock_bin/oracle" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    exit 1
fi
echo "mock oracle ok"
exit 0
EOF
    chmod +x "$mock_bin/oracle"

    echo "$mock_bin"
}

create_path_without_oracle() {
    local mock_bin="$TEST_DIR/no_oracle_bin"
    mkdir -p "$mock_bin"

    ln -s "$(command -v jq)" "$mock_bin/jq"
    ln -s "$(command -v awk)" "$mock_bin/awk"
    ln -s "$(command -v date)" "$mock_bin/date"
    # Keep enough coreutils available for test helpers (capture_streams, logging).
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

# =============================================================================
# preflight_check() Tests
# =============================================================================

@test "preflight_check: happy path returns 0" {
    create_docs
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 0 ]]
}

@test "preflight_check: README missing returns 1" {
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"README not found"* ]]
}

@test "preflight_check: README not readable returns 1" {
    create_docs
    chmod 000 "$TEST_PROJECT/README.md"
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"README not readable"* ]]
}

@test "preflight_check: Spec missing returns 1" {
    printf '%s\n' "# README" > "$TEST_PROJECT/README.md"
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"Spec not found"* ]]
}

@test "preflight_check: Spec not readable returns 1" {
    create_docs
    chmod 000 "$TEST_PROJECT/SPEC.md"
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"Spec not readable"* ]]
}

@test "preflight_check: impl missing returns warning (2)" {
    create_docs
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/MISSING_IMPL.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *"Implementation not found"* ]]
}

@test "preflight_check: impl not readable returns warning (2)" {
    create_docs
    chmod 000 "$TEST_PROJECT/IMPL.md"
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *"Implementation not readable"* ]]
}

@test "preflight_check: impl valid returns 0" {
    create_docs
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 0 ]]
}

@test "preflight_check: oracle missing returns 1" {
    create_docs
    check_oracle() { return 1; }

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"Oracle not available"* ]]
}

@test "preflight_check: oracle version check failure returns warning (2)" {
    create_docs
    local mock_bin
    mock_bin="$(create_oracle_version_fail)"
    local original_path="$PATH"
    PATH="$mock_bin:$PATH"
    export PATH

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    PATH="$original_path"
    export PATH

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *"Could not verify Oracle version"* ]]
}

# =============================================================================
# run_round() Validation Path Tests
# =============================================================================

@test "run_round: missing workflow config returns EXIT_CONFIG_ERROR" {
    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; run_round 1'

    log_test_actual "exit code" "$status"
    [[ "$status" -eq 4 ]]
}

@test "run_round: missing required document returns EXIT_CONFIG_ERROR" {
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    write_workflow_config "$TEST_PROJECT/MISSING_README.md" "$TEST_PROJECT/SPEC.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; DRY_RUN=true; run_round 1' 2>&1

    log_test_actual "exit code" "$status"
    [[ "$status" -eq 4 ]]
    [[ "$output" == *"Required file not found"* ]]
}

@test "run_round: include_impl with no implementation configured warns and continues" {
    printf '%s\n' "# README" > "$TEST_PROJECT/README.md"
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; INCLUDE_IMPL=true; DRY_RUN=true; run_round 1' 2>&1

    log_test_actual "exit code" "$status"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Implementation document not configured; skipping"* ]]
}

@test "run_round: include_impl with missing file warns and continues" {
    printf '%s\n' "# README" > "$TEST_PROJECT/README.md"
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/MISSING_IMPL.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; INCLUDE_IMPL=true; DRY_RUN=true; run_round 1' 2>&1

    log_test_actual "exit code" "$status"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Implementation file not found"* ]]
}

@test "run_round: existing output can cancel with prompt" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    mkdir -p ".apr/rounds/default"
    printf '%s\n' "existing" > ".apr/rounds/default/round_1.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; SKIP_PREFLIGHT=true; can_prompt() { return 0; }; confirm() { return 1; }; run_round 1' 2>&1

    log_test_actual "exit code" "$status"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Cancelled."* ]]
}

# =============================================================================
# robot_validate() Tests
# =============================================================================

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

@test "robot_validate: workflow not found returns validation_failed" {
    mkdir -p ".apr/workflows"
    echo "default_workflow: default" > ".apr/config.yaml"

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "validation_failed"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Workflow 'default' not found"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=validation_failed"* ]]
}

@test "robot_validate: README missing populates errors" {
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    write_workflow_config "$TEST_PROJECT/MISSING_README.md" "$TEST_PROJECT/SPEC.md"
    setup_mock_oracle

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "validation_failed"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "README not found: $TEST_PROJECT/MISSING_README.md"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=validation_failed"* ]]
}

@test "robot_validate: spec missing populates errors" {
    printf '%s\n' "# README" > "$TEST_PROJECT/README.md"
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/MISSING_SPEC.md"
    setup_mock_oracle

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "validation_failed"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Spec not found: $TEST_PROJECT/MISSING_SPEC.md"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=validation_failed"* ]]
}

@test "robot_validate: oracle missing populates errors" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    local original_path="$PATH"
    local mock_path
    mock_path="$(create_path_without_oracle)"
    PATH="$mock_path"
    export PATH

    capture_streams robot_validate 1

    PATH="$original_path"
    export PATH

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "validation_failed"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Oracle not available"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=validation_failed"* ]]
}

@test "robot_validate: previous round missing yields warnings but ok true" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    setup_mock_oracle

    capture_streams robot_validate 2

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "true"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.warnings" "Previous round 1 not found - starting fresh?"
    [[ -z "$CAPTURED_STDERR" ]]
}

@test "robot_validate: all valid returns ok true" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    setup_mock_oracle

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "true"
    assert_json_value "$CAPTURED_STDOUT" ".code" "ok"
    [[ -z "$CAPTURED_STDERR" ]]
}
