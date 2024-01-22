local k8s = import "k8s.libsonnet";
local util = import "util.libsonnet";
{
  daemonset: k8s.daemonset("kube-proxy", pod={
    // As kube-proxy manipulates iptables on the host, it needs to be in the host's
    // network namespace.
    hostNetwork: true,
    containers: [{
      name: "kube-proxy",
      image: "registry.k8s.io/kube-proxy:v1.28.4",
      command: ["kube-proxy"],
      args: util.opts_to_args({
        cluster_cidr: "192.168.64.0/19",
        v: 2,
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
