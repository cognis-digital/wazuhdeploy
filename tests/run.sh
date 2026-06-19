#!/usr/bin/env bash
#
# tests/run.sh - self-contained test suite for wazuhdeploy.
#
# Runs without Docker or Wazuh installed. Asserts:
#   * generate produces a docker-compose.yml containing the expected services
#   * generate emits the base config files
#   * multi-node generate produces a clustered compose
#   * validate passes on the example config (exit 0)
#   * validate fails on broken configs (non-zero exit): missing var,
#     port conflict, bad deploy mode, bad port value
#   * healthcheck --dry-run lists the right targets (and touches no network)
#   * --help / version behave
#
# Exits non-zero if any assertion fails.
#
# Maintainer: Cognis Digital. License: COCL 1.0

set -u

# Resolve paths relative to this script.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." >/dev/null 2>&1 && pwd)"
WD="$ROOT_DIR/wazuhdeploy.sh"
EXAMPLE="$ROOT_DIR/examples/wazuh.env"
EXAMPLE_MULTI="$ROOT_DIR/examples/wazuh-multi.env"

# Disable colour for deterministic output.
export NO_COLOR=1

PASS=0
FAIL=0
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t wazuhdeploy-test)"

cleanup() {
    rm -rf "$WORK" 2>/dev/null || true
}
trap cleanup EXIT

# --- assertion helpers -----------------------------------------------------

ok() {
    PASS=$((PASS + 1))
    printf '  ok   - %s\n' "$1"
}

bad() {
    FAIL=$((FAIL + 1))
    printf '  FAIL - %s\n' "$1"
    if [ -n "${2:-}" ]; then
        printf '         %s\n' "$2"
    fi
}

# assert_eq <expected> <actual> <message>
assert_eq() {
    if [ "$1" = "$2" ]; then
        ok "$3"
    else
        bad "$3" "expected [$1] got [$2]"
    fi
}

# assert_file_contains <file> <needle> <message>
assert_file_contains() {
    if [ -f "$1" ] && grep -q -- "$2" "$1"; then
        ok "$3"
    else
        bad "$3" "file=$1 needle=$2"
    fi
}

# assert_file_exists <file> <message>
assert_file_exists() {
    if [ -f "$1" ]; then
        ok "$2"
    else
        bad "$2" "missing file: $1"
    fi
}

# assert_contains <haystack> <needle> <message>
assert_contains() {
    case "$1" in
        *"$2"*) ok "$3" ;;
        *) bad "$3" "needle [$2] not in output" ;;
    esac
}

# assert_not_contains <haystack> <needle> <message>
assert_not_contains() {
    case "$1" in
        *"$2"*) bad "$3" "unexpected [$2] in output" ;;
        *) ok "$3" ;;
    esac
}

# run_expect_rc <expected_rc> <message> -- <command...>
# Runs the command, captures combined output, asserts the exit code.
LAST_OUTPUT=""
run_expect_rc() {
    local expected="$1"; shift
    local msg="$1"; shift
    [ "$1" = "--" ] && shift
    local out rc
    out="$("$@" 2>&1)"
    rc=$?
    LAST_OUTPUT="$out"
    if [ "$rc" -eq "$expected" ]; then
        ok "$msg (rc=$rc)"
    else
        bad "$msg" "expected rc=$expected got rc=$rc; output: $out"
    fi
}

# --- begin tests -----------------------------------------------------------

printf '== wazuhdeploy test suite ==\n'
printf 'root: %s\n' "$ROOT_DIR"
printf 'work: %s\n\n' "$WORK"

# Sanity: entrypoint exists.
assert_file_exists "$WD" "entrypoint wazuhdeploy.sh exists"
assert_file_exists "$EXAMPLE" "example config exists"

# --- help / version --------------------------------------------------------
printf '\n-- help & version --\n'
run_expect_rc 0 "help exits 0" -- bash "$WD" help
assert_contains "$LAST_OUTPUT" "wazuhdeploy" "help mentions tool name"
assert_contains "$LAST_OUTPUT" "generate" "help lists generate"
assert_contains "$LAST_OUTPUT" "healthcheck" "help lists healthcheck"
assert_contains "$LAST_OUTPUT" "COCL 1.0" "help shows license line"

run_expect_rc 0 "version exits 0" -- bash "$WD" version
assert_contains "$LAST_OUTPUT" "wazuhdeploy 1.0.0" "version prints version string"

run_expect_rc 1 "no args exits non-zero" -- bash "$WD"
run_expect_rc 1 "unknown command exits non-zero" -- bash "$WD" frobnicate

# --- validate: happy path --------------------------------------------------
printf '\n-- validate (valid) --\n'
run_expect_rc 0 "validate passes on example" -- bash "$WD" validate --config "$EXAMPLE"
assert_contains "$LAST_OUTPUT" "configuration is valid" "valid config reported valid"

run_expect_rc 0 "validate passes on multi-node example" -- bash "$WD" validate --config "$EXAMPLE_MULTI"

