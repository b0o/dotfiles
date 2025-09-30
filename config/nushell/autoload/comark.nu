const COMARK_DIR = ($nu.home-path | path join ",")

# Initialize comark directory
def comark-init [] {
  if not ($COMARK_DIR | path exists) {
    print $"Creating comark directory: ($COMARK_DIR)"
    mkdir $COMARK_DIR
  }
}

# Make a new bookmark
export def m, [
  alias: string
  dest?: string
] {
  comark-init
  let bookmark_path = ($COMARK_DIR | path join $alias)

  if ($bookmark_path | path exists) {
    error make {msg: $"bookmark exists: ($alias)"}
  }

  let target = if ($dest | is-empty) { $env.PWD } else { $dest | path expand }
  ^ln -s $target $bookmark_path
  print $"($alias) -> ($target)"
}

# Remove a bookmark
export def r, [alias: string] {
  comark-init
  let bookmark_path = ($COMARK_DIR | path join $alias)

  if not ($bookmark_path | path exists) {
    error make {msg: $"bookmark does not exist: ($alias)"}
  }

  let dest = ($bookmark_path | path expand)
  rm $bookmark_path
  print $"removed bookmark ($alias) -> ($dest)"
}

# Rename a bookmark
export def rename, [old: string, new: string] {
  comark-init
  let old_path = ($COMARK_DIR | path join $old)
  let new_path = ($COMARK_DIR | path join $new)

  if not ($old_path | path exists) {
    error make {msg: $"bookmark does not exist: ($old)"}
  }

  if ($new_path | path exists) {
    error make {msg: $"bookmark exists: ($new)"}
  }

  mv $old_path $new_path
  print $"bookmark ($old) renamed to ($new)"
}

# Print bookmark destination path
export def p, [alias: string] {
  comark-init
  let bookmark_path = ($COMARK_DIR | path join $alias)

  if not ($bookmark_path | path exists) {
    error make {msg: $"bookmark does not exist: ($alias)"}
  }

  let target = ($bookmark_path | path expand)
  if ($target | path type) == "dir" { $"($target)/" } else { $target }
}

# List all bookmarks
export def l, [pattern?: string] {
  comark-init

  let bookmarks = (
    ls $COMARK_DIR
    | where type == symlink
    | each {|row|
      let alias = ($row.name | path basename)
      let target = ($row.name | path expand)
      if ($pattern | is-empty) or ($alias | str contains $pattern) {
        {name: $alias, target: $target}
      }
    }
    | compact
    | sort-by name
  )

  if ($bookmarks | is-empty) {
    print -e $"no bookmarks found matching '($pattern)'"
    return
  }

  $bookmarks
}

# Change directory to bookmark
export def --env cd, [alias: string] {
  comark-init
  let bookmark_path = ($COMARK_DIR | path join $alias)

  if not ($bookmark_path | path exists) {
    error make {msg: $"bookmark does not exist: ($alias)"}
  }

  cd ($bookmark_path | path expand)
}

# Select bookmark with fzf
export def f, [query?: string] {
  comark-init

  let bookmark_list = (
    ls $COMARK_DIR
    | where type == symlink
    | each {|row|
      let alias = ($row.name | path basename)
      let target = ($row.name | path expand)
      $"($alias)\t($target)"
    }
    | str join "\n"
  )

  if ($bookmark_list | is-empty) {
    return ""
  }

  let sel = (
    echo $bookmark_list
    | ^fzf --layout=reverse --delimiter='\t' --with-nth=1,2
           --query ($query | default "") --tiebreak=begin
           --preview $"eza -TlaF -L1 --group-directories-first --color=always --git --extended --follow-symlinks {2}"
    | complete
  )

  if $sel.exit_code != 0 or ($sel.stdout | is-empty) {
    return ""
  }

  $sel.stdout | str trim | split row "\t" | first
}

# Helper to insert text at cursor
def insert-at-cursor [text: string] {
  let before = (commandline | str substring 0..<(commandline get-cursor))
  let after = (commandline | str substring (commandline get-cursor)..)
  let new_buffer = $before + $text + $after

  commandline edit --replace $new_buffer
  commandline set-cursor (($before | str length) + ($text | str length))
}

# Smart fzf: cd if empty/dir, insert if file, expand ,bookmark pattern
export def --env fzf,smart [] {
  let line_buffer = (commandline)
  let cursor_pos = (commandline get-cursor)
  let before_cursor = ($line_buffer | str substring 0..<$cursor_pos)
  let after_cursor = ($line_buffer | str substring $cursor_pos..)

  # Empty buffer: cd to dir bookmark, insert file bookmark
  if ($line_buffer | str trim | is-empty) {
    let bookmark = (f,)
    if ($bookmark | is-empty) { return }

    let path = ($bookmark | p, $in)
    if ($path | str ends-with '/') {
      cd, $bookmark
    } else {
      insert-at-cursor $path
    }
    return
  }

  # Check for ,<bookmark> pattern at cursor
  let matches = ($before_cursor | parse --regex '(.*\s+)?,(\S+)$')

  if not ($matches | is-empty) {
    let match = ($matches | first)
    let prefix = ($match.capture0 | default "")
    let bookmark_name = $match.capture1
    let bookmark_path = (do --ignore-errors { p, $bookmark_name })

    if not ($bookmark_path | is-empty) {
      # Expand existing bookmark
      commandline edit --replace ($prefix + $bookmark_path + $after_cursor)
      commandline set-cursor (($prefix | str length) + ($bookmark_path | str length))
      return
    }

    # Try fuzzy search with query
    let selected = (f, $bookmark_name)
    if not ($selected | is-empty) {
      let path = (p, $selected)
      commandline edit --replace ($prefix + $path + $after_cursor)
      commandline set-cursor (($prefix | str length) + ($path | str length))
    }
    return
  }

  # Default: insert at cursor
  let bookmark = (f,)
  if not ($bookmark | is-empty) {
    insert-at-cursor (p, $bookmark)
  }
}

# FZF insert (always insert path)
export def --env fzf,insert [] {
  let bookmark = (f,)
  if not ($bookmark | is-empty) {
    insert-at-cursor (p, $bookmark)
  }
}

# FZF cd (always change directory)
export def --env fzf,cd [] {
  let bookmark = (f,)
  if not ($bookmark | is-empty) {
    cd, $bookmark
  }
}
