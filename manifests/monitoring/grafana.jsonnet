local k8s = import "k8s.libsonnet";
{
  configmap: k8s.configmap("grafana", data = {
    "grafana.ini": std.manifestIni({
      sections: {
        analytics: {
          enabled: false,
          reporting_enabled: false,
          check_for_updates: false,
        },
      },
    }),
    "datasources.yaml": std.manifestJson({
      apiVersion: 1,
      datasources: [{
        name: "prometheus",
        type: "prometheus",
        access: "proxy", // for ease-of-use for now, since I don't have cluster DNS externally resolvable
        uid: "prometheus",
        url: "http://prometheus",
        isDefault: true,
      }],
    }),
  }),

  service: k8s.service("grafana", ports = {
    http: { port: 80, targetPort: 3000 }, // TODO change grafana's listen port
  }),

  deployment: k8s.deployment("grafana",
    pod = {
      volumes: [{
        name: "config",
        configMap: { name: "grafana" },
      }],
      containers: [{
        name: "grafana",
        image: "grafana/grafana:10.3.1",
        volumeMounts: [
          {
            name: "data",
            mountPath: "/var/lib/grafana",
          },
          {
            name: "config",
            subPath: "grafana.ini",
            mountPath: "/etc/grafana/grafana.ini",
          },
          {
            name: "config",
            subPath: "datasources.yaml",
            mountPath: "/etc/grafana/provisioning/datasources/datasources.yaml",
          },
        ],
        securityContext: {
          // Avoid fs permission issues by running as root
          runAsUser: 0,
        },
      }],
    } + k8s.mixins.host_path("data", "charm", "/srv/grafana"),
  ) + k8s.mixins.run_one,
}
