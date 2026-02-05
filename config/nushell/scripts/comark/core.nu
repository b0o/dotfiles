# Comark core - bookmark CRUD operations and helpers

use db.nu [dir db-path]

# Save a reference to the builtin cd before we shadow it with `export def cd`
alias builtin-cd = cd

# Initialize comark directory and database
export def init [] {
  let comark_dir = (dir)
  if not ($comark_dir | path exists) {
    print $"Creating comark directory: ($comark_dir)"
    mkdir $comark_dir
  }
  let db = (db-path)
  if not ($db | path exists) {
    '{"version": 1, "bookmarks": {}}' | save $db
  }
}

# Load the bookmark database, returns the bookmarks record (alias -> target)
export def load [] {
  init
  open (db-path) | get bookmarks
}

# Save the bookmark database (accepts bookmarks record via pipeline)
export def persist []: record -> nothing {
  let bookmarks = $in
  {version: 1 bookmarks: $bookmarks} | to json --indent 2 | save -f (db-path)
}

# Collapse $HOME prefix to ~ for storage
export def collapse-home [p: string] {
  let home = $env.HOME
  if ($p | str starts-with $"($home)/") {
    $"~($p | str substring ($home | str length)..)"
  } else if $p == $home {
    "~"
  } else {
    $p
  }
}

# Append trailing / to a path if it points to a directory
def trailing-slash [p: string] {
  let expanded = ($p | path expand)
  if ($expanded | path exists) and ($expanded | path type) == "dir" {
    if ($p | str ends-with '/') { $p } else { $"($p)/" }
  } else {
    $p | str trim --right --char '/'
  }
}

export def validate-alias [alias: string] {
  if not ($alias =~ '^[a-zA-Z0-9_,.][a-zA-Z0-9_,.-]*$') {
    error make -u {msg: $"invalid alias: ($alias)"}
  }
}

export def complete-alias [] {
  list | each {|row|
    {
      value: $row.name
      description: $row.target
      style: (
        if ($row.target | str ends-with '/') {
          {fg: yellow attr: b}
        } else {
          {fg: green}
        }
      )
    }
  }
}

# List all bookmarks
# Returns table with columns: name, target (display path with ~), path (expanded absolute path)
export def list [pattern?: string] {
  let bookmarks = load
  $bookmarks
  | transpose name raw_target
  | where { ($pattern | is-empty) or ($in.name | str contains $pattern) }
  | each {|row|
    let target = (trailing-slash $row.raw_target)
    let path = (trailing-slash ($row.raw_target | path expand))
    {name: $row.name target: $target path: $path}
  }
  | sort-by name
}

# Make a new bookmark
export def new [
  alias: string
  dest?: string
  --force (-f) # Overwrite existing bookmark
  --expand-symlinks (-e) # Expand symlinks in destination path (default: false)
] {
  validate-alias $alias
  let bookmarks = load
  let target = if ($dest | is-empty) { $env.PWD } else { $dest | path expand --no-symlink=(not $expand_symlinks) }
  let display_target = (collapse-home $target)

  if $alias in $bookmarks {
    let existing = ($bookmarks | get $alias)
    if not $force {
      print -e $"bookmark exists: ($alias) -> ($existing)"
      let reply = (input $"Overwrite bookmark ($alias) with ($display_target)? \(Y/n) " | str trim | str downcase)
      if $reply not-in ["y" "Y" ""] {
        print -e $"Cancelled"
        return
      }
    }
  }

  $bookmarks | upsert $alias $display_target | persist
  print $"($alias) -> ($display_target)"
}

# Remove a bookmark
export def remove [alias: string@complete-alias] {
  validate-alias $alias
  let bookmarks = load

  if $alias not-in $bookmarks {
    error make -u {msg: $"bookmark does not exist: ($alias)"}
  }

  let dest = ($bookmarks | get $alias)
  $bookmarks | reject $alias | persist
  print $"removed bookmark ($alias) -> ($dest)"
}

# Rename a bookmark
export def rename [old: string new: string] {
  validate-alias $old
  validate-alias $new
  let bookmarks = load

  if $old not-in $bookmarks {
    error make -u {msg: $"bookmark does not exist: ($old)"}
  }

  if $new in $bookmarks {
    error make -u {msg: $"bookmark exists: ($new)"}
  }

  let target = ($bookmarks | get $old)
  $bookmarks | reject $old | upsert $new $target | persist
  print $"bookmark ($old) renamed to ($new)"
}

