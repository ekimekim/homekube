{
  local opts_to_args(opts) = [
    local key = std.strReplace(opt, "_", "-");
    local value = opts[opt];
    if value == true then
      "--%s" % [key]
    else
      "--%s=%s" % [key, std.toString(value)]
    for opt in std.objectFields(opts)
  ],
  kind: "Pod",
  apiVersion: "v1",
  metadata: {
    namespace: "kube-system",
    name: "controller-manager",
    labels: {
      app: "controller-manager",
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
      image: "registry.k8s.io/kube-controller-manager:v1.28.4",
      command: ["kube-controller-manager"],
      args: opts_to_args({
        kubeconfig: "/etc/kubernetes/kube-controller-manager.kubeconfig",
        // These two extra args are required to defer authn/authz to the kube api.
        // Without them, all requests are considered anonymous/rejected.
        // It's possible for them to be seperate credentials but the existing credentials are
        // more powerful anyway and I can't see any way least-privilege access is helpful here.
        authentication_kubeconfig: self.kubeconfig,
        authorization_kubeconfig: self.kubeconfig,
        service_cluster_ip_range: "192.168.43.0/24",
        root_ca_file: "/etc/kubernetes/root.pem",
        service_account_private_key_file: "/etc/kubernetes/service-accounts-key.pem",
        // Have each controller use its own service account, for further division of permissions
        use_service_account_credentials: true,
        // Log verbosity. This is the level used by Kubernetes the Hard Way.
        v: 2,
      }),
      volumeMounts: [
        {
          name: "config",
          mountPath: "/etc/kubernetes",
        },
      ],
      ports: [{
        name: "prom-system",
        containerPort: 10257,
      }],
    }],
  },
}
