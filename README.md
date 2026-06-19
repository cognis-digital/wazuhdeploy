# wazuhdeploy

An opinionated deployment scaffolder and healthcheck for a
[Wazuh](https://wazuh.com) open-source SIEM/XDR stack, written in portable
Bash.

From a small config file (`wazuh.env`), `wazuhdeploy` **generates** a
ready-to-run `docker-compose.yml` plus base configuration for the three core
Wazuh components — **manager**, **indexer**, and **dashboard** — in either a
single-node or multi-node topology. It also **validates** your config (catching
missing variables and port conflicts before they bite) and provides a
**healthcheck** that probes the expected endpoints and reports status.

It does **not** require Wazuh or Docker to be installed in order to generate
configs or to run its own test suite. Scope is strictly defensive /
deployment-side.

## Features

- `generate` — emit `docker-compose.yml` + base configs (`ossec.conf`,
  `opensearch.yml`, `opensearch_dashboards.yml`) from a config file, choosing a
  single-node or clustered multi-node compose automatically.
- `validate` — check required variables, deploy mode, port shape, indexer
  quorum, and cross-service port conflicts; exits non-zero on any error.
- `healthcheck` — probe the indexer REST API, manager API, dashboard UI, and
  agent listeners; `--dry-run` lists the targets without touching the network.
- Modular: a `lib/` of sourced functions; templates you can read and edit in
  `templates/`.
- Self-contained test suite that runs without Docker or Wazuh.

## Wazuh component model

`wazuhdeploy` follows the documented three-tier Wazuh architecture:

| Component         | Role                                             | Default ports (host) |
|-------------------|--------------------------------------------------|----------------------|
| Wazuh manager     | Analysis engine, agent endpoints, REST API       | 1514, 1515, 55000    |
| Wazuh indexer     | OpenSearch-based search/storage backend          | 9200                 |
| Wazuh dashboard   | Web UI                                            | 443 (-> 5601)        |

## Install

No install step — it is a Bash script. Clone the repo and run it. Requires
`bash`. `curl` is only needed for live `healthcheck` (not for `--dry-run`,
`generate`, or `validate`).

```sh
git clone <your-fork> wazuhdeploy
cd wazuhdeploy
bash wazuhdeploy.sh --help
```

## Usage

### Validate

```sh
$ wazuhdeploy.sh validate --config examples/wazuh.env
[ ok ] configuration is valid
```

A broken config exits non-zero and explains why:

```sh
$ wazuhdeploy.sh validate --config broken.env
[err ] port conflict: MANAGER_API_PORT and INDEXER_PORT both use port 9200
[err ] configuration has 1 error(s)
```

### Generate

```sh
$ wazuhdeploy.sh generate --config examples/wazuh.env --out ./deploy
[ ok ] configuration is valid
[ ok ] wrote ./deploy/docker-compose.yml (single-node)
[ ok ] wrote ./deploy/config/ossec.conf
[ ok ] wrote ./deploy/config/opensearch.yml
[ ok ] wrote ./deploy/config/opensearch_dashboards.yml
[ ok ] wrote ./deploy/resolved.env
```

This produces:

```
deploy/
├── docker-compose.yml
├── resolved.env
└── config/
    ├── ossec.conf
    ├── opensearch.yml
    └── opensearch_dashboards.yml
```

Then (with Docker installed, outside the scope of this tool):

```sh
cd deploy && docker compose up -d
```

Use `--force` to overwrite an existing deployment directory. Set
`DEPLOY_MODE=multi-node` (with `INDEXER_NODES>=3`) in the config to emit a
clustered three-seed-node indexer compose instead.

### Healthcheck

`--dry-run` lists exactly what would be probed, with no network traffic:

```sh
$ wazuhdeploy.sh healthcheck --config examples/wazuh.env --dry-run
[ ok ] configuration is valid
[info] dry-run: the following single-node targets would be probed
WOULD-CHECK indexer              https://localhost:9200/_cluster/health
WOULD-CHECK manager-api          https://localhost:55000/
WOULD-CHECK dashboard            https://localhost:443/app/login
WOULD-CHECK agent-events         tcp://localhost:1514
WOULD-CHECK agent-registration   tcp://localhost:1515
```

Drop `--dry-run` to actually probe (uses `curl` for HTTP(S) targets and a TCP
connect test for the agent listeners). Each probe reports PASS/FAIL and the
command exits non-zero if any target is unhealthy. Tune per-probe timeout with
`--timeout <secs>`.

## Configuration

Config is a simple `KEY=VALUE` env file (see `examples/wazuh.env` and
`examples/wazuh-multi.env`). Recognised keys:

| Key                       | Default          | Meaning                                  |
|---------------------------|------------------|------------------------------------------|
| `STACK_NAME`              | `wazuh`          | Compose project name + network prefix    |
| `DEPLOY_MODE`             | `single-node`    | `single-node` or `multi-node`            |
| `DATA_DIR`                | `./wazuh-data`   | Host dir for bind-mounted data/config    |
| `WAZUH_VERSION`           | `4.9.0`          | Image tag for manager/indexer/dashboard  |
| `INDEXER_NODES`           | `1`              | Indexer count (multi-node needs >= 3)    |
| `INDEXER_PORT`            | `9200`           | Indexer REST API host port               |
| `DASHBOARD_PORT`          | `443`            | Dashboard host port                      |
| `MANAGER_API_PORT`        | `55000`          | Manager REST API host port               |
| `AGENT_REGISTRATION_PORT` | `1515`           | Agent enrollment listener                |
| `AGENT_EVENTS_PORT`       | `1514`           | Agent event listener                     |
| `INDEXER_HOST`            | `wazuh.indexer`  | Indexer service hostname                 |
| `MANAGER_HOST`            | `wazuh.manager`  | Manager service hostname                 |
| `DASHBOARD_HOST`          | `wazuh.dashboard`| Dashboard service hostname               |
| `DASHBOARD_USER`          | `kibanaserver`   | Dashboard/indexer service account        |

Unknown keys are ignored with a warning.

## Testing

The suite runs without Docker or Wazuh. With [bats](https://github.com/bats-core/bats-core)
or plain Bash:

```sh
bash tests/run.sh
```

It asserts that `generate` produces a compose file with the expected services,
that `validate` passes on the examples and fails (non-zero) on broken configs,
and that `healthcheck --dry-run` lists the right targets without networking.
The runner exits non-zero on any failure.

## Project layout

```
wazuhdeploy/
├── wazuhdeploy.sh            # entrypoint / subcommand dispatch
├── lib/
│   ├── common.sh             # logging + small utilities
│   ├── config.sh             # safe env-file parser + defaults
│   ├── validate.sh           # validation + the `validate` subcommand
│   ├── generate.sh           # templating + the `generate` subcommand
│   └── healthcheck.sh        # probing + the `healthcheck` subcommand
├── templates/                # docker-compose + base config templates
├── examples/                 # wazuh.env, wazuh-multi.env
├── tests/run.sh              # self-contained test suite
└── .github/workflows/ci.yml  # shellcheck + tests on ubuntu
```

## License

License: COCL 1.0

Maintainer: Cognis Digital
