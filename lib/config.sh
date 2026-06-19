#!/usr/bin/env bash
#
# lib/config.sh - load and normalise a wazuh.env config file.
#
# The config is a simple KEY=VALUE env file. We parse it safely (no `source`
# of arbitrary code) into a set of WD_CFG_* shell variables and apply
# documented defaults.
#
# Maintainer: Cognis Digital
# License: COCL 1.0

if [ -n "${WD_CONFIG_SOURCED:-}" ]; then
    return 0
fi
WD_CONFIG_SOURCED=1

# Recognised configuration keys and their defaults.
# Keep this list in sync with examples/wazuh.env and the README.
wd_config_defaults() {
    WD_CFG_STACK_NAME="wazuh"
    WD_CFG_DEPLOY_MODE="single-node"      # single-node | multi-node
    WD_CFG_DATA_DIR="./wazuh-data"
    WD_CFG_WAZUH_VERSION="4.9.0"
    WD_CFG_INDEXER_PORT="9200"
    WD_CFG_DASHBOARD_PORT="443"
    WD_CFG_MANAGER_API_PORT="55000"
    WD_CFG_AGENT_REGISTRATION_PORT="1515"
    WD_CFG_AGENT_EVENTS_PORT="1514"
    WD_CFG_INDEXER_NODES="1"
    WD_CFG_DASHBOARD_USER="kibanaserver"
    WD_CFG_INDEXER_HOST="wazuh.indexer"
    WD_CFG_MANAGER_HOST="wazuh.manager"
    WD_CFG_DASHBOARD_HOST="wazuh.dashboard"
}

# The canonical list of keys we will read from a config file.
WD_CONFIG_KEYS="\
STACK_NAME DEPLOY_MODE DATA_DIR WAZUH_VERSION \
INDEXER_PORT DASHBOARD_PORT MANAGER_API_PORT \
AGENT_REGISTRATION_PORT AGENT_EVENTS_PORT INDEXER_NODES \
DASHBOARD_USER INDEXER_HOST MANAGER_HOST DASHBOARD_HOST"

# wd_config_is_known_key <key> - true if key is recognised.
wd_config_is_known_key() {
    local k
    for k in $WD_CONFIG_KEYS; do
        [ "$k" = "$1" ] && return 0
    done
    return 1
}

# wd_load_config <file> - parse the env file into WD_CFG_* variables.
# Returns non-zero (and prints) on a malformed line or unreadable file.
wd_load_config() {
    local file="$1"

    if [ -z "$file" ]; then
        wd_err "no config file specified"
        return 1
    fi
    if [ ! -f "$file" ]; then
        wd_err "config file not found: $file"
        return 1
    fi
    if [ ! -r "$file" ]; then
        wd_err "config file not readable: $file"
        return 1
    fi

    wd_config_defaults

    local lineno=0
    local raw key val
    local rc=0
    while IFS= read -r raw || [ -n "$raw" ]; do
        lineno=$((lineno + 1))

        # Strip a trailing carriage return (CRLF files / Windows).
        raw="${raw%$'\r'}"

        # Trim surrounding whitespace.
        raw="$(wd_trim "$raw")"

        # Skip blank lines and comments.
        [ -z "$raw" ] && continue
        case "$raw" in
            \#*) continue ;;
        esac

        # Allow an optional leading "export ".
        case "$raw" in
            export\ *) raw="${raw#export }"; raw="$(wd_trim "$raw")" ;;
        esac

        # Must contain '='.
        case "$raw" in
            *=*) : ;;
            *)
                wd_err "malformed line $lineno (no '='): $raw"
                rc=1
                continue
                ;;
        esac

        key="${raw%%=*}"
        val="${raw#*=}"
        key="$(wd_trim "$key")"
        val="$(wd_trim "$val")"

        # Strip a single layer of matching surrounding quotes from the value.
        case "$val" in
            \"*\") val="${val#\"}"; val="${val%\"}" ;;
            \'*\') val="${val#\'}"; val="${val%\'}" ;;
        esac

        # Validate key shape.
        case "$key" in
            ''|*[!A-Za-z0-9_]*)
                wd_err "malformed key on line $lineno: $key"
                rc=1
                continue
                ;;
        esac

        if ! wd_config_is_known_key "$key"; then
            wd_warn "unknown config key (ignored): $key"
            continue
        fi

        # Assign into WD_CFG_<key>.
        printf -v "WD_CFG_$key" '%s' "$val"
    done < "$file"

    return "$rc"
}

# wd_config_dump - print the resolved configuration (for debugging/tests).
wd_config_dump() {
    local k var
    for k in $WD_CONFIG_KEYS; do
        var="WD_CFG_$k"
        printf '%s=%s\n' "$k" "${!var}"
    done
}
