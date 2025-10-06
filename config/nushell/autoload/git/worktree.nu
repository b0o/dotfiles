# Print git repo and worktree information
export def gw-parse [path?: string] {
  let dir = $path | default $env.PWD

  let result = (do {
    cd -P $dir
    git worktree list --porcelain
  } | complete)

  if $result.exit_code != 0 {
    error make -u {msg: $"git command failed: ($result.stderr)"}
  }

  # Parse the porcelain output
  let lines = $result.stdout | lines

  mut root = ""
  mut worktrees = {}
  mut bare = false
  mut current_worktree = null

  for line in $lines {
    if ($line | str starts-with "bare") {
      $bare = true
    } else if ($line | str starts-with "worktree ") {
      let worktree_path = ($line | str substring 9..)
      if ($root | is-empty) {
        $root = $worktree_path
      } else {
        # Make path relative to root and remove leading slash
        $current_worktree = ($worktree_path
          | str replace $root ""
          | str trim --left --char '/')
      }
    } else if ($line | str starts-with "branch ") {
      if $current_worktree != null {
        let branch_ref = ($line | str substring 7..)
        # Get abbreviated branch name
        let branch_result = (git rev-parse --abbrev-ref $branch_ref | complete)
        let branch = if $branch_result.exit_code == 0 and ($branch_result.stdout | str trim | is-not-empty) {
          $branch_result.stdout | str trim
        } else {
          $branch_ref
        }

        $worktrees = ($worktrees | insert $current_worktree $branch)
        $current_worktree = null
      }
    }
  }

  {
    git_root: $root,
    git_worktrees: $worktrees,
    git_bare: $bare
  }
}

# Select a git worktree (for scripting)
export def gw-select [
  target?: string              # Target worktree or branch name
  --ignore-cwd (-c)            # Don't ignore current worktree in candidates
  --prefill-cwd (-C)           # Prefill fzf with current worktree
  --header (-H): string        # Custom fzf header
] {
  let ignore_cwd = not $ignore_cwd

  let git_info = (gw-parse)

  if ($git_info.git_worktrees | is-empty) {
    error make -u {msg: "no worktrees"}
  }

  let git_root = $git_info.git_root
  let git_worktrees = $git_info.git_worktrees
  let git_bare = $git_info.git_bare

  let candidates = ([""] | append ($git_worktrees | columns))

  # Find current worktree by checking which worktree path contains PWD
  mut current_worktree = ""
  mut current_worktree_relative_path = ""
  mut other_worktrees = []

  mut target_resolved = $target

  for w in $candidates {
    # Check if target matches a branch name
    if $target != null and ($git_worktrees | get -o $w) == $target {
      $target_resolved = $w
    }

    let worktree_path = if $w == "" {
      $git_root
    } else {
      [$git_root $w] | path join
    }

    # Check if PWD is within this worktree
    let pwd_str = ($env.PWD | path expand | str trim --right --char '/')
    let wp_str = ($worktree_path | path expand | str trim --right --char '/')

    if ($pwd_str | str starts-with $wp_str) {
      let rel = ($pwd_str | str replace $wp_str "")
      if $current_worktree == "" or ($rel | str length) < ($current_worktree_relative_path | str length) {
        $current_worktree = $w
        $current_worktree_relative_path = $rel
      }
    } else {
      $other_worktrees = ($other_worktrees | append $w)
    }
  }

  # Adjust other_worktrees based on current worktree
  if $current_worktree != "" {
    if not $ignore_cwd {
      $other_worktrees = ($other_worktrees | append $current_worktree)
    }
    if $current_worktree != "" {
      $other_worktrees = ($other_worktrees | append "")
    }
  }

  # Determine final target
  mut final_target = $target_resolved
  let target_path = if $target_resolved != null {
    [$git_root $target_resolved] | path join
  } else {
    null
  }

  if $final_target == null or $target_path == null or not ($target_path | path exists) {
    # Use fzf to select worktree
    let fzf_preview_cmd = [
      "git -c color.ui=always log --decorate --max-count=7 --format=\"tformat:%C(auto,yellow)%<(8,trunc)%h %C(blue)%<(15,trunc)%cN %<(\\$((COLUMNS - 42)),trunc)%Creset%s %C(yellow)%G?%C(magenta)%>(15,trunc)%cr%Creset\""
      "echo"
      "git -c color.status=always status"
      "echo"
      "ls --color=always -la"
    ] | str join "\n"

    let fzf_header = if $header != null {
      $header
    } else {
      if $current_worktree == "" {
        "Current: repo root"
      } else {
        $"Current: ($current_worktree)"
      }
    }

    let fzf_query = if $prefill_cwd {
      $current_worktree
    } else {
      $target_resolved | default ""
    }

    mut fzf_args = [
      --cycle
      --reverse
      --height=30
      $"--preview=cd '($git_root)/{}' && ($fzf_preview_cmd)"
      $"--header=($fzf_header)"
      $"--query=($fzf_query)"
    ]

    # Add -1 flag if we have multiple options and not prefilling cwd
    if ($other_worktrees | length) >= 2 and not $prefill_cwd {
      $fzf_args = ($fzf_args | append "-1")
    }

    let fzf_input = ($other_worktrees | each {|w|
      if $w == "" { "/" } else { $"\/($w)" }
    } | str join "\n")

    let fzf_args = $fzf_args # make immutable for closure
    let fzf_result = (do {
      $fzf_input | ^fzf ...$fzf_args
    } | complete)

    if $fzf_result.exit_code != 0 {
      return null
    }

    $final_target = ($fzf_result.stdout | str trim)
    if $final_target == "/" {
      $final_target = ""
    } else {
      $final_target = ($final_target | str trim --left --char '/')
    }
  }

  let dest_base = [$git_root $final_target] | path join
  let dest_full = if $current_worktree_relative_path != "" {
    [$dest_base $current_worktree_relative_path] | path join
  } else {
    $dest_base
  }

  let dest = if ($dest_full | path exists) {
    $dest_full
  } else {
    $dest_base
  }

  {
    worktree: $final_target,
    branch: ($git_worktrees | get -o $final_target),
    path: ($dest | path expand),
    root: $git_root,
    is_bare: ($git_bare and $final_target == ""),
    relative_path: $current_worktree_relative_path
  }
}

