#!/usr/bin/env bash
#
# lib/common.sh - shared helpers: logging, colour, small utilities.
#
# Maintainer: Cognis Digital
# License: COCL 1.0

# Guard against double-sourcing.
if [ -n "${WD_COMMON_SOURCED:-}" ]; then
    return 0
fi
WD_COMMON_SOURCED=1

# Colour output only when stderr is a terminal and NO_COLOR is unset.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    WD_C_RED=$'\033[31m'
    WD_C_YELLOW=$'\033[33m'
    WD_C_GREEN=$'\033[32m'
    WD_C_DIM=$'\033[2m'
    WD_C_RESET=$'\033[0m'
else
    WD_C_RED=""
    WD_C_YELLOW=""
    WD_C_GREEN=""
    WD_C_DIM=""
    WD_C_RESET=""
fi

wd_log() {
    printf '%s\n' "$*" >&2
}

wd_info() {
    printf '%s[info]%s %s\n' "$WD_C_DIM" "$WD_C_RESET" "$*" >&2
}

wd_ok() {
    printf '%s[ ok ]%s %s\n' "$WD_C_GREEN" "$WD_C_RESET" "$*" >&2
}

wd_warn() {
    printf '%s[warn]%s %s\n' "$WD_C_YELLOW" "$WD_C_RESET" "$*" >&2
}

wd_err() {
    printf '%s[err ]%s %s\n' "$WD_C_RED" "$WD_C_RESET" "$*" >&2
}

# wd_die <message> - print an error and exit non-zero.
wd_die() {
    wd_err "$*"
    exit 1
}

# wd_require_cmd <cmd> - ensure a command is on PATH.
wd_require_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# wd_is_uint <value> - true if value is a non-negative integer.
wd_is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# wd_trim <string> - echo the string with leading/trailing whitespace removed.
wd_trim() {
    local s="$1"
    # Remove leading whitespace.
    s="${s#"${s%%[![:space:]]*}"}"
    # Remove trailing whitespace.
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}
