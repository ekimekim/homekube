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
    // kube-state-metrics don't label with node
    kube_state_pod: 'namespace=~"$namespace", pod!="", pod=~"$pod_regex", pod=~"$pod"',
    kube_state_container: '%s, container!="", container=~"$container"' % self.kube_state_pod,
    pod: '%s, node=~"$node"' % self.kube_state_pod,
    container: '%s, node=~"$node"' % self.kube_state_container,
    // this "and ..." filter expression will restrict to pods with the correct node,
    // though without the node label in the result.
    // It should be used along with the kube_state_* filters.
    and_with_node: 'and on (uid) kube_pod_info{%s}' % self.pod
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
    // Secondary usage metrics: network IO, open FDs, disk IO
    [
      grafana.mixins.plus_minus("\\[Rx\\] .*") + {
        name: "Network throughput by pod",
        axis+: {
          units: grafana.units.byte_rate,
          label: "Rx | Tx",
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
        axis: { label: "files" },
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
          label: "Read | Write",
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
    // Breakdowns of previous usage into detailed types + limits,
    // plus disk usage since it didn't fit on prev line
    [
      {
        name: "CPU usage breakdown",
        axis: {
          units: grafana.units.percent,
          stack: true,
        },
        series: {
          user: "sum(rate(container_cpu_user_seconds_total{%s}[1m]))" % filters.container,
          system: "sum(rate(container_cpu_system_seconds_total{%s}[1m]))" % filters.container,
          request: |||
            min(
              kube_pod_container_resource_requests{%(kube_state_container)s, resource="cpu"}
              %(and_with_node)s
            )
          ||| % filters,
          limit: |||
            min(
              kube_pod_container_resource_limits{%(kube_state_container)s, resource="cpu"}
              %(and_with_node)s
            )
          ||| % filters,
        },
        overrides: {
          "request|limit": {
            "custom.stacking": {mode: "none", group: "A"},
            "custom.lineStyle": {fill: "dash", dash: [10, 10]},
            "custom.fillOpacity": 0,
          }
        },
      },
      // CPU into system, user, request, limit
      // Memory into various subtypes, request, limit
      // Disk space
    ],
    // Tertiary usage info: page faults, inodes, process/thread counts, dropped packets
    [
    ],
  ],
})
