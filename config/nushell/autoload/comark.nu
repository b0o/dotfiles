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

def validate-alias [alias: string] {
  if not ($alias =~ '^[a-zA-Z0-9_,.][a-zA-Z0-9_,.-]*$') {
    error make -u {msg: $"invalid alias: ($alias)"}
  }
}

# Make a new bookmark
export def m, [
  alias: string
  dest?: string
  --force (-f)            # Overwrite existing bookmark
  --expand-symlinks (-e)  # Expand symlinks in destination path (default: false)
] {
  comark-init
  validate-alias $alias
  let bookmark_path = ($comark_dir | path join $alias)

  if ($bookmark_path | path exists) {
    if $force {
      r, $alias
    } else {
      error make -u {msg: $"bookmark exists: ($alias)"}
    }
  }

  let target = if ($dest | is-empty) { $env.PWD } else { $dest | path expand --no-symlink=(not $expand_symlinks) }
  ^ln -s $target $bookmark_path
  print $"($alias) -> ($target)"
}

# Remove a bookmark
export def r, [alias: string] {
  comark-init
  validate-alias $alias
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
  validate-alias $old
  validate-alias $new
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

def resolve-bookmark [alias: string] {
  let bookmark_path = ($comark_dir | path join $alias)
  if not ($bookmark_path | path exists --no-symlink ) {
    error make -u {msg: $"bookmark does not exist: ($alias)"}
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
  validate-alias $alias
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
  validate-alias $alias
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

# Parse fzf output with --print-query and --expect flags
# Returns: {query: string, key: string, selection: string}
def parse-fzf-output [output: string] {
  let lines = ($output | str trim | split row "\n")
  let line_count = ($lines | length)
  let first_line = ($lines | get 0? | default "")

  # Check if first line is a selection (contains tab) or a key
  let is_selection = ($first_line | str contains "\t")
  let first_is_key = $first_line in ["alt-d", "alt-f", "alt-/", "alt-i", "alt-u"]

  # Determine query based on line structure
  let query = if $is_selection or ($line_count == 2 and $first_is_key) {
    ""
  } else {
    $first_line
  }

  # Determine which key was pressed
  # Possible outputs:
  # - ["selection"] -> key = "", selection exists
  # - ["key", "selection"] -> key in line 0, selection in line 1
  # - ["query", "selection"] -> key = "", selection in line 1
  # - ["query", "key"] -> key in line 1, no selection
  # - ["query", "key", "selection"] -> key in line 1, selection in line 2
  let second_line = ($lines | get 1? | default "")
  let second_is_key = $second_line in ["alt-d", "alt-f", "alt-/", "alt-i", "alt-u"]
  let second_is_selection = ($second_line | str contains "\t")

  let key = if $is_selection {
    ""
  } else if $line_count == 2 and $first_is_key {
    $first_line
  } else if $line_count >= 2 and $second_is_key {
    $second_line
  } else {
    ""
  }

  # Determine the selected line
  let selection = if $is_selection {
    $first_line
  } else if $line_count == 2 and $second_is_selection {
    $second_line
  } else if $line_count == 3 {
    $lines | get 2
  } else {
    ""
  }

  {query: $query, key: $key, selection: $selection}
}

# Generate filtered bookmark list for fzf
def generate-filtered-bookmarks [filter: string, parent_path?: oneof<string,nothing>] {
  ls $comark_dir
  | where type == symlink
  | each {|e|
    let alias = $e.name | path basename
    let target = resolve-bookmark $alias
    let type = $target | path type
    {alias: $alias, target: $target, type: $type, entry: $"($alias)\t($target)"}
  }
  | where {|e|
    # Apply type filter
    let type_match = if $filter == "dir" {
      $e.type == "dir"
    } else if $filter == "file" {
      $e.type == "file"
    } else {
      true
    }

    # Apply parent path filter
    let parent_match = if ($parent_path | is-empty) {
      true
    } else {
      ($e.target | str starts-with $parent_path)
    }

    $type_match and $parent_match
  }
  | get entry
  | str join "\n"
}

# Select bookmark with fzf
export def f, [
  query?: string
  --directory (-d)  # Only show bookmarks that point to a directory
  --file (-f)       # Only show bookmarks that point to a file
] {
  comark-init

  if ($directory and $file) {
    error make -u {msg: "--directory and --file are mutually exclusive"}
  }

  mut current_filter = if $directory { "dir" } else if $file { "file" } else { "all" }
  mut current_query = ($query | default "")
  mut current_parent_path = null  # Filter to bookmarks under this path
  mut current_parent_alias = null  # Alias of the parent bookmark

  while true {
    let bookmark_list = (generate-filtered-bookmarks $current_filter $current_parent_path)

    if ($bookmark_list | is-empty) {
      return ""
    }

    let base_prompt = match $current_filter {
      "dir" => "dirs> ",
      "file" => "files> ",
      _ => "> "
    }

    let prompt = if ($current_parent_alias | is-not-empty) {
      $"($current_parent_alias) ($base_prompt)"
    } else {
      $base_prompt
    }

    let sel = (
      $bookmark_list
      | ^fzf --layout=reverse --delimiter='\t' --nth='1' --with-nth=1,2
             --query $current_query --tiebreak=begin,chunk
             --preview $"eza -TlaF -L1 --group-directories-first --color=always --git --extended --follow-symlinks {2}"
             --bind 'alt-,:change-nth(1,2|1)'
             --bind 'alt-/:accept'
             --bind 'alt-i:accept'
             --bind 'alt-u:accept'
             --expect='alt-/,alt-d,alt-f,alt-i,alt-u'
             --print-query
             --prompt $prompt
             --no-exit-0
             --preview-border=none --separator='─' --scrollbar='▌'
      | complete
    )

    # Exit code 1 with output means a special key was pressed (like alt-d/alt-f)
    # Exit code 1 without output means user cancelled (ESC)
    # Exit code 0 means normal selection
    if ($sel.stdout | is-empty) {
      return ""
    }

    if $sel.exit_code != 0 {
      # Check if we have a valid key in the output
      let parsed = (parse-fzf-output $sel.stdout)
      if $parsed.key not-in ["alt-d", "alt-f", "alt-/", "alt-i", "alt-u"] {
        # User cancelled, exit
        return ""
      }
      # Valid key pressed, continue processing
    }

    let parsed = (parse-fzf-output $sel.stdout)

    # Handle filter toggle keys (even if no selection)
    if $parsed.key == "alt-d" {
      $current_filter = if $current_filter == "dir" { "all" } else { "dir" }
      $current_query = $parsed.query
      continue
    } else if $parsed.key == "alt-f" {
      $current_filter = if $current_filter == "file" { "all" } else { "file" }
      $current_query = $parsed.query
      continue
    }

    # Handle alt-i: filter by parent directory
    if $parsed.key == "alt-i" {
      # Need a selection to use as parent
      if ($parsed.selection | is-empty) {
        continue
      }

      let selection_parts = ($parsed.selection | split row "\t")
      let bookmark_alias = ($selection_parts | get 0? | default "")
      let bookmark_path = ($selection_parts | get 1? | default "")

      # Only works for directories
      if ($bookmark_path | str ends-with '/') {
        $current_parent_path = $bookmark_path
        $current_parent_alias = $bookmark_alias
        $current_query = ""
        continue
      }

      # If not a directory, just ignore
      continue
    }

    # Handle alt-u: clear parent filter and return to all bookmarks
    if $parsed.key == "alt-u" {
      $current_parent_path = null
      $current_parent_alias = null
      $current_query = $parsed.query
      continue
    }

    # For non-filter keys, we need a selection to proceed
    if ($parsed.selection | is-empty) {
      return ""
    }

    let selection_parts = ($parsed.selection | split row "\t")
    let bookmark_name = ($selection_parts | first)
    let bookmark_path = ($selection_parts | get 1? | default "")

    # If alt-/ was pressed, search for files in the bookmark directory
    if $parsed.key == "alt-/" {
      # If bookmark points to a file, just return it
      if not ($bookmark_path | str ends-with '/') {
        return $bookmark_path
      }

      # Save the current query to restore later
      let saved_query = $parsed.query

      mut search_depth = 1  # Start with non-recursive (only immediate files)
      mut go_back_to_bookmarks = false
      mut file_query = ""

      while not $go_back_to_bookmarks {
        # Search for files in the directory with current depth
        let file_list = (
          ^fd --type f --hidden --exclude .git --max-depth $search_depth . $bookmark_path
        )

        let depth_indicator = if $search_depth == 999 { "∞" } else { $search_depth }

        let file_sel = (
          $file_list
          | ^fzf --layout=reverse
                 --query $file_query
                 --preview 'bat --color=always --style=numbers {}'
                 --expect='alt-,,alt-/,alt-.,alt-1,alt-2,alt-3,alt-4,alt-5,alt-6,alt-7,alt-8,alt-9'
                 --print-query
                 --prompt $"depth:($depth_indicator) > "
                 --no-exit-0
                 --preview-border=none --separator='─' --scrollbar='▌'
          | complete
        )

        if ($file_sel.stdout | is-empty) {
          # User cancelled file search (ESC/Ctrl-C), go back to bookmark selection
          $current_query = $saved_query
          $go_back_to_bookmarks = true
          continue
        }

        let file_lines = ($file_sel.stdout | str trim | split row "\n")
        # With --print-query: [query, key/selection, selection?]
        let file_query_out = ($file_lines | get 0? | default "")
        let file_key = ($file_lines | get 1? | default "")

        # If alt-, pressed, go back to bookmark selection with saved query
        if $file_key == "alt-," {
          $current_query = $saved_query
          $go_back_to_bookmarks = true
          continue
        }

        # Handle depth increase/decrease
        if $file_key == "alt-/" {
          # Increase depth and preserve query
          if $search_depth < 999 {
            $search_depth = $search_depth + 1
          }
          $file_query = $file_query_out
          continue
        } else if $file_key == "alt-." {
          # Decrease depth (minimum 1) and preserve query
          if $search_depth > 1 {
            $search_depth = $search_depth - 1
          }
          $file_query = $file_query_out
          continue
        }

        # Handle absolute depth changes
        if $file_key == "alt-1" {
          $search_depth = 1
          $file_query = $file_query_out
          continue
        } else if $file_key == "alt-2" {
          $search_depth = 2
          $file_query = $file_query_out
          continue
        } else if $file_key == "alt-3" {
          $search_depth = 3
          $file_query = $file_query_out
          continue
        } else if $file_key == "alt-4" {
          $search_depth = 4
          $file_query = $file_query_out
          continue
        } else if $file_key == "alt-5" {
          $search_depth = 5
          $file_query = $file_query_out
          continue
        } else if $file_key == "alt-6" {
          $search_depth = 6
          $file_query = $file_query_out
          continue
        } else if $file_key == "alt-7" {
          $search_depth = 7
          $file_query = $file_query_out
          continue
        } else if $file_key == "alt-8" {
          $search_depth = 8
          $file_query = $file_query_out
          continue
        } else if $file_key == "alt-9" {
          $search_depth = 999  # Effectively unlimited
          $file_query = $file_query_out
          continue
        }

        # Otherwise return the selected file
        let file_path = if ($file_lines | length) > 2 {
          $file_lines | get 2
        } else {
          $file_lines | get 1? | default ""
        }

        if not ($file_path | is-empty) {
          return $file_path
        }

        # If no file selected, restore query and continue to bookmark selection
        $current_query = $saved_query
        $go_back_to_bookmarks = true
      }

      # Continue to outer loop (bookmark selection)
      continue
    }

    return $bookmark_name
  }
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
export def --env fzf,smart [
  query?: string    # Initial fzf query
  --directory (-d)  # Only show bookmarks that point to a directory
  --file (-f)       # Only show bookmarks that point to a file
] {
  let line_buffer = (commandline)
  let cursor_pos = (commandline get-cursor)
  let before_cursor = ($line_buffer | str substring 0..<$cursor_pos)
  let after_cursor = ($line_buffer | str substring $cursor_pos..)

  # Empty buffer: cd to dir bookmark, insert file bookmark
  if ($line_buffer | str trim | is-empty) {
    let result = (f, --file=$file --directory=$directory $query)
    if ($result | is-empty) { return }

    # Check if result is already a full path (from Ctrl-i) or a bookmark name
    if ($result | str starts-with '/') {
      # Direct path from Ctrl-i - insert it
      insert-at-cursor $result
    } else {
      # Bookmark name - resolve and handle
      let path = (p, $result)
      if ($path | str ends-with '/') {
        cd, $result
      } else {
        insert-at-cursor $path
      }
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
    let result = (f, $bookmark_name)
    if not ($result | is-empty) {
      # Check if result is already a full path (from Ctrl-i) or a bookmark name
      let path = if ($result | str starts-with '/') {
        $result
      } else {
        p, $result
      }
      commandline edit --replace ($prefix + $path + $after_cursor)
      commandline set-cursor (($prefix | str length) + ($path | str length))
    }
    return
  }

  # Default: insert at cursor
  let result = (f,)
  if not ($result | is-empty) {
    # Check if result is already a full path (from Ctrl-i) or a bookmark name
    let path = if ($result | str starts-with '/') {
      $result
    } else {
      p, $result
    }
    insert-at-cursor $path
  }
}
