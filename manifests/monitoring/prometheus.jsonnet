local k8s = import "k8s.libsonnet";
{
  local config = {
    // Helper function for renaming labels in relabel rules
    local labelmap(from, to) = {
      action: "labelmap",
      regex: from,
      replacement: to,
    },
    // Mixin that uses kubernetes auth when scraping.
    // ie. Use https with the cluster root CA, and our service account token for auth.
    local use_k8s_auth = {
      scheme: "https",
      tls_config: {
        ca_file: "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
      },
      authorization: {
        credentials_file: "/var/run/secrets/kubernetes.io/serviceaccount/token",
      },
    },
    // Base scrape config common to the scrape configs that talk to kubelet
    local kubelet_config = use_k8s_auth + {
      // Scrape every kubelet
      kubernetes_sd_configs: [{ role: "node" }],
      relabel_configs: [
        // Record node name and labels as metric labels.
        // Don't record annotations as these may change too often
        labelmap("__meta_kubernetes_node_name", "node"),
        labelmap("__meta_kubernetes_node_label_(.*)", "node_${1}"),
      ],
    },
    // Base scrape config common to the scrape configs that use pod discovery.
    // It saves some pod metadata as labels, and allows overriding the metric path
    // with the prometheus.io/path annotation.
    local pod_config = {
      kubernetes_sd_configs: [{
        // Make a scrape target for each port defintion of each pod
        role: "pod",
        attach_metadata: { node: true },
      }],
      relabel_configs: [
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
    // Actual config
    global: {
      scrape_interval: "15s",
      evaluation_interval: "15s",
    },
    scrape_configs: [
      // for metrics involving kubelet itself
      kubelet_config + { job_name: "kubelet" },
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
      pod_config + {
        job_name: "pods",
        relabel_configs+: [
          // Only keep targets where port name == "prom"
          {
            action: "keep",
            source_labels: ["__meta_kubernetes_pod_container_port_name"],
            regex: "prom",
          },
        ],
      },
      // Special case for scraping kubernetes component pods. Scrapes pods with a port called
      // "prom-system". Uses TLS and auths with service account.
      // Because we're scraping by pod ip (not service) and the pod ip is ephemeral, it is not on the cert.
      // Setting the correct service name in prometheus via relabel rule is not yet supported:
      //   https://github.com/prometheus/prometheus/issues/4827
      // Our options are a hard-coded scrape config per service (which isn't awful), or
      // ignoring TLS verification. If an attacker is able to MitM direct-ip connections within
      // the cluster, we have bigger problems than "they can mis-report system metrics".
      pod_config + use_k8s_auth + {
        job_name: "system-pods",
        tls_config+: { insecure_skip_verify: true },
        relabel_configs+: [
          // Only keep targets where port name == "prom-system"
          {
            action: "keep",
            source_labels: ["__meta_kubernetes_pod_container_port_name"],
            regex: "prom-system",
          },
        ],
      },
    ],
  },

  // TODO: send postgres a HUP when this changes
  configmap: k8s.configmap("prometheus", data = {
    "prometheus.yml": std.manifestJson(config),
  }),

  perms: k8s.sa_with_role("prometheus", namespace = "monitoring", cluster_role = true, rules = [
    {
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
    },
    {
      // To scrape metrics from system components
      nonResourceURLs: ["/metrics"],
      verbs: ["get"],
    },
  ]),

  service: k8s.service("prometheus", ports = {
    http: { port: 80, targetPort: 9090 }, // TODO change prom port
  }),

  deployment: k8s.deployment("prometheus",
    pod={
      serviceAccount: "prometheus",
      volumes: [{
        name: "config",
        configMap: { name: "prometheus" },
      }],
      containers: [{
        name: "prometheus",
        image: "prom/prometheus:v2.45.3",
        args: [
          "--storage.tsdb.retention=30d",
          "--config.file=/etc/prometheus/prometheus.yml",
        ],
        volumeMounts: [
          {
            name: "config",
            mountPath: "/etc/prometheus/",
          },
          {
            name: "data",
            mountPath: "/prometheus",
          },
        ],
        // prom container defaults to nobody user, use root instead to avoid fs perm issues
        securityContext: {
          runAsUser: 0,
        }
      }],
    } + k8s.mixins.host_path("data", "charm", "/srv/prometheus"),
  ) + k8s.mixins.run_one,

}
