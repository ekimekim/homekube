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

// top-level function, this file is expected to be called with the contents of a manifest file
flatten
