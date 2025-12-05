# Rofi helper functions for nushell scripts

# Display a rofi dmenu with optional image preview panel
export def main [
  --input: string           # Pre-formatted rofi input (alternative to --options)
  --options: list<string>   # Simple options list
  --icon: string            # Icon file for all options (used with --options, requires --preview)
  --prompt: string          # Prompt text
  --mesg: string            # Optional message
  --placeholder: string     # Search field placeholder (null = default)
  --lines: int = 6          # Number of visible lines
  --preview                 # Enable image preview panel
  --multi-select            # Enable multi-select mode
  --win-scale: int = 3      # Window is 1/N of screen (3 = 33%, 2 = 50%)
  --list-width: string      # Custom listview width CSS (e.g., "35%")
  --element-icon-size: int  # Size for per-element icons (null = disabled)
  --extra: list<string>     # Extra rofi args (e.g., kb shortcuts)
] {
  let rofi_input = if $input != null {
    $input
  } else if $preview and $icon != null {
    $options | each {|opt| $"($opt)\u{0}icon\u{1f}($icon)" } | str join "\n"
  } else {
    $options | str join "\n"
  }

  let mesg_args = if $mesg != null { [-mesg $mesg] } else { [] }
  let placeholder_css = if $placeholder != null {
    [-theme-str $"entry { placeholder: \"($placeholder)\"; }"]
  } else {
    []
  }

  let multi_args = if $multi_select { [-multi-select] } else { [] }

  if $preview {
    let mon = niri msg -j focused-output | from json | get logical
    let win_width = $mon.width // $win_scale
    let win_height = $mon.height // $win_scale
    let preview_size = [($win_height - 100), ($win_width * 55 // 100)] | math min

    let list_width_css = if $list_width != null { $" width: ($list_width);" } else { "" }
    let element_icon_css = if $element_icon_size != null {
      $"element-icon { size: ($element_icon_size)px; }"
    } else {
      "element-icon { enabled: false; }"
    }

    $rofi_input | ^rofi -dmenu -i -p $prompt -show-icons ...$multi_args ...$mesg_args ...[
      -theme-str $"window { width: ($win_width)px; height: ($win_height)px; children: [ mainbox ]; }"
      -theme-str "mainbox { children: [ inputbar, message, listview-split ]; }"
      -theme-str "listview-split { orientation: horizontal; spacing: 1em; children: [listview, icon-current-entry]; }"
      -theme-str $"listview {($list_width_css) columns: 1; lines: ($lines); fixed-columns: true; }"
      -theme-str $"icon-current-entry { expand: true; size: ($preview_size)px; }"
      -theme-str $element_icon_css
    ] ...$placeholder_css ...($extra | default []) | complete
  } else {
    $rofi_input | ^rofi -dmenu -i -p $prompt ...$multi_args ...$mesg_args ...[
      -theme-str $"listview { lines: ($lines); }"
    ] ...$placeholder_css ...($extra | default []) | complete
  }
}
