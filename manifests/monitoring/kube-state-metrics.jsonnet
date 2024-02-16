local k8s = import "k8s.libsonnet";
local util = import "util.libsonnet";
{
  perms: k8s.sa_with_role("kube-state-metrics", namespace="monitoring", cluster_role=true, rules={
    // https://github.com/kubernetes/kube-state-metrics/blob/main/examples/standard/cluster-role.yaml
    read: {
      "": [
        "configmaps",
        "secrets",
        "nodes",
        "pods",
        "services",
        "serviceaccounts",
        "resourcequotas",
        "replicationcontrollers",
        "limitranges",
        "persistentvolumeclaims",
        "persistentvolumes",
        "namespaces",
        "endpoints",
      ],
      apps: [
        "statefulsets",
        "daemonsets",
        "deployments",
        "replicasets",
      ],
      batch: ["cronjobs", "jobs"],
      autoscaling: ["horizontalpodautoscalers"],
      policy: ["poddisruptionbudgets"],
      "certificates.k8s.io": ["certificatesigningrequests"],
      "discovery.k8s.io": ["endpointslices"],
      "storage.k8s.io": ["storageclasses", "volumeattachments"],
      "admissionregistration.k8s.io": [
        "mutatingwebhookconfigurations",
        "validatingwebhookconfigurations",
      ],
      "networking.k8s.io": [
        "networkpolicies",
        "ingressclasses",
        "ingresses",
      ],
      "coordination.k8s.io": ["leases"],
      "rbac.authorization.k8s.io": [
        "clusterrolebindings",
        "clusterroles",
        "rolebindings",
        "roles",
      ],
    },
    create: {
      "authentication.k8s.io": ["tokenreviews"],
      "authorization.k8s.io": ["subjectaccessreviews"],
    },
  }),

  deployment: k8s.deployment("kube-state-metrics", pod={
    serviceAccount: "kube-state-metrics",
    containers: [{
      name: "kube-state-metrics",
      image: "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.0",
      args: util.opts_to_args({
        // What labels to include in metrics. This is of the form "TYPE=[LABEL,...], ..."
        // but the value "*" can be used to mean "all" for either TYPE or LABEL.
        // So "*=[*]" means "all labels for all resources", which may be expensive in prometheus
        // but we'll start from there and see.
        metric_labels_allowlist: "*=[*]",
      }),
      readinessProbe: {
        httpGet: { path: "/", port: 8081 },
      },
      ports: [
        // This port is scraped by prom without adding metadata for this pod,
        // as the data itself has pod, namespace etc labels.
        {
          name: "prom-no-meta",
          containerPort: 8080,
        },
        // This is the prom metrics for kube-state-metrics itself, which we scrape normally.
        {
          name: "prom",
          containerPort: 8081,
        },
      ],
    }],
  }),
}
