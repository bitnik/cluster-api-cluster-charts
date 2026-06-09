# Each app chart ships a `config_linting.yaml` with the minimum values to template successfully.
# APP_CHARTS := "example-workload-cluster management-cluster workload-cluster helpers/cluster-bootstrap-configs helpers/eso-providers helpers/eso-secrets"
APP_CHARTS := "find charts -mindepth 2 -name config_linting.yaml -printf '%h\n' | sed 's|^charts/||' | sort | tr '\n' ' '"

WORKSPACE  := justfile_directory()
DC_UP      := "devcontainer up   --workspace-folder " + WORKSPACE
DC_EXEC    := "devcontainer exec --workspace-folder " + WORKSPACE

# Show available recipes.
default:
    @just --list

# Ensure the devcontainer is up. Used as a dependency.
[private]
_up:
    {{ DC_UP }}

# Start a bash shell inside the devcontainer.
[group('container')]
bash: _up
    {{ DC_EXEC }} bash

# Start Claude Code inside the devcontainer.
[group('container')]
code: _up
    {{ DC_EXEC }} claude

# Run an arbitrary command inside the devcontainer.
[group('container')]
exec +CMD: _up
    {{ DC_EXEC }} {{ CMD }}

# Stop and remove the devcontainer.
[group('container')]
destroy:
    docker rm -f $(docker ps -aq --filter "label=devcontainer.local_folder={{ WORKSPACE }}") || true
    @echo ""
    @echo "To rm the devcontainer-claude-code-config volume:"
    @echo "  docker volume ls | grep devcontainer-claude-code-config"
    @echo "  docker volume rm devcontainer-claude-code-config-<id>"

# Lint everything: library chart + all application/helper charts.
[group('lint')]
lint: _up
    {{ DC_EXEC }} just _lint

[private]
_lint: _lint-cluster _lint-apps

# Lint only the cluster library chart (no values file, no template step).
[group('lint')]
lint-cluster: _up
    {{ DC_EXEC }} just _lint-cluster

[private]
_lint-cluster:
    helm dependency update charts/cluster
    helm lint charts/cluster

# Lint every application and helper chart.
[group('lint')]
lint-apps: _up
    {{ DC_EXEC }} just _lint-apps

[private]
_lint-apps:
    #!/usr/bin/env bash
    set -euo pipefail
    for chart in $({{ APP_CHARTS }}); do
        just _lint-chart "$chart"
    done

# Lint a single chart by its path under charts/ (e.g. `just lint-chart workload-cluster`).
[group('lint')]
lint-chart CHART: _up
    {{ DC_EXEC }} just _lint-chart {{ CHART }}

[private]
_lint-chart CHART DEBUG='false':
    #!/usr/bin/env bash
    set -euo pipefail
    chart="charts/{{ CHART }}"
    out="$(mktemp -d)"
    trap 'rm -rf "$out"' EXIT
    helm dependency update "$chart"
    helm lint "$chart" -f "$chart/config_linting.yaml"
    helm template "$chart" -f "$chart/config_linting.yaml" --output-dir "$out"
    if [[ "{{ DEBUG }}" == "true" ]]; then
        yamlfmt -conf=./.yamlfmt -lint        "$out/**/*.{yaml,yml}"
    else
        yamlfmt -conf=./.yamlfmt -lint -quiet "$out/**/*.{yaml,yml}"
    fi

# Format every YAML in the repo with yamlfmt.
[group('lint')]
fmt: _up
    {{ DC_EXEC }} just _fmt

[private]
_fmt:
    yamlfmt "**/*.{yaml,yml,yamlfmt}"

# Run pre-commit on all files.
[group('lint')]
pre-commit: _up
    {{ DC_EXEC }} just _pre-commit

[private]
_pre-commit:
    pre-commit run --all-files

# Clean up generated Helm chart artifacts (all charts).
[group('lint')]
cleanup: _up
    {{ DC_EXEC }} just _cleanup

[private]
_cleanup:
    #!/usr/bin/env bash
    set -euo pipefail
    for chart in $({{ APP_CHARTS }}); do
      echo "Cleaning up $chart"
      rm -f "charts/$chart/Chart.lock"
      rm -f "charts/$chart/charts/"*.tgz
    done
