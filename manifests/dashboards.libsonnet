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
  variables: TODO.
  rows: A list of Row, default [].
    Will be in the first part of the dashboard (before any sections)
  sections: A list of Section, default [].

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
  Options for custom panels:
    custom: Required. An opaque object that will be merged into the panel JSON.

*/
{
  dashboard(raw_args):
    local args = {
      name: error "Name is required",
      uid: args.name, // TODO slugify
      time_range: "1h",
      refresh: "15s",
      timepicker: {},
      rows: [],
      sections: [],
    } + raw_args;
    {
      schemaVersion: 39,
      version: 1,

      title: args.name,
      uid: args.uid,

      //annotations: {list: []},
      //links: [],
      //tags: [],
      //templating: [],

      [if args.refresh != null then "refresh"]: args.refresh,
      time: {
        from: "now-%s" % args.time_range,
        to: "now",
      },
      timepicker: args.timepicker,

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

  panel(args): // TODO for non-custom
    {
      title: args.name,
    } + args.custom,
}
