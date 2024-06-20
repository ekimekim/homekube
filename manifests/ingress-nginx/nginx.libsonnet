local k8s = import "k8s.libsonnet";
local util = import "util.libsonnet";
function(ingress_name, httpHostPort=false) {
  // Creates an account NAME and binds it to a role NAME *and* a cluster role NAME.
  local auth(name, rules, cluster_rules) = {
    service_account: k8s.service_account(name),
    role: k8s.role(name, rules=rules),
    role_binding: k8s.role_binding(name,
      role = {role: name},
      subjects = [{name: name, namespace: "ingress-nginx"}],
    ),
    cluster_role: k8s.role(name, namespace="", rules=cluster_rules),
    cluster_role_binding: k8s.role_binding(name,
      role = {cluster_role: name},
      subjects = [{name: name, namespace: "ingress-nginx"}],
      namespace = "",
    ),
  },

  local controller_name = "%s-controller" % ingress_name,
  local admission_name = "%s-admission" % ingress_name,

  controller_auth: auth(
    controller_name,
    {
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
          resourceNames: [controller_name],
        },
      ],
    },
    {
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
    },
  ),

  admission_auth: auth(
    admission_name,
    {
      "get,create": {
        "": ["secrets"],
      },
    },
    {
      "get,update": {
        "admissionregistration.k8s.io": ["validatingwebhookconfigurations"],
      },
    },
  ),

  config: k8s.configmap(controller_name, data={
    // Global ingress options. (barely) documented here: https://github.com/kubernetes/ingress-nginx/blob/main/internal/ingress/controller/config/config.go
  }),

  controller: k8s.deployment(controller_name, pod={
    serviceAccount: controller_name,
    volumes: [{
      name: "webhook-cert",
      secret: {secretName: admission_name},
    }],
    containers: [{
      name: "ingress-nginx-controller",
      image: "registry.k8s.io/ingress-nginx/controller:v1.9.6@sha256:1405cc613bd95b2c6edd8b2a152510ae91c7e62aea4698500d23b2145960ab9c",
      args: ["/nginx-ingress-controller"] + util.opts_to_args({
        election_id: controller_name,
        controller_class: "k8s.io/ingress-nginx",
        ingress_class: ingress_name,
        configmap: "ingress-nginx/%s" % controller_name,
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
      ports: [
        {
          name: "prom",
          containerPort: 10254,
        },
        {
          name: "http",
          containerPort: 80,
          [if httpHostPort then "hostPort"]: 80,
        },
      ],
    }],
  }),

  service: k8s.service(controller_name, ports={
    http: 80,
    https: 443,
  }),

  webhook_service: k8s.service(
    admission_name,
    labels = { app: controller_name },
    ports = {
      "https-webhook": {
        port: 443,
        targetPort: 8443,
      },
    },
  ),

  local admission_certgen_job(name, opts) = k8s.job("%s-certgen-%s" % [admission_name, name], pod={
    serviceAccount: admission_name,
    containers: [{
      name: "ingress-nginx-admission-certgen",
      image: "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20231226-1a7112e06@sha256:25d6a5f11211cc5c3f9f2bf552b585374af287b4debf693cacbe2da47daa5084",
      args: [name] + util.opts_to_args({
        namespace: "ingress-nginx",
        secret_name: admission_name,
      } + opts),
    }],
  }),

  create_job: admission_certgen_job("create", {
    host: "%(service)s,%(service)s.ingress-nginx.svc" % { service: admission_name },
  }),

  patch_job: admission_certgen_job("patch", {
    webhook_name: admission_name,
    patch_mutating: "false",
    patch_failure_policy: "Fail",
  }),

  ingress_class: k8s.resource("networking.k8s.io/v1", "IngressClass", ingress_name, namespace="") + {
    spec: {controller: "k8s.io/ingress-nginx"},
  },

  webhook_config:
    k8s.resource(
      "admissionregistration.k8s.io/v1", "ValidatingWebhookConfiguration",
      admission_name, namespace="",
    ) + {
      webhooks: [{
        name: "validate.nginx.ingress.kubernetes.io",
        clientConfig: {
          service: {
            name: admission_name,
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
