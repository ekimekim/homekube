{
  local opts_to_args(opts) = [
    local key = std.strReplace(opt, "_", "-");
    local value = std.toString(opts[opt]);
    "--%s=%s" % [key, value]
    for opt in std.objectFields(opts)
  ],
  kind: "Pod",
  apiVersion: "v1",
  metadata: {
    namespace: "kube-system",
    name: "api-server",
    labels: {
      app: "api-server",
      static: "master",
    },
  },
  spec: {
    // This needs to work before kube-proxy, etc, so we can't use a Service, and pod ips make things
    // difficult. Easiest way is to just directly bind to the host's interface.
    hostNetwork: true,
    volumes: [
      {
        name: "config",
        hostPath: {path: "/etc/kubernetes"},
      },
    ],
    containers: [{
      name: "api-server",
      image: "registry.k8s.io/kube-apiserver:v1.28.4",
      command: ["kube-apiserver"],
      args: opts_to_args({
        local certs = {
          root: "/etc/kubernetes/root.pem",
          cert: "/etc/kubernetes/api-server.pem",
          key: "/etc/kubernetes/api-server-key.pem",
        },
        // allow privileged containers (default is false)
        allow_privileged: true,
        // enable RBAC + special kubelet auth (default is "everything is allowed")
        authorization_mode: "Node,RBAC",
        // CA to check incoming clients' certs with
        client_ca_file: certs.root,
        // Secret to encrypt k8s Secrets in etcd with
        encryption_provider_config: "/etc/kubernetes/encryption-config.yaml",
        // etcd connection info
        etcd_cafile: certs.root,
        etcd_certfile: certs.cert,
        etcd_keyfile: certs.key,
        etcd_servers: "https://192.168.42.2:2379",
        // kubelet connection info
        kubelet_certificate_authority: certs.root,
        kubelet_client_certificate: certs.cert,
        kubelet_client_key: certs.key,
        // Not clear if this is the default or not. Enable all api types.
        runtime_config: "api/all=true",
        // Cert that service accounts should be signed with
        service_account_key_file: "/etc/kubernetes/service-accounts.pem",
        // Key to sign service accounts with
        service_account_signing_key_file: "/etc/kubernetes/service-accounts-key.pem",
        // "Issuer" to use, which "should" be the api server's URL
        service_account_issuer: "https://192.168.42.2:6443",
        // IP range for service IPs
        service_cluster_ip_range: "192.168.43.0/24",
        // Cert and key for server
        tls_cert_file: certs.cert,
        tls_private_key_file: certs.key,
        // Log verbosity. This is the level used by Kubernetes the Hard Way.
        v: 2,
        // Audit logging config. Our config records metadata (but not req/resp bodies) of all events.
        audit_log_path: "-", // stdout
        audit_policy_file: "/etc/kubernetes/audit-policy.yaml",
      }),
      volumeMounts: [
        {
          name: "config",
          mountPath: "/etc/kubernetes",
        },
      ],
    }],
  },
}
