export def xc [
  --out(-o) # Output/paste mode
  ...args   # Additional arguments
] {
  if 'WAYLAND_DISPLAY' in $env {
    if $out {
      ^wl-paste ...$args
    } else {
      ^wl-copy -t text/plain -n ...$args
    }
  } else if 'DISPLAY' in $env {
    if $out {
      ^xclip -o -selection clipboard ...$args
    } else {
      ^xclip -selection clipboard ...$args
    }
  } else {
    if $out {
      print -e 'xc: no graphical session detected'
      print -e 'OSC 52: output not supported'
      error make {msg: "no graphical session"}
    } else {
      let encoded = (^base64 | str trim)
      print -n $"(\u{001b})]52;;($encoded)(\u{001b})\\"
    }
  }
}

# Copy last n command(s) to clipboard
def xcl [count: int = 1] {
  let lines = (history | last $count | get command | str join "\n")
  echo $lines | xc
  print -e $"Copied:\n($lines)"
}

# Copy command and its output to clipboard
# TODO: custom commands do not work
def xcc [...args] {
  let cmd = if ($args | is-not-empty) {
    ($args | str join " ")
  } else {
    $in
  }

  let header = $"$ ($cmd)\n"
  let result = (do { nu -i -c $cmd } | complete)
  let full_str = $header + $result.stdout + $result.stderr

  print -e $full_str
  echo $full_str | xc
}

# Copy last n command(s) and its output to clipboard (command(s) are re-run)
def xccl [count: int = 1] {
  let lines = (history | last $count | get command | str join "\n")
  print -e $lines
  let reply = (input "Run command? [Y/n] " | str trim)

  if $reply not-in ["y", "Y", ""] {
    print -e "Aborted"
    return 1
  }

  print ""
  xcc $lines
}

# Copy a file to clipboard (as file attachment or text)
export def xcf [
  path?: path          # File path (omit to read from stdin)
  --name (-n): string   # Filename for stdin input (default: paste.txt)
  --text (-t)           # Copy as text content instead of file reference
] {
  let file_path = if $path != null {
    $path | path expand
  } else {
    let name = ($name | default "paste.txt")
    let tmp = (mktemp --suffix $"-($name)")
    $in | save -f $tmp
    $tmp
  }

  if $text {
    open $file_path | xc
  } else {
    if 'WAYLAND_DISPLAY' in $env {
      let uri = $"file://($file_path)"
      ^wl-copy -L 'x-special/gnome-copied-files' $"copy\n($uri)" -L 'text/uri-list' $uri
    } else if 'DISPLAY' in $env {
      # X11: xclip doesn't handle this well, fall back to text
      print -e "xcf: file reference copy not supported on X11, copying as text"
      open $file_path | xc
    } else {
      print -e "xcf: file reference copy requires graphical session, copying as text via OSC 52"
      open $file_path | xc
    }
  }
}

alias xco = xc -o
