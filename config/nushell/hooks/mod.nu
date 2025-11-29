const hooks_dir = $"($nu.data-dir)/vendor/autoload" | path expand
const manifest_path = $"($hooks_dir)/hooks.json"

def hook-path [name: string] {
  $"($hooks_dir)/hooks__($name).nu"
}

def module-path [name: string] {
  $"($hooks_dir)/hooks/($name).nu"
}

def hook-hash [hook: record] {
  let date = date now | format date '%Y-%m-%d'
  {hook: $hook, date: $date} | to json --serialize  | hash md5
}

def hook-init [name: string, hook: record] {
  if not ($name =~ "^[a-zA-Z0-9_:-]+$") {
    error make -u {
      msg: $"hooks: invalid hook name: ($name)"
    }
  }

  let module = $hook | get -o module | default false
  let overlay = $hook | get -o overlay | default false
  let lazy = $hook | get -o lazy | default false
  let on_load = $hook | get -o on_load
  if ($on_load | is-not-empty) and (not ($on_load | describe | str starts-with "closure")) {
    error make -u {
      msg: $"hooks: ($name): on_load must be a closure, got: ($on_load | describe)"
    }
  }

  if $overlay and (not $module) {
    error make -u {
      msg: $"hooks: ($name): overlay=true requires module=true"
    }
  }
  if $lazy and $overlay {
    error make -u {
      msg: $"hooks: ($name): lazy=true and overlay=true are mutually exclusive"
    }
  }

  let generated = (try {
    # Check if cmd is a closure or a command
    let is_closure = ($hook.cmd | describe) =~ '^closure'

    let res = if $is_closure {
      # Invoke the closure and capture output
      let output = do $hook.cmd
      {
        stdout: (if ($output | describe) =~ '^list' {
          $output | str join "\n"
        } else {
          $output | into string
        })
        stderr: ""
        exit_code: 0
      }
    } else {
      # Execute as external command
      ^$hook.cmd | complete
    }

    if ($res | get -o exit_code) != 0 {
      error make -u {
        msg: $"hooks: ($name): command failed to initialize: ($res.stderr)"
      }
    }

    let on_load = if ($on_load | is-not-empty) {
      # NOTE: wrapping in export-env makes this work with both `use` (as in module = true) and `source` / autoload scenarios
      "export-env { do --env " + (view source $on_load) + " }"
    }

    let out = [
      $res.stdout
      $on_load
    ] | where { is-not-empty } | str join "\n"

    if $module {
      # Save command output to module file
      mkdir ($hooks_dir | path join "hooks")
      let mod_path = module-path $name
      $out | save -f $mod_path

      # Create hook file that uses or overlays the module
      if $overlay {
        [
          $"# Load ($name) overlay"
          $"alias \"hooks load ($name)\" = overlay use ($mod_path)"
          $"# Unload ($name) overlay"
          $"alias \"hooks unload ($name)\" = overlay hide ($name)"
        ] | str join "\n"
      } else if $lazy {
        ""
      } else {
        $"use ($mod_path)"
      }
    } else {
      $out
    }
  } catch { |e|
    $"error make -u {\n  msg: \"hooks: ($name): failed to initialize: ($e.msg)\\nFix the issue and then run 'hooks clean ($name)' and restart Nushell, or disable the hook.\"\n}"
  })
  if ($generated | is-not-empty) {
    $generated | save -f (hook-path $name)
  }
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

  # Check if main command exists (only for external commands, not closures)
  let is_closure = ($hook.cmd | describe) =~ '^closure'
  if not $is_closure {
    let cmd = $hook.cmd | first
    if (which $cmd | is-empty) {
      print -e $"Warning: Hook '($name)': command '($cmd)' not found. Disabling hook."
      return false
    }
  }

  true
}

# Set up hooks
# hooks should be a record of the form:
# {
#   hook_name: {
#     enabled?: bool = true           # Whether to enable the hook
#     cmd: list<string> | closure     # Command to run to initialize the hook, or a closure that returns a string/list of lines
#     depends?: string                # Command that must be installed; if not found, hook is quietly disabled
#     env?: record                    # Environment variables to set before running the command
#     module?: bool = false           # If true, save as a module
#     lazy?: bool = false             # If true, don't load the module immediately, use `hooks load <name>` to load the module
#                                     # Mutually exclusive with `overlay`
#     overlay?: bool = false          # If true (requires module), don't load the module immediately,
#                                     # create aliases `hooks load/unload <name>` to load/unload the module as an overlay
#                                     # Mutually exclusive with `lazy`
#     on_load?: closure               # Closure to run after the hook is loaded (for overlays, runs after `hooks load <name>`)
#                                     # Note: the closure is run in the context of the hook module, variables captured at the
#                                     # lambda definition will not be available, but variables/functions from the generated
#                                     # hook module will be available.
#   }
# }
# All hooks are automatically regenerated daily
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

      # Clean up module file if it exists
      let manifest_entry = $manifest | get $name
      let has_module = $manifest_entry | get -o module | default false
      if $has_module {
        let mod_path = module-path $name
        if ($mod_path | path exists) {
          rm -f $mod_path
        }
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
    let manifest_entry = $manifest | get -o $name | default {}
    let current_hash = $manifest_entry | get -o hash | default ""
    $hook | get -o env | default {} | load-env

    if ($current_hash != $hash) or (not ($path | path exists)) {
      hook-init $name $hook

      let has_module = $hook | get -o module | default false

      $manifest = ($manifest | upsert $name {
        hash: $hash
        module: $has_module
      })
    }
  }

  $manifest | save-manifest
}

def complete-hook-names [] {
  get-manifest | columns
}

# Clean up a hook by name
export def clean [name: string@complete-hook-names] {
  let manifest = get-manifest
  let manifest_entry = $manifest | get -o $name

  if $manifest_entry == null {
    print -e $"Hook does not exist: ($name)"
    return
  }

  let path = hook-path $name
  if ($path | path exists) {
    rm $path
  }

  # Clean up module file if it exists
  let has_module = $manifest_entry | get -o module | default false
  if $has_module {
    let mod_path = module-path $name
    if ($mod_path | path exists) {
      rm $mod_path
    }
  }

  $manifest | reject $name | save-manifest
}

# Clean up all hooks
export def clean-all [] {
  if not ($manifest_path | path exists) {
    return
  }

  let manifest = get-manifest
  for hook in ($manifest | columns) {
    let path = hook-path $hook
    if ($path | path exists) {
      rm $path
    }

    # Clean up module file if it exists
    let manifest_entry = $manifest | get $hook
    let has_module = $manifest_entry | get -o module | default false
    if $has_module {
      let mod_path = module-path $hook
      if ($mod_path | path exists) {
        rm $mod_path
      }
    }
  }
  rm $manifest_path
}
