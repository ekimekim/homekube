local k8s = import "k8s.libsonnet";
{
  // upstream.json is taken from https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
  // then run through a yaml -> json converter as jsonnet's yaml parser isn't usable.
  upstream: import "upstream.json",

  issuer: k8s.resource("cert-manager.io/v1", "ClusterIssuer", "letsencrypt", namespace="") + {
    spec: {
      acme: {
        email: "letsencrypt@ekime.kim",
        server: "https://acme-v02.api.letsencrypt.org/directory",
        privateKeySecretRef: {
          name: "letsencrypt-account-key",
        },
        solvers: [
          {
            http01: {
              ingress: { ingressClassName: "nginx-external" },
            },
          },
        ],
      },
    },
  },
}
