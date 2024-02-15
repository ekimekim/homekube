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
  local filters = {
    pod: 'pod!="", pod=~"$pod_regex", node=~"$node", namespace=~"$namespace", pod=~"$pod"',
    container: '%s, container!="", container=~"$container"' % self.pod,
  },
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
          ||| % filters.container,
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
          ||| % filters.container,
        },
      },
    ],
    // Secondary usage metrics: network IO, open FDs, disk IO, disk space
    [
      grafana.mixins.plus_minus("\\[Rx\\] .*") + {
        name: "Network throughput by pod",
        axis+: {
          units: grafana.units.byte_rate,
          labels: "Rx | Tx",
          stack: true,
        },
        series: {
          "[Tx] {{namespace}} - {{pod}} ({{node}})": |||
            sum by (node, namespace, pod, id) (
              rate(container_network_transmit_bytes_total{%s}[1m])
            )
          ||| % filters.pod,
          "[Rx] {{namespace}} - {{pod}} ({{node}})": |||
            sum by (node, namespace, pod, id) (
              rate(container_network_receive_bytes_total{%s}[1m])
            )
          ||| % filters.pod,
        },
      },
      {
        name: "Open FDs by container",
        axis: { label: "FDs" },
        series: {
          "{{namespace}} - {{pod}} - {{container}} ({{node}})": |||
            max by (node, namespace, pod, container, id) (
              container_file_descriptors{%s}
            )
          ||| % filters.container,
        },
      },
      grafana.mixins.plus_minus("\\[Read\\] .*") + {
        name: "Disk throughput by pod",
        axis+: {
          units: grafana.units.byte_rate,
          labels: "Read | Write",
          stack: true,
        },
        series: {
          "[Read] {{namespace}} - {{pod}} - {{container}} ({{node}})": |||
            sum by (node, namespace, pod, container, id) (
              rate(container_fs_reads_bytes_total{%s}[1m])
            )
          ||| % filters.container,
          "[Write] {{namespace}} - {{pod}} - {{container}} ({{node}})": |||
            sum by (node, namespace, pod, container, id) (
              rate(container_fs_writes_bytes_total{%s}[1m])
            )
          ||| % filters.container,
        },
      },
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
