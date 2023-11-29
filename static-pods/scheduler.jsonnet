{
  local opts_to_args(opts) = [
    local key = std.strReplace(opt, "_", "-");
    local value = std.toString(opts[opt]);
    "--%s=%s" % [key, value]
    for opt in std.objectFields(opts)
  ],
  kind: "Pod",
  apiVersion: "v1",
  metadata: {
    namespace: "kube-system",
    name: "scheduler",
    labels: {
      app: "scheduler",
      static: "master",
    },
  },
  spec: {
    volumes: [
      {
        name: "config",
        hostPath: {path: "/etc/kubernetes"},
      },
    ],
    containers: [{
      name: "scheduler",
      image: "registry.k8s.io/kube-scheduler:v1.28.4",
      command: ["kube-scheduler"],
      args: opts_to_args({
        kubeconfig: "/etc/kubernetes/kube-scheduler.kubeconfig",
        // Log verbosity. This is the level used by Kubernetes the Hard Way.
        v: 2,
      }),
      volumeMounts: [
        {
          name: "config",
          mountPath: "/etc/kubernetes",
        },
      ],
    }],
  },
}
