{
  apiVersion: "v1",
  kind: "EncryptionConfig",
  resources: [{
    resources: ["secrets"],
    providers: [
      {
        aescbc: {
          keys: [{
            name: "key1",
            secret: std.stripChars(importstr "../secrets/secret-encryption-key.secret", "\n"),
          }],
        },
      },
      {
        identity: {},
      },
    ],
  }],
}
