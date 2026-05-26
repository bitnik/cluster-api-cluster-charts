<p align="center">
  <a href="https://unbyte.de">
    <img src="https://www.unbyte.de/wp-content/uploads/2024/12/unbyte_logo.svg" alt="unbyte GmbH" width="300">
  </a>
</p>

# cluster-api-cluster-charts

[![Helm](https://img.shields.io/badge/Helm-3.x-0f1689.svg)](https://helm.sh)
[![GHCR](https://img.shields.io/badge/GHCR-ghcr.io-181717?logo=github&logoColor=white&label=charts)](https://github.com/orgs/unbyte-de/packages?repo_name=cluster-api-cluster-charts)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.31+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Cluster API](https://img.shields.io/badge/Cluster%20API-v1beta1-326CE5?logo=kubernetes&logoColor=white)](https://cluster-api.sigs.k8s.io/)
[![Hetzner Cloud](https://img.shields.io/badge/Hetzner%20Cloud-D50C2D?logo=hetzner&logoColor=white)](https://www.hetzner.com/cloud)
[![Kubeadm](https://img.shields.io/badge/Bootstrap-kubeadm-326CE5)](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
<!-- [![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE) -->
<!-- [![GitHub release](https://img.shields.io/github/v/release/unbyte/cluster-api-cluster-charts)](https://github.com/unbyte/cluster-api-cluster-charts/releases) -->
<!-- [![GitHub Actions](https://img.shields.io/github/actions/workflow/status/unbyte/cluster-api-cluster-charts/lint.yaml?label=lint)](https://github.com/unbyte-de/cluster-api-cluster-charts/actions/workflows/lint.yaml) -->
<!-- [![Pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit) -->
<!-- [![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](CONTRIBUTING.md) -->

Helm charts for defining, provisioning, and managing Kubernetes clusters using
[Cluster API (CAPI)](https://cluster-api.sigs.k8s.io/).

All charts in this repository are either directly responsible for provisioning
a Cluster API cluster or required to make that provisioning succeed.

This repository contains a reusable base chart as well as opinionated application
charts used by **unbyte** to create management and workload clusters.
It also includes tightly-coupled helper charts that are required during cluster bootstrapping
(e.g. External Secrets Operator configuration).

## Charts

### Core Cluster Templates

These charts define the primary infrastructure and Cluster API specifications.

The `cluster` library chart is designed to be reusable outside of unbyte-specific setups,
while the application charts provide opinionated defaults used by unbyte.

| Chart Name | Type | Description |
| :--- | :--- | :--- |
| `cluster` | library | **Base library** providing standardized templates and schemas for Cluster API resources. |
| `management-cluster` | application | Opinionated chart for provisioning **unbyte-style management clusters**. |
| `workload-cluster` | application | Opinionated chart for provisioning **unbyte-style workload clusters**. |

### Bootstrap & Provisioning Helpers

Helper charts required during the initial cluster lifecycle and secret management,
primarily for **unbyte-style clusters**.
These charts are grouped under `charts/helpers`.

| Chart Name | Type | Description |
| :--- | :--- | :--- |
| `cluster-bootstrap-configs` | application | Helper chart for generating ConfigMaps required during cluster bootstrapping. |
| `eso-providers` | application | Helper chart for deploying External Secrets Operator providers required during cluster bootstrapping. |
| `eso-secrets` | application | Helper chart for deploying External Secrets Operator secrets required during cluster bootstrapping. |

### Development & Validation

| Chart Name | Type | Description |
| :--- | :--- | :--- |
| `example-workload-cluster` | application | Minimal example workload cluster used for validation, testing, and documentation. **Not for production use.** |

## Notes

- Application charts depend on the `cluster` library chart.
- Charts are designed to work with Cluster API–compatible infrastructure providers.
- The `example-workload-cluster` chart is **not intended for production use**.

## Versioning

All charts in this repository share a single version number and are released in lockstep.
Application charts pin the `cluster` library by an exact version constraint (not a `~` or
`^` range), so library bumps always reach consumers through a coordinated release rather
than dependency resolution.

When bumping any chart, bump all of them to the same new version in the same PR. The
release workflow (`.github/workflows/release.yaml`) iterates every `Chart.yaml` and skips
versions already published to GHCR, so unchanged charts cost nothing in the pipeline.

## Scope & Non-Goals

### Scope

This repository focuses on **Cluster API cluster provisioning** and the
**minimum set of tightly-coupled helper charts required to bootstrap clusters**.

It includes:

- A reusable Cluster API library chart
- Opinionated charts for management and workload clusters
- Helper charts required during cluster bootstrap (e.g. ESO providers and secrets)

### Non-Goals

This repository intentionally does **not** include:

- General-purpose platform add-ons installed *after* cluster provisioning
  (e.g. Kyverno policies, network policies, RBAC baselines, shared services)
- Application workloads or tenant-specific deployments
- Charts intended to be reused independently of Cluster API cluster provisioning

Such charts belong in separate, dedicated repositories (e.g. platform add-ons).

## Local Developmemt

To run yamlfmt locally:

```sh
yamlfmt "**/*.{yaml,yml,yamlfmt}"
# Or remove -quiet and/or -lint flag of yamlfmt in .pre-commit-config.yaml and run
pre-commit run --all-files
```
