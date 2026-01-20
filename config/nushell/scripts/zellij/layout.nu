use types/kdl.nu *

# Placeholder for where child panes should be inserted in templates
export def children [] {
  node children
}

# Plugin specification
export def plugin [
  location: string  # "zellij:plugin-name" or "file:/path/to/plugin.wasm"
  options: record = {}  # Plugin options
] {
  node plugin --props={ location: $location } ...(child-args $options)
}

# Plugin options
export def child-args [props: record] {
  $props | items {|k, v|
    node $k --args=(if ($v | describe -d | get type) != "list" { [$v] } else { $v })
  }
}

# Basic pane building block
export def pane [
  ...children
  --command (-c): string      # Command to run instead of default shell
  --args (-a): list<string>   # Arguments for command
  --cwd: string               # Working directory
  --name (-n): string         # Pane title
  --size (-s): any            # Fixed (int) or percentage ("50%")
  --borderless (-b)           # No frame
  --focus (-f)                # Focus on startup
  --stacked                   # Children arranged in stack
  --expanded                  # Expanded in a stack context
  --split (-d): string        # "vertical" | "horizontal"
  --edit (-e): string         # File to open in $EDITOR
  --close-on-exit             # Close when command exits
  --start-suspended           # Wait for ENTER before running command
  # Floating pane positioning
  --x: any
  --y: any
  --width: any
  --height: any
] {
  mut props = {}
  if $command != null { $props = ($props | insert command $command) }
  if $cwd != null { $props = ($props | insert cwd $cwd) }
  if $name != null { $props = ($props | insert name $name) }
  if $size != null { $props = ($props | insert size $size) }
  if $borderless { $props = ($props | insert borderless true) }
  if $focus { $props = ($props | insert focus true) }
  if $stacked { $props = ($props | insert stacked true) }
  if $expanded { $props = ($props | insert expanded true) }
  if $split != null { $props = ($props | insert split_direction $split) }
  if $edit != null { $props = ($props | insert edit $edit) }
  if $close_on_exit { $props = ($props | insert close_on_exit true) }
  if $start_suspended { $props = ($props | insert start_suspended true) }
  if $x != null { $props = ($props | insert x $x) }
  if $y != null { $props = ($props | insert y $y) }
  if $width != null { $props = ($props | insert width $width) }
  if $height != null { $props = ($props | insert height $height) }
  let children = [
    ...(if ($args | is-not-empty) { [(node args --args=$args)] })
    ...$children
  ]
  node pane ...$children --props=$props
}

# Tab node
export def tab [
  ...children
  --name (-n): string     # Tab title
  --cwd: string           # Working directory for all panes
  --focus (-f)            # Focus on startup
  --split (-d): string    # "vertical" | "horizontal"
  --hide-floating         # Hide floating panes on startup
] {
  mut props = {}
  if $name != null { $props = ($props | insert name $name) }
  if $cwd != null { $props = ($props | insert cwd $cwd) }
  if $focus { $props = ($props | insert focus true) }
  if $split != null { $props = ($props | insert split_direction $split) }
  if $hide_floating { $props = ($props | insert hide_floating_panes true) }
  node tab ...$children --props=$props
}

# Container for floating panes
export def floating-panes [...children] {
  node floating_panes ...$children
}

# Pane template definition
export def pane-template [
  name: string
  ...children
  --command (-c): string
  --args (-a): list<string>
  --cwd: string
  --borderless (-b)
  --split (-d): string
] {
  mut props = { name: $name }
  if $command != null { $props = ($props | insert command $command) }
  if $cwd != null { $props = ($props | insert cwd $cwd) }
  if $borderless { $props = ($props | insert borderless true) }
  if $split != null { $props = ($props | insert split_direction $split) }
  let children = [
    ...(if ($args | is-not-empty) { [(node args --args=$args)] })
    ...$children
  ]
  node pane_template ...$children --props=$props
}

# Tab template definition
export def tab-template [
  name: string
  ...children
  --split (-d): string
] {
  mut props = { name: $name }
  if $split != null { $props = ($props | insert split_direction $split) }

  node tab_template ...$children --props=$props
}

# Default tab template (applies to all tabs and new tabs)
export def default-tab-template [...children] {
  node default_tab_template ...$children
}

# Template for new tabs only
export def new-tab-template [...children] {
  node new_tab_template ...$children
}

# Root layout node
export def main [
  ...children
  --cwd: string  # Global working directory
] {
  node layout ...$children --props=(if $cwd != null { { cwd: $cwd } })
}
