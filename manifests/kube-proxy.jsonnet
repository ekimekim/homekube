local k8s = import "k8s.libsonnet";
local util = import "util.libsonnet";
{

  service_account: k8s.service_account("kube-proxy", "kube-system"),
  binding: k8s.resource("rbac.authorization.k8s.io/v1", "ClusterRoleBinding")
    + k8s.metadata("kube-proxy", "kube-system")
    + {
      roleRef: {
        apiGroup: "rbac.authorization.k8s.io",
        kind: "ClusterRole",
        name: "system:node-proxier",
      },
      subjects: [{
        kind: "ServiceAccount",
        name: "kube-proxy",
        namespace: "kube-system",
      }],
    },

  daemonset: k8s.daemonset("kube-proxy", namespace="kube-system", pod={
    // As kube-proxy manipulates iptables on the host, it needs to be in the host's
    // network namespace.
    hostNetwork: true,
    serviceAccount: "kube-proxy",
    containers: [{
      name: "kube-proxy",
      image: "registry.k8s.io/kube-proxy:v1.28.4",
      command: ["kube-proxy"],
      args: util.opts_to_args({
        cluster_cidr: "192.168.64.0/19",
        v: 2,
        master: "192.168.42.2:6443",
        // Disable system conntrack modifications
        conntrack_max_per_core: 0,
        conntrack_tcp_timeout_close_wait: 0,
        conntrack_tcp_timeout_established: 0,
      }),
      // In order to manipulate iptables, kube-proxy requires CAP_NET_ADMIN.
      securityContext: {
        capabilities: {
          add: ["NET_ADMIN"],
        },
      },
    }]
  }),

}
