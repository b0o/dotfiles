def --env venv [targetdir?: string] {
  # Check if already in a virtual environment
  if ($env.VIRTUAL_ENV? != null) {
    print $"Already in venv ($env.VIRTUAL_ENV)"
    return
  }

  let startdir = $env.PWD

  # Change to target directory if provided
  if $targetdir != null {
    if not ($targetdir | path exists) {
      print $"error: not a directory: ($targetdir)" --stderr
      return
    }
    try {
      cd $targetdir
    } catch {
      print $"error: failed to change directory to ($targetdir)" --stderr
      cd $startdir
      return
    }
  }

  let repo = try {
    git rev-parse --show-toplevel
      | complete
      | if $in.exit_code == 0 { $in.stdout | str trim } else { null }
  } catch {
    null
  }
  let project_root = if $repo != null { $repo } else { $env.PWD }

  let venv = if ($env.PWD | path join "pyvenv.cfg" | path exists) {
    $env.PWD
  } else if ($env.PWD | path join ".venv" | path exists) {
    $env.PWD | path join ".venv"
  } else if $repo != null and ($repo | path join ".venv" | path exists) {
    $repo | path join ".venv"
  } else if ($project_root | path join "pyproject.toml" | path exists) {
    let response = input "No venv found. Create one with uv? (y/n): " | str trim | str downcase
    if not ($response == "y" or response == "") {
      return null
    }
    if (do {
      cd $project_root
      try {
        ^uv venv
      } catch {
        print "error: failed to create virtual environment" --stderr
        return null
      }
    } | complete).exit_code != 0 {
      print "error: failed to create virtual environment" --stderr
      return null
    }

    $project_root | path join ".venv"
  }
  if $venv == null {
    print "No virtual environment found"
    cd $startdir
    return
  }

  print $"Activating virtual environment ($venv)"

  # Activate the virtual environment
  $env.VIRTUAL_ENV = $venv
  let venv_bin = $venv | path join "bin"
  $env.PATH = ($env.PATH | prepend $venv_bin)

  cd $startdir
}
