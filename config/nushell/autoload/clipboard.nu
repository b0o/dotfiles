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

# Copy a file to clipboard
def xcf [path: path] {
  open $path | xc
}

alias xco = xc -o
