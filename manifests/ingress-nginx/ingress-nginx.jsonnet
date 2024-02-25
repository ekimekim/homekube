local k8s = import "k8s.libsonnet";
local util = import "util.libsonnet";
{
  // Creates an account NAME and binds it to a role NAME *and* a cluster role NAME.
  // We define those roles seperately.
  local bound_account(name) = {
    service_account: k8s.service_account(name),
    role_binding: k8s.role_binding(name,
      role = {role: name},
      subjects = [{name: name, namespace: "ingress-nginx"}],
    ),
    cluster_role_binding: k8s.role_binding(name,
      role = {cluster_role: name},
      subjects = [{name: name, namespace: "ingress-nginx"}],
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

  config: k8s.configmap("ingress-nginx-controller", data={
    // Global ingress options. (barely) documented here: https://github.com/kubernetes/ingress-nginx/blob/main/internal/ingress/controller/config/config.go
  }),

  deployment: k8s.deployment("ingress-nginx-controller", pod={
    serviceAccount: "nginx-ingress",
    volumes: [{
      name: "webhook-cert",
      secret: {secretName: "ingress-nginx-admission"},
    }],
    containers: [{
      name: "ingress-nginx-controller",
      image: "registry.k8s.io/ingress-nginx/controller:v1.9.6@sha256:1405cc613bd95b2c6edd8b2a152510ae91c7e62aea4698500d23b2145960ab9c",
      args: ["/nginx-ingress-controller"] + util.opts_to_args({
        election_id: "ingress-nginx-leader",
        controller_class: "k8s.io/ingress-nginx",
        ingress_class: "nginx",
        configmap: "$(POD_NAMESPACE)/ingress-nginx-controller",
        validating_webhook: ":8443",
        validating_webhook_certificate: "/usr/local/certificates/cert",
        validating_webhook_key: "/usr/local/certificates/key",
      }),
      env: [
        {
          name: "POD_NAME",
          valueFrom: {fieldRef: {fieldPath: "metadata.name"}},
        },
        {name: "POD_NAMESPACE", value: "ingress-nginx"},
        {name: "LD_PRELOAD", value: "/usr/local/lib/libmimalloc.so"},
      ],
      volumeMounts: [{
        name: "webhook-cert",
        mountPath: "/usr/local/certificates/",
        readOnly: true,
      }],
      lifecycle: {
        preStop: {
          exec: {
            command: ["/wait-shutdown"],
          },
        },
      },
      readinessProbe: {
        httpGet: {
          path: "/healthz",
          port: 10254,
        },
      },
    }],
  }),

  service: k8s.service("ingress-nginx-controller", ports={
    http: 80,
    https: 443,
  }),

  webhook_service: k8s.service(
    "ingress-nginx-controller-admission",
    labels = { app: "ingress-nginx-controller" },
    ports = { "https-webhook": 443 },
  ),

  local admission_certgen_job(name, opts) = k8s.job("ingress-nginx-admission-certgen-%s" % name, pod={
    serviceAccount: "nginx-ingress-admission",
    containers: [{
      name: "ingress-nginx-admission-certgen",
      image: "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20231226-1a7112e06@sha256:25d6a5f11211cc5c3f9f2bf552b585374af287b4debf693cacbe2da47daa5084",
      args: [name] + util.opts_to_args({
        namespace: "ingress-nginx",
        secret_name: "ingress-nginx-admission",
      } + opts),
    }],
  }),

  create_job: admission_certgen_job("create", {
    host: "ingress-nginx-controller-admission,ingress-nginx-controller-admission.ingress-nginx.svc"
  }),

  patch_job: admission_certgen_job("patch", {
    webhook_name: "ingress-nginx-admission",
    patch_mutating: "false",
    patch_failure_policy: "Fail",
  }),

  ingress_class: k8s.resource("networking.k8s.io/v1", "IngressClass") + k8s.metadata("nginx", "") + {
    spec: {controller: "k8s.io/ingress-nginx"},
  },

  webhook_config:
    k8s.resource("admissionregistration.k8s.io/v1", "ValidatingWebhookConfiguration")
    + k8s.metadata("ingress-nginx-admission", "")
    + {
      webhooks: [{
        name: "validate.nginx.ingress.kubernetes.io",
        clientConfig: {
          service: {
            name: "ingress-nginx-controller-admission",
            namespace: "ingress-nginx",
            path: "/networking/v1/ingresses",
          },
        },
        admissionReviewVersions: ["v1"],
        failurePolicy: "Fail",
        matchPolicy: "Equivalent",
        sideEffects: "None",
        rules: [{
          apiGroups: ["networking.k8s.io"],
          apiVersions: ["v1"],
          operations: ["CREATE", "UPDATE"],
          resources: ["ingresses"],
        }],
      }],
    },
}
