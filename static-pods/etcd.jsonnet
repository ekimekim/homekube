{
  local basename(path) =
    local parts = std.split(path, "/");
    parts[std.length(parts)-1],
  metadata: {
    namespace: "kube-system",
    name: "etcd",
    labels: {
      app: "etcd",
      static: "master",
    },
  },
  spec: {
    // This needs to work before kube-proxy, etc, so we can't use a Service, and pod ips make things
    // difficult. Easiest way is to just directly bind to the host's interface.
    hostNetwork: true,
    // Grab various files from the local setup
    volumes: [
      {
        name: "files",
        hostPath: {path: std.extVar("basedir")},
      },
      {
        name: "data",
        hostPath: "/srv/etcd",
      },
    ],
    containers: [{
      name: "etcd",
      image: "quay.io/coreos/etcd:v3.5.4",
      command: ["etcd", "--config-file", "/etcd.conf.yml"],
      env: [
        // Disable application-level auth. This is safe because we authenticate using client certs
        // and only api-server has access.
        {key: "ALLOW_NONE_AUTHENTICATION", value: "yes"},
      ],
      volumeMounts: [
        {
          name: "data",
          mountPath: "/mnt",
        },
      ] + [
        {
          name: "files",
          subPath: file,
          readOnly: true,
          mountPath: "/%s" % basename(file),
        } for file in [
          "ca/api-server.pem",
          "ca/api-server-key.pem",
          "ca/root.pem",
          "etcd.conf.yml",
        ]
      ]
    }],
  },
}