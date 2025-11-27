#!/usr/bin/env nu

# Screenshot utility for niri
# Usage: screenshot [action] [--dir path]
#   capture (default) - take a screenshot via region selection or window pick
#   pick - browse and manage existing screenshots
#
# NOTE: Depends on wl-copy from https://github.com/b0o/wl-clipboard-rs/tree/feat-cli-copy-multi
#       for multi-selection support.

def dismiss-notifications [] {
  let lines = makoctl list | lines
  let notif_idx = $lines | enumerate | where {|it|
    ($it.item | str starts-with "Notification") and ($it.item | str contains "Screenshot captured")
  } | each {|it|
    let next_line = $lines | get ($it.index + 1) | default ""
    if ($next_line | str contains "App name: niri") { $it.index } else { null }
  } | compact | get -o 0 | default null

  if $notif_idx != null {
    let id = $lines | get $notif_idx | parse "Notification {id}: {rest}" | get id | first
    makoctl dismiss -n $id
  }
}

def capture [dir: path] {
  let selection = slurp | complete
  if $selection.exit_code != 0 or ($selection.stdout | str trim | is-empty) {
    return
  }
  let selection = $selection.stdout | str trim

  let parsed = $selection | parse "{x},{y} {w}x{h}" | first
  let w = $parsed.w | into int
  let h = $parsed.h | into int

  let timestamp = date now | format date "%Y-%m-%d_%H-%M-%S"

  let out = if $w == 1 and $h == 1 {
    # Single click - pick a window
    let focused = niri msg -j focused-window | from json | get id
    job spawn { niri msg -j pick-window | from json | job send 0 }
    ydotool click 0x00 0xC0 | complete
    let selected = job recv
    niri msg action focus-window --id $focused

    if ($selected | is-empty) {
      return
    }

    let app_id = $selected.app_id | str replace -ra "[^a-zA-Z0-9._-]" "_" | str trim --char "_"
    let path = $dir | path join $"($timestamp)_($app_id).png"

    let result = niri msg action screenshot-window --id $selected.id --path $path | complete
    if $result.exit_code != 0 {
      notify-send -a screenshot -u critical "Screenshot Failed" "Failed to save screenshot"
      return
    }

    # Wait for file to be created with timeout
    mut attempts = 0
    while not ($path | path exists) and $attempts < 100 {
      dismiss-notifications
      sleep 5ms
      $attempts += 1
    }
    dismiss-notifications
    if not ($path | path exists) {
      notify-send -a screenshot -u critical "Screenshot Failed" "Timed out waiting for file"
      return
    }

    $path
  } else {
    # Region screenshot
    let path = $dir | path join $"($timestamp).png"
    let result = grim -g $selection $path | complete
    if $result.exit_code != 0 {
      notify-send -a screenshot -u critical "Screenshot Failed" "Failed to save screenshot"
      return
    }
    $path
  }

  wl-copy -F auto $out -L text/plain $out

  let action = notify-send -a screenshot -i $out --action=default="Edit" "Screenshot Saved" $"Saved to ($out)" | str trim
  if $action == "default" {
    satty --filename $out
  }
}

def pick [dir: path] {
  # Get monitor dimensions
  let mon = niri msg -j focused-output | from json | get logical
  let mon_width = $mon.width
  let mon_height = $mon.height

  # Calculate window size (50% of screen)
  let win_width = $mon_width // 2
  let win_height = $mon_height // 2

  # Calculate preview size (fit within right side, accounting for listview and padding)
  let list_width = $win_width * 35 // 100
  mut preview_size = $win_width * 55 // 100
  let max_preview_height = $win_height - 100
  if $preview_size > $max_preview_height {
    $preview_size = $max_preview_height
  }

  # Build rofi input: filename\0icon\x1fpath
  let files = ls --mime-type --threads $dir | where {
    get type | str starts-with image/
  } | sort-by -r modified | get name

  if ($files | is-empty) {
    notify-send -a screenshot "No Screenshots" "No screenshots found in the directory"
    return
  }

  let rofi_input = $files | each {|f|
    let basename = $f | path basename
    $"($basename)\u{0}icon\u{1f}($f)"
  } | str join "\n"

  let result = $rofi_input | rofi -dmenu -i -p "Screenshot" -show-icons ...[
    -theme-str $"window { width: ($win_width)px; height: ($win_height)px; children: [ mainbox ]; }"
    -theme-str "mainbox { children: [ inputbar, message, listview-split ]; }"
    -theme-str "listview-split { orientation: horizontal; spacing: 1em; children: [listview, icon-current-entry]; }"
    -theme-str $"listview { width: ($list_width)px; columns: 1; lines: 6; fixed-columns: true; }"
    -theme-str $"icon-current-entry { expand: true; size: ($preview_size)px; }"
    -theme-str "element-icon { size: 60px; }"
    -mesg "<span size='small' alpha='70%'>&lt;C-e&gt; edit / &lt;C-c&gt; copy / &lt;C-BackSpace&gt; delete / &lt;Cr&gt; menu / &lt;C-Cr&gt; open</span>"
    -kb-move-end ""
    -kb-cancel "Escape"
    -kb-remove-word-back ""
    -kb-accept-custom ""
    -kb-secondary-copy ""
    -kb-custom-1 "Control+e"
    -kb-custom-2 "Control+c"
    -kb-custom-3 "Control+BackSpace"
    -kb-custom-4 "Control+Return"
  ] | complete

  let selected = $result.stdout | str trim
  if ($selected | is-empty) {
    return
  }

  let file = $dir | path join $selected
  let code = $result.exit_code

  match $code {
    0 => {
      # Enter - show action menu
      let action = "Open\nCopy\nEdit\nDelete" | rofi -dmenu -i -p "Action"
      match ($action | str trim) {
        "Open" => { xdg-open $file }
        "Copy" => {
          wl-copy -F auto $file -L text/plain $file
          notify-send -a screenshot -i $file "Copied" "Screenshot copied to clipboard"
        }
        "Edit" => { satty --filename $file }
        "Delete" => { confirm-delete $file $selected }
      }
    }
    10 => { satty --filename $file }  # C-e: edit
    11 => {  # C-c: copy
      wl-copy -F auto $file -L text/plain $file
      notify-send -a screenshot -i $file "Copied" "Screenshot copied to clipboard"
    }
    12 => { confirm-delete $file $selected }  # C-BackSpace: delete
    13 => { xdg-open $file }  # C-Return: open
  }
}

def confirm-delete [file: string, selected: string] {
  let confirm = "Yes\nNo" | rofi -dmenu -p $"Delete ($selected)?" -mesg "Are you sure?"
  if ($confirm | str trim) == "Yes" {
    rm $file
    notify-send -a screenshot -i $file "Screenshot Deleted" $selected
  }
}

def main [
  action: string = "capture"  # Action to perform: capture or pick
  --dir (-d): path  # Screenshot directory (default: ~/Documents/screenshots)
] {
  let dir = $dir | default ($env.HOME | path join "Documents/screenshots")

  match $action {
    "capture" => { capture $dir }
    "pick" => { pick $dir }
    _ => {
      print $"Unknown action: ($action)"
      print "Usage: screenshot [capture|pick] [--dir path]"
      exit 1
    }
  }
}
