local util = import "util.libsonnet";
{
  // Basic helper for specifying an api version, kind and metadata
  // Set namespace = null to omit entirely (which uses the default for your manifest).
  // Set namespace = "" to explicitly indicate "not namespaced".
  resource(apiVersion, kind, name, namespace = null, labels = {}): {
    apiVersion: apiVersion,
    kind: kind,
    metadata: {
      name: name,
      [if namespace != null then "namespace"]: namespace,
      labels: labels,
    },
  },

  namespace(name): $.resource("v1", "Namespace", name, namespace="", labels={name: name}),

  // Ports should be a map {name: port number | port spec object}
  service(
    name,
    namespace = null,
    labels = { app: name },
    ports = {},
  ): $.resource("v1", "Service", name, namespace, labels) + {
    spec: {
      selector: labels,
      ports: [
        local value = ports[name];
        { name: name } + (if std.type(value) == "object" then value else { port: value })
        for name in std.objectFields(ports)
      ],
    },
  },

  deployment(
    name,
    pod,
    namespace = null,
    labels = { app: name },
    replicas = 1,
  ): $.resource("apps/v1", "Deployment", name, namespace, labels) + {
    spec: {
      replicas: replicas,
      selector: { matchLabels: labels },
      template: {
        metadata: {
          labels: labels,
        },
        spec: pod,
      },
    },
  },

  daemonset(
    name,
    pod,
    namespace = null,
    labels = { app: name },
  ): $.resource("apps/v1", "DaemonSet", name, namespace, labels) + {
    spec: {
      selector: { matchLabels: labels },
      template: {
        metadata: {
          labels: labels,
        },
        spec: pod,
      },
    },
  },

  job(
    name,
    pod,
    namespace = null,
    labels = { app: name },
  ): $.resource("batch/v1", "Job", name, namespace, labels) + {
    spec: {
      template: {
        metadata: {
          labels: labels,
        },
        spec: {restartPolicy: "OnFailure"} + pod,
      },
    },
  },

  configmap(
    name,
    data,
    namespace = null,
    labels = { app: name },
  ): $.resource("v1", "ConfigMap", name, namespace, labels) + { data: data },

  service_account(name, namespace = null, labels = {}):
    $.resource("v1", "ServiceAccount", name, namespace, labels),

  // Role or ClusterRole (for the latter, set namespace = "").
  // Rules object maps from defined permission sets to resource objects.
  // Resource objects map from an apiGroup to a list of resources.
  // Permission sets:
  //   read: ["get", "list", "watch"]
  //   enumerate: ["list", "watch"],
  //   custom: Instead of a resource object, maps to a list of already-expanded rules.
  //   anything else: Comma-seperated list of verbs
  role(name, namespace = null, labels = {}, rules = {}):
    $.resource(
      "rbac.authorization.k8s.io/v1",
      if namespace == "" then "ClusterRole" else "Role",
      name, namespace, labels,
    ) + {
      rules: std.flatMap(
        function(verb)
          if verb.key == "custom" then verb.value
          else [
            {
              verbs:
                if verb.key == "read" then ["get", "list", "watch"]
                else if verb.key == "enumerate" then ["list", "watch"]
                else std.split(verb.key, ","),
              apiGroups: [group.key],
              resources: group.value,
            } for group in std.objectKeysValues(verb.value)
          ],
        std.objectKeysValues(rules),
      ),
    },

  // RoleBinding or ClusterRoleBinding (for the latter, set namespace = "")
  role_binding(
    name,
    role, // one of { role: NAME } or { cluster_role: NAME }
    // list of:
    //   NAME - a service account in the role's namespace, invalid for ClusterRoleBinding.
    //   { name, namespace } - a service account in a specific namespace
    //   { kind: "User" | "Group", name } - a user or group
    subjects,
    namespace = null,
    labels = {},
  ):
    $.resource(
      "rbac.authorization.k8s.io/v1",
      if namespace == "" then "ClusterRoleBinding" else "RoleBinding",
      name, namespace, labels,
    ) + {
      roleRef: {
        local key = util.unwrap_single(std.objectFields(role)),
        local value = util.unwrap_single(std.objectValues(role)),
        apiGroup: "rbac.authorization.k8s.io",
        kind: {role: "Role", cluster_role: "ClusterRole"}[key],
        name: value,
      },
      subjects: [
        {
          namespace: if self.kind == "ServiceAccount" then namespace else "",
          kind: "ServiceAccount"
        } + (if std.type(subject) == "string" then { name: subject } else subject)
        for subject in subjects
      ],
    },

  sa_with_role(
    name,
    // Because we need to specify namespace in the Subject, we cannot use the null namspace
    // and have it be auto-filled.
    namespace,
    labels = {},
    cluster_role = false,
    rules = [],
  ): {
    local role_namespace = if cluster_role then "" else namespace,
    service_account: $.service_account(name, namespace, labels),
    role: $.role(name, role_namespace, labels, rules),
    role_binding: $.role_binding(
      name,
      role = { [if cluster_role then "cluster_role" else "role"]: name },
      subjects = [{ name: name, namespace: namespace }],
      namespace = role_namespace,
      labels = labels,
    ),
  },

  // Patches to objects of various kinds to add certain common configurations.
  mixins: {

    // For deployments, configure them to only ever run one at a time.
    // This is not a guarentee but k8s won't do it intentionally.
    run_one: {
      spec+: {
        replicas: 1,
        strategy: { type: "Recreate" },
      },
    },

    // For pod specs, add a hostpath volume on a specific node. This forces it to run
    // on that node. NAME is the volume name which can then be referenced in volume mounts.
    host_path(name, host, path): {
      nodeName: host,
      volumes+: [{
        name: name,
        hostPath: { path: path },
      }]
    },

  },

}
