const hooks_dir = $"($nu.data-dir)/vendor/autoload" | path expand
const manifest_path = $"($hooks_dir)/hooks.json"

def hook-path [name: string] {
  $"($hooks_dir)/hooks__($name).nu"
}

def hook-hash [hook: record] {
  $hook | to json | hash md5
}

def hook-init [name: string, hook: record] {
  if not ($name =~ "^[a-zA-Z0-9_:-]+$") {
    error make -u {
      msg: $"hooks: invalid hook name: ($name)"
    }
  }
  (try {
    let res = ^$hook.cmd | complete
    if ($res | get -o exit_code) != 0 {
      error make -u {
        msg: $"hooks: ($name): command failed to initialize: ($res.stderr)"
      }
    }
    $res.stdout
  } catch { |e|
    $"error make -u {\n  msg: \"hooks: ($name): failed to initialize: ($e.msg)\\nFix the issue and then run 'hooks clean ($name)' and restart Nushell, or disable the hook.\"\n}"
  }) | save -f (hook-path $name)
}

def get-manifest [] {
  if ($manifest_path | path exists) {
    open $manifest_path
  } else {
    {}
  }
}

def save-manifest [] {
  $in | save -f $manifest_path
}

def hook-enabled [name: string, hook: record] {
  # Check if explicitly disabled
  if not ($hook | get -o enabled | default true) {
    return false
  }

  # Check if dependency command exists
  let depends = $hook | get -o depends
  if ($depends != null) and (which $depends | is-empty) {
    return false
  }

  # Check if main command exists
  let cmd = $hook.cmd | first
  if (which $cmd | is-empty) {
    print -e $"Warning: Hook '($name)': command '($cmd)' not found. Disabling hook."
    return false
  }

  true
}

# Set up hooks
# hooks should be a record of the form:
# {
#   hook_name: {
#     enabled?: bool = true  # Whether to enable the hook
#     cmd: list<string>      # Command to run to initialize the hook
#     depends?: string       # Command that must be installed; if not found, hook is quietly disabled
#     env?: record           # Environment variables to set before running the command
#   }
# }
export def --env use [hooks: record] {
  mkdir $hooks_dir

  mut manifest = get-manifest
  mut hooks = $hooks

  # Remove hooks that are no longer present or disabled
  for name in ($manifest | columns) {
    let hook = $hooks | get -o $name
    if ($hook == null) or (not (hook-enabled $name $hook)) {
      let path = hook-path $name
      if ($path | path exists) {
        rm -f $path
      }
      $manifest = ($manifest | reject $name)
      $hooks = ($hooks | reject -o $name)
    }
  }

  # Initialize or update hooks
  for name in ($hooks | columns) {
    let hook = $hooks | get $name
    if not (hook-enabled $name $hook) {
      continue
    }

    let hash = hook-hash $hook
    let path = hook-path $name
    let current_hash = $manifest | get -o $name | default ""
    $hook | get -o env | default {} | load-env

    if ($current_hash != $hash) or (not ($path | path exists)) {
      hook-init $name $hook
      $manifest = ($manifest | upsert $name $hash)
    }
  }

  $manifest | save-manifest
}

# Clean up a hook by name
export def clean [name: string] {
  let path = hook-path $name
  if not ($path | path exists) {
    print -e $"Hook does not exist: ($name)"
    return
  }
  rm $path
  get-manifest | reject -o $name | save-manifest
}

# Clean up all hooks
export def clean-all [] {
  if not ($manifest_path | path exists) {
    return
  }
  for hook in (get-manifest | columns) {
    let path = hook-path $hook
    if ($path | path exists) {
      rm $path
    }
  }
  rm $manifest_path
}
