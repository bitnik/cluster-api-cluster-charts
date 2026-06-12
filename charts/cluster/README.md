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

| Component | Version | Notes |
|-----------|---------|-------|
| Core provider (CAPI) | `v1.8.12` | apiVersion served: `v1beta1`, CAPI contract: `v1beta1` |
| Bootstrap provider (kubeadm) | `v1.8.12` | ships with CAPI |
| Control-plane provider (kubeadm) | `v1.8.12` | ships with CAPI |
| Infrastructure provider (CAPH) | `v1.0.7` | apiVersion: `v1beta1`, contract: `v1beta1` |
| Node OS image | `Ubuntu 24.04` | `osVersion: "2404"` |
| Kubernetes (node image) | `v1.31.4` | set via `k8sVersion` in the chart |

`cilium` or `hcloud-cloud-controller-manager` versions,installed via `ClusterResourceSet`, are independent of providers.
<!--| hcloud-cloud-controller-manager (chart) | `1.26.0` | independent of CAPI, CAPH |-->
<!--| Cilium (chart) | `1.18.0` | independent of CAPI, CAPH |-->

This chart renders CAPI resources at the **`v1beta1`** API version.
CAPH still implements `v1beta1`; its `v1.2.x` line moves to `v1beta2`, which this chart does not yet target.
Therefore, this chart is currently compatible with CAPH `v1.0.x` and CAPI `v1.8.x`, `v1.9.x` and `v1.10.x`.

| Pairing | apiVersion served | Contract (core <-> provider) | What to do with v1beta1 YAMLs | Notes |
|---------|-------------------|------------------------------|-------------------------------|-------|
| CAPI `v1.8.x - v1.10.x` and CAPH `v1.0.x`  | v1beta1 only | v1beta1 <-> v1beta1 | leave as v1beta1 |  stable, but CAPI 1.10 is now **EOL**! (Current status) |
| CAPI `v1.12.x - v1.15.x` and CAPH [`v1.1.x`](https://github.com/syself/cluster-api-provider-hetzner/releases/tag/v1.1.0) | core v1beta1+v1beta2; CAPH v1beta1 | v1beta2 <-> v1beta1 (bridged by temporary shim) | Optionally migrate only CAPI resources (Cluster, KubeadmControlPlane, MachineDeployment) to v1beta2 | Works via shim (next step) |
| CAPI `>= v1.12.x` and CAPH `v1.2.x` | v1beta2 | v1beta2 <-> v1beta2 | Migrate all resources to v1beta2 | Fully aligned. This is the destination, but CAPH `v1.2.x` not released yet. |

For Kubernetes version support, check the [CAPH compatibility matrix](https://syself.com/docs/caph/getting-started/introduction#compatibility-with-cluster-api-and-kubernetes-versions) (pay attention to compatibility notes).

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

## Migration from 0.10.2 to 0.11.0

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
