local k8s = import "k8s.libsonnet";
local util = import "util.libsonnet";
{
  perms: k8s.sa_with_role("kube-state-metrics", namespace="kube-system", clusterRole=true, rules=[
    // https://github.com/kubernetes/kube-state-metrics/blob/main/examples/standard/cluster-role.yaml
  {
    apiGroups: [""],
    verbs: ["list", "watch"],
    resources: [
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
  },
  {
    apiGroups: ["apps"],
    verbs: ["list", "watch"],
    resources: [
      "statefulsets",
      "daemonsets",
      "deployments",
      "replicasets",
    ],
  },
  {
    apiGroups: ["batch"],
    verbs: ["list", "watch"],
    resources: ["cronjobs", "jobs"],
  },
  {
    apiGroups: ["autoscaling"],
    verbs: ["list", "watch"],
    resources: ["horizontalpodautoscalers"],
  },
  {
    apiGroups: ["authentication.k8s.io"],
    verbs: ["create"],
    resources: ["tokenreviews"],
  },
  {
    apiGroups: ["authorization.k8s.io"],
    verbs: ["create"],
    resources: ["subjectaccessreviews"],
  },
  {
    apiGroups: ["policy"],
    verbs: ["list", "watch"],
    resources: ["poddisruptionbudgets"],
  },
  {
    apiGroups: ["certificates.k8s.io"],
    verbs: ["list", "watch"],
    resources: ["certificatesigningrequests"],
  },
  {
    apiGroups: [
      "discovery.k8s.io",
    ],
    verbs: [
      "list",
      "watch",
    ],
    resources: [
      "endpointslices",
    ],
  },
  {
    apiGroups: [
      "storage.k8s.io",
    ],
    verbs: [
      "list",
      "watch",
    ],
    resources: [
      "storageclasses",
      "volumeattachments",
    ],
  },
  {
    apiGroups: [
      "admissionregistration.k8s.io",
    ],
    verbs: [
      "list",
      "watch",
    ],
    resources: [
      "mutatingwebhookconfigurations",
      "validatingwebhookconfigurations",
    ],
  },
  {
    apiGroups: [
      "networking.k8s.io",
    ],
    verbs: [
      "list",
      "watch",
    ],
    resources: [
      "networkpolicies",
      "ingressclasses",
      "ingresses",
    ],
  },
  {
    apiGroups: [
      "coordination.k8s.io",
    ],
    verbs: [
      "list",
      "watch",
    ],
    resources: [
      "leases",
    ],
  },
  {
    apiGroups: [
      "rbac.authorization.k8s.io",
    ],
    verbs: [
      "list",
      "watch",
    ],
    resources: [
      "clusterrolebindings",
      "clusterroles",
      "rolebindings",
      "roles",
    ],
  },
]
  ]),

  deployment: k8s.deployment("kube-state-metrics", pod={
    containers: [{
      name: "kube-state-metrics",
      image: "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.0",
      args: util.opts_to_args({
        // What labels to include in metrics. This is of the form "TYPE=[LABEL,...], ..."
        // but the value "*" can be used to mean "all" for either TYPE or LABEL.
        // So "*=[*]" means "all labels for all resources", which may be expensive in prometheus
        // but we'll start from there and see.
        metric_labels_allowlist: "*=[*]",
        port: 80,
        telemetry_port: 8080,
      }),
      readinessProbe: {
        httpGet: { path: "/", port: 8080 },
      },
      ports: [
        // This port is scraped by prom, but not using the standard scrape target.
        {
          name: "state-metrics",
          containerPort: 80,
        },
        // This is the prom metrics for kube-state-metrics itself, which we scrape normally.
        {
          name: "prom",
          containerPort: 8080,
        },
      ],
    }],
  }),
}
