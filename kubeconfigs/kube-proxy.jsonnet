(import "kubeconfig.libsonnet")(
  "system:kube-proxy",
  importstr "../ca/kube-proxy.pem",
  importstr "../ca/kube-proxy-key.pem",
)
