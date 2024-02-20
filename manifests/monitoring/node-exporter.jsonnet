local k8s = import "k8s.libsonnet";
{
  daemonset: k8s.daemonset("node-exporter", pod={
    // Host namespaces required for monitoring
    hostNetwork: true,
    hostPID: true,
    // Host root fs mount (inc. submounts) required for monitoring
    volumes: [{
      name: "root",
      hostPath: { path: "/" },
    }],
    containers: [{
      name: "node-exporter",
      image: "quay.io/prometheus/node-exporter:v1.7.0",
      args: [
        "--path.rootfs=/host",
        // Don't monitor network filesystems, it's slow and causes problems if they're down
        "--collector.filesystem.fs-types-exclude=cifs",
        "--web.listen-address=:9999" // avoid conflict with depict dev env
      ],
      volumeMounts: [{
        name: "root",
        mountPath: "/host",
        readOnly: true,
        mountPropagation: "HostToContainer",
      }],
      ports: [{
        name: "prom",
        containerPort: 9999,
      }]
    }],
  })
}
