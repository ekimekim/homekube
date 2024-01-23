{
  // Convert an options object {key: value} to a list of args `--key=value`.
  // Underscores in keys are converted to dashes. If value is `true`, value is omitted
  // (ie. {foo: true} -> "--foo"). Other values are stringified.
  opts_to_args(opts): [
    local key = std.strReplace(opt, "_", "-");
    local value = opts[opt];
    if value == true then
      "--%s" % [key]
    else
      "--%s=%s" % [key, std.toString(value)]
    for opt in std.objectFields(opts)
  ],

  // Returns the singular element of a 1-element array, or else errors.
  unwrap_single(value):
    if std.length(value) == 1 then
      value[0]
    else
      error "Expected single element but got %s: %s" % [std.length(value), value],
}
