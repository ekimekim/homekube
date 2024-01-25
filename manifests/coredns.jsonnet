local k8s = import "k8s.libsonnet";
{
  local corefile = |||
    .:53 {
      # log all queries
      log
      # log errors
      errors
      # expose prometheus metrics on :80/metrics
      prometheus :80
      # enables a health check endpoint on :80/health
      health :80
      # enables a readiness check endpoint on :80/ready
      ready :80
      # automatically detect corefile changes and reload the config
      reload 10s
      # on startup, attempt to detect resolve loops and die if found
      loop
      # resolve "localhost" and similar names to 127.0.0.1
      local
      # maintain a 30sec record cache (if record TTL is not shorter)
      cache 30
      # look up kubernetes-related dns names in kubernetes
      # defaults to using in-cluster endpoint with pod service account
      kubernetes xenon.ekime.kim
      # for all other requests, use upstream DNS servers
      forward . 8.8.8.8 1.1.1.1
    }
  |||,

  configmap: k8s.configmap("coredns", namespace="kube-system", data={
    Corefile: corefile,
  }),

  // There is a "system:kube-dns" default cluster role, but it doesn't provide everything
  // that coredns needs
  perms: k8s.sa_with_role("coredns", namespace = "kube-system", cluster_role = true, rules = [
    {
      apiGroups: [""],
      resources: ["endpoints", "services", "namespaces"],
      verbs: ["list", "watch"],
    },
    {
      apiGroups: ["discovery.k8s.io"],
      resources: ["endpointslices"],
      verbs: ["list", "watch"],
    },
  ]),

  deployment: k8s.deployment("coredns", namespace="kube-system", pod={
    serviceAccount: "coredns",
    volumes: [{
      name: "config",
      configMap: { name: "coredns" },
    }],
    containers: [{
      name: "coredns",
      image: "coredns/coredns:1.11.1",
      args: ["-conf", "/etc/Corefile"],
      ports: [{
        name: "prom",
        containerPort: 80,
      }],
      readinessProbe: {
        httpGet: {
          port: 80,
          path: "/ready",
        },
      },
      volumeMounts: [{
        name: "config",
        subPath: "Corefile",
        mountPath: "/etc/Corefile",
      }],
    }],
  }),

  service: k8s.service("coredns", namespace="kube-system", ports={
    dns: { protocol: "UDP", port: 53 },
    dnstcp: 53,
  }) + {
    spec+: {
      // Hard-coded service IP for the dns service, which we put in kubelet's resolv.conf
      clusterIP: "192.168.43.254",
    },
  },
}
