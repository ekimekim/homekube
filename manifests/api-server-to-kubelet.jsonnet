local k8s = import "k8s.libsonnet";

[
  // The api server automatically creates the system:kubelet-api-admin role which grants full
  // access to kubelet resources, but does not bind it to any subject. The api server needs access
  // to these resources when calling kubelet on behalf of a user, so we need to explicitly bind
  // this role to the api-server user.
  k8s.resource("rbac.authorization.k8s.io/v1", "ClusterRoleBinding", "system:api-server", namespace="") + {
    roleRef: {
      apiGroup: "rbac.authorization.k8s.io",
      kind: "ClusterRole",
      name: "system:kubelet-api-admin",
    },
    subjects: [{
      apiGroup: "rbac.authorization.k8s.io",
      kind: "User",
      name: "api-server",
    }],
  }
]
