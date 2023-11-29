{
  // Basic helper for specifying an api version and kind
  resource(apiVersion, kind): {
    apiVersion: apiVersion,
    kind: kind,
  },

  deployment(
    name,
    namespace = "default",
    labels = { app: name },
    replicas = 1,
    pod,
  ): $.resource("apps/v1", "Deployment") + {
    metadata: {
      name: name,
      labels: labels,
    },
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
  }
}
