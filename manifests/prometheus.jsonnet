local k8s = import "k8s.libsonnet";
{
  local config = {
    local labelmap(from, to) = {
      action: "labelmap",
      regex: from,
      replacement: to,
    },
    local kubelet_config = {
      job_name: "kubelet",
      // Use https with the cluster root CA, and our service account token for auth.
      // Prom docs say it uses the plaintext http port by default but our kubelet doesn't
      // seem to have one.
      scheme: "https",
      tls_config: {
        ca_file: "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
      },
      authorization: {
        credentials_file: "/var/run/secrets/kubernetes.io/serviceaccount/token",
      },
      // Scrape every kubelet
      kubernetes_sd_configs: [{ role: "node" }],
      relabel_configs: [
        // Record node name and labels as metric labels.
        // Don't record annotations as these may change too often
        labelmap("__meta_kubernetes_node_name", "node"),
        labelmap("__meta_kubernetes_node_label_(.*)", "node_${1}"),
      ],
    },
    global: {
      scrape_interval: "15s",
      evaluation_interval: "15s",
    },
    scrape_configs: [
      // for metrics involving kubelet itself
      kubelet_config,
      // for metrics kubelet gathers about running pods
      kubelet_config + {
        job_name: "cadvisor",
        metrics_path: "/metrics/cadvisor"
      },
      // for metrics about readiness and liveness probes
      kubelet_config + {
        job_name: "probes",
        metrics_path: "/metrics/probes",
      },
      // Scrape every pod on any port called "prom".
      // If present, the "prometheus.io/path" annotation sets the path (default /metrics).
      {
        job_name: "pods",
        kubernetes_sd_configs: [{
          // Make a scrape target for each port defintion of each pod
          role: "pod",
          attach_metadata: { node: true },
        }],
        relabel_configs: [
          // Only keep targets where port name == "prom"
          {
            action: "keep",
            source_labels: ["__meta_kubernetes_pod_container_port_name"],
            regex: "prom",
          },
          // If the prometheus.io/path annotation is set, replace __metrics_path__ with it.
          {
            action: "replace",
            source_labels: ["__meta_kubernetes_pod_annotation_prometheus_io_path"],
            regex: "(.+)",
            target_label: "__metrics_path__",
            replacement: "${1}",
          },
          // Record useful info as metric labels.
          // No need to record the pod ip as it is saved in "instance".
          // The container/pod ids aren't meaningful on their own but are useful
          // for differentiating containers across restarts / stable-named pods across recreates.
          // Annotations are excluded as they may change often.
          labelmap("__meta_kubernetes_namespace", "namespace"),
          labelmap("__meta_kubernetes_pod_name", "pod"),
          labelmap("__meta_kubernetes_pod_label_(.+)", "${1}"),
          labelmap("__meta_kubernetes_pod_container_name", "container"),
          labelmap("__meta_kubernetes_pod_container_id", "container_id"),
          labelmap("__meta_kubernetes_pod_node_name", "node"),
          labelmap("__meta_kubernetes_pod_uid", "pod_id"),
          labelmap("__meta_kubernetes_pod_controller_name", "controller"),
          labelmap("__meta_kubernetes_pod_controller_kind", "controller_kind"),
        ],
      },
    ],
  },

  // TODO: send postgres a HUP when this changes
  configmap: k8s.configmap("prometheus", namespace = "monitoring", data = {
    "prometheus.yml": std.manifestJson(config),
  }),

  perms: k8s.sa_with_role("prometheus", namespace = "monitoring", cluster_role = true, rules = [
    apiGroups: [""],
    verbs: ["get", "list", "watch"],
    resources: [
      // To list kubelets to scrape, and get node metadata for pods
      "nodes",
      // To scrape kubelet metrics
      "nodes/metrics",
      // To list pods to scrape
      "pods",
    ],
  ]),

}
