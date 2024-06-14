local k8s = import "k8s.libsonnet";
local util = import "util.libsonnet";

{
  // This stunnel server terminates SSL before passing the underlying stream on
  // to charm's host-level sshd.

  certificate: k8s.certificate("ssh-proxy", ["ssh.ekime.kim"]),

  service: k8s.service("ssh-proxy", ports={
    tls: 443,
  }),

  deployment: k8s.deployment("ssh-proxy", pod={
    volumes: [{
      name: "tls",
      secret: { secretName: "ssh-proxy" },
    }],
    containers: [{
      name: "ssh-proxy",
      image: "dweomer/stunnel@sha256:c46e11e6cc135275566de318d739f815c272c23084fc1e65704f7e228992e9ef",
      env: util.env_to_list({
        STUNNEL_SERVICE: "ssh",
        STUNNEL_ACCEPT: 443,
        STUNNEL_CONNECT: "192.168.42.2:22",
        STUNNEL_KEY: "/certs/tls.key",
        STUNNEL_CRT: "/certs/tls.crt",
      }),
      volumeMounts: [
        {
          name: "tls",
          mountPath: "/certs",
        },
      ],
    }],
  }),
}
