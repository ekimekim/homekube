local grafana = import "grafana.libsonnet";
grafana.dashboard({
  name: "Containers",
  variables: [
    {
      name: "pod_regex",
      label: "pod regex",
      textbox: true,
      value: ".*",
    },
    {
      name: "node",
      multi: true,
      query: {
        node: 'container_cpu_usage_seconds_total{container!="", pod=~"$pod_regex"}',
      },
    },
    {
      name: "namespace",
      multi: true,
      query: {
        namespace: 'container_cpu_usage_seconds_total{container!="", pod=~"$pod_regex", node=~"$node"}',
      },
    },
    {
      name: "pod",
      multi: true,
      query: {
        pod: 'container_cpu_usage_seconds_total{container!="", pod=~"$pod_regex", node=~"$node", namespace=~"$namespace"}',
      },
    },
    {
      name: "container",
      multi: true,
      query: {
        container: 'container_cpu_usage_seconds_total{container!="", pod=~"$pod_regex", node=~"$node", namespace=~"$namespace", pod=~"$pod"}',
      },
    },
  ],
  local filters = 'container!="", pod=~"$pod_regex", node=~"$node", namespace=~"$namespace", pod=~"$pod", container=~"$container"',
  rows: [
    // Top-line usage metrics: CPU and memory
    [
      {
        name: "CPU usage by container",
        axis: {
          label: "cpus",
          units: grafana.units.percent,
        },
        series: {
          "{{namespace}} - {{pod}} - {{container}} ({{node}})": |||
            sum by (node, namespace, pod, container, id) (
              rate(container_cpu_usage_seconds_total{%s}[1m])
            )
          ||| % filters,
        },
      },
      {
        name: "RSS by container",
        axis: { units: grafana.units.bytes },
        series: {
          "{{namespace}} - {{pod}} - {{container}} ({{node}})": |||
            max by (node, namespace, pod, container, id) (
              container_memory_rss{%s}
            )
          ||| % filters,
        },
      },
    ],
    // Secondary usage metrics: network IO, open FDs, disk IO, disk space
    [
    ],
    // Breakdowns of previous usage into detailed types + limits
    [
      // CPU into system, user, request, limit
      // Memory into various subtypes, request, limit
      // FDs into sockets and not, limit
    ],
    // Tertiary usage info: page faults, inodes, process/thread counts, dropped packets
    [
    ],
  ],
})
