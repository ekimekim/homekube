function (
  user,
  clientCertificate,
  clientKey,
  apiServer = "192.168.42.2:6443",
  rootCertificate = importstr "../ca/root.pem",
) {
  apiVersion: "v1",
  kind: "Config",
  preferences: {},
  clusters: [
    {
      name: "xenon",
      cluster: {
        server: apiServer,
        "certificate-authority-data": std.base64(rootCertificate),
      },
    },
  ],
  users: [
    {
      name: user,
      user: {
        "client-certificate-data": std.base64(clientCertificate),
        "client-key-data": std.base64(clientKey),
      },
    },
  ],
  local contextName = "xenon-%s" % user,
  contexts: [
    {
      name: contextName,
      context: {
        cluster: "xenon",
        user: user,
      },
    },
  ],
  "current-context": contextName,
}
