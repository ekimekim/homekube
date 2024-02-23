local k8s = import "k8s.libsonnet";

{
  // This file defines a coredns server that listens *on my public IP*.
  // ie. it accepts incoming DNS queries from the public internet.
  // It is delegated as the authoritative nameserver for xenon.ekime.kim,
  // and can thus answer any public queries under that domain.
  // Most importantly, it will serve a "CNAME ekime.kim" by default for ANY subdomain,
  // recursively. ie. not only *.xenon.ekime.kim, but *.*.xenon.ekime.kim, etc.
  // Not only does this allow us to host services on this IP, but it enables
  // HTTP01-based ACME for fully internal domains like myservice.myns.svc.xenon.ekime.kim.
  local corefile = ||| 
    xenon.ekime.kim. {
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

      # We want to avoid having ACME challenge queries match the template plugin below.
      # However templates run very early in the list of plugins, so other plugins we want to use
      # to match the ACME challenges won't be reached. And avoiding the acme challenge domains
      # by regex in the template match is very difficult due to golang's lack of negative lookahead.
      # Our hack here is to first rewrite (which runs before template) the acme queries
      # so that they are not under xenon.ekime.kim. Then we can match them later.
      # The query:
      #   _acme-challenge.NAME.xenon.ekime.kim
      # will be rewritten:
      #   NAME.xenon.ekime.kim.acme.invalid
      rewrite stop {
        name regex _acme-challenge\.(.*)\. {1}.acme.invalid.
      }

      # For all non-ACME queries, respond with a CNAME to ekime.kim.
      # We set a reasonably long TTL since this should never change.
      template IN ANY xenon.ekime.kim {
        answer "{{ .Name }} 86400 IN CNAME ekime.kim"
      }
    }
  |||,

  configmap: k8s.configmap("coredns", data={
    Corefile: corefile,
  }),

  deployment: k8s.deployment("coredns", pod={
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
  })

}
