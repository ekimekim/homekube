local k8s = import "k8s.libsonnet";
{
  local corefile = |||
    . {
      # log all queries
      log
      # log errors
      errors
      # Note http plugins cannot share a port despite using different paths
      # expose prometheus metrics on :8080/metrics
      prometheus :8080
      # enables a health check endpoint on :8081/health
      health :8081
      # enables a readiness check endpoint on :8082/ready
      ready :8082
      # automatically detect corefile changes and reload the config
      reload 10s
      # on startup, attempt to detect resolve loops and die if found
      loop
      # resolve "localhost" and similar names to 127.0.0.1
      local
      # maintain a 30sec record cache (if record TTL is not shorter)
      cache 30
      # For A records for *.xenon.ekime.kim (but only direct subdomains, not nested,
      # to avoid .svc.xenon.ekime.kim), respond with a CNAME
      # to the internal ingress-nginx controller.
      template IN ANY xenon.ekime.kim {
        match "^[^.]*\.xenon\.ekime\.kim\.$"
        answer "{{ .Name }} 3600 IN CNAME nginx-internal-controller.ingress-nginx.svc.xenon.ekime.kim"
        fallthrough
      }
      # look up kubernetes-related dns names in kubernetes
      # defaults to using in-cluster endpoint with pod service account
      kubernetes xenon.ekime.kim
      # for all other requests, use upstream DNS servers
      forward . 8.8.8.8 1.1.1.1
    }
  |||,

  configmap: k8s.configmap("coredns", data={
    Corefile: corefile,
  }),

  // There is a "system:kube-dns" default cluster role, but it doesn't provide everything
  // that coredns needs
  perms: k8s.sa_with_role("coredns", namespace = "kube-system", cluster_role = true, rules = {
    read: {
      "": ["endpoints", "services", "namespaces"],
      "discovery.k8s.io": ["endpointslices"],
    },
  }),

  deployment: k8s.deployment("coredns", pod={
    serviceAccount: "coredns",
    volumes: [{
      name: "config",
      configMap: { name: "coredns" },
    }],
    containers: [{
      name: "coredns",
      image: "coredns/coredns:1.11.1",
      args: ["-conf", "/etc/coredns/Corefile"],
      ports: [{
        name: "prom",
        containerPort: 8080,
      }],
      readinessProbe: {
        httpGet: {
          port: 8082,
          path: "/ready",
        },
      },
      volumeMounts: [{
        name: "config",
        mountPath: "/etc/coredns",
      }],
    }],
  }),

  service: k8s.service("coredns", ports={
    dns: { protocol: "UDP", port: 53 },
    dnstcp: 53,
  }) + {
    spec+: {
      // Hard-coded service IP for the dns service, which we put in kubelet's resolv.conf
      clusterIP: "192.168.43.254",
    },
  },
}