# --- validate: broken configs ----------------------------------------------
printf '\n-- validate (broken) --\n'

# Missing required var (no STACK_NAME).
BROKEN_MISSING="$WORK/missing.env"
cat > "$BROKEN_MISSING" <<'EOF'
DEPLOY_MODE=single-node
DATA_DIR=./d
WAZUH_VERSION=4.9.0
INDEXER_NODES=1
INDEXER_PORT=9200
DASHBOARD_PORT=443
MANAGER_API_PORT=55000
AGENT_REGISTRATION_PORT=1515
AGENT_EVENTS_PORT=1514
STACK_NAME=
EOF
run_expect_rc 1 "validate fails on empty required var" -- bash "$WD" validate --config "$BROKEN_MISSING"
assert_contains "$LAST_OUTPUT" "STACK_NAME" "missing-var error names STACK_NAME"

# Port conflict (indexer == manager api).
BROKEN_CONFLICT="$WORK/conflict.env"
cat > "$BROKEN_CONFLICT" <<'EOF'
STACK_NAME=wazuh
DEPLOY_MODE=single-node
DATA_DIR=./d
WAZUH_VERSION=4.9.0
INDEXER_NODES=1
INDEXER_PORT=9200
DASHBOARD_PORT=443
MANAGER_API_PORT=9200
AGENT_REGISTRATION_PORT=1515
AGENT_EVENTS_PORT=1514
EOF
run_expect_rc 1 "validate fails on port conflict" -- bash "$WD" validate --config "$BROKEN_CONFLICT"
assert_contains "$LAST_OUTPUT" "port conflict" "conflict error mentions port conflict"

# Bad deploy mode.
BROKEN_MODE="$WORK/mode.env"
cat > "$BROKEN_MODE" <<'EOF'
STACK_NAME=wazuh
DEPLOY_MODE=triple-node
DATA_DIR=./d
WAZUH_VERSION=4.9.0
INDEXER_NODES=1
INDEXER_PORT=9200
DASHBOARD_PORT=443
MANAGER_API_PORT=55000
AGENT_REGISTRATION_PORT=1515
AGENT_EVENTS_PORT=1514
EOF
run_expect_rc 1 "validate fails on bad deploy mode" -- bash "$WD" validate --config "$BROKEN_MODE"
assert_contains "$LAST_OUTPUT" "DEPLOY_MODE" "bad-mode error names DEPLOY_MODE"

# Bad port value (out of range).
BROKEN_PORT="$WORK/port.env"
cat > "$BROKEN_PORT" <<'EOF'
STACK_NAME=wazuh
DEPLOY_MODE=single-node
DATA_DIR=./d
WAZUH_VERSION=4.9.0
INDEXER_NODES=1
INDEXER_PORT=70000
DASHBOARD_PORT=443
MANAGER_API_PORT=55000
AGENT_REGISTRATION_PORT=1515
AGENT_EVENTS_PORT=1514
EOF
run_expect_rc 1 "validate fails on out-of-range port" -- bash "$WD" validate --config "$BROKEN_PORT"
assert_contains "$LAST_OUTPUT" "valid TCP port" "bad-port error mentions port range"

# Multi-node with too few indexer nodes.
BROKEN_QUORUM="$WORK/quorum.env"
cat > "$BROKEN_QUORUM" <<'EOF'
STACK_NAME=wazuh
DEPLOY_MODE=multi-node
DATA_DIR=./d
WAZUH_VERSION=4.9.0
INDEXER_NODES=2
INDEXER_PORT=9200
DASHBOARD_PORT=443
MANAGER_API_PORT=55000
AGENT_REGISTRATION_PORT=1515
AGENT_EVENTS_PORT=1514
EOF
run_expect_rc 1 "validate fails on multi-node quorum < 3" -- bash "$WD" validate --config "$BROKEN_QUORUM"

# Missing config file.
run_expect_rc 1 "validate fails on missing file" -- bash "$WD" validate --config "$WORK/nope.env"

# Missing required flag.
run_expect_rc 2 "validate without --config exits 2" -- bash "$WD" validate

# --- generate (single-node) ------------------------------------------------
printf '\n-- generate (single-node) --\n'
OUT1="$WORK/deploy-single"
run_expect_rc 0 "generate single-node succeeds" -- bash "$WD" generate --config "$EXAMPLE" --out "$OUT1"

assert_file_exists "$OUT1/docker-compose.yml" "compose file generated"
assert_file_exists "$OUT1/config/ossec.conf" "ossec.conf generated"
assert_file_exists "$OUT1/config/opensearch.yml" "opensearch.yml generated"
assert_file_exists "$OUT1/config/opensearch_dashboards.yml" "dashboard config generated"
assert_file_exists "$OUT1/resolved.env" "resolved.env generated"

