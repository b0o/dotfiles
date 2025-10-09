# Comark (Comma Bookmark) for Nushell
# Shell bookmark manager for quick navigation and file management

let comark_dir = (
  $env
  | get -o COMARK_DIR
  | default (
      $env
      | get -o XDG_CONFIG_HOME
      | default ($nu.home-path | path join ".config")
      | path join "comark"
    )
)

# Initialize comark directory
def comark-init [] {
  if not ($comark_dir | path exists) {
    print $"Creating comark directory: ($comark_dir)"
    mkdir $comark_dir
  }
}

# Make a new bookmark
export def m, [
  alias: string
  dest?: string
  --force (-f)  # Overwrite existing bookmark
] {
  comark-init
  let bookmark_path = ($comark_dir | path join $alias)

  if ($bookmark_path | path exists) {
    if $force {
      r, $alias
    } else {
      error make -u {msg: $"bookmark exists: ($alias)"}
    }
  }

  let target = if ($dest | is-empty) { $env.PWD } else { $dest | path expand }
  ^ln -s $target $bookmark_path
  print $"($alias) -> ($target)"
}

# Remove a bookmark
export def r, [alias: string] {
  comark-init
  let bookmark_path = ($comark_dir | path join $alias)

  if not ($bookmark_path | path exists --no-symlink) {
    error make -u {msg: $"bookmark does not exist: ($alias)"}
  }

  let dest = (resolve-bookmark $alias)
  rm $bookmark_path
  print $"removed bookmark ($alias) -> ($dest)"
}

# Rename a bookmark
export def rename, [old: string, new: string] {
  comark-init
  let old_path = ($comark_dir | path join $old)
  let new_path = ($comark_dir | path join $new)

  if not ($old_path | path exists --no-symlink) {
    error make -u {msg: $"bookmark does not exist: ($old)"}
  }

  if ($new_path | path exists --no-symlink) {
    error make -u {msg: $"bookmark exists: ($new)"}
  }

  mv $old_path $new_path
  print $"bookmark ($old) renamed to ($new)"
}

def resolve-bookmark [bookmark: string] {
  let bookmark_path = ($comark_dir | path join $bookmark)
  if not ($bookmark_path | path exists --no-symlink ) {
    error make -u {msg: $"bookmark does not exist: ($bookmark)"}
  }
  # symlink exists but points to a non-existent file
  # use realpath to resolve the symlink
  if not ($bookmark_path | path exists) {
    return (realpath -m $bookmark_path)
  }
  let target = ($bookmark_path | path expand)
  if ($target | path type) == "dir" {
    return $"($target)/"
  }
  $target
}

# Print bookmark destination path
export def p, [alias: string] {
  comark-init
  resolve-bookmark $alias
}

# List all bookmarks
export def l, [pattern?: string] {
  comark-init

  let bookmarks = (
    ls $comark_dir
    | where type == symlink
    | par-each {|row|
      let alias = ($row.name | path basename)
      let target = (resolve-bookmark $alias)
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
  let bookmark_path = ($comark_dir | path join $alias)

  if not ($bookmark_path | path exists --no-symlink) {
    error make -u {msg: $"bookmark does not exist: ($alias)"}
  }
  # symlink exists but points to a non-existent file
  if not ($bookmark_path | path exists) {
    error make -u  {msg: $"bookmark destination does not exist: ($alias)"}
  }

  cd ($bookmark_path | path expand)
}

# Select bookmark with fzf
export def f, [query?: string] {
  comark-init

  let bookmark_list = (
    ls $comark_dir
    | where type == symlink
    | par-each {|row|
      let alias = ($row.name | path basename)
      let target = (resolve-bookmark $alias)
      $"($alias)\t($target)"
    }
    | str join "\n"
  )

  if ($bookmark_list | is-empty) {
    return ""
  }

  let sel = (
    echo $bookmark_list
    | ^fzf --layout=reverse --delimiter='\t' --nth='1' --with-nth=1,2
           --query ($query | default "") --tiebreak=begin,chunk
           --preview $"eza -TlaF -L1 --group-directories-first --color=always --git --extended --follow-symlinks {2}"
           --bind 'alt-,:change-nth(1,2|1)'
           --preview-border=none --separator='─' --scrollbar='▌'
    | complete
  )

  if $sel.exit_code != 0 or ($sel.stdout | is-empty) {
    return ""
  }

  $sel.stdout | str trim | split row "\t" | first
}

# Remove bookmarks that point to non-existent files
export def prune, [
  --force (-f)  # Skip confirmation prompt
] {
  let bookmarks = (
    ls $comark_dir
    | where type == symlink
    | each {|row|
      let alias = ($row.name | path basename)
      let target = (resolve-bookmark $alias)
      if not ($target | path exists) {
        {name: $alias, target: $target}
      }
    }
    | compact
    | sort-by name
  )

  if ($bookmarks | is-empty) {
    print -e "No bookmarks to prune"
    return
  }

  for $bookmark in $bookmarks {
    let alias = ($bookmark.name | path basename)
    let target = ($bookmark.target | path expand)
    if not ($target | path exists) {
      print -e $"($alias) -> ($target) \(does not exist)"
      let reply = (input $"Remove bookmark? \(Y/n) " | str trim | str downcase)
      if $reply not-in ["y", "Y", ""] {
        continue
      }
      r, $alias
      print -e ""
    }
  }
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
