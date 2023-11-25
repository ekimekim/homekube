(import "kubeconfig.libsonnet")(
  "system:kube-controller-manager",
  importstr "../ca/kube-controller-manager.pem",
  importstr "../ca/kube-controller-manager-key.pem",
)
