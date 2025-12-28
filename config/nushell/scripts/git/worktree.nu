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
  mut current_worktree: string = ""

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
      if $current_worktree != "" {
        let branch_ref = ($line | str substring 7..)
        # Get abbreviated branch name
        let branch_result = (git rev-parse --abbrev-ref $branch_ref | complete)
        let branch = if $branch_result.exit_code == 0 and ($branch_result.stdout | str trim | is-not-empty) {
          $branch_result.stdout | str trim
        } else {
          $branch_ref
        }

        $worktrees = ($worktrees | insert $current_worktree $branch)
        $current_worktree = ""
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
  --ignore-cwd (-c)            # Ignore current worktree in candidates
  --prefill-cwd (-C)           # Prefill fzf with current worktree
  --header (-H): string        # Custom fzf header
  --no-auto-select (-n)        # Don't automatically select if only one match
  --ignore-root (-R)               # Don't include root worktree in candidates
] {
  let git_info = gw-parse

  if ($git_info.git_worktrees | is-empty) {
    error make -u {msg: "no worktrees"}
  }

  let git_root = $git_info.git_root
  let git_worktrees = $git_info.git_worktrees
  let git_bare = $git_info.git_bare

  let candidates = if $ignore_root {
    ($git_worktrees | columns)
  } else {
    ([""] | append ($git_worktrees | columns))
  }

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
    if $current_worktree != "" and not $ignore_root {
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
    if ($other_worktrees | length) >= 2 and not $prefill_cwd and not $no_auto_select {
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
  let selection = gw-select $target --ignore-cwd=$ignore_cwd --prefill-cwd=$prefill_cwd --header=$header
  if ($selection | is-not-empty) {
    cd -P $selection.path
  }
}

# Switch to the root of the git repo
export def --env gwr [] {
  cd -P (gw-parse | get git_root)
}

# Execute git command in worktree
export def gwx [
  ...git_args               # Git command and arguments
  --current (-c)            # Use current worktree
  --worktree (-w): string   # Use specified worktree
] {
  let w = if $current {
    # Note: This requires gwc (get worktree current) to be implemented
    # gwc -p should return the path of the current worktree
    let result = (gw-current | complete)
    if $result.exit_code != 0 {
      error make {msg: "failed to get current worktree"}
    }
    $result.stdout | str trim
  } else if $worktree != null {
    let selection = (gw-select $worktree)
    if $selection == null {
      error make {msg: "failed to select worktree"}
    }
    $selection.path
  } else {
    # Interactive selection
    let selection = (gw-select)
    if $selection == null {
      error make {msg: "no worktree selected"}
    }
    $selection.path
  }

  if ($w | is-empty) {
    error make {msg: "no worktree path determined"}
  }

  # Execute git command in worktree directory
  git -C $w ...$git_args
}

# Completer for Git branches
def complete-git-branch [context: string] {
  let git_info = gw-parse
  let git_root = $git_info.git_root

  # Get all branches
  let branches = (do {
    git -C $git_root branch --format "%(refname:short)"
  } | complete)

  {
    completions: ($branches.stdout | str trim | lines)
  }
}

# Add a new worktree
export def --env gwa [
  branch: string@complete-git-branch # Branch name
  worktree_name?: string             # Worktree name (defaults to branch name)
] {
  let wt_name = ($worktree_name | default $branch)

  let git_info = gw-parse
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

# Get the git worktree marked as "current"
export def gw-current [] {
  let git_info = gw-parse
  let git_root = $git_info.git_root
  let current_path = [$git_root "worktree" "current"] | path join
  if not ($current_path | path exists) {
    error make -u {msg: "no current worktree"}
  }
  let path_type = ($current_path | path type)
  if $path_type != "symlink" {
    error make -u {msg: "no current worktree"}
  }
  $current_path
}

# Change "current" worktree symlink
export def --env gwcc [
  target?: string  # Target worktree or branch name
] {
  let git_info = gw-parse
  let git_root = $git_info.git_root
  let current_link = [$git_root "worktree" "current"] | path join

  let has_current = (
    ($current_link | path exists) and
    (($current_link | path type) == "symlink")
  )

  # Build header if current link exists
  let header = if $has_current {
    # Get symlink target
    let link_target = ($current_link | path expand | path dirname)
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
    gw-select $target --header=$header
  } else {
    gw-select --prefill-cwd --header=$header
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

def get-icon [
  state: string
  isDraft: bool
] {
  match $state {
    "OPEN" => (if $isDraft { "" } else { "" }),
    "CLOSED" => "",
    "MERGED" => "󰘭",
  }
}

def get-current-branch [] {
  let branch_result = (git rev-parse --abbrev-ref HEAD | complete)
  if $branch_result.exit_code != 0 {
    error make -u {msg: "failed to get current branch"}
  }
  $branch_result.stdout | str trim
}

def get-remotes [] {
  git remote -v
    | lines
    | each { parse --regex '(?<name>\S+)\s+(?<url>\S+)\s+\((?<kind>fetch|push)\)' }
    | flatten
}

def get-remote-info [remote: string] {
  get-remotes | where name == $remote | first | default null
}

def get-default-remote [] {
  let remotes = get-remotes | where kind == 'fetch'
  if ($remotes | length) == 1 {
    $remotes | first
  } else {
    let default_repo = gh repo set-default --view | complete
    if ($default_repo.exit_code != 0) or ($default_repo.stdout | str trim | is-empty) {
      let fzf_result = ($remotes | get name | str join "\n"
        | fzf --height=10% --prompt="Select remote" --no-preview | complete
      )
      if $fzf_result.exit_code != 0 {
        return null
      }
      let selected = $fzf_result.stdout | str trim
      $remotes | where name == $selected | first
    } else {
      let default_repo = $default_repo.stdout | str trim
      let remotes = get-remotes | where { $default_repo in $in.url }
      if ($remotes | is-not-empty) {
        $remotes.0
      } else {
        null
      }
    }
  }
}

def gwpr-info [
  --remote (-r): string  # Use specified remote instead default
  pr?: string  # PR number or search term
  --no-detect-pr # Don't detect PR number from branch name
] {
  let git_info = gw-parse
  let git_root = $git_info.git_root

  let remote = if $remote != null { get-remote-info $remote } else { get-default-remote }

  let remote_info = if ($remote | is-empty) { null } else {
    let remote_info = $remote.url | parse -r '(?P<owner>[^/:]+)/(?P<repo>[^/]+?)(?:\.git)?$' | first
    if ($remote_info | is-empty) {
      error make -u {msg: $"failed to parse remote URL: ($remote.url)"}
    }
    $remote_info
  }

  # Get PR number from argument or fzf selection
  let pr_num = if $pr != null {
    $pr
  } else if not $no_detect_pr {
    # Check if we're on a `pull/<num>` branch
    let branch = get-current-branch
    let pull_match = ($branch | parse -r '^pull/(\d+)$')
    if ($pull_match | is-not-empty) {
      $pull_match.capture0.0 | into int
    } else {
      null
    }
  }
  let pr_num = if $pr_num != null {
    $pr_num
  } else {
    # List PRs and let user select with fzf
    let gh_args = if $remote_info != null {
      ["-R" $"($remote_info.owner)/($remote_info.repo)"]
    } else { [] }
    let gh_result = gh pr list ...$gh_args | complete
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

  return {
    git_info: $git_info,
    pr: $pr_num,
    remote: $remote,
    ref: $"refs/pull/($pr_num)/head"
    branch: $"pull/($pr_num)"
  }
}

# Completer for GitHub PRs using the new @complete attribute
# Takes spans and filters PRs by title or number based on user input
def complete-gh-pr [spans: list<string>] {
  # Extract the search term from all argument spans (join multi-word searches)
  let search_term = if ($spans | length) > 1 {
    $spans | skip 1 | str join " "
  } else {
    ""
  }

  # Fetch PRs from GitHub (filtering is done by gh API via --search)
  let prs = do {(
    gh pr list
      --state all
      --limit 20
      --json number,state,title,createdAt,isDraft
      --search $search_term
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

  # Build help completions (filtered by search term)
  let help_completions = [
    { value: "-h", description: "Display help message" }
    { value: "--help", description: "Display help message" }
  ] | where {|item|
    if ($search_term | is-empty) {
      true
    } else {
      $item.value | str contains $search_term
    }
  }

  # Return completions directly (no wrapping in options/completions structure)
  let pr_completions = $prs | par-each {|pr|
    use xtras/format.nu
    let number = ($pr.number | into int)
    let isDraft = ($pr.isDraft | into bool)
    let state = ($pr.state | str trim)
    let createdAgo = ((date now) - ($pr.createdAt | into datetime)) | format duration human
    let icon = (get-icon $state $isDraft)
    let status = (match $state {
      "OPEN" => (if $isDraft { "Draft" } else { "Open" }),
      "CLOSED" => "Closed",
      "MERGED" => "Merged",
    })

    {
      value: ($number | into string)
      description: $"($icon) #($number) ($status) - ($pr.title | str trim | str substring 0..60 | str trim) ($createdAgo)"
      style: (match $state {
        "OPEN" => (if $isDraft { "gray" } else { "green" }),
        "CLOSED" => "red",
        "MERGED" => "magenta",
      })
    }
  }

  $help_completions | append $pr_completions
}

# Create worktree for a GitHub PR
@complete complete-gh-pr
export def --env gwpr [
  --remote (-r): string # Use specified remote instead default
  pr?: string # PR number or search term
] {
  let pr_info = gwpr-info --no-detect-pr --remote=$remote $pr
  if ($pr_info | is-empty) {
    return
  }

  # Fetch the PR
  let fetch_result = git fetch $pr_info.remote.name $"($pr_info.ref):($pr_info.branch)" | complete
  if $fetch_result.exit_code != 0 {
    error make -u {msg: $"failed to fetch PR ($pr_info.pr): ($fetch_result.stderr)"}
  }

  let worktree_path = [$pr_info.git_info.git_root "worktree" $pr_info.branch] | path join

  # Add worktree
  let add_result = (git worktree add $worktree_path $pr_info.branch | complete)
  if $add_result.exit_code != 0 {
    error make -u {msg: $"failed to add worktree: ($add_result.stderr)"}
  }

  # cd to worktree (path expand handles symlink resolution like -P)
  cd -P ($worktree_path | path expand)
}

# Pull latest changes from a GitHub PR to the current branch
@complete complete-gh-pr
export def gwprp [
  --remote (-r): string # Use specified remote instead default
  pr?: string # PR number or search term
] {
  let pr_info = gwpr-info --remote=$remote $pr
  if ($pr_info | is-empty) or ($pr_info.remote | is-empty) or ($pr_info.ref | is-empty) {
    return
  }
  git pull $pr_info.remote.name $pr_info.ref
}

# Remove a git worktree
export def gwrm [
  target?: string  # Target worktree or branch name
] {
  let git_info = gw-parse
  let git_root = $git_info.git_root

  # Get the target worktree
  let selection = if $target != null {
    gw-select --ignore-root --ignore-cwd --no-auto-select $target
  } else {
    gw-select --ignore-root --ignore-cwd --no-auto-select
  }

  if $selection == null {
    return
  }

  # Don't allow removing the main worktree (root)
  if $selection.worktree == "" {
    error make -u {msg: "cannot remove main worktree (repo root)"}
  }

  let worktree_path = $selection.path
  let display_name = $selection.worktree

  # Try to remove the worktree
  let remove_result = (git worktree remove $worktree_path | complete)

  if $remove_result.exit_code == 0 {
    print $"Removed worktree: ($display_name)"
    return
  }

  # Check if it failed due to modifications (exit code 128 + specific error message)
  let has_modifications = (
    $remove_result.exit_code == 128 and
    ($remove_result.stderr | str contains "contains modified or untracked files")
  )

  if $has_modifications {
    print $"Worktree has modifications or untracked files:"
    let should_force = (input "Force deletion? [y/N] " | str downcase | str starts-with "y")
    if $should_force {
      let force_result = (git worktree remove --force $worktree_path | complete)
      if $force_result.exit_code == 0 {
        print $"Forcefully removed worktree: ($display_name)"
      } else {
        error make -u {msg: $"failed to force remove worktree: ($force_result.stderr)"}
      }
    } else {
      print "Removal cancelled"
    }
  } else {
    error make -u {msg: $"failed to remove worktree: ($remove_result.stderr)"}
  }
}

# Git push with smart default remote and branch
# If no remote is specified, use "origin" or the first remote with "push" access
# If no branch is specified, use the current branch
export def --wrapped gpp [
  ...args: string
] {
  mut opts = []
  mut positional = []
  for item in $args {
    if ($item | to text | str starts-with "-") {
      $opts = $opts | append $item
    } else {
      $positional = $positional | append $item
    }
  }
  if ($positional | length) < 2 {
    let remotes = get-remotes | where kind == 'push'
    let default_remote = if ($remotes | any { $in.name == "origin" }) {
      "origin"
    } else {
      $remotes | first | get name
    }
    let default_branch = git rev-parse --abbrev-ref HEAD
    if ($positional | length) == 0 {
      $positional = [$default_remote $default_branch]
    } else if ($positional | length) == 1 {
      $positional = ($positional | append $default_branch)
    }
  }
  git push ...$opts ...$positional
}