# Expected services present, placeholders substituted.
assert_file_contains "$OUT1/docker-compose.yml" "wazuh.manager" "compose contains manager service"
assert_file_contains "$OUT1/docker-compose.yml" "wazuh.indexer" "compose contains indexer service"
assert_file_contains "$OUT1/docker-compose.yml" "wazuh.dashboard" "compose contains dashboard service"
assert_file_contains "$OUT1/docker-compose.yml" "wazuh/wazuh-manager:4.9.0" "compose pins manager image+version"
assert_file_contains "$OUT1/docker-compose.yml" "9200:9200" "compose publishes indexer port"
assert_file_contains "$OUT1/docker-compose.yml" "55000:55000" "compose publishes manager API port"

# No unsubstituted template tokens should remain.
if grep -q '@@' "$OUT1/docker-compose.yml"; then
    bad "no leftover @@TOKEN@@ in compose" "$(grep -n '@@' "$OUT1/docker-compose.yml" | head -n1)"
else
    ok "no leftover @@TOKEN@@ in compose"
fi
if grep -rq '@@' "$OUT1/config/"; then
    bad "no leftover @@TOKEN@@ in config files"
else
    ok "no leftover @@TOKEN@@ in config files"
fi

# ossec.conf wired to the indexer host.
assert_file_contains "$OUT1/config/ossec.conf" "wazuh.indexer:9200" "ossec.conf points at indexer"

# Refuse to overwrite without --force.
run_expect_rc 1 "generate refuses overwrite without --force" -- bash "$WD" generate --config "$EXAMPLE" --out "$OUT1"
# Succeeds with --force.
run_expect_rc 0 "generate overwrites with --force" -- bash "$WD" generate --config "$EXAMPLE" --out "$OUT1" --force

# Missing flags.
run_expect_rc 2 "generate without --out exits 2" -- bash "$WD" generate --config "$EXAMPLE"
run_expect_rc 2 "generate without --config exits 2" -- bash "$WD" generate --out "$OUT1"

# Generate refuses an invalid config.
run_expect_rc 1 "generate refuses invalid config" -- bash "$WD" generate --config "$BROKEN_CONFLICT" --out "$WORK/should-not-exist"

# --- generate (multi-node) -------------------------------------------------
printf '\n-- generate (multi-node) --\n'
OUT2="$WORK/deploy-multi"
run_expect_rc 0 "generate multi-node succeeds" -- bash "$WD" generate --config "$EXAMPLE_MULTI" --out "$OUT2"
assert_file_contains "$OUT2/docker-compose.yml" "wazuh.indexer-1" "multi compose has indexer-1"
assert_file_contains "$OUT2/docker-compose.yml" "wazuh.indexer-2" "multi compose has indexer-2"
assert_file_contains "$OUT2/docker-compose.yml" "wazuh.indexer-3" "multi compose has indexer-3"
assert_file_contains "$OUT2/docker-compose.yml" "cluster.initial_cluster_manager_nodes" "multi compose configures cluster bootstrap"

# --- healthcheck --dry-run -------------------------------------------------
printf '\n-- healthcheck --dry-run --\n'
run_expect_rc 0 "healthcheck --dry-run exits 0" -- bash "$WD" healthcheck --config "$EXAMPLE" --dry-run
assert_contains "$LAST_OUTPUT" "WOULD-CHECK" "dry-run prints WOULD-CHECK lines"
assert_contains "$LAST_OUTPUT" "indexer" "dry-run lists indexer target"
assert_contains "$LAST_OUTPUT" "manager-api" "dry-run lists manager-api target"
assert_contains "$LAST_OUTPUT" "dashboard" "dry-run lists dashboard target"
assert_contains "$LAST_OUTPUT" "agent-events" "dry-run lists agent-events target"
assert_contains "$LAST_OUTPUT" "agent-registration" "dry-run lists agent-registration target"
assert_contains "$LAST_OUTPUT" "https://localhost:9200/_cluster/health" "dry-run shows indexer URL with config port"
assert_contains "$LAST_OUTPUT" "https://localhost:55000/" "dry-run shows manager API URL with config port"
assert_contains "$LAST_OUTPUT" "tcp://localhost:1514" "dry-run shows agent events TCP target"

# Dry-run must not actually connect: verify by pointing at a fake-but-valid
# config and confirming it still returns instantly with rc 0 (no probing).
run_expect_rc 0 "dry-run does not probe the network" -- bash "$WD" healthcheck --config "$EXAMPLE_MULTI" --dry-run
assert_not_contains "$LAST_OUTPUT" "PASS " "dry-run produces no PASS probe lines"
assert_not_contains "$LAST_OUTPUT" "FAIL " "dry-run produces no FAIL probe lines"

# healthcheck argument validation.
run_expect_rc 2 "healthcheck without --config exits 2" -- bash "$WD" healthcheck
run_expect_rc 2 "healthcheck rejects bad --timeout" -- bash "$WD" healthcheck --config "$EXAMPLE" --timeout abc

# --- summary ---------------------------------------------------------------
printf '\n== results: %d passed, %d failed ==\n' "$PASS" "$FAIL"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
exit 0
