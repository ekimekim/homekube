local k8s = import "k8s.libsonnet";
{
  local bound_account(name) = {
    service_account: k8s.service_account(name),
    role_binding: k8s.role_binding(name,
      role = {role: name},
      subjects = [{name: name, namespace: "nginx-ingress"}],
    ),
    cluster_role_binding: k8s.role_binding(name,
      role = {cluster_role: name},
      subjects = [{name: name, namespace: "nginx-ingress"}],
      namespace = "",
    ),
  },

  main_account: bound_account("nginx-ingress"),
  admission_account: bound_account("nginx-ingress-admission"),

  main_role: k8s.role("nginx-ingress", rules={
    get: {
      "": ["configmaps", "pods", "secrets", "endpoints"],
    },
    create: {
      "coordination.k8s.io": ["leases"],
    },
    custom: [
      {
        verbs: ["get", "update"],
        apiGroups: ["coordination.k8s.io"],
        resources: ["leases"],
        resourceNames: ["ingress-nginx-leader"],
      },
    ],
  }),

  main_cluster_role: k8s.role("nginx-ingress", namespace="", rules={
    enumerate: {
      "": ["configmaps", "endpoints", "pods", "secrets", "namespaces"],
      "coordination.k8s.io": ["leases"],
    },
    read: {
      "": ["nodes", "services"],
      "networking.k8s.io": ["ingresses", "ingressclasses"],
      "discovery.k8s.io": ["endpointslices"],
    },
    update: {
      "networking.k8s.io": ["ingresses/status"],
    },
    "create,patch": {
      "": ["events"],
    }
  }),

  admission_role: k8s.role("nginx-ingress-admission", rules={
    "get,create": {
      "": ["secrets"],
    },
  }),

  admission_cluster_role: k8s.role("nginx-ingress-admission", namespace="", rules={
    "get,update": {
      "admissionregistration.k8s.io": ["validatingwebhookconfigurations"],
    },
  }),
}
