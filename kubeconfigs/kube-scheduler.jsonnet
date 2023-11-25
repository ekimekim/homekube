(import "kubeconfig.libsonnet")(
  "system:kube-scheduler",
  importstr "../ca/kube-scheduler.pem",
  importstr "../ca/kube-scheduler-key.pem",
)
