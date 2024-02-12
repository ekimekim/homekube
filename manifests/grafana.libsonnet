/*

Generates Grafana dashboards.

Dashboard:
  name: string, required. dashboard title.
  uid: string, dashboard id. defaults to slugged version of name.
  time_range: An interval string. Defaults to "1h". Interval the dashboard should cover.
  refresh: An interval string. Defaults to "15s". How often the dashboard should refresh.
    Null to disable auto refresh.
  timepicker: Advanced options for timepicker, such as available presets, or hiding the picker.
  tags: TODO.
  links: TODO.
  variables: A list of Variable, default [].
  rows: A list of Row, default [].
    Will be in the first part of the dashboard (before any sections)
  sections: A list of Section, default [].

Variable:
  Options common to all variable types:
    name: string, required. The identifier used to refer to it in queries
    label: string. The name shown in the UI (unless display is not "full").
      Defaults to name.
    tooltip: string, optional tooltip to show on the variable.
    value: Default value for variable. One of:
      null or not given: Use grafana's default, which is "all" if available,
        or the first option otherwise.
      string: Value that is selected. Multi must be false.
      list of string: List of values that are selected. Multi must be true.
  Options common to query and custom variables:
    multi: Boolean, default false. If true, allows selecting multiple options at once.
    all: string or null. If null, no "All" option is provided. If a string, this is used
      as the "custom all value". The default is null if multi is false, or ".*" if multi is true.
  Options for query variables:
    query: string, required. The prometheus query to use. Generally should be of the form:
      label_values(METRIC, LABEL)
    datasource: The name of the datasource to use, default "prometheus".
    regex: Optional regex that filters the results to only the matching entries
  Options for custom variables:
    values: required. List of possible values for the variable.
  Options for textbox variables:
    textbox: true, required. Indicates this is a textbox variable.

Section:
  name: string, required. Section header.
  collapse: bool, default false. If true, section is collapsed by default.
  rows: A list of Row.

Row: Either a list of Panel, or an object:
  height: number, default 8. Height for panels in row.

Panel:
  Common options for all panel types:
    name: string, required. Panel title.
    tooltip: string, tooltip to show on panel.
    width: number, width of panel. Default is to evenly divide row width
      between all panels in row without an explicit width. So eg. a row with 3 panels
      where one sets width: 12, the other two would default to 6.
  Options for time series panels:
    series: Required. Map from series name to query.
    datasource: The name of the datasource to use, default "prometheus".
    axis:
      units: string, what units the values are in
        You should use values from grafana.units.
      label: string, the axis label
      log: If not given, makes a linear axis. If given:
        base: Required. The log base shown in the axis. Must(?) be 2 or 10.
        threshold: If given, values within this range of 0 will be linear instead.
          This allows values which get near or pass through 0.
      min: The lowest value to show on the axis. Set to null to use the lowest shown value.
        Defaults to 0.
      max: The highest value to show on the axis. Defaults to highest shown value.
      stack: Set true to make a stacked graph. Set "percent" to make a 100%-stack graph.
      style: One of "line", "bars", or "points", default "line".
    legend: TODO (always hidden for now)
    hover: one of:
      "hidden": No values shown on hover
      "single": Only the series hovered over is shown
      "desc": Default. All series are shown, sorted by value decending.
      "asc": All series are shown, sorted by value ascending.
  Options for custom panels:
    custom: Required. An opaque object that will be merged into the panel JSON.

*/
local util = import "util.libsonnet";

