{
  // upstream.json is taken from https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
  // then run through a yaml -> json converter as jsonnet's yaml parser isn't usable.
  upstream: import "upstream.json",
}
