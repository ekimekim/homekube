local k8s = import "k8s.libsonnet";
local grafana = import "grafana.libsonnet";
{
  configmap: k8s.configmap("grafana", data = {
    "grafana.ini": std.manifestIni({
      sections: {
        server: {
          http_port: 80,
        },
        // Log to stderr as JSON
        log: {
          mode: "console",
        },
        "log.console": {
          format: "json",
        },
        // Turn off phone home / marketing malware
        analytics: {
          enabled: false,
          reporting_enabled: false,
          check_for_updates: false,
        },
        news: { news_feed_enabled: false },
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
    "dashboards.yaml": std.manifestJson({
      apiVersion: 1,
      providers: [{
        name: "dashboards",
        updateIntervalSeconds: 10,
        options: {
          path: "/etc/grafana/dashboards",
        },
      }],
    }),
    "home.yaml": std.manifestJson(grafana.dashboard({
      name: "Home",
      // home dashboard needs to not have a uid, or grafana gets errors trying to read annotations
      uid: null,
      refresh: null,
      timepicker: {hidden: true},
      rows: [
        // A single row, the full screen height
        {
          height: 24,
          panels: [
            // A single panel, the full screen width
            {
              name: "Dashboards",
              custom: {
                type: "dashlist",
                options: {
                  // There's no way to show all dashboards, so we emulate it with a search
                  // for "anything" with a large max items.
                  showStarred: false,
                  showSearch: true,
                  query: "",
                  maxItems: 1000,
                },
              },
            },
          ],
        },
      ],
    })),
  }),

  dashboards: k8s.configmap("grafana-dashboards", data = {
    ["%s.json" % item.key]: std.manifestJson(item.value)
    for item in std.objectKeysValues(import "dashboards.libsonnet")
  }),

  service: k8s.service("grafana", ports = { http: 80 }),

  ingress: k8s.ingress("grafana", tls=true, rules={
    "grafana.xenon.ekime.kim": {},
  }),

  deployment: k8s.deployment("grafana",
    pod = {
      volumes: [
        {
          name: "config",
          configMap: { name: "grafana" },
        },
        {
          name: "dashboards",
          configMap: { name: "grafana-dashboards" },
        },
      ],
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
          {
            name: "config",
            subPath: "dashboards.yaml",
            mountPath: "/etc/grafana/provisioning/dashboards/dashboards.yaml",
          },
          {
            name: "config",
            subPath: "home.yaml",
            mountPath: "/usr/share/grafana/public/dashboards/home.json",
          },
          {
            name: "dashboards",
            mountPath: "/etc/grafana/dashboards",
          },
        ],
        securityContext: {
          // Avoid fs permission issues by running as root
          runAsUser: 0,
        },
        ports: [{
          name: "prom",
          containerPort: 80,
        }],
      }],
    } + k8s.mixins.host_path("data", "charm", "/srv/grafana"),
  ) + k8s.mixins.run_one,
}
