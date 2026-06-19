#!/usr/bin/env bash
#
# lib/healthcheck.sh - probe the expected Wazuh endpoints and report status.
#
# Builds the list of target endpoints from the loaded config, then either
# prints them (--dry-run, no network) or probes each with curl and reports a
# per-target PASS/FAIL plus an aggregate exit code.
#
# Maintainer: Cognis Digital
# License: COCL 1.0

if [ -n "${WD_HEALTHCHECK_SOURCED:-}" ]; then
    return 0
fi
WD_HEALTHCHECK_SOURCED=1

# wd_build_targets - emit "NAME|URL" lines for every endpoint to probe.
# Uses localhost + the host-published ports from the config.
wd_build_targets() {
    local host="localhost"

    # Indexer REST API (HTTPS, self-signed by default).
    printf 'indexer|https://%s:%s/_cluster/health\n' "$host" "$WD_CFG_INDEXER_PORT"

    # Manager API (HTTPS).
    printf 'manager-api|https://%s:%s/\n' "$host" "$WD_CFG_MANAGER_API_PORT"

    # Dashboard web UI.
    printf 'dashboard|https://%s:%s/app/login\n' "$host" "$WD_CFG_DASHBOARD_PORT"

    # Agent-facing TCP listeners are not HTTP; we report them as TCP targets.
    printf 'agent-events|tcp://%s:%s\n' "$host" "$WD_CFG_AGENT_EVENTS_PORT"
    printf 'agent-registration|tcp://%s:%s\n' "$host" "$WD_CFG_AGENT_REGISTRATION_PORT"
}

# wd_probe_http <url> <timeout> - probe an HTTP(S) endpoint.
# Returns 0 if curl got any HTTP response (even 401/403 — the service is up),
# non-zero on connection failure.
wd_probe_http() {
    local url="$1"
    local timeout="$2"

    if ! wd_require_cmd curl; then
        wd_warn "curl not found; cannot probe $url"
        return 2
    fi

    local code
    # -k: accept self-signed certs (Wazuh ships self-signed by default).
    # -s: silent, -o /dev/null: discard body, write the HTTP status code.
    code="$(curl -k -s -o /dev/null -w '%{http_code}' \
                 --connect-timeout "$timeout" --max-time "$timeout" \
                 "$url" 2>/dev/null || true)"

    if [ -n "$code" ] && [ "$code" != "000" ]; then
        printf '%s' "$code"
        return 0
    fi
    printf '000'
    return 1
}

# wd_probe_tcp <host> <port> <timeout> - probe a raw TCP port via bash /dev/tcp.
wd_probe_tcp() {
    local host="$1"
    local port="$2"
    local timeout="$3"

    # bash supports /dev/tcp; wrap with a timeout if the binary exists.
    if wd_require_cmd timeout; then
        if timeout "$timeout" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
            exec 3>&- 2>/dev/null || true
            return 0
        fi
        return 1
    fi

    if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
        exec 3>&- 2>/dev/null || true
        return 0
    fi
    return 1
}

# wd_healthcheck <dry_run> <timeout>
wd_healthcheck() {
    local dry_run="$1"
    local timeout="$2"

    local targets
    targets="$(wd_build_targets)"

    if [ "$dry_run" = "1" ]; then
        wd_info "dry-run: the following ${WD_CFG_DEPLOY_MODE} targets would be probed"
        local line name url
        while IFS='|' read -r name url; do
            [ -z "$name" ] && continue
            printf 'WOULD-CHECK %-20s %s\n' "$name" "$url"
        done <<EOF
$targets
EOF
        return 0
    fi

    local failures=0
    local total=0
    local name url scheme code rest hostport host port
    while IFS='|' read -r name url; do
        [ -z "$name" ] && continue
        total=$((total + 1))

        case "$url" in
            tcp://*)
                hostport="${url#tcp://}"
                host="${hostport%%:*}"
                port="${hostport##*:}"
                if wd_probe_tcp "$host" "$port" "$timeout"; then
                    wd_ok "PASS $name ($url) - port open"
                else
                    wd_err "FAIL $name ($url) - port closed/unreachable"
                    failures=$((failures + 1))
                fi
                ;;
            http://*|https://*)
                if code="$(wd_probe_http "$url" "$timeout")"; then
                    wd_ok "PASS $name ($url) - HTTP $code"
                else
                    wd_err "FAIL $name ($url) - no response"
                    failures=$((failures + 1))
                fi
                ;;
            *)
                wd_warn "SKIP $name - unrecognised target: $url"
                ;;
        esac
    done <<EOF
$targets
EOF

    if [ "$failures" -eq 0 ]; then
        wd_ok "healthcheck: $total/$total targets healthy"
        return 0
    fi
    wd_err "healthcheck: $failures/$total targets unhealthy"
    return 1
}

# ---------------------------------------------------------------------------
# Subcommand: healthcheck
# ---------------------------------------------------------------------------
cmd_healthcheck() {
    local config=""
    local dry_run="0"
    local timeout="5"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --config) config="${2:-}"; shift 2 ;;
            --config=*) config="${1#--config=}"; shift ;;
            --dry-run) dry_run="1"; shift ;;
            --timeout) timeout="${2:-}"; shift 2 ;;
            --timeout=*) timeout="${1#--timeout=}"; shift ;;
            -h|--help)
                cat <<'EOF'
wazuhdeploy healthcheck --config <file> [--dry-run] [--timeout <secs>]

Probe the indexer, manager API, dashboard, and agent listeners derived from
the config. --dry-run lists the targets without touching the network.
EOF
                return 0
                ;;
            *)
                wd_err "healthcheck: unknown option: $1"
                return 2
                ;;
        esac
    done

    if [ -z "$config" ]; then
        wd_err "healthcheck: --config <file> is required"
        return 2
    fi
    if ! wd_is_uint "$timeout" || [ "$timeout" -lt 1 ]; then
        wd_err "healthcheck: --timeout must be a positive integer, got: $timeout"
        return 2
    fi

    if ! wd_load_config "$config"; then
        wd_err "healthcheck: failed to load config"
        return 1
    fi

    # A broken config makes targets meaningless; validate first.
    if ! wd_validate_config; then
        wd_err "healthcheck: refusing to probe from an invalid config"
        return 1
    fi

    wd_healthcheck "$dry_run" "$timeout"
}
