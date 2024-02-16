local k8s = import "k8s.libsonnet";
[
  k8s.namespace(name) for name in import "namespaces.json"
]
