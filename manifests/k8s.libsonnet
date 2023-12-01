{
  // Basic helper for specifying an api version and kind
  resource(apiVersion, kind): {
    apiVersion: apiVersion,
    kind: kind,
  },

  // Helper that sets common metadata fields
  metadata(name, namespace = "default", labels = {}): {
    metadata: {
      name: name,
      namespace: namespace,
      labels: labels,
    },
  },

  deployment(
    name,
    pod,
    namespace = "default",
    labels = { app: name },
    replicas = 1,
  ): $.resource("apps/v1", "Deployment") + $.metadata(name, namespace, labels) + {
    spec: {
      replicas: replicas,
      selector: { matchLabels: labels },
      template: {
        metadata: {
          labels: labels,
        },
        spec: pod,
      },
    },
  },

  configmap(
    name,
    data,
    namespace = "default",
    labels = { app: name },
  ): $.resource("v1", "ConfigMap") + $.metadata(name, namespace, labels) + { data: data },

  // Patches to objects of various kinds to add certain common configurations.
  mixins: {
    // For deployments, configure them to only ever run one at a time.
    // This is not a guarentee but k8s won't do it intentionally.
    run_one: {
      spec+: {
        replicas: 1,
        strategy: { type: "Recreate" },
      },
    },
  },

}