{
  units: {
    percent: "percentunit",
    bytes: "bytes",
    byte_rate: "binBps",
    time_ago: "dateTimeFromNow",
    time: "dtdurations",
  },

  dashboard(raw_args):
    local args = {
      name: error "Name is required",
      uid: util.replaceNonMatching(
        std.asciiLower(args.name),
        "-",
        function(c) c >= "a" && c <= "z",
      ),
      time_range: "1h",
      refresh: "15s",
      timepicker: {},
      variables: [],
      rows: [],
      sections: [],
    } + raw_args;
    {
      schemaVersion: 39,
      version: 1,

      title: args.name,
      [if args.uid != null then "uid"]: args.uid,

      annotations: {list: []},
      //links: [],
      //tags: [],
      //templating: [],

      [if args.refresh != null then "refresh"]: args.refresh,
      time: {
        from: "now-%s" % args.time_range,
        to: "now",
      },
      timepicker: args.timepicker,

      templating: {
        list: std.map($.variable, args.variables),
      },

      // In grafana, sections are modeled as a kind of panel that implicitly puts all panels
      // between it and the next section (or the end) inside it. So we need to flatten sections
      // down into a list of rows, where a section is a kind of row.
      local rows = args.rows + std.flatMap(function(section) [
        // This is a Row object of height 1, with a single custom "panel"
        {
          height: 1,
          panels: [{
            name: section.name,
            custom: {
              type: "row",
              panels: [],
              collapsed: section.collapse,
            },
          }]
        }
      ] + section.rows, args.sections),

      // Panels need to be laid out via an iterative process that tracks id numbers as well as
      // y position of each row. We use a foldl to maintain this state.
      panels: std.foldl(
        function(row_state, raw_row) {
          // normalize row
          local row = {
            height: 8,
            panels: [],
          } + if std.type(raw_row) == "array" then {panels: raw_row} else raw_row,

          // determine default panel width
          local has_width = std.filter(function(panel) std.objectHas(panel, "width"), row.panels),
          local used_width = std.sum([panel.width for panel in has_width]),
          local needs_width = std.length(row.panels) - std.length(has_width),
          // There's a possible divide by zero here, but the default width is only USED in cases
          // where needs_width > 0, so if needs_width is 0 this will never be evaluated.
          local default_width = std.floor((24 - used_width) / needs_width),

          next_id: row_state.next_id + std.length(row.panels),
          y: row_state.y + row.height,
          panels: row_state.panels + std.foldl(
            function(panel_state, panel) {
              local width = std.get(panel, "width", default_width),
              next_id: panel_state.next_id + 1,
              x: panel_state.x + width,
              panels: panel_state.panels + [
                $.panel(panel) + {
                  id: panel_state.next_id,
                  gridPos: {
                    h: row.height,
                    w: width,
                    x: panel_state.x,
                    y: row_state.y,
                  },
                },
              ],
            },
            row.panels,
            {
              next_id: row_state.next_id,
              x: 0,
              panels: [],
            },
          ).panels,
        },
        rows,
        {
          next_id: 1,
          y: 0,
          panels: [],
        }
      ).panels,
    },

  panel(raw_args):
    local args = {
      name: error "Panel name is required",
      tooltip: null,
    } + raw_args;
    {
      title: args.name,
      [if args.tooltip != null then "description"]: args.tooltip,
    } +
    if std.objectHas(args, "custom") then args.custom else
    if std.objectHas(args, "series") then $.timeseries_panel(args) else
    error "Cannot determine panel type",

  timeseries_panel(raw_args):
    local args = {
      axis: {},
      hover: "hidden",
      datasource: "prometheus",
    } + raw_args;
    local axis = {
      units: "short",
      label: "",
      log: null,
      min: 0,
      max: null,
      stack: null,
      style: "line",
    } + args.axis;
    local datasource = {
      type: "prometheus",
      uid: args.datasource,
    };
    {
      type: "timeseries",
      datasource: datasource,
      targets: std.mapWithIndex(
        function(index, item) {
          editorMode: "code",
          instant: false,
          range: true,
          datasource: datasource,
          expr: item.value,
          legendFormat: item.key,
          // The refId needs to be "A" for the first one, then "B", etc...
          refId:
            if index >= 26 then error "This many series not supported"
            else std.char(std.codepoint("A") + index),
        },
        std.objectKeysValues(args.series)
      ),
      options: {
        legend: {
          showLegend: false,
        },
        tooltip: {
          hidden: { mode: "none" },
          single: { mode: "single" },
          desc: { mode: "multi", sort: "desc" },
          asc: { mode: "multi", sort: "asc" },
        }[args.hover],
      },
      fieldConfig: {
        defaults: {
          unit: axis.units,
          [if axis.min != null then "min"]: axis.min,
          [if axis.max != null then "max"]: axis.max,
          custom: {
            axisLabel: axis.label,
            drawStyle: axis.style,
            fillOpacity: if axis.stack != null then 40 else 0,
            stacking: {
              group: "A",
              mode:
                if axis.stack == null then "none"
                else if axis.stack == true then "normal"
                else axis.stack
            },
          },
        },
      },
    },

  variable(raw_args):
    local args = {
      name: error "Name is required",
      label: self.name,
      tooltip: null,
      value: null,
      multi: false,
      all: if self.multi then ".*" else null,
    } + raw_args;
    local multi_options = {
      multi: args.multi,
      includeAll: args.all != null,
      [if args.all != null then "allValue"]: args.all,
    };
    {
      name: args.name,
      label: args.label,
      [if args.tooltip != null then "description"]: args.tooltip,
      [if args.value != null then "current"]: {
        text: args.value,
        value: args.value,
      },
      hide: 0, // show labels and values
      skipUrlSync: false,
    } +
    if std.objectHas(args, "query") then multi_options + $.query_variable(args)
    else if std.objectHas(args, "values") then multi_options + $.custom_variable(args)
    else if std.objectHas(args, "textbox") then { type: "textbox" }
    else error "Cannot determine variable type",

  query_variable(args): {
    type: "query",
    sort: 1, // ascending
    refresh: 2, // refresh on time range change (most often)
    regex: std.get(args, "regex", ""),
    datasource: {
      type: "prometheus",
      uid: std.get(args, "datasource", "prometheus"),
    },
    definition: args.query,
    query: {
      qryType: 5,
      refId: "PrometheusVariableQueryEditor-VariableQuery",
      query: args.query,
    },
  },

  custom_variable(args): {
    type: "custom",
    options: [
      {
        text: value,
        value: value,
      }
      for value in args.values
    ],
    query: std.join(",\n", [
      # escape , in values
      std.strReplace(value, ",", "\\,")
      for value in args.values
    ]),
    # Experimentally, custom variables don't tolerate a missing "current" the way others do.
    # Instead, default to the first option in the list.
    [if args.value == null then "current"]: self.options[0],
  },
}
