local k8s = import "k8s.libsonnet";
{
  // TODO auth to prevent malicious writes that I then pull later
  local config = {
    version: "0.1",
    log: {
      formatter: "json",
      accesslog: { enabled: true },
    },
    storage: {
      filesystem: {
        rootdirectory: "/mnt"
      },
      delete: { enabled: true },
    },
    http: {
      addr: "0.0.0.0:80",
      relativeurls: true,
      draintimeout: "10s", # how long to wait after SIGTERM for clients to finish
      prometheus: { enabled: true },
    },
  },

  configmap: k8s.configmap("registry", {
    "config.yml": std.manifestJson(config),
  }),

  deployment: k8s.deployment("registry",
    pod={
      volumes: [
        {
          name: "config",
          configMap: { name: "registry" },
        },
      ],
      containers: [{
        name: "registry",
        image: "registry:2",
        volumeMounts: [
          {
            name: "data",
            mountPath: "/mnt",
          },
          {
            name: "config",
            subPath: "config.yml",
            mountPath: "/etc/docker/registry/config.yml",
          },
        ],
      }],
    } + k8s.mixins.host_path("data", "charm", "/srv/registry"),
  ) + k8s.mixins.run_one,

  service: k8s.service("registry", ports={ http: 80 }),
}
