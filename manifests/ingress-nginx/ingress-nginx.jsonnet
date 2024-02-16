local k8s = import "k8s.libsonnet";
{
  local bound_account(name) = {
    service_account: k8s.service_account(name),
    role_binding: k8s.role_binding(name,
      role = {role: name},
      subject = [{name: name, namespace: "nginx-ingress"}],
    ),
    cluster_role_binding: k8s.role_binding(name,
      role = {cluster_role: name},
      subject = [{name: name, namespace: "nginx-ingress"}],
      namespace = "",
    ),
  },

  main_account: bound_account("nginx-ingress"),
  admission_account: bound_account("nginx-ingress-admission"),

  main_role: k8s.role("nginx-ingress", rules={
    get: {
      "": ["namespaces"],
    },
    read: {
      "": ["configmaps", "pods", "secrets", "endpoints", "services"],
      "networking.k8s.io": ["ingresses", "ingressclasses"],
      "discovery.k8s.io": ["endpointslices"],
    },
    update: {
      "networking.k8s.io": ["ingresses/status"],
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
      {
        verbs: ["create", "patch"],
        apiGroups: [""],
        resources: ["events"],
      },
    ],
  }),

  main_cluster_role: k8s.role("nginx-ingress", namespace="", rules={
    read: {
      "": ["configmaps", "endpoints", "nodes", "pods", "secrets", "namespaces", "services"],
      "coordination.k8s.io": ["leases"],
      "networking.k8s.io": ["ingresses", "ingressclasses"],
      "discovery.k8s.io": ["endpointslices"],
    },
    get: {
      "": ["nodes"],
    },
    update: {
      "networking.k8s.io": ["ingresses/status"],
    },
    custom: [
      {
        verbs: ["create", "patch"],
        apiGroups: [""],
        resources: ["events"],
      },
    ],
  }),

  admission_role: k8s.role("nginx-ingress-admission", rules={
    custom: [{
      verbs: ["get", "create"],
      apiGroups: [""],
      resources: ["secrets"],
    }],
  }),

  admission_cluster_role: k8s.role("nginx-ingress-admission", namespace="", rules={
    custom: [{
      verbs: ["get", "update"],
      apiGroups: ["admissionregistration.k8s.io"],
      resources: ["validatingwebhookconfigurations"],
    }],
  }),
}
