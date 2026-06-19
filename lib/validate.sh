#!/usr/bin/env bash
#
# lib/validate.sh - validate a loaded configuration.
#
# Checks performed:
#   * required variables are present and non-empty
#   * DEPLOY_MODE is one of the accepted values
#   * all port values are valid TCP ports (1..65535)
#   * no two services share the same port (conflict detection)
#   * INDEXER_NODES is a positive integer and >= 3 when multi-node
#
# Maintainer: Cognis Digital
# License: COCL 1.0

if [ -n "${WD_VALIDATE_SOURCED:-}" ]; then
    return 0
fi
WD_VALIDATE_SOURCED=1

# Variables that must be present and non-empty.
WD_REQUIRED_VARS="\
STACK_NAME DEPLOY_MODE DATA_DIR WAZUH_VERSION \
INDEXER_PORT DASHBOARD_PORT MANAGER_API_PORT \
AGENT_REGISTRATION_PORT AGENT_EVENTS_PORT INDEXER_NODES"

# Variables that must be valid TCP port numbers.
WD_PORT_VARS="\
INDEXER_PORT DASHBOARD_PORT MANAGER_API_PORT \
AGENT_REGISTRATION_PORT AGENT_EVENTS_PORT"

# wd_is_valid_port <n> - true if n is an integer in 1..65535.
wd_is_valid_port() {
    wd_is_uint "$1" || return 1
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# wd_validate_config - run all checks against the loaded WD_CFG_* vars.
# Returns the number of errors found (0 == valid). Prints findings.
wd_validate_config() {
    local errors=0
    local var val

    # Required, non-empty.
    for v in $WD_REQUIRED_VARS; do
        var="WD_CFG_$v"
        val="${!var:-}"
        if [ -z "$val" ]; then
            wd_err "required variable is empty or missing: $v"
            errors=$((errors + 1))
        fi
    done

    # DEPLOY_MODE.
    case "${WD_CFG_DEPLOY_MODE:-}" in
        single-node|multi-node) : ;;
        '')
            : # already counted above as empty required.
            ;;
        *)
            wd_err "DEPLOY_MODE must be 'single-node' or 'multi-node', got: ${WD_CFG_DEPLOY_MODE}"
            errors=$((errors + 1))
            ;;
    esac

    # Port shape.
    for v in $WD_PORT_VARS; do
        var="WD_CFG_$v"
        val="${!var:-}"
        if [ -n "$val" ] && ! wd_is_valid_port "$val"; then
            wd_err "$v is not a valid TCP port (1-65535): $val"
            errors=$((errors + 1))
        fi
    done

    # INDEXER_NODES sanity.
    if [ -n "${WD_CFG_INDEXER_NODES:-}" ]; then
        if ! wd_is_uint "$WD_CFG_INDEXER_NODES" || [ "$WD_CFG_INDEXER_NODES" -lt 1 ]; then
            wd_err "INDEXER_NODES must be a positive integer, got: ${WD_CFG_INDEXER_NODES}"
            errors=$((errors + 1))
        elif [ "${WD_CFG_DEPLOY_MODE:-}" = "multi-node" ] && [ "$WD_CFG_INDEXER_NODES" -lt 3 ]; then
            wd_err "multi-node deployments need INDEXER_NODES >= 3 (quorum), got: ${WD_CFG_INDEXER_NODES}"
            errors=$((errors + 1))
        elif [ "${WD_CFG_DEPLOY_MODE:-}" = "single-node" ] && [ "$WD_CFG_INDEXER_NODES" -ne 1 ]; then
            wd_err "single-node deployments must set INDEXER_NODES=1, got: ${WD_CFG_INDEXER_NODES}"
            errors=$((errors + 1))
        fi
    fi

    # Port conflict detection across the distinct host-published ports.
    if ! wd_check_port_conflicts; then
        errors=$((errors + 1))
    fi

    if [ "$errors" -eq 0 ]; then
        wd_ok "configuration is valid"
    else
        wd_err "configuration has $errors error(s)"
    fi

    return "$errors"
}

# wd_check_port_conflicts - detect two services bound to the same host port.
# Returns 0 when no conflict, 1 when a conflict was found (and prints it).
wd_check_port_conflicts() {
    local seen=""
    local conflict=0
    local v var val

    for v in $WD_PORT_VARS; do
        var="WD_CFG_$v"
        val="${!var:-}"
        # Skip empty/invalid; those are reported elsewhere.
        wd_is_valid_port "$val" || continue

        case " $seen " in
            *" ${val}:"*)
                # Find the prior owner.
                local prior
                prior="$(printf '%s\n' $seen | sed -n "s/^${val}://p" | head -n1)"
                wd_err "port conflict: $v and $prior both use port $val"
                conflict=1
                ;;
            *)
                seen="$seen ${val}:${v}"
                ;;
        esac
    done

    [ "$conflict" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Subcommand: validate
# ---------------------------------------------------------------------------
cmd_validate() {
    local config=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --config) config="${2:-}"; shift 2 ;;
            --config=*) config="${1#--config=}"; shift ;;
            -h|--help)
                cat <<'EOF'
wazuhdeploy validate --config <file>

Validate a wazuh.env config: required vars, deploy mode, port shape, and
port conflicts. Exits non-zero when the configuration is invalid.
EOF
                return 0
                ;;
            *)
                wd_err "validate: unknown option: $1"
                return 2
                ;;
        esac
    done

    if [ -z "$config" ]; then
        wd_err "validate: --config <file> is required"
        return 2
    fi

    if ! wd_load_config "$config"; then
        wd_err "validate: failed to load config"
        return 1
    fi

    wd_validate_config
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        return 1
    fi
    return 0
}
