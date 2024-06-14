local k8s = import "k8s.libsonnet";

{
  // sniproxy (https://github.com/atenart/sniproxy) is a simple TCP proxy that
  // routes to a backend based on the SNI given by a TLS connection.
  // It does *not* terminate TLS itself, and cannot read any of the encrypted data.
  // We are using it here so we can share HTTPS and non-HTTPS traffic on port 443.
  // In particular we want to expose a proxy that looks like HTTPS so middleware doesn't
  // fuck with it.
  // It can also use the PROXY protocol, which nginx understands, so we get the connecting
  // client's IP at the nginx level.

  // Some notes on the poorly-documented "domains" matching behaviour, gathered from
  // reading the implementation:
  // - Routes are checked in order, and the first match is taken
  // - Domains are regexes, except "." is converted to "\." and "*" is converted to ".*"
  // - This is done naively, so "\." will become "\\.", ie. a literal backslash then any char.
  local config = {
    routes: [
      {
        domains: ["ssh.ekime.kim"],
        backend: {
          address: "ssh-proxy:443",
        },
      },
      {
        domains: ["*"],
        backend: {
          address: "nginx-external-controller.ingress-nginx:443",
        },
      },
    ],
  },

  configmap: k8s.configmap("sniproxy", data={
    "sniproxy.yaml": std.manifestJson(config),
  }),

  // Needs run_one and explicit node name due to host port usage.
  deployment: k8s.deployment("sniproxy", pod={
    nodeName: "charm",
    volumes: [{
      name: "config",
      configMap: { "name": "sniproxy" },
    }],
    containers: [{
      name: "sniproxy",
      image: "atenart/sniproxy@sha256:0cc67952b1da92674ec252401dbbe949d760b59dd5cfa631d0cf936c00fa7579",
      args: [
        "--config",
        "/etc/sniproxy/sniproxy.yaml",
      ],
      volumeMounts: [{
        name: "config",
        mountPath: "/etc/sniproxy",
      }],
      ports: [{
        name: "tls",
        containerPort: 443,
        hostPort: 443
      }],
    }],
  }) + k8s.mixins.run_one,
}
