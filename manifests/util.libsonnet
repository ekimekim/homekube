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
}