# Switch to another git worktree with fzf (interactive)
export def --env gw [
  target?: string              # Target worktree or branch name
  --ignore-cwd (-c)            # Don't ignore current worktree in candidates
  --prefill-cwd (-C)           # Prefill fzf with current worktree
  --header (-H): string        # Custom fzf header
] {
  let selection = (gw-select $target --ignore-cwd=$ignore_cwd --prefill-cwd=$prefill_cwd --header=$header)

  if $selection == null {
    return
  }

  let bare_str = if $selection.is_bare {
    " (bare)"
  } else {
    ""
  }

  let display_name = if $selection.worktree == "" {
    "repo root"
  } else {
    $selection.worktree
  }

  cd -P $selection.path
}

# Switch to the root of the git repo
export def --env gwr [] {
  cd -P (gw-parse | get git_root)
}

# Add a new worktree
export def --env gwa [
  branch: string                  # Branch name
  worktree_name?: string          # Worktree name (defaults to branch name)
] {
  let wt_name = ($worktree_name | default $branch)

  let git_info = (gw-parse)
  let git_root = $git_info.git_root
  let prev = $env.PWD

  cd -P $git_root

  let branch_exists = (do { git show-branch $branch } | complete | get exit_code) == 0

  mut opts = []
  mut stashed = false

  if $branch_exists {
    $opts = [$"worktree/($wt_name)" $branch]
  } else {
    # Branch doesn't exist, we need to create it
    # Check if HEAD points to a valid commit
    let head_valid = (do { git rev-parse --verify HEAD } | complete | get exit_code) == 0

    if $head_valid {
      # We have a valid HEAD, get the branch name and use it as base
      let prev_branch_result = (git rev-parse --abbrev-ref HEAD | complete)
      let prev_branch = ($prev_branch_result.stdout | str trim)
      $opts = ["-b" $branch $"worktree/($wt_name)" $prev_branch]
    } else {
      # No valid HEAD (bare repo with no commits), create orphan branch
      $opts = ["--orphan" "-b" $branch $"worktree/($wt_name)"]
    }

    # Check if working tree is clean (for any new branch creation)
    let status_result = (git -C $prev status --porcelain --untracked-files=all | complete)
    let is_dirty = not ($status_result.stdout | str trim | is-empty)

    if $is_dirty {
      print "Working tree is not clean."
      git -C $prev status --porcelain --untracked-files=all

      let should_stash = (input "Stash changes and apply on new branch? [y/N] " | str downcase | str starts-with "y")

      if $should_stash {
        mut stash_opts = []
        mut keep_changes = false

        # Check if there are untracked files
        let status_all = (git -C $prev status --porcelain --untracked-files=all | complete | get stdout | lines | length)
        let status_tracked = (git -C $prev status --porcelain --untracked-files=no | complete | get stdout | lines | length)

        if $status_all > $status_tracked {
          let stash_untracked = (input "Stash untracked files? [y/N] " | str downcase | str starts-with "y")
          if $stash_untracked {
            $stash_opts = ($stash_opts | append "--include-untracked")
          }
        }

        # Always ask about preserving changes
        let preserve = (input "Preserve changes in starting branch? [y/N] " | str downcase | str starts-with "y")
        if $preserve {
          $keep_changes = true
        }

        # Stash changes
        let stash_msg = $"Stash before creating new branch '($branch)'"
        let stash_args = ($stash_opts | append ["push" "-m" $stash_msg])
        let stash_result = (git -C $prev stash ...$stash_args | complete)

        if $stash_result.exit_code != 0 {
          print -e "Failed to stash changes."
          error make -u {msg: $"stash failed: ($stash_result.stderr)"}
        }

        if $keep_changes {
          let apply_result = (git -C $prev stash apply | complete)
          if $apply_result.exit_code != 0 {
            print -e "Failed to apply stashed changes."
            error make -u {msg: $"stash apply failed: ($apply_result.stderr)"}
          }
        }

        $stashed = true
      }
    }
  }

  # Add worktree
  let add_result = (git worktree add ...$opts | complete)
  if $add_result.exit_code != 0 {
    print -e "Failed to add worktree."
    error make -u {msg: $"worktree add failed: ($add_result.stderr)"}
  }

  # Return to previous directory and switch to new worktree
  cd -P $prev
  let selection = (gw-select $"worktree/($wt_name)")
  if $selection == null {
    error make -u {msg: "failed to select new worktree"}
  }
  cd -P $selection.path

  # Apply stashed changes if we stashed
  if $stashed {
    let apply_result = (git stash apply | complete)
    if $apply_result.exit_code != 0 {
      print -e "Failed to apply stashed changes."
      error make -u {msg: $"stash apply failed: ($apply_result.stderr)"}
    }
  }
}

