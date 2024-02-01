local k8s = import "k8s.libsonnet";

[
  k8s.deployment("ekimbot", pod={
    containers: [{
      name: "ekimbot",
      image: "quay.io/ekimekim/ekimbot:latest",
      // currently, this isn't actually pushed anywhere. don't try to pull it.
      imagePullPolicy: "Never"
    }],
  }),
]
