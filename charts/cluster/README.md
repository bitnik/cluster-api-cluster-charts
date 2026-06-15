# cluster chart

This is a [library chart](https://helm.sh/docs/topics/library_charts/)
and implemented to be used by umbrella/parent charts
to create [Cluster API](https://cluster-api.sigs.k8s.io/) (CAPI) clusters
for their own purposes.
This chart can't be installed as itself.

Supported [providers](https://cluster-api-operator.sigs.k8s.io/01_user/01_concepts):

* Core provider: [Cluster API](https://github.com/kubernetes-sigs/cluster-api) (CAPI)
* Infrastructure providers:
  * [hetzner](https://github.com/syself/cluster-api-provider-hetzner) (CAPH)
* Control Plane providers
  * [kubeadm](https://github.com/kubernetes-sigs/cluster-api/tree/main/controlplane/kubeadm)
* Bootstrap providers:
  * [kubeadm](https://github.com/kubernetes-sigs/cluster-api/tree/main/bootstrap/kubeadm)

Providers itself are installed out-of-band (using cluster-api-operator / clusterctl / ArgoCD),
not by this chart.

## Compatibility

For the authoritative CAPH <-> CAPI <-> Kubernetes support ranges, see the
[CAPH compatibility matrix](https://syself.com/docs/caph/getting-started/introduction#compatibility-with-cluster-api-and-kubernetes-versions)
and the [Cluster API version support](https://cluster-api.sigs.k8s.io/reference/versions) page.

This chart is currently tested against:

| Cluster chart version | Core provider (CAPI) | Bootstrap provider | Control-plane provider | Infrastructure provider | Node OS image | Kubernetes (node image) | Notes |
|-----------|---------|---------|-----------|--------------|-------|-------|-------------------------|
| `0.11.1` | `v1.8.12` | kubeadm: `v1.8.12` | kubeadm: `v1.8.12` | CAPH: `v1.0.7` | Ubuntu `24.04` | `1.31.4` | [See also migration notes](#from-0102-to-0110) |
| `0.12.0` | `v1.10.10` | kubeadm: `v1.10.10` | kubeadm: `v1.10.10` | CAPH: `v1.0.12` | Ubuntu `24.04` | `1.32.13`, `1.33.12` | `1.33.12` requires a [manual RBAC fix](https://github.com/kubernetes-sigs/cluster-api/blob/6c70a17c7f343442238fc695e66884e6c84cfa01/docs/book/src/user/troubleshooting.md#kubeadm-join-fails-after-upgrading-to-kubernetes-patch-releases) [See also migration notes](#from-0110-to-0120) |
| `0.13.0` | `v1.13.2` | kubeadm: `v1.13.2` | kubeadm: `v1.13.2` | CAPH: `v1.1.6` | Ubuntu `24.04` | `1.33.12`, `1.34.8`, `1.35.5`, `1.36.1` | [See also migration notes](#from-0120-to-0130) |

As of `0.13.0` this chart renders the CAPI core resources at `v1beta2`
(infrastructure resources stay `v1beta1`, served by CAPH `v1.1.x`),
the middle row of the table below (v1beta2 <-> v1beta1 via shim).
Chart `0.12.0` and earlier render v1beta1 and target CAPI v1.8.x–v1.10.x with CAPH v1.0.x (top row).

| Pairing | apiVersion served | Contract (core <-> provider) | What to do with v1beta1 YAMLs | Notes |
|---------|-------------------|------------------------------|-------------------------------|-------|
| CAPI `v1.8.x - v1.10.x` and CAPH `v1.0.x`  | v1beta1 only | v1beta1 <-> v1beta1 | leave as v1beta1 |  stable, but CAPI 1.10 is now **EOL**! |
| CAPI `v1.12.x - v1.15.x` and CAPH [`v1.1.x`](https://github.com/syself/cluster-api-provider-hetzner/releases/tag/v1.1.0) | core v1beta1+v1beta2; CAPH v1beta1 | v1beta2 <-> v1beta1 (bridged by temporary shim) | Optionally migrate only CAPI resources (Cluster, KubeadmControlPlane, MachineDeployment) to v1beta2 | Works via shim |
| CAPI `>= v1.12.x` and CAPH `v1.2.x` | v1beta2 | v1beta2 <-> v1beta2 | Migrate all resources to v1beta2 | Fully aligned. This is the destination, but CAPH `v1.2.x` not released yet. |

For Kubernetes version support

* check the [CAPH compatibility matrix](https://syself.com/docs/caph/getting-started/introduction#compatibility-with-cluster-api-and-kubernetes-versions) (pay attention to compatibility notes)
* check CAPI release notes, e.g. for [v1.10.10](https://github.com/kubernetes-sigs/cluster-api/releases/tag/v1.10.10)
* check [containerd's kubernetes version support](https://containerd.io/releases/#kubernetes-support)

`cilium` or `hcloud-cloud-controller-manager` versions,installed via `ClusterResourceSet`, are independent of providers.

References:

* [CAPH compatibility matrix](https://syself.com/docs/caph/getting-started/introduction#compatibility-with-cluster-api-and-kubernetes-versions)
* [CAPI release vs contract versions](https://cluster-api.sigs.k8s.io/reference/versions#cluster-api-release-vs-contract-versions)
* [CAPI release support](https://cluster-api.sigs.k8s.io/reference/versions#cluster-api-release-support)
* [CAPI v1.10 to v1.11 migration guide](https://cluster-api.sigs.k8s.io/developer/providers/migrations/v1.10-to-v1.11)
* [CAPI removes v1beta1 apiVersion (GitHub Issue)](https://github.com/kubernetes-sigs/cluster-api/issues/11920)

## Worker pools

A cluster's worker `MachineDeployment` set is configured as **multiple pools**:
`machines.workers.pools:` + `hCloud.machines.workers.pools:`.
Each key under `pools` becomes its own
`MachineDeployment` + `HCloudMachineTemplate` + `KubeadmConfigTemplate` (+ `MachineHealthCheck`),
letting you mix machine types, images, replica counts, and autoscaler settings in the same cluster.

Each pool inherits `machines.workers.defaults` and `hCloud.machines.workers.defaults:` by default,
so you only need to specify fields that differ from the defaults.

### Multi-pool example

For hetzner cloud:

```yaml
hCloud:
  machines:
    workers:
      defaults:
        type: "cpx32"
        osVersion: "2404"
        k8sVersion: "v1.31.4"
        buildTimestamp: "1744781328"
        imageName: >-
          {{- $machines := (include "machines" $) | fromYaml -}}
          cluster-api-ubuntu-{{ $machines.workers.defaults.osVersion }}-{{ $machines.workers.defaults.k8sVersion }}-{{ $machines.workers.defaults.buildTimestamp | required "ERROR: worker image buildTimestamp is required." }}
        # If autoscaler is enabled, replicas must be ignored by ArgoCD.
        # If autoscaler is enabled, replicas is in effect only until autoscaler is active, e.g. during bootstrap of the cluster.
        replicas: 3
        autoscaler:
          enabled: false
          minSize: "3"
          maxSize: "5"
        remediation:
          enabled: true
      pools:
        # general-purpose workers
        # Uses the legacy `worker:` naming for backwards compatibility.
        default: {}
        # specialized pool
        gpu:
          type: "x"
          placementGroupName: worker-gpu
          osVersion: "2404"
          k8sVersion: "v1.32.4"
          buildTimestamp: "1234567890"
          imageName: >-
            {{- $machines := (include "machines" $) | fromYaml -}}
            cluster-api-ubuntu-{{ $machines.workers.pools.gpu.osVersion }}-{{ $machines.workers.pools.gpu.k8sVersion }}-{{ $machines.workers.pools.gpu.buildTimestamp | required "ERROR: worker image buildTimestamp is required." }}
          replicas: 1
          autoscaler:
            enabled: true
            minSize: "1"
            maxSize: "2"
```

## `extraCommands` run as root - treat them as trusted code

`kubeadm.postKubeadm.extraCommandsCp` and `kubeadm.postKubeadm.extraCommandsWorker` are
inlined into the postKubeadm bash that runs **as root** on every node during cluster
bootstrap. Treat them as trusted code, not data — anyone who can write either value can
execute arbitrary commands on every CP / worker node.

Two differences worth knowing before you write either value:

- `extraCommandsCp` is rendered as a Helm template first (`{{ tpl . $ }}`), so you can
  reference other values inside it (e.g. `{{ include "cluster-name" . }}`). The
  trade-off is that anything in this field is interpreted as both a Helm template and
  a bash script.
- `extraCommandsWorker` is **not** templated — its content is passed to bash verbatim.
  Helm `{{ … }}` expressions inside it will reach the node as literal text.

Both blocks run under `set -eu`, so a non-zero exit aborts the rest of postKubeadm and
the node never finishes joining the cluster. Validate snippets locally before shipping
them via GitOps.

## When does an update replace nodes?

This chart names each `HCloudMachineTemplate` and `KubeadmConfigTemplate` with a hash of its **spec**.
CAPI replaces machines only when the name that a `MachineDeployment` or `KubeadmControlPlane` references changes,
i.e. only when the underlying spec changes.
Labels and other metadata are **not** part of the hash.

**Replaces nodes (rolling update):**

- Changing `k8sVersion`, `osVersion` or `buildTimestamp` or `imageName` (new node image).
- Changing the server `type` or `placementGroupName`.
- Changing the kubeadm config: kubelet args, `postKubeadm` commands, etc.

**Does _not_ replace nodes:**

- Bumping the chart `version` alone (only the `helm.sh/chart` label changes).
- Upgrading the providers (CAPI or CAPH controllers), related to management-plane only.
- Bumping `cilium` or `hcloud-cloud-controller-manager` versions (installed via `ClusterResourceSet`, unrelated to machine specs).
- Changing `replicas`, autoscaler annotations, or `MachineHealthCheck` settings.

## Migration

### From 0.12.0 to 0.13.0

Version 0.13.0 renders the CAPI **core** resources (`Cluster`, `KubeadmControlPlane`,
`MachineDeployment`, `MachineHealthCheck`, `ClusterResourceSet`) at the **`v1beta2`**
API version (previously `v1beta1`). The infrastructure resources (`HetznerCluster`,
`HCloudMachineTemplate`, `HCloudRemediationTemplate`) are still rendered at
`infrastructure.cluster.x-k8s.io/v1beta1`, because CAPH `v1.1.x` only serves `v1beta1`.
The core `v1beta2` objects reference them by `apiGroup`, and CAPI bridges the contract
(see [Compatibility](#compatibility)).

**Provider requirements - upgrade the management plane first**

- CAPI **`v1.13.x`** (tested with `v1.13.2`) must be installed and serving `v1beta2`
  **before** the chart is upgraded, otherwise the API server rejects the new manifests.
- CAPH **`v1.1.x`** (tested with `v1.1.6`).

Upgrade the CAPI and CAPH controllers out-of-band and confirm they are healthy,
then upgrade the chart.

**Breaking `values.yaml` changes - `MachineHealthCheck`**

The `v1beta2` `MachineHealthCheck` schema reshaped the health-check fields,
so the `healthCheck` block (under `machines.cp` and under every `machines.workers` pool) changed.
Durations are now **integer seconds** instead of duration strings. If you override any of these, migrate them:

| 0.12.0 (`v1beta1`) | 0.13.0 (`v1beta2`) |
|---|---|
| `healthCheck.nodeStartupTimeout: 15m0s` | `healthCheck.checks.nodeStartupTimeoutSeconds: 900` |
| `healthCheck.unhealthyConditions` | `healthCheck.checks.unhealthyNodeConditions` |
| `healthCheck.unhealthyConditions[].timeout: 5m0s` | `healthCheck.checks.unhealthyNodeConditions[].timeoutSeconds: 300` |
| `healthCheck.maxUnhealthy: 100%` | `healthCheck.remediation.triggerIf.unhealthyLessThanOrEqualTo: 100%` |

**This upgrade replaces all nodes**

`v1beta2` requires kubeadm `extraArgs`/`kubeletExtraArgs` as `name`/`value` lists instead of maps.
That changes the `KubeadmConfigTemplate` spec (and therefore its spec-hash name) and
the control-plane `kubeadmConfigSpec`,
so upgrading to 0.13.0 triggers a **rolling replacement of all control-plane and worker nodes**;
treat it like a `k8sVersion` bump and plan for a rolling update.
See [When does an update replace nodes?](#when-does-an-update-replace-nodes).

**Recommended steps**

1. Upgrade CAPI to `v1.13.x` and CAPH to `v1.1.x` (out-of-band); confirm both controllers are healthy.
2. Update your `healthCheck` overrides per the table above.
3. Render and validate against the live cluster before applying:
  ```bash
  helm template <release> charts/workload-cluster -f your-values.yaml \
    | kubectl apply --dry-run=server -f -
  ```
4. Apply / sync the **control-plane** resources first, excluding the worker
  `MachineDeployment` / `KubeadmConfigTemplate` (ArgoCD: selective sync or sync-waves;
  `kubectl`: apply `cluster.yaml` and `controlplane-nodes.yaml` only).
  Wait for the control-plane machines to roll and the cluster to report healthy.
5. Then apply / sync the **worker** changes and watch those nodes roll.

### From 0.11.0 to 0.12.0

Version 0.12.0 supports kubernetes version 1.32 and 1.33.

`1.33.12` requires a [manual RBAC fix](https://github.com/kubernetes-sigs/cluster-api/blob/6c70a17c7f343442238fc695e66884e6c84cfa01/docs/book/src/user/troubleshooting.md#kubeadm-join-fails-after-upgrading-to-kubernetes-patch-releases) after upgrading.

### From 0.10.2 to 0.11.0

Version 0.11.0 introduces the `workers.pools:` shape, which replaces the legacy `worker:` shape.
This is a breaking change, because it changes the resource names and `nodepool` labels of existing `MachineDeployment`s,
which causes **replacing** the existing nodes with new ones during the update.
To prevent this, the chart treats the **pool named `default` as un-suffixed**,
it renders with the same resource names and `nodepool` label as the legacy singular
shape. Using the **default** pool, you can safely update to 0.11.0 without any disruption.

| pool key | MachineDeployment | `nodepool` label |
|---|---|---|
| (legacy `worker:`) | `<cluster>-worker` | `<cluster>-worker` |
| `pools.default`    | `<cluster>-worker` | `<cluster>-worker` |
| `pools.gpu`        | `<cluster>-worker-gpu` | `<cluster>-worker-gpu` |

Two migration paths, all safe:

1. **Convert to a single-pool plural shape:**
  Move the config from `machines.worker:` into `machines.workers.defaults:`
  and `hCloud.machines.worker` into `hCloud.machines.workers.defaults`,
  and define `hCloud.machines.workers.pools.default: {}`.
  This will update without any disruption.
2. **Add more pools**:
  Do (1) first to establish `pools.default`,
  then add additional keys (e.g. `pools.gpu: { type: ccx33, ... }`).
  The `default` pool is unchanged, only the new pool's resources are created.
  See the [multi-pool example](#multi-pool-example) above for more details.

### From 0.10.1 to 0.10.2

Node IP discovery in `postKubeadmCommands` now uses the Hetzner metadata service (`169.254.169.254`) instead of `api.ipify.org`,
fixing silent empty-IP failures when ipify was unreachable.

**Replaces all nodes.** The change alters the embedded bootstrap config, so CP and worker nodes are **rolled and re-created** on upgrade.
No config changes needed; plan for a full node rollout.