# Print bookmark destination path
export def path [
  alias: string
  --expand (-e) # Print the expanded absolute path instead of the display path
] {
  validate-alias $alias
  let bookmarks = load

  if $alias not-in $bookmarks {
    error make -u {msg: $"bookmark does not exist: ($alias)"}
  }

  let raw = ($bookmarks | get $alias)
  if $expand {
    trailing-slash ($raw | path expand)
  } else {
    trailing-slash $raw
  }
}

# Find bookmarks that contain the given path, sorted by closest match (longest path first)
# With --direct, only direct ancestors are returned.
# By default, if the path is in a git worktree, bookmarks under the git root are also included,
# with sort order:
#   1. Direct ancestors within the git repo (longest first)
#   2. Siblings in the git repo (by relative distance, shorter is higher)
#   3. Direct ancestors outside the git repo (longest first)
export def find [
  path: string
  --direct (-d) # Disable smart search functionality, only return direct ancestors
] {
  let expanded_path = $path | path expand
  let bookmarks = list

  # Find direct ancestor bookmarks (path starts with bookmark path)
  let ancestors = (
    $bookmarks
    | each {|row|
      let path_normalized = $row.path | str trim --right --char '/'
      if ($expanded_path | str starts-with $path_normalized) {
        $row
      }
    }
    | compact
  )

  if $direct {
    return ($ancestors | sort-by { ($in.path | str length) } --reverse)
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
    return ($ancestors | sort-by { ($in.path | str length) } --reverse)
  }

  let git_root = $git_info.git_root
  let git_root_normalized = $git_root | str trim --right --char '/'

  # Split ancestors into those inside vs outside the git repo
  let ancestors_grouped = $ancestors | group-by {
      $in.path | str trim --right --char '/' | str starts-with $git_root_normalized
    }

  let ancestors_in_repo = $ancestors_grouped | get -o "true" | default [] | sort-by { $in.path | str length } --reverse
  let ancestors_outside_repo = $ancestors_grouped | get -o "false" | default [] | sort-by { $in.path | str length } --reverse

  # Find sibling bookmarks (under git root but not ancestors of the path)
  # Calculate relative distance: how many path components differ from the input path
  let ancestor_paths = $ancestors | get path | each { $in | str trim --right --char '/' }

  let siblings = (
    $bookmarks
    | each {|row|
      let path_normalized = $row.path | str trim --right --char '/'
      # Must be under git root but not already an ancestor
      if ($path_normalized | str starts-with $git_root_normalized) and ($path_normalized not-in $ancestor_paths) {
        # Calculate relative distance:
        # Find common prefix length, then count differing components in both paths
        let target_parts = $path_normalized | path split
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

# Change directory to bookmark
def --env _cd [alias?: string@complete-alias]: nothing -> nothing {
  if ($alias | is-empty) {
    builtin-cd ~
    return
  }
  validate-alias $alias
  let bookmarks = load

  if $alias not-in $bookmarks {
    error make -u {msg: $"bookmark does not exist: ($alias)"}
  }

  let target = ($bookmarks | get $alias | path expand)
  if not ($target | path exists) {
    error make -u {msg: $"bookmark destination does not exist: ($alias)"}
  }

  builtin-cd $target
}

# Change directory to bookmark
export alias cd = _cd

# Remove bookmarks that point to non-existent files
export def prune [
  --force (-f) # Skip confirmation prompt
] {
  let dead = (
    list
    | where { not ($in.path | str trim --right --char '/' | path exists) }
  )

  if ($dead | is-empty) {
    print -e "No bookmarks to prune"
    return
  }

  for $bookmark in $dead {
    print -e $"($bookmark.name) -> ($bookmark.target) \(does not exist)"
    if not $force {
      let reply = (input $"Remove bookmark? \(Y/n) " | str trim | str downcase)
      if $reply not-in ["y" "Y" ""] {
        continue
      }
    }
    remove $bookmark.name
    print -e ""
  }
}

export def command-not-found [cmd_name: string] {
  if not ($cmd_name | str starts-with ",") {
    return null
  }
  let bookmarks = load

  # Try the full command name (e.g. ",app" as a bookmark alias)
  # then the stripped version (e.g. "app")
  let alias = if $cmd_name in $bookmarks {
    $cmd_name
  } else {
    let stripped = ($cmd_name | str trim --left --char ',')
    if $stripped in $bookmarks {
      $stripped
    } else {
      return null
    }
  }

  let target = ($bookmarks | get $alias)
  $"(ansi yellow_italic)($cmd_name)(ansi reset) is a bookmark -> (ansi blue)($target)(ansi reset)\nrun: (ansi green)comark ($alias)(ansi reset)"
}
