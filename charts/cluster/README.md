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

## `extraCommands` run as root — treat them as trusted code

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
