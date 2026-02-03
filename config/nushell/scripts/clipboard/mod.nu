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
export def xcl [
  --markdown (-m)  # Copy as markdown code block
  count: int = 1
] {
  let lines = (history | last $count | get command | str join "\n")
  # $lines | xc
  if $markdown {
    $lines | xcm --lang nu
    print -e $"Copied:\n($lines)"
  } else {
    $lines | xc
    print -e $"Copied:\n($lines)"
  }
  print -e $"Copied:\n($lines)"
}

export alias xclm = xcl --markdown

# TODO: custom commands do not work
def --wrapped _xcc [...args: string] {
  let cmd = if ($args | is-not-empty) {
    ($args | str join " ")
  } else {
    $in
  }

  let header = $"$ ($cmd)\n"
  let result = (do { nu -l -i -c $cmd } | complete)
  $header + $result.stdout + $result.stderr
}

# Copy command and its output to clipboard
export def --wrapped xcc [...args: string] {
  let full_str = _xcc ...$args
  print -e $full_str
  $full_str | xc
}

# Copy command and its output to clipboard as markdown
export def xccm --wrapped [...args: string] {
  let full_str = _xcc ...$args
  print -e $full_str
  $full_str | xcm --lang nu
}

# Copy last n command(s) and its output to clipboard (command(s) are re-run)
export def xccl [count: int = 1] {
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
    open --raw $file_path | xc
  } else {
    if 'WAYLAND_DISPLAY' in $env {
      let uri = $"file://($file_path)"
      ^wl-copy -L 'x-special/gnome-copied-files' $"copy\n($uri)" -L 'text/uri-list' $uri
    } else if 'DISPLAY' in $env {
      # X11: xclip doesn't handle this well, fall back to text
      print -e "xcf: file reference copy not supported on X11, copying as text"
      open --raw $file_path | xc
    } else {
      print -e "xcf: file reference copy requires graphical session, copying as text via OSC 52"
      open --raw $file_path | xc
    }
  }
}

export alias xcff = xcf --text

# Copy text wrapped in markdown fenced code block
export def xcm [
  --lang (-l): string  # Language for the fence (e.g., nu, py, sh)
  ...args              # Text to copy (or pipe via $in)
] {
  let content = if ($args | is-not-empty) {
    $args | str join " "
  } else {
    $in | into string
  }

  let fence = if $lang != null { $"```($lang)" } else { "```" }
  let wrapped = $"($fence)\n($content)\n```"

  $wrapped | xc
}

# Copy file content wrapped in markdown fenced code block
export def xcfm [
  path: path           # File path to copy
  --lang (-l): string  # Language override (defaults to file extension)
] {
  let ext = if $lang != null { $lang } else { $path | path parse | get extension }
  open --raw $path | xcm -l $ext
}

export alias xco = xc -o
