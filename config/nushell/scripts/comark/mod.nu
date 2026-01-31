# Comark (Comma Bookmark) for Nushell
# Shell bookmark manager and file search utility for quick navigation and file management

# TODO: store bookmarks in json file
# TODO: configurable default bookmark
# TODO: in l, and fzf, show direct symlink, not recursively expanded

# Get the comark directory path
def comark-dir [] {
  $env
  | get -o COMARK_DIR
  | default (
    $env
    | get -o XDG_CONFIG_HOME
    | default ($env.HOME | path join ".config")
    | path join "comark"
  )
}

# Initialize comark directory
def comark-init [] {
  let dir = (comark-dir)
  if not ($dir | path exists) {
    print $"Creating comark directory: ($dir)"
    mkdir $dir
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
  let bookmark_path = ((comark-dir) | path join $alias)
  let target = if ($dest | is-empty) { $env.PWD } else { $dest | path expand --no-symlink=(not $expand_symlinks) }

  if ($bookmark_path | path exists --no-symlink) {
    if not $force {
      print -e $"bookmark exists: ($alias) -> (resolve-bookmark $alias)"
      let reply = (input $"Overwrite bookmark ($alias) with ($target)? \(Y/n) " | str trim | str downcase)
      if $reply not-in ["y", "Y", ""] {
        print -e $"Cancelled"
        return
      }
    }
    r, $alias
  }

  ^ln -s $target $bookmark_path
  print $"($alias) -> ($target)"
}

def complete-alias [] {
  l, | each { |row|
    {
      value: $row.name
      description: $row.target
      style: (
        if ($row.target | str ends-with '/') {
          { fg: yellow attr: b }
        } else {
          { fg: green }
        }
      )
    }
  }
}

# Remove a bookmark
export def r, [alias: string@complete-alias] {
  comark-init
  validate-alias $alias
  let bookmark_path = ((comark-dir) | path join $alias)

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
  let old_path = ((comark-dir) | path join $old)
  let new_path = ((comark-dir) | path join $new)

  if not ($old_path | path exists --no-symlink) {
    error make -u {msg: $"bookmark does not exist: ($old)"}
  }

  if ($new_path | path exists --no-symlink) {
    error make -u {msg: $"bookmark exists: ($new)"}
  }

  mv $old_path $new_path
  print $"bookmark ($old) renamed to ($new)"
}

def resolve-bookmark [
  --direct (-d) # Resolve direct symlink only (not recursively)
  alias: string
] {
  let bookmark_path = (comark-dir) | path join $alias
  if not ($bookmark_path | path exists --no-symlink ) {
    error make -u {msg: $"bookmark does not exist: ($alias)"}
  }
  # symlink exists but points to a non-existent file
  # use realpath to resolve the symlink
  if not ($bookmark_path | path exists) {
    return (realpath -m $bookmark_path)
  }
  let target = ($bookmark_path | path expand)
  let res = if $direct { readlink $bookmark_path } else { $target }
  if ($target | path type) == "dir" {
    return $"($res)/"
  }
  $res
}

# Print bookmark destination path
export def p, [alias: string] {
  comark-init
  validate-alias $alias
  resolve-bookmark $alias
}

# Find bookmarks that contain the given path, sorted by closest match (longest target first)
# With --direct, only direct ancestors are returned.
# By default, if the path is in a git worktree, bookmarks under the git root are also included,
# with sort order:
#   1. Direct ancestors within the git repo (longest first)
#   2. Siblings in the git repo (by relative distance, shorter is higher)
#   3. Direct ancestors outside the git repo (longest first)
export def find, [
  path: string
  --direct (-d) # Disable smart search functionality, only return direct ancestors
] {
  let expanded_path = $path | path expand
  let bookmarks = l,

  # Find direct ancestor bookmarks (path starts with bookmark target)
  let ancestors = (
    $bookmarks
    | each {|row|
      let target_normalized = $row.target | str trim --right --char '/'
      if ($expanded_path | str starts-with $target_normalized) {
        $row
      }
    }
    | compact
  )

  if $direct {
    return ($ancestors | sort-by { ($in.target | str length) } --reverse)
  }

  use git/worktree.nu gw-parse

  # gw-parse needs a directory, so use dirname if path is a file
  let git_path = if ($expanded_path | path type) == "file" {
    $expanded_path | path dirname
  } else {
    $expanded_path
  }
  let git_info = do --ignore-errors { gw-parse $git_path }
  if ($git_info | is-empty) {
    return ($ancestors | sort-by { ($in.target | str length) } --reverse)
  }

  let git_root = $git_info.git_root
  let git_root_normalized = $git_root | str trim --right --char '/'

  # Split ancestors into those inside vs outside the git repo
  let ancestors_grouped = $ancestors | group-by {
    $in.target | str trim --right --char '/' | str starts-with $git_root_normalized
  }

  let ancestors_in_repo = $ancestors_grouped | get -o "true" | default [] | sort-by { $in.target | str length } --reverse
  let ancestors_outside_repo = $ancestors_grouped | get -o "false" | default [] | sort-by { $in.target | str length } --reverse

  # Find sibling bookmarks (under git root but not ancestors of the path)
  # Calculate relative distance: how many path components differ from the input path
  let ancestor_targets = $ancestors | get target | each { $in | str trim --right --char '/' }

  let siblings = (
    $bookmarks
    | each {|row|
      let target_normalized = $row.target | str trim --right --char '/'
      # Must be under git root but not already an ancestor
      if ($target_normalized | str starts-with $git_root_normalized) and ($target_normalized not-in $ancestor_targets) {
        # Calculate relative distance:
        # Find common prefix length, then count differing components in both paths
        let target_parts = $target_normalized | path split
        let path_parts = $expanded_path | path split

        # Find the length of common prefix
        let min_len = [($target_parts | length) ($path_parts | length)] | math min
        mut common_len = 0
        for i in 0..<$min_len {
          if ($target_parts | get $i) == ($path_parts | get $i) {
            $common_len = $common_len + 1
          } else {
            break
          }
        }
        let distance = (($target_parts | length) - $common_len) + (($path_parts | length) - $common_len)
        $row | insert distance $distance
      }
    }
    | compact
    | sort-by distance
  )

  $ancestors_in_repo
  | append ($siblings | reject distance)
  | append $ancestors_outside_repo
}

# List all bookmarks
export def l, [pattern?: string] {
  comark-init

  let bookmarks = (
    ls (comark-dir)
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

  $bookmarks
}


# Change directory to bookmark
export def --env cd, [alias?: string@complete-alias]: nothing -> nothing {
  if ($alias | is-empty) {
    cd ~ # TODO: cd to "default" bookmark (when JSON file is implemented)
    return
  }
  comark-init
  validate-alias $alias
  let bookmark_path = ((comark-dir) | path join $alias)

  if not ($bookmark_path | path exists --no-symlink) {
    error make -u {msg: $"bookmark does not exist: ($alias)"}
  }
  # symlink exists but points to a non-existent file
  if not ($bookmark_path | path exists) {
    error make -u  {msg: $"bookmark destination does not exist: ($alias)"}
  }

  cd ($bookmark_path | path expand)
}

# Quote a path for Nushell if it contains spaces or special characters
def quote-path [path: string] {
  # Check if path needs quoting (contains spaces or special chars)
  if ($path | str contains ' ') or ($path | str contains '(') or ($path | str contains ')') or ($path | str contains '&') or ($path | str contains '|') or ($path | str contains ';') or ($path | str contains '$') or ($path | str contains '"') or ($path | str contains "'") or ($path | str contains '#') or ($path | str contains '`') {
    # Use double quotes and escape any embedded double quotes
    let escaped = ($path | str replace --all '"' '\"')
    $'"($escaped)"'
  } else {
    $path
  }
}

# Parse fzf output with --print-query and --expect flags
# Returns: {query: string, key: string, selection: string}
def parse-fzf-output [output: string] {
  let lines = ($output | str trim | split row "\n")
  let line_count = ($lines | length)
  let first_line = ($lines | get 0? | default "")

  # Check if first line is a selection (contains tab) or a key
  let is_selection = ($first_line | str contains "\t")
  let first_is_key = $first_line in ["alt-,", "alt-d", "alt-f", "alt-/", "alt-i", "alt-u"]

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
  let second_is_key = $second_line in ["alt-,", "alt-d", "alt-f", "alt-/", "alt-i", "alt-u"]
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

# File search with depth control
# Returns the selected file path or empty string
def file-search [
  directory: string     # Directory to search in (absolute path for fd)
  saved_query: string   # Initial query
  display_base: string  # Base path for display (e.g., "./" or "~/Documents/")
] {
  mut search_depth = 1  # Start with non-recursive (only immediate files)
  mut file_query = $saved_query
  mut current_dir = $directory
  mut current_display_base = $display_base
  mut current_filter = "all"  # Can be "all", "dir", or "file"
  mut show_ignored = false  # Whether to show VCS ignored files
  mut show_absolute = false  # Whether to show absolute paths

  while true {
    # Build fd command with type filter
    let type_args = if $current_filter == "dir" {
      ["--type", "d"]
    } else if $current_filter == "file" {
      ["--type", "f"]
    } else {
      []
    }

    # Build fd command with ignore flag
    let ignore_args = if $show_ignored {
      ["-I"]
    } else {
      []
    }

    # Search for files and directories with current depth
    # Transform paths to use display base prefix (normalize slashes)
    let display_prefix = $current_display_base | str trim --right --char '/'
    let search_dir = $current_dir | str trim --right --char '/'
    let use_absolute = $show_absolute
    let file_list = (
      ^fd --follow --hidden --exclude .git --max-depth $search_depth ...$type_args ...$ignore_args . $current_dir
      | lines
      | each { |p|
        if $use_absolute {
          $p
        } else {
          # fd returns paths with search_dir prefix - strip it and use display prefix instead
          let rel = $p | str replace $search_dir '' | str trim --left --char '/'
          $"($display_prefix)/($rel)"
        }
      }
      | str join "\n"
    )

    let depth_indicator = "󰙅 " + (if $search_depth == 999 { "∞" } else { $"($search_depth)" })
    let dir_name = ($current_dir | path basename)

    let filter_indicator = match $current_filter {
      "dir" => "󰈲 dirs",
      "file" => "󰈲 files",
      _ => " "
    }

    let ignore_indicator = (if $show_ignored { "󰄱 gitignore" } else { "󰄵 gitignore" })
    let path_indicator = (if $show_absolute { "󰝰 abs" } else { "󰝰 rel" })

    let info = [
      "󰘵 a ignore    󰘵 d 󰈲 dirs    󰘵 u up dir   󰘵 / depth+"
      "󰘵 , go back   󰘵 f 󰈲 files   󰘵 i in dir   󰘵 . depth-"
      "󰘵 o cur dir   󰘵 e abs/rel"
    ] | str join "\n"

    let file_sel = (
      $file_list
      | ^fzf --layout=reverse
      --query $file_query
      --expect='alt-,,alt-/,alt-.,alt-a,alt-d,alt-e,alt-f,alt-i,alt-o,alt-u,alt-1,alt-2,alt-3,alt-4,alt-5,alt-6,alt-7,alt-8,alt-9'
      --print-query
      --no-exit-0
      --prompt $"($ignore_indicator)  ($filter_indicator)  ($path_indicator)  ($depth_indicator)   "
      --header $search_dir
      --footer $info
      | complete
    )

    if ($file_sel.stdout | is-empty) {
      # User cancelled file search
      return ""
    }

    let file_lines = ($file_sel.stdout | str trim | split row "\n")
    # With --print-query and --expect, fzf outputs: query, key, selection
    # But when query is empty and a key is pressed, fzf outputs: key, selection (query line is omitted)
    let line0 = ($file_lines | get 0? | default "")
    let line1 = ($file_lines | get 1? | default "")
    let line2 = ($file_lines | get 2? | default "")

    # Check if line0 or line1 is a key we expect
    let line0_is_key = $line0 in ["alt-,", "alt-/", "alt-.", "alt-a", "alt-d", "alt-e", "alt-f", "alt-i", "alt-o", "alt-u", "alt-1", "alt-2", "alt-3", "alt-4", "alt-5", "alt-6", "alt-7", "alt-8", "alt-9"]
    let line1_is_key = $line1 in ["alt-,", "alt-/", "alt-.", "alt-a", "alt-d", "alt-e", "alt-f", "alt-i", "alt-o", "alt-u", "alt-1", "alt-2", "alt-3", "alt-4", "alt-5", "alt-6", "alt-7", "alt-8", "alt-9"]

    let file_query_out = if $line0_is_key { "" } else { $line0 }
    let file_key = if $line0_is_key { $line0 } else if $line1_is_key { $line1 } else { "" }
    # Parse selection based on number of lines:
    # 1 line: just selection (Enter with no query)
    # 2 lines: key+selection (key with no query) OR query+selection (Enter with query)
    # 3 lines: query+key+selection (key with query)
    let file_selection = if ($file_lines | length) >= 3 {
      $line2
    } else if $line0_is_key {
      $line1
    } else if ($file_lines | length) == 1 {
      $line0  # Single line = the selection itself
    } else {
      $line1
    }

    # If alt-, pressed, exit file search and return to bookmarks
    if $file_key == "alt-," {
      return ""
    }

    # If alt-o pressed, accept current directory
    if $file_key == "alt-o" {
      return (if $show_absolute { $current_dir } else { $current_display_base })
    }

    # Handle show ignored files toggle
    if $file_key == "alt-a" {
      $show_ignored = not $show_ignored
      $file_query = $file_query_out
      continue
    }

    # Handle absolute/relative path toggle
    if $file_key == "alt-e" {
      $show_absolute = not $show_absolute
      $file_query = $file_query_out
      continue
    }

    # Handle filter toggle keys
    if $file_key == "alt-d" {
      $current_filter = if $current_filter == "dir" { "all" } else { "dir" }
      $file_query = $file_query_out
      continue
    } else if $file_key == "alt-f" {
      $current_filter = if $current_filter == "file" { "all" } else { "file" }
      $file_query = $file_query_out
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

    # Handle directory navigation
    if $file_key == "alt-i" {
      # Enter the selected directory if it's a directory, otherwise accept the file
      if not ($file_selection | is-empty) {
        let selection_path = ($file_selection | path expand)
        if ($selection_path | path exists) and (($selection_path | path type) == "dir") {
          $current_dir = $selection_path
          $current_display_base = $file_selection
          $file_query = $file_query_out
          continue
        } else {
          # It's a file - accept it
          return $file_selection
        }
      }
      # No selection, just continue
      $file_query = $file_query_out
      continue
    } else if $file_key == "alt-u" {
      # Go up to parent directory
      let parent = ($current_dir | path dirname)
      if $parent != $current_dir {  # Make sure we're not at root
        $current_dir = $parent
        # Handle relative path display properly
        # path dirname doesn't work correctly for "." or ".." or paths ending in ".."
        let display_trimmed = $current_display_base | str trim --right --char '/'
        $current_display_base = if $display_trimmed == "." {
          ".."
        } else if $display_trimmed == ".." or ($display_trimmed | str ends-with "/..") {
          $"../($display_trimmed)"
        } else {
          $display_trimmed | path dirname
        }
      }
      $file_query = $file_query_out
      continue
    }

    # Otherwise return the selected file/directory
    if not ($file_selection | is-empty) {
      return $file_selection
    }
  }
}

# Generate filtered bookmark list for fzf
def generate-filtered-bookmarks [filter: string, parent_path?: oneof<string,nothing>] {
  ls (comark-dir)
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
  --directory (-d)          # Only show bookmarks that point to a directory
  --file (-f)               # Only show bookmarks that point to a file
  --path (-p): string       # Start directly in file search mode for this path
  --display-base: string    # Base path for display in file search (e.g., "./" or "~/")
  --record                  # Output result as nushell record like { alias?: string, path: string, is_root: bool }|null
] {
  comark-init

  if ($directory and $file) {
    error make -u {msg: "--directory and --file are mutually exclusive"}
  }

  # If --path is provided, skip bookmark selection and go straight to file search
  if ($path | is-not-empty) {
    let expanded_path = ($path | path expand)
    if ($expanded_path | path exists) and (($expanded_path | path type) == "dir") {
      # Use display_base if provided, otherwise use the original path
      let base = if ($display_base | is-not-empty) { $display_base } else { $path }
      let result = (file-search $expanded_path ($query | default "") $base)
      if $record {
        return { alias: null, path: $result, is_root: false }
      } else {
        return $result
      }
    } else {
      error make -u {msg: $"path does not exist or is not a directory: ($path)"}
    }
  }

  mut current_filter = if $directory { "dir" } else if $file { "file" } else { "all" }
  mut current_query = ($query | default "")
  mut current_parent_path = null  # Filter to bookmarks under this path
  mut current_parent_alias = null  # Alias of the parent bookmark
  mut search_mode = "alias"  # Can be "alias" (search alias only) or "full" (search alias and path)

  while true {
    let bookmark_list = (generate-filtered-bookmarks $current_filter $current_parent_path)

    if ($bookmark_list | is-empty) {
      return null
    }

    let filter_indicator = match $current_filter {
      "dir" => "󰈲 dirs",
      "file" => "󰈲 files",
      _ => " "
    }

    let parent_indicator = if ($current_parent_alias | is-not-empty) {
      $"󰉖 ($current_parent_alias)"
    } else {
      "Bookmarks"
    }

    let search_indicator = if $search_mode == "full" {
      "󰍉 full"
    } else {
      "󰍉 alias"
    }

    let info = [
      "󰘵 , search mode     󰘵 d 󰈲 dirs    󰘵 u up dir"
      "󰘵 / search inside   󰘵 f 󰈲 files   󰘵 i in dir"
    ] | str join "\n"

    # Determine which columns to search based on search mode
    let nth_arg = if $search_mode == "full" { "1,2" } else { "1" }

    let sel = (
      $bookmark_list
      | ^fzf --layout=reverse
      --delimiter '\t'
      --nth $nth_arg
      --with-nth 1,2
      --query $current_query
      --tiebreak begin,chunk
      --print-query
      --no-exit-0
      --preview 'bat --decorations=never --color=always {2} 2>/dev/null || eza -algF --git --group-directories-first -TL1 --color=always {2}'
      --bind 'alt-/:accept'
      --bind 'alt-i:accept'
      --bind 'alt-u:accept'
      --expect 'alt-,,alt-/,alt-d,alt-f,alt-i,alt-u'
      --prompt $"($parent_indicator)  ($filter_indicator)  ($search_indicator)   "
      --footer $info
      | complete
    )

    # Exit code 1 with output means a special key was pressed (like alt-d/alt-f)
    # Exit code 1 without output means user cancelled (ESC)
    # Exit code 0 means normal selection
    if ($sel.stdout | is-empty) {
      return null
    }

    if $sel.exit_code != 0 {
      # Check if we have a valid key in the output
      let parsed = (parse-fzf-output $sel.stdout)
      if $parsed.key not-in ["alt-,", "alt-d", "alt-f", "alt-/", "alt-i", "alt-u"] {
        # User cancelled, exit
        return null
      }
      # Valid key pressed, continue processing
    }

    let parsed = (parse-fzf-output $sel.stdout)

    # Handle search mode toggle
    if $parsed.key == "alt-," {
      $search_mode = if $search_mode == "alias" { "full" } else { "alias" }
      $current_query = $parsed.query
      continue
    }

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
      return null
    }

    let selection_parts = ($parsed.selection | split row "\t")
    let bookmark_name = ($selection_parts | first)
    let bookmark_path = ($selection_parts | get 1? | default "")

    # If alt-/ was pressed, search for files in the bookmark directory
    if $parsed.key == "alt-/" {
      # If bookmark points to a file, just return it
      if not ($bookmark_path | str ends-with '/') {
        return (if $record {
          { alias: $bookmark_name, path: $bookmark_path, is_root: true }
        } else {
          $bookmark_path
        })
      }

      # Enter file search mode - use bookmark path (without trailing /) as display base
      let display_path = ($bookmark_path | str trim --right --char '/')
      let result = (file-search $bookmark_path $parsed.query $display_path)

      if not ($result | is-empty) {
        # return $result
        return (if $record {
          { alias: $bookmark_name, path: $result, is_root: (($result | path expand) == ($bookmark_path | path expand)) }
        } else {
          $result
        })
      }

      # If empty (user pressed alt-,), restore query and continue to bookmark selection
      $current_query = $parsed.query
      continue
    }

    return (if $record {
      { alias: $bookmark_name, path: $bookmark_path, is_root: true }
    } else {
      $bookmark_name
    })
  }
}

# Remove bookmarks that point to non-existent files
export def prune, [
  --force (-f)  # Skip confirmation prompt
] {
  let bookmarks = (
    ls (comark-dir)
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
    let result = f, --record --file=$file --directory=$directory $query
    if ($result | is-empty) { return }

    if not ($result.is_root) {
      insert-at-cursor (quote-path $result.path)
    } else {
      if ($result.path | path type) == "dir" {
        cd $result.path
      } else {
        insert-at-cursor (quote-path $result.path)
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
      let quoted_path = (quote-path $bookmark_path)
      commandline edit --replace ($prefix + $quoted_path + $after_cursor)
      commandline set-cursor (($prefix | str length) + ($quoted_path | str length))
      return
    }

    # Try fuzzy search with query
    let result = (f, $bookmark_name)
    if not ($result | is-empty) {
      # Check if result is already a full path (from file search) or a bookmark name
      let path = if ($result | str starts-with '/') {
        quote-path $result
      } else {
        quote-path (p, $result)
      }
      commandline edit --replace ($prefix + $path + $after_cursor)
      commandline set-cursor (($prefix | str length) + ($path | str length))
    }
    return
  }

  # Default: insert at cursor
  let result = (f,)
  if not ($result | is-empty) {
    # Check if result is already a full path (from file search) or a bookmark name
    let path = if ($result | str starts-with '/') {
      quote-path $result
    } else {
      quote-path (p, $result)
    }
    insert-at-cursor $path
  }
}

# edits the current commandline to search for the path at the cursor position
# using comark's file search with depth control
export def fzf,path [] {
  let line_buffer = (commandline)
  let cursor_pos = (commandline get-cursor)

  # Find word boundaries around cursor position
  let before_cursor = ($line_buffer | str substring 0..<$cursor_pos)
  let after_cursor = ($line_buffer | str substring $cursor_pos..)

  # Check if we're inside a quoted string
  let quote_info = if ($before_cursor | str ends-with '"') or ($before_cursor | str ends-with "'") {
    # Cursor is on closing quote
    let quote_char = ($before_cursor | str substring (($before_cursor | str length) - 1)..)
    let before_quote = ($before_cursor | str substring 0..<(($before_cursor | str length) - 1))
    let quote_start = ($before_quote | str reverse | str index-of $quote_char)
    if $quote_start != -1 {
      let start_pos = (($before_quote | str length) - 1 - $quote_start)
      {
        quoted: true,
        start: $start_pos,
        end: $cursor_pos,
        quote_char: $quote_char
      }
    } else {
      {quoted: false}
    }
  } else {
    # Search backwards for opening quote
    let double_quote_idx = ($before_cursor | str reverse | str index-of '"')
    let single_quote_idx = ($before_cursor | str reverse | str index-of "'")

    let quote_match = if $double_quote_idx != -1 and ($single_quote_idx == -1 or $double_quote_idx < $single_quote_idx) {
      {char: '"', idx: $double_quote_idx}
    } else if $single_quote_idx != -1 {
      {char: "'", idx: $single_quote_idx}
    } else {
      null
    }

    if $quote_match != null {
      # Check if there's a closing quote after cursor
      let closing_idx = ($after_cursor | str index-of $quote_match.char)
      let start_pos = (($before_cursor | str length) - $quote_match.idx - 1)
      if $closing_idx != -1 {
        # Properly closed quoted string
        {
          quoted: true,
          start: $start_pos,
          end: ($cursor_pos + $closing_idx + 1),
          quote_char: $quote_match.char
        }
      } else {
        # Unclosed quoted string - treat as quoted until end of line
        {
          quoted: true,
          unclosed: true,
          start: $start_pos,
          end: ($line_buffer | str length),
          quote_char: $quote_match.char
        }
      }
    } else {
      {quoted: false}
    }
  }

  # Find word boundaries based on whether we're in quotes
  let word_bounds = if $quote_info.quoted {
    {start: $quote_info.start, end: $quote_info.end}
  } else {
    # Find where the current word starts (last space before cursor, or beginning)
    let word_start = if ($before_cursor | str contains ' ') {
      let reversed = ($before_cursor | str reverse)
      let space_pos = ($reversed | str index-of ' ')
      if $space_pos == -1 {
        0
      } else {
        ($before_cursor | str length) - $space_pos
      }
    } else {
      0
    }

    # Find where the current word ends (first space after cursor, or end)
    let word_end = if ($after_cursor | str contains ' ') {
      let first_space = ($after_cursor | str index-of ' ')
      $cursor_pos + $first_space
    } else {
      $line_buffer | str length
    }

    {start: $word_start, end: $word_end}
  }

  # Extract the current word and the parts before/after it
  let current_word_raw = ($line_buffer | str substring $word_bounds.start..<$word_bounds.end)
  let prefix = ($line_buffer | str substring 0..<$word_bounds.start)
  let suffix = ($line_buffer | str substring $word_bounds.end..)

  # If quoted, strip the quotes for processing
  let current_word = if $quote_info.quoted {
    if ($quote_info | get -o unclosed | default false) {
      # Unclosed quote - only strip opening quote
      $current_word_raw | str substring 1..
    } else {
      # Closed quote - strip both opening and closing quotes
      $current_word_raw | str substring 1..<(($current_word_raw | str length) - 1)
    }
  } else {
    $current_word_raw
  }

  # Detect the original path style for preservation
  let path_style = if ($current_word | str starts-with '~/') or ($current_word == '~') {
    {type: "tilde", prefix: "~"}
  } else if ($current_word | str starts-with './') or ($current_word == '.') {
    {type: "dot", prefix: "."}
  } else if ($current_word | str starts-with '../') or ($current_word == '..') {
    {type: "dotdot", prefix: ".."}
  } else if not ($current_word | str starts-with '/') {
    # Prefix-less relative paths (including empty) are treated as "./" style
    {type: "dot", prefix: "."}
  } else {
    {type: "other", prefix: ""}
  }

  # Expand tilde for path operations
  let expanded_word = ($current_word | path expand)

  # Helper to format display path based on style
  let format_display = {|p|
    if $path_style.type == "dot" and not ($current_word | str starts-with './') and $p != "." {
      $"./($p)"
    } else {
      $p
    }
  }

  # Determine search directory, initial query, and display base
  let search_info = if ($current_word | str trim | is-empty) {
    {dir: ".", query: "", display_base: "."}
  } else if ($expanded_word | path exists) and ($expanded_word | path type) == "dir" {
    let display = do $format_display ($current_word | str trim --right --char '/')
    {dir: $expanded_word, query: "", display_base: $display}
  } else {
    # Path doesn't exist or is a file - use parent dir and basename as query
    let parent_dir = ($expanded_word | path dirname)
    let basename = ($expanded_word | path basename)
    if ($parent_dir | path exists) {
      let parent_display = $current_word | path dirname
      let display = do $format_display $parent_display
      {dir: $parent_dir, query: $basename, display_base: $display}
    } else {
      {dir: ".", query: "", display_base: "."}
    }
  }

  # Use comark's file search
  let selected = (f, $search_info.query --path $search_info.dir --display-base $search_info.display_base)

  # If something was selected, update the commandline
  if not ($selected | is-empty) {
    # Result is already in display format from file-search
    let result = $selected

    # Build the new buffer with the selected item replacing the current word
    # Re-add quotes if original was quoted (and close if it was unclosed)
    # Or add quotes if the result needs them (has spaces/special chars)
    let final_result = if $quote_info.quoted {
      $quote_info.quote_char + $result + $quote_info.quote_char
    } else {
      quote-path $result
    }

    let new_buffer = $prefix + $final_result + $suffix

    # Position cursor at the end of the inserted result
    let new_cursor_pos = ($prefix | str length) + ($final_result | str length)

    commandline edit --replace $new_buffer
    commandline set-cursor $new_cursor_pos
  }
}

export def "comark generate-autoload" [] {
  [
    "use comark *\n"
    ...(l, | each { |row|
      $"# cd ($row.target)\nexport alias ,($row.name) = cd, ($row.name)"
    })
  ] | str join "\n"
}

export def "comark generate-autoload-hash" [] {
  try {
    glob $"(comark-dir)/*"
      | par-each { $in ++ ":" ++ ($in | path expand) }
      | sort
      | str join "\n"
      | hash md5
  } catch {
    ""
  }
}
