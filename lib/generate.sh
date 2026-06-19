#!/usr/bin/env bash
#
# lib/generate.sh - render templates into a deployment directory.
#
# Templating is deliberately simple and dependency-free: each @@KEY@@ token in
# a template is replaced with the corresponding WD_CFG_<KEY> value. We do the
# substitution in pure bash (no sed/awk escaping headaches) so it behaves the
# same across platforms, including Git Bash on Windows.
#
# Maintainer: Cognis Digital
# License: COCL 1.0

if [ -n "${WD_GENERATE_SOURCED:-}" ]; then
    return 0
fi
WD_GENERATE_SOURCED=1

# wd_render_template <src-template> <dest-file>
# Reads the template, substitutes every @@KEY@@ for which a WD_CFG_KEY exists,
# and writes the result to dest.
wd_render_template() {
    local src="$1"
    local dest="$2"

    if [ ! -f "$src" ]; then
        wd_err "template not found: $src"
        return 1
    fi

    # Read the whole template into memory.
    local content
    content="$(cat "$src")"

    # Substitute each known key.
    local k var val
    for k in $WD_CONFIG_KEYS; do
        var="WD_CFG_$k"
        val="${!var:-}"
        # Replace all occurrences of @@k@@ with val (pure bash, no regex).
        content="${content//@@${k}@@/$val}"
    done

    # Write atomically-ish: write then move.
    local tmp="${dest}.tmp.$$"
    printf '%s\n' "$content" > "$tmp"
    mv -f "$tmp" "$dest"
}

# wd_generate - render the full deployment into WD_OUT_DIR.
# Expects WD_OUT_DIR and WD_FORCE to be set, and config already loaded+valid.
wd_generate() {
    local out="$1"
    local force="$2"

    if [ -z "$out" ]; then
        wd_err "generate: output directory is empty"
        return 1
    fi

    # Refuse to clobber a non-empty dir unless --force.
    if [ -e "$out/docker-compose.yml" ] && [ "$force" != "1" ]; then
        wd_err "generate: $out/docker-compose.yml already exists (use --force to overwrite)"
        return 1
    fi

    mkdir -p "$out"
    mkdir -p "$out/config"

    # Choose the compose template by deploy mode.
    local compose_tmpl
    case "$WD_CFG_DEPLOY_MODE" in
        multi-node)
            compose_tmpl="$WAZUHDEPLOY_TEMPLATES/docker-compose.multi.yml.tmpl"
            ;;
        *)
            compose_tmpl="$WAZUHDEPLOY_TEMPLATES/docker-compose.single.yml.tmpl"
            ;;
    esac

    wd_render_template "$compose_tmpl" "$out/docker-compose.yml" || return 1
    wd_ok "wrote $out/docker-compose.yml ($WD_CFG_DEPLOY_MODE)"

    wd_render_template "$WAZUHDEPLOY_TEMPLATES/ossec.conf.tmpl" "$out/config/ossec.conf" || return 1
    wd_ok "wrote $out/config/ossec.conf"

    wd_render_template "$WAZUHDEPLOY_TEMPLATES/indexer.yml.tmpl" "$out/config/opensearch.yml" || return 1
    wd_ok "wrote $out/config/opensearch.yml"

    wd_render_template "$WAZUHDEPLOY_TEMPLATES/dashboard.yml.tmpl" "$out/config/opensearch_dashboards.yml" || return 1
    wd_ok "wrote $out/config/opensearch_dashboards.yml"

    # Drop a copy of the resolved config for reproducibility.
    {
        printf '# Resolved configuration captured by wazuhdeploy generate.\n'
        printf '# Maintainer: Cognis Digital. License: COCL 1.0\n'
        wd_config_dump
    } > "$out/resolved.env"
    wd_ok "wrote $out/resolved.env"

    return 0
}

# ---------------------------------------------------------------------------
# Subcommand: generate
# ---------------------------------------------------------------------------
cmd_generate() {
    local config=""
    local out=""
    local force="0"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --config) config="${2:-}"; shift 2 ;;
            --config=*) config="${1#--config=}"; shift ;;
            --out) out="${2:-}"; shift 2 ;;
            --out=*) out="${1#--out=}"; shift ;;
            --force) force="1"; shift ;;
            -h|--help)
                cat <<'EOF'
wazuhdeploy generate --config <file> --out <dir> [--force]

Render docker-compose.yml + base config files (ossec.conf, opensearch.yml,
opensearch_dashboards.yml) into <dir> from the given config.
EOF
                return 0
                ;;
            *)
                wd_err "generate: unknown option: $1"
                return 2
                ;;
        esac
    done

    if [ -z "$config" ]; then
        wd_err "generate: --config <file> is required"
        return 2
    fi
    if [ -z "$out" ]; then
        wd_err "generate: --out <dir> is required"
        return 2
    fi

    if ! wd_load_config "$config"; then
        wd_err "generate: failed to load config"
        return 1
    fi

    # Generation requires a valid config.
    if ! wd_validate_config; then
        wd_err "generate: refusing to generate from an invalid config"
        return 1
    fi

    wd_generate "$out" "$force"
}
