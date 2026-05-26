{{/*
Expand the name of the chart.
*/}}
{{- define "cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "cluster.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cluster.labels" -}}
helm.sh/chart: {{ include "cluster.chart" . }}
{{ include "cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
validate runs preflight checks on .Values. Called from the top of
`cluster.cluster` so the whole render fails at the first invalid config,
instead of relying on top-level {{ fail }} blocks scattered through this
helper file (which made the trigger point opaque and ran the hetzner-only
LB check even when a different infrastructure provider was selected).
*/}}
{{- define "cluster.validate" -}}
{{- if ne .Values.capi.providers.core.name "cluster-api" -}}
{{- fail "Please set which CAPI core provider to use. Supported providers: 'cluster-api'." -}}
{{- end -}}
{{- if ne .Values.capi.providers.controlPlane.name "kubeadm" -}}
{{- fail "Please set which CAPI controlPlane provider to use. Supported providers: 'kubeadm'." -}}
{{- end -}}
{{- if ne .Values.capi.providers.bootstrap.name "kubeadm" -}}
{{- fail "Please set which CAPI bootstrap provider to use. Supported providers: 'kubeadm'." -}}
{{- end -}}
{{- if eq .Values.capi.providers.infrastructure.name "hetzner" -}}
  {{- if not (or .Values.hCloud.lb.existing.ip .Values.hCloud.lb.new) -}}
  {{- fail "Please use an existing LB via '.Values.hCloud.lb.existing' or add configuration for a new one via '.Values.hCloud.lb.new'." -}}
  {{- end -}}
{{- else -}}
{{- fail "Please set which CAPI infrastructure provider to use. Supported providers: 'hetzner'." -}}
{{- end -}}
{{- end }}

{{/*
Merge hCloud.networking with networking. hCloud.networking overwrites.
*/}}
{{- define "networking" -}}
  {{- if eq .Values.capi.providers.infrastructure.name "hetzner" }}
  {{- mustMergeOverwrite (deepCopy .Values.networking) .Values.hCloud.networking | toYaml }}
  {{- end }}
{{- end }}

{{/*
Merge hCloud.machines with machines. hCloud.machines overwrites.
*/}}
{{- define "machines" -}}
  {{- if eq .Values.capi.providers.infrastructure.name "hetzner" }}
  {{- mustMergeOverwrite (deepCopy .Values.machines) .Values.hCloud.machines | toYaml }}
  {{- end }}
{{- end }}

{{- define "cluster-name" -}}
{{- .Values.cluster.name | default .Release.Name }}
{{- end }}

{{- define "lb-existing-name" -}}
{{- .Values.hCloud.lb.existing.name | default .Release.Name }}
{{- end }}

{{- define "cp-name" -}}
{{- printf "%s-cp" (include "cluster-name" .) }}
{{- end }}

{{/*
worker-name renders the base name shared by a pool's MachineDeployment,
HCloudMachineTemplate, KubeadmConfigTemplate, MachineHealthCheck, and the
`nodepool` label.
The pool named "default" is intentionally un-suffixed so it
matches the legacy single-pool name `<cluster>-worker`. This is what makes
migrating `machines.worker` → `machines.workers.pools.default` a no-op.

Accepts a {root, poolName, poolSpec} dict (per-pool helper call sites).
NOTE: poolSpec is not used by this helper.
*/}}
{{- define "worker-pool-name" -}}
{{- if eq .poolName "default" -}}
{{- printf "%s-worker" (include "cluster-name" .root) -}}
{{- else -}}
{{- printf "%s-worker-%s" (include "cluster-name" .root) .poolName -}}
{{- end -}}
{{- end }}

{{- define "cp-hcloud-machine-template-spec" -}}
{{- $machines := (include "machines" .) | fromYaml -}}
{{- /*
PublicNetwork specifies information for public networks. It defines the specs about the primary IP address of the server.
If both IPv4 and IPv6 are disabled, then the private network has to be enabled.
*/ -}}
publicNetwork:
  enableIPv4: true
  enableIPv6: false
imageName: {{ tpl ($machines.cp.imageName | required "ERROR: CP imageName is required.") . }}
placementGroupName: {{ $machines.cp.placementGroupName }}
type: {{ $machines.cp.type | required "ERROR: CP type is required." }}
{{- end }}
{{- define "cp-hcloud-machine-template-name" -}}
{{- printf "%s-%s" (include "cp-name" .) ((include "cp-hcloud-machine-template-spec" .) | sha256sum | trunc 16) }}
{{- end }}
{{- define "cp-hcloud-machine-template-labels" -}}
{{- $machines := (include "machines" .) | fromYaml -}}
{{- with $machines.cp.osVersion -}}
capi/osVersion: {{ . | quote }}
{{- end }}
capi/k8sVersion: {{ $machines.cp.k8sVersion | required "ERROR: CP k8sVersion is required" | quote }}
capi/imageName: {{ tpl ($machines.cp.imageName | required "ERROR: CP imageName is required.") . | quote }}
{{- end }}

{{/*
cluster.workerPools returns a YAML map `{ <pool-name>: <merged-pool-spec> }`
that callers iterate over to render per-pool MachineDeployment, templates and MHC resources.
It accepts machines.workers.{defaults,pools} + hCloud.machines.workers.{defaults,pools}.
*/}}
{{- define "cluster.workerPools" -}}
{{- /* First get machine defaults and pools */}}
{{- $defaults := (.Values.machines.workers.defaults | default dict) -}}
{{- $pools := (.Values.machines.workers.pools | default dict) -}}
{{- /* Prepare merged output */}}
{{- $out := dict -}}
{{- /* Get hetzner cloud defaults and pools, and merge. */}}
{{- if eq .Values.capi.providers.infrastructure.name "hetzner" -}}
{{- $hcDefaults := (.Values.hCloud.machines.workers.defaults | default dict) -}}
{{- $hcPools := (.Values.hCloud.machines.workers.pools | default dict) -}}
{{- $mergedDefaults := mustMergeOverwrite (deepCopy $defaults) $hcDefaults -}}
{{- $allKeys := keys $pools | concat (keys $hcPools) | uniq -}}
{{- range $k := $allKeys -}}
  {{- $p := (index $pools $k) | default dict -}}
  {{- $hcp := (index $hcPools $k) | default dict -}}
  {{- $poolMerged := mustMergeOverwrite (deepCopy $mergedDefaults) $p $hcp -}}
  {{- $_ := set $out $k $poolMerged -}}
{{- end -}}
{{- /* Validate worker pool names length */}}
{{- $cluster := include "cluster-name" . -}}
{{- range $k, $_ := $out -}}
  {{- $base := "" -}}
  {{- if eq $k "default" -}}
    {{- $base = printf "%s-worker" $cluster -}}
  {{- else -}}
    {{- $base = printf "%s-worker-%s" $cluster $k -}}
  {{- end -}}
  {{- if gt (int (add (len $base) 17)) 63 -}}
    {{- fail (printf "worker pool %q produces resource name %q which exceeds 63 chars once the 17-char spec-hash suffix is appended; shorten the cluster name or pool name" $k $base) -}}
  {{- end -}}
{{- end -}}
{{- end -}}
{{- $out | toYaml -}}
{{- end }}

{{/*
worker-hcloud-machine-template-spec renders the HCloudMachineTemplate.spec.template.spec
for a single pool. Accepts a {root, poolName, poolSpec} dict where:
  - .root is the chart root context (for `tpl` and required-key errors)
  - .poolName is the pool key (used only in error messages)
  - .poolSpec is the merged pool spec from `cluster.workerPools`
*/}}
{{- define "worker-hcloud-machine-template-spec" -}}
publicNetwork:
  enableIPv4: true
  enableIPv6: false
imageName: {{ tpl (.poolSpec.imageName | required (printf "ERROR: worker pool %q imageName is required." .poolName)) .root }}
placementGroupName: {{ .poolSpec.placementGroupName }}
type: {{ .poolSpec.type | required (printf "ERROR: worker pool %q type is required." .poolName) }}
{{- end }}
{{/*
Accepts a {root, poolName, poolSpec} dict (per-pool helper call sites).
*/}}
{{- define "worker-hcloud-machine-template-name" -}}
{{- printf "%s-%s" (include "worker-pool-name" .) ((include "worker-hcloud-machine-template-spec" .) | sha256sum | trunc 16) }}
{{- end }}
{{/*
Accepts a {root, poolName, poolSpec} dict (per-pool helper call sites).
*/}}
{{- define "worker-hcloud-machine-template-labels" -}}
{{- with .poolSpec.osVersion -}}
capi/osVersion: {{ . | quote }}
{{- end }}
capi/k8sVersion: {{ .poolSpec.k8sVersion | required (printf "ERROR: worker pool %q k8sVersion is required" .poolName) | quote }}
capi/imageName: {{ tpl (.poolSpec.imageName | required (printf "ERROR: worker pool %q imageName is required." .poolName)) .root | quote }}
{{- end }}

{{/*
worker-kubeadm-config-template-spec renders the KubeadmConfigTemplate body.
The body is currently identical across pools (no per-pool kubelet overrides).

Accepts a {root, poolName, poolSpec} dict (per-pool helper call sites).
NOTE: poolName and poolSpec is not used by this helper.
*/}}
{{- define "worker-kubeadm-config-template-spec" -}}
{{- with .root -}}
joinConfiguration:
  nodeRegistration:
    criSocket: unix:///var/run/containerd/containerd.sock
    # https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/
    # https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/
    # https://cluster-api.sigs.k8s.io/tasks/bootstrap/kubeadm-bootstrap/kubelet-config
    kubeletExtraArgs:
      anonymous-auth: "false"
      authentication-token-webhook: "true"
      authorization-mode: Webhook
      cloud-provider: external
      event-qps: "1"
      # feature-gates: RotateKubeletServerCertificate=true
      kubeconfig: /etc/kubernetes/kubelet.conf
      max-pods: "220"
      node-labels: "node.kubernetes.io/role=worker"
      protect-kernel-defaults: "true"
      read-only-port: "0"
      rotate-certificates: "true"
      rotate-server-certificates: "true"
      seccomp-default: "true"
      streaming-connection-idle-timeout: "5m"
      tls-min-version: VersionTLS12
      tls-cipher-suites: TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305
  {{- /*
  # https://cluster-api.sigs.k8s.io/tasks/bootstrap/kubeadm-bootstrap/kubelet-config.html?highlight=KubeletConfiguration#use-kubeadms-kubeletconfiguration-patch-target
  # kubectl explain KubeadmControlPlane.spec.kubeadmConfigSpec.joinConfiguration.patches
  # patches:
  #   directory: /etc/kubernetes/patches
  */}}
  {{- if .Values.kubeadm.kubeApiServer.disablePublicAccessClusterInfoConfigMap }}
  discovery:
    file:
      kubeConfig:
        {{- /*
        user:
          # exec:
          #   apiVersion: client.authentication.k8s.io/v1
          #   command: |
          #     cat <<EOF
          #     {
          #       "apiVersion": "client.authentication.k8s.io/v1",
          #       "kind": "ExecCredential",
          #       "spec": {},
          #       "status": {}
          #     }
          #     EOF
      */}}
      kubeConfigPath: /etc/kubernetes/discovery-kubeconfig.yaml
  {{- end }}
{{- /*
preKubeadmCommands:
- bash /etc/kubernetes/preKubeadmCommands.sh 2>&1 | tee -a /var/log/preKubeadmCommands.log
*/}}
postKubeadmCommands:
- bash /etc/kubernetes/postKubeadmCommands.sh 2>&1 | tee -a /var/log/postKubeadmCommands.log
files:
{{- /*
- path: /etc/kubernetes/preKubeadmCommands.sh
  owner: root:root
  permissions: "0700"
  content: |-
    #!/usr/bin/env bash
    set -eu
    echo "preKubeadmCommands started!"

    # {{- if .Values.kubeadm.kubeApiServer.disablePublicAccessClusterInfoConfigMap }}
    # if [ -f /etc/kubernetes/discovery-kubeconfig.yaml ]; then
    #   # cat /run/kubeadm/kubeadm-join-config.yaml
    #   yq eval '.users = null' -i /etc/kubernetes/discovery-kubeconfig.yaml
    #   yq eval '.clusters.0.name = ""' -i /etc/kubernetes/discovery-kubeconfig.yaml
    #   yq eval '.contexts = null' -i /etc/kubernetes/discovery-kubeconfig.yaml
    #   yq eval '.current-context = ""' -i /etc/kubernetes/discovery-kubeconfig.yaml
    # fi
    # {{- end }}
    echo "Done!"
*/}}
- path: /etc/kubernetes/postKubeadmCommands.sh
  owner: root:root
  permissions: "0700"
  content: |-
    #!/usr/bin/env bash
    set -eu
    echo "postKubeadmCommands started!"

    {{- if .Values.kubeadm.setKubeletNodeIp }}
    NODEIP=$(curl -s https://api.ipify.org | tr -d '\n')
    echo "$NODEIP"
    sed -i "/--node-ip/d" /var/lib/kubelet/kubeadm-flags.env
    echo "KUBELET_KUBEADM_ARGS=\"--node-ip=$NODEIP $(cat /var/lib/kubelet/kubeadm-flags.env \
      | sed 's/KUBELET_KUBEADM_ARGS=\"//')" > /var/lib/kubelet/kubeadm-flags.env
    systemctl restart kubelet
    {{- end }}

    {{- with .Values.kubeadm.postKubeadm.extraCommandsWorker }}
    {{- . | nindent 10 }}
    {{- end }}
    echo "Done!"
{{- /*
{{- if not .Values.kubeadm.disableKubeProxy }}
# https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/#kubelet-config-k8s-io-v1beta1-KubeletConfiguration
- path: /etc/kubernetes/patches/kubeproxyconfiguration0+strategic.json
  owner: root:root
  permissions: "0644"
  content: |-
    {
      "apiVersion": "kubeproxy.config.k8s.io/v1alpha1",
      "kind": "KubeletConfiguration",
      "metricsBindAddress": "0.0.0.0:10249"
    }
{{- end }}
*/}}
{{- end }}
{{- end }}
{{/*
Accepts a {root, poolName, poolSpec} dict (per-pool helper call sites).
*/}}
{{- define "worker-kubeadm-config-template-name" -}}
{{- printf "%s-%s" (include "worker-pool-name" .) ((include "worker-kubeadm-config-template-spec" .) | sha256sum | trunc 16) }}
{{- end }}

{{/* Trim a version like "v1.31.4" to "v1.31" */}}
{{- define "cluster.cp.k8sVersionMajor" -}}
{{- $machines := (include "machines" .) | fromYaml -}}
{{- $v := $machines.cp.k8sVersion | splitList "." -}}
{{- printf "%s.%s" (index $v 0) (index $v 1) -}}
{{- end -}}

{{/* Check if there is any resource with strategy "ApplyOnce". Used in _cluster-resource-set.yaml */}}
{{- define "hasApplyOnce" -}}
{{- $found := false -}}
{{- range $k, $v := . -}}
  {{- if eq (default "" $v.strategy) "ApplyOnce" }}
    {{- $found = true -}}
  {{- end -}}
{{- end -}}
{{- $found -}}
{{- end -}}
{{/* Check if there is any resource with strategy "Reconcile". Used in _cluster-resource-set.yaml */}}
{{- define "hasReconcile" -}}
{{- $found := false -}}
{{- range $k, $v := . -}}
  {{- if eq (default "" $v.strategy) "Reconcile" }}
    {{- $found = true -}}
  {{- end -}}
{{- end -}}
{{- $found -}}
{{- end -}}
