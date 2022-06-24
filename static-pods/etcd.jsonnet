{
  local etcd_config = {
    name: "charm",
    "data-dir": "/mnt/data",
    "wal-dir": "/mnt/wal",
    "listen-client-urls": "https://0.0.0.0:2379",
    "client-transport-security": {
      "cert-file": "/api-server.pem",
      "key-file": "/api-server-key.pem",
      "trusted-ca-file": "/root.pem",
      "client-cert-auth": true,
    }
  },
  metadata: {
    namespace: "kube-system",
    name: "etcd",
    labels: {
      static: "master",
    },
  },
  spec: {
    volumes: [{
        name: "host",
        hostPath: {path: std.extVar("basedir")},
    }],
    containers: [{
      name: "etcd",
      ...TODO UPTO
    }],
  },
}
