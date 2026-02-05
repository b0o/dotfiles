# Comark core - bookmark CRUD operations and helpers

# TODO: store bookmarks in json file
# TODO: configurable default bookmark
# TODO: in l, and fzf, show direct symlink, not recursively expanded

# Get the comark directory path
export def comark-dir [] {
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
export def comark-init [] {
  let dir = (comark-dir)
  if not ($dir | path exists) {
    print $"Creating comark directory: ($dir)"
    mkdir $dir
  }
}

export def validate-alias [alias: string] {
  if not ($alias =~ '^[a-zA-Z0-9_,.][a-zA-Z0-9_,.-]*$') {
    error make -u {msg: $"invalid alias: ($alias)"}
  }
}

export def resolve-bookmark [
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

export def complete-alias [] {
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
