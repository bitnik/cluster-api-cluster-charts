# cluster chart

This is a [library chart](https://helm.sh/docs/topics/library_charts/)
and implemented to be used by umbrella/parent charts
to create [Cluster API](https://cluster-api.sigs.k8s.io/) (CAPI) clusters
for their own purposes.
This chart can't be installed as itself.

Supported [providers](https://cluster-api-operator.sigs.k8s.io/01_user/01_concepts):

* Core provider: [Cluster API](https://github.com/kubernetes-sigs/cluster-api)
* Infrastructure providers:
  * [hetzner](https://github.com/syself/cluster-api-provider-hetzner) (CAPH)
* Control Plane providers
  * [kubeadm](https://github.com/kubernetes-sigs/cluster-api/tree/main/controlplane/kubeadm)
* Bootstrap providers:
  * [kubeadm](https://github.com/kubernetes-sigs/cluster-api/tree/main/bootstrap/kubeadm)

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
