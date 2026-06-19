#!/usr/bin/env bash
#
# wazuhdeploy - opinionated deployment scaffolder + healthcheck for a
#               Wazuh (open-source SIEM/XDR) stack.
#
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# This is the entrypoint. It dispatches subcommands to functions defined
# in the sourced lib/ modules. It does NOT require Wazuh or Docker to be
# installed in order to generate configs or run its own tests.

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve the directory this script lives in so lib/ and templates/ can be
# found regardless of the caller's working directory.
# ---------------------------------------------------------------------------
wd_resolve_self_dir() {
    local src="${BASH_SOURCE[0]}"
    # Follow symlinks.
    while [ -h "$src" ]; do
        local dir
        dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
        src="$(readlink "$src")"
        [[ $src != /* ]] && src="$dir/$src"
    done
    cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

WAZUHDEPLOY_HOME="$(wd_resolve_self_dir)"
export WAZUHDEPLOY_HOME
WAZUHDEPLOY_LIB="$WAZUHDEPLOY_HOME/lib"
WAZUHDEPLOY_TEMPLATES="$WAZUHDEPLOY_HOME/templates"
export WAZUHDEPLOY_TEMPLATES

# ---------------------------------------------------------------------------
# Source library modules.
# ---------------------------------------------------------------------------
# shellcheck source=lib/common.sh
. "$WAZUHDEPLOY_LIB/common.sh"
# shellcheck source=lib/config.sh
. "$WAZUHDEPLOY_LIB/config.sh"
# shellcheck source=lib/validate.sh
. "$WAZUHDEPLOY_LIB/validate.sh"
# shellcheck source=lib/generate.sh
. "$WAZUHDEPLOY_LIB/generate.sh"
# shellcheck source=lib/healthcheck.sh
. "$WAZUHDEPLOY_LIB/healthcheck.sh"

WAZUHDEPLOY_VERSION="1.0.0"

usage() {
    cat <<'EOF'
wazuhdeploy - deployment scaffolder + healthcheck for a Wazuh SIEM/XDR stack

USAGE:
    wazuhdeploy.sh <command> [options]

COMMANDS:
    generate     Emit docker-compose.yml + base config files from a config.
    validate     Validate a config file (required vars, port conflicts).
    healthcheck  Probe the expected Wazuh endpoints/containers and report.
    version      Print the version.
    help         Show this help.

GENERATE:
    wazuhdeploy.sh generate --config <file> --out <dir> [--force]
        --config <file>   Path to the wazuh.env config file (required).
        --out <dir>       Output directory for generated artifacts (required).
        --force           Overwrite existing files in the output directory.

VALIDATE:
    wazuhdeploy.sh validate --config <file>
        --config <file>   Path to the wazuh.env config file (required).
        Exits non-zero if required vars are missing or ports conflict.

HEALTHCHECK:
    wazuhdeploy.sh healthcheck --config <file> [--dry-run] [--timeout <secs>]
        --config <file>   Path to the wazuh.env config file (required).
        --dry-run         Print the endpoints that would be probed; no network.
        --timeout <secs>  Per-probe curl timeout (default: 5).

GLOBAL:
    -h, --help    Show this help.

EXAMPLES:
    wazuhdeploy.sh validate --config examples/wazuh.env
    wazuhdeploy.sh generate --config examples/wazuh.env --out ./deploy
    wazuhdeploy.sh healthcheck --config examples/wazuh.env --dry-run

License: COCL 1.0  -  Maintainer: Cognis Digital
EOF
}

main() {
    if [ "$#" -eq 0 ]; then
        usage
        return 1
    fi

    local cmd="$1"
    shift || true

    case "$cmd" in
        generate)
            cmd_generate "$@"
            ;;
        validate)
            cmd_validate "$@"
            ;;
        healthcheck)
            cmd_healthcheck "$@"
            ;;
        version|--version|-V)
            printf 'wazuhdeploy %s\n' "$WAZUHDEPLOY_VERSION"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            wd_err "unknown command: $cmd"
            usage
            return 1
            ;;
    esac
}

main "$@"