# Print or cd to the worktree set as "current"
export def --env gwc [
  --print (-p)  # Print the path instead of changing directory
] {
  let git_info = (gw-parse)
  let git_root = $git_info.git_root
  let current_path = [$git_root "worktree" "current"] | path join

  if not ($current_path | path exists) {
    error make -u {msg: "no current worktree"}
  }

  let path_type = ($current_path | path type)
  if $path_type != "symlink" {
    error make -u {msg: "no current worktree"}
  }

  if $print {
    print $current_path
  } else {
    cd -P $current_path
  }
}

# Change "current" worktree symlink
export def --env gwcc [
  target?: string  # Target worktree or branch name
] {
  let git_info = (gw-parse)
  let git_root = $git_info.git_root
  let current_link = [$git_root "worktree" "current"] | path join

  let has_current = (
    ($current_link | path exists) and
    (($current_link | path type) == "symlink")
  )

  # Build header if current link exists
  let header = if $has_current {
    # Get symlink target
    let link_target = (ls -l $current_link | get target.0)
    # Expand relative to symlink directory
    let worktree_dir = [$git_root "worktree"] | path join
    let target_full = ([$worktree_dir $link_target] | path join | path expand)
    # Make relative to git root
    let relative = ($target_full
      | str replace ($git_root | str trim --right --char '/') ""
      | str trim --left --char '/')
    let display = if $relative == "" { "/" } else { $relative }
    $"Current: ($display)"
  } else {
    null
  }

  # Select worktree
  let selection = if $target != null {
    gw-select $target --ignore-cwd --header=$header
  } else {
    gw-select --ignore-cwd --prefill-cwd --header=$header
  }

  if $selection == null {
    return
  }

  # cd to selected worktree
  cd -P $selection.path

  # Remove old symlink if it exists
  if $has_current {
    rm $current_link
  }

  # Create new symlink
  let target_relative = if $selection.worktree == "" {
    ".."  # Link to parent (git root)
  } else {
    # Strip "worktree/" prefix to get just the worktree name
    $selection.worktree | str replace "worktree/" ""
  }

  # Create the symlink
  ln -sv $target_relative $current_link
}

