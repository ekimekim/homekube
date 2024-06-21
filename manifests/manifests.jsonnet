// Wrapper script that is used to render all manifest jsonnet files.
// It flattens out the structure to a list of manifests only, and automatically
// inserts the namespace based on the first level of directory info.

local flatten(value) =
  if std.type(value) == "array" then
    // For arrays, flatten each value.
    std.flatMap(flatten, value)
  else if std.type(value) != "object" then
    error "Expected manifest, object or array but got %s" % [value]
  else if std.objectHas(value, "apiVersion") && std.objectHas(value, "kind") then
    // Object looks like a manifest, return it
    [value]
  else
    // non-manifest object, flatten each value
    std.flatMap(flatten, std.objectValues(value))
  ;

// Top-level function, this file is expected to be called with the contents of a manifest file.
// Path is expected to be "manifests/*.jsonnet" or "manifests/NAMESPACE/*.jsonnet"
function(path, value)
  local path_parts = std.split(path, "/");
  local namespace =
    if std.length(path_parts) <= 1 || std.length(path_parts) > 3 || path_parts[0] != "manifests" then
      error "Unexpected path: %s" % path
    else if std.length(path_parts) == 2 then
      ""
    else
      path_parts[1];
  [
    // We want to merge metadata, but can't rely on manifest.metadata being set to merge.
    // We want to do so in a way that their namespace value overrides ours, so we can't just
    // do `metadata+: { namespace: ... }`.
    // So we explicitly replace manifest.metadata, but do it with a reverse-merge of their metadata
    // into our base.
    // THEN we add in our extra labels.
    manifest + {
      metadata: {
        namespace: namespace,
      } + manifest.metadata + {
        labels+: { "managed-by": "homekube" },
      },
    }
    for manifest in flatten(value)
  ]
