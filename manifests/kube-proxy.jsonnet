local k8s = import "k8s.libsonnet";
local util = import "util.libsonnet";
{
  // Without an explicit kubeconfig telling it to use the in-cluster cert/token,
  // it can't talk to the api server properly.
  local kubeconfig = {
    apiVersion: "v1",
    kind: "Config",
    preferences: {},
    clusters: [{
      name: "local",
      cluster: {
        server: "https://192.168.42.2:6443",
        "certificate-authority": "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
      },
    }],
    users: [{
      name: "kube-proxy",
      user: {
        tokenFile: "/var/run/secrets/kubernetes.io/serviceaccount/token",
      },
    }],
    contexts: [{
      name: "local",
      context: {
        cluster: "local",
        user: "kube-proxy",
      },
    }],
    "current-context": "local",
  },

  configmap: k8s.configmap("kube-proxy", namespace="kube-system", data={
    "kube-proxy.kubeconfig": std.manifestJson(kubeconfig),
  }),

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
    volumes: [{
      name: "kubeconfig",
      configMap: { name: "kube-proxy" },
    }],
    containers: [{
      name: "kube-proxy",
      image: "registry.k8s.io/kube-proxy:v1.28.4",
      command: ["kube-proxy"],
      args: util.opts_to_args({
        cluster_cidr: "192.168.64.0/19",
        v: 2,
        kubeconfig: "/etc/kube-proxy.kubeconfig",
        // Disable system conntrack modifications
        conntrack_max_per_core: 0,
        conntrack_tcp_timeout_close_wait: 0,
        conntrack_tcp_timeout_established: 0,
        // Disable connecting to nodeports on localhost interface, this is a legacy behaviour
        // anyway and by disabling it we avoid needing to give elevated permissions to kube-proxy
        // to set localnet routing up.
        iptables_localhost_nodeports: false,
      }),
      volumeMounts: [{
        name: "kubeconfig",
        subPath: "kube-proxy.kubeconfig",
        mountPath: "/etc/kube-proxy.kubeconfig",
      }],
      // In order to manipulate iptables, kube-proxy requires CAP_NET_ADMIN.
      securityContext: {
        capabilities: {
          add: ["NET_ADMIN"],
        },
      },
    }]
  }),

}