export def complete-gh-pr [
  # context: string = ""
] {
  # let context = ($context | split words | skip 1 | str join " ")
  let prs = do {(
    gh pr list
      --state all
      --limit 100
      --json number,state,title,createdAt,isDraft
      # --search $context # TODO: revist once https://github.com/nushell/nushell/issues/15479 is fixed
  )} | from json | sort-by -c {|a, b|
    let state_priority = {|state|
      match $state {
        "OPEN" => 0,
        "MERGED" => 1,
        "CLOSED" => 1,
      }
    }
    let a_priority = do $state_priority $a.state
    let b_priority = do $state_priority $b.state

    # Compare by state first, then by number
    if $a_priority != $b_priority {
      $a_priority < $b_priority
    } else {
      # If states are equal, compare by number
      $a.number < $b.number
    }
  }
  if ($prs | length) == 0 {
    return []
  }

  let descriptions = (
    $prs
    | each {|pr|
      use ../xtras
      let number = ($pr.number | into int)
      let isDraft = ($pr.isDraft | into bool)
      let state = ($pr.state | str trim)
      let createdAgo = ((date now) - ($pr.createdAt | into datetime)) | xtras format duration human
      let icon = (match $state {
        "OPEN" => (if $isDraft { "" } else { "" }),
        "CLOSED" => "",
        "MERGED" => "󰘭",
      })
      let status = (match $state {
        "OPEN" => (if $isDraft { "Draft" } else { "Open" }),
        "CLOSED" => "Closed",
        "MERGED" => "Merged",
      })
      {
        0: $icon
        1: $"#($number)"
        2: $status
        3: ($pr.title | str trim | str substring 0..40 | str trim)
        4: $createdAgo
      }
    } | table --collapse -t none | ansi strip | lines | skip 1
  )
  {
    options: {
      sort: false
      case_sensitive: false
      completion_algorithm: fuzzy
    },
    completions: ($prs | enumerate | each {|e|
      let i = $e.index
      let pr = $e.item
      let number = ($pr.number | into int)
      let state = ($pr.state | str trim)
      let isDraft = ($pr.isDraft | into bool)
      let description = ($descriptions | get $i | to text)
      {
        value: $number
        description: $description
        style: (match $state {
          "OPEN" => (if $isDraft { "gray" } else { "green" }),
          "CLOSED" => "red",
          "MERGED" => "magenta",
        })
      }
    })
  }
}

# Create worktree for a GitHub PR
export def --env gwpr [
  pr?: string@complete-gh-pr  # PR number
] {
  let git_info = (gw-parse)
  let git_root = $git_info.git_root

  # Get PR number from argument or fzf selection
  let pr_num = if $pr != null {
    $pr
  } else {
    # List PRs and let user select with fzf
    let gh_result = (gh pr list | complete)
    if $gh_result.exit_code != 0 {
      error make -u {msg: "failed to list PRs"}
    }

    let fzf_result = (do {
      $gh_result.stdout | fzf --height=10%
    } | complete)

    if $fzf_result.exit_code != 0 {
      return
    }

    # Extract PR number (remove leading # and keep only the number)
    let selected = ($fzf_result.stdout | str trim)
    let pr_str = ($selected | parse -r '^#?(\d+)' | get capture0.0)
    $pr_str | into int
  }

  # Fetch the PR
  let fetch_result = (git fetch origin $"refs/pull/($pr_num)/head:pull/($pr_num)" | complete)
  if $fetch_result.exit_code != 0 {
    error make -u {msg: $"failed to fetch PR ($pr_num): ($fetch_result.stderr)"}
  }

  let worktree_path = [$git_root "worktree" "pull" ($pr_num | into string)] | path join

  # Add worktree
  let add_result = (git worktree add $worktree_path $"pull/($pr_num)" | complete)
  if $add_result.exit_code != 0 {
    error make -u {msg: $"failed to add worktree: ($add_result.stderr)"}
  }

  # cd to worktree (path expand handles symlink resolution like -P)
  cd -P ($worktree_path | path expand)
}

# Pull latest changes from a GitHub PR to the current branch
export def gppr [
  pr?: string@complete-gh-pr  # PR number
] {
  # Get PR number from argument, current branch, or fzf selection
  let pr_num = if $pr != null {
    $pr
  } else {
    # Check if current branch is a pull branch
    let branch_result = (git rev-parse --abbrev-ref HEAD | complete)
    let from_branch = if $branch_result.exit_code == 0 {
      let branch = ($branch_result.stdout | str trim)
      let pull_match = ($branch | parse -r '^pull/(\d+)$')
      if ($pull_match | is-not-empty) {
        $pull_match.capture0.0 | into int
      } else {
        null
      }
    } else {
      null
    }

    if $from_branch != null {
      $from_branch
    } else {
      # Not on a pull branch, use fzf
      let gh_result = (gh pr list | complete)
      if $gh_result.exit_code != 0 {
        error make -u {msg: "failed to list PRs"}
      }

      let fzf_result = (do {
        $gh_result.stdout | fzf --height=10%
      } | complete)

      if $fzf_result.exit_code != 0 {
        return
      }

      # Extract PR number (remove leading # and keep only the number)
      let selected = ($fzf_result.stdout | str trim)
      let pr_str = ($selected | parse -r '^#?(\d+)' | get capture0.0)
      $pr_str | into int
    }
  }

  git pull origin $"refs/pull/($pr_num)/head:pull/($pr_num)"
}
