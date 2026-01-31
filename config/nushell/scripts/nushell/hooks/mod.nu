const hooks_dir = $"($nu.data-dir)/vendor/autoload" | path expand
const manifest_path = $"($hooks_dir)/hooks.json"

# TODO: prefer using $env._nu_hooks over get-manifest
# get-manifest should be used only for hashes and detecting
# hooks which have been removed

def hook-path [name: string] {
  $"($hooks_dir)/hooks__($name).nu"
}

def module-path [name: string] {
  $"($hooks_dir)/hooks/($name).nu"
}

# Get file stat (inode + size + mtime) as a fast change indicator
# Using all three: mtime works for normal files, inode+size catches Nix replacements
def file-stat [path: string] {
  if ($path | is-empty) or (not ($path | path exists)) {
    return null
  }
  let info = ls -l $path | first
  $"($info.inode):($info.size):($info.modified | format date '%s')"
}

# Hash a file's contents (expensive, only called when mtime changes)
def file-hash [path: string] {
  if ($path | is-empty) or (not ($path | path exists)) {
    return null
  }
  open --raw $path | hash md5
}

# Get combined stat string for multiple files (for fast change detection)
def files-stat [paths: list<string>] {
  $paths | each { file-stat $in } | str join "|"
}

# Get combined hash for multiple files
def files-hash [paths: list<string>] {
  $paths | each { file-hash $in } | str join ":" | hash md5
}

# Check if files need rehashing based on stat, returns {changed: bool, hash: string|null, stat: string}
def files-check [paths: list<string>, manifest_entry: record] {
  let current_stat = files-stat $paths
  let manifest_stat = $manifest_entry | get -o files_stat
  let manifest_hash = $manifest_entry | get -o files_hash

  if ($manifest_stat != $current_stat) {
    # stat changed, compute hash
    let hash = files-hash $paths
    if ($manifest_hash != $hash) {
      {changed: true, hash: $hash, stat: $current_stat}
    } else {
      # stat changed but hash is same
      {changed: false, hash: $hash, stat: $current_stat}
    }
  } else {
    # stat unchanged, no need to rehash
    {changed: false, hash: $manifest_hash, stat: $current_stat}
  }
}

# Get list of installed nushell plugins
def get-installed-plugins [] {
  plugin list
}

# Get the path to a plugin binary
def plugin-path [hook: record] {
  if ($hook | get -o plugin_path | is-not-empty) {
    $hook.plugin_path
  } else if ($hook | get -o plugin_cmd | is-not-empty) {
    which $hook.plugin_cmd | first | get path
  } else {
    null
  }
}

# Check if plugin needs update, returns {needs_update: bool, hash: string|null, mtime: string|null}
def plugin-check [name: string, hook: record, manifest_entry: record] {
  let path = plugin-path $hook
  if ($path | is-empty) {
    error make -u {
      msg: $"hooks: ($name): plugin=true requires plugin_cmd or plugin_path"
    }
  }
  if not ($path | path exists) {
    error make -u {
      msg: $"hooks: ($name): plugin binary not found at ($path)"
    }
  }

  let installed = get-installed-plugins | where name == $name | first | default null

  if ($installed | is-empty) {
    # Plugin not installed
    let hash = file-hash $path
    let stat = file-stat $path
    {needs_update: true, hash: $hash, stat: $stat, reason: "not installed"}
  } else {
    # Use files-check for stat-first optimization
    let check = files-check [$path] {
      files_stat: ($manifest_entry | get -o plugin_stat)
      files_hash: ($manifest_entry | get -o plugin_hash)
    }
    if $check.changed {
      {needs_update: true, hash: $check.hash, stat: $check.stat, reason: "binary changed"}
    } else {
      {needs_update: false, hash: $check.hash, stat: $check.stat, reason: null}
    }
  }
}

# Update or install a plugin based on check result
def plugin-update [name: string, hook: record, check: record] {
  if not $check.needs_update {
    return false
  }

  let path = plugin-path $hook

  if $check.reason == "not installed" {
    plugin add $path
    print -e $"hooks: Installed plugin ($name) from ($path)"
  } else {
    plugin rm $name
    plugin add $path
    print -e $"hooks: Updated plugin ($name) from ($path)"
  }
  true
}

# Normalize hash_files to a list of paths
def normalize-hash-files [hook: record] {
  let hash_files = $hook | get -o hash_files
  if ($hash_files | is-empty) {
    return []
  }
  let type = $hash_files | describe
  if ($type == 'string') {
    [$hash_files]
  } else if ($type =~ '^list') {
    $hash_files
  } else {
    error make -u {
      msg: $"hooks: hash_files must be a string or list of strings, got: ($type)"
    }
  }
}

# Compute the "fast hash" for a hook - uses file stat for file-based hashes
def hook-hash [hook: record] {
  let date = date now | format date '%Y-%m-%d'
  let is_plugin = $hook | get -o plugin | default false
  let hash_files = normalize-hash-files $hook

  # Determine the hash component:
  # - hash: string -> use directly
  # - hash_fn: closure -> call it (expensive, user's responsibility)
  # - hash_files: paths -> use stat for fast check
  let hash_value = if ($hook | get -o hash | describe) == 'string' {
    $hook.hash
  } else if ($hook | get -o hash_fn | describe) =~ '^closure' {
    do $hook.hash_fn
  } else {
    null
  }

  {
    hook: $hook
    date: $date
    hash: $hash_value
    # Use stat as fast change indicator for hash_files; actual hash check is done lazily
    files_stat: (if ($hash_files | is-not-empty) { files-stat $hash_files })
    # Plugin also uses stat-first
    plugin_stat: (if $is_plugin { file-stat (plugin-path $hook) })
  } | to json --serialize | hash md5
}

def hook-init [name: string, hook: record] {
  if not ($name =~ "^[a-zA-Z0-9_:-]+$") {
    error make -u {
      msg: $"hooks: invalid hook name: ($name)"
    }
  }

  let cmd = $hook | get -o cmd | default null
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

  let hook_env = $hook | get -o env | default {}
  let hook_env = (
    if ($hook_env | describe -d | get type) == 'closure' {
      do $hook_env
    } else {
      $hook_env
    }
  )

  let generated = try {
    let type = $cmd | describe
    let res = if ($type =~ '^closure') {
      # Invoke the closure and capture output
      let output = do $cmd
      {
        stdout: (if ($output | describe) =~ '^list' {
          $output | str join "\n"
        } else {
          $output | into string
        })
        stderr: ""
        exit_code: 0
      }
    } else if ($type == 'string') or ($type == 'list<string>') {
      # Execute as external command
      ^$cmd | complete
    } else if ($cmd | is-empty) {
      # Empty
      {
        stdout: ""
        stderr: ""
        exit_code: 0
      }
    } else {
      error make -u {
        msg: $"hooks: ($name): cmd must be a string, list of strings, or closure, got: ($type)"
      }
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

    let load_env = if ($hook_env | is-not-empty) {
      "load-env " ++ ($hook_env | to nuon)
    }

    let timeit = $hook.timeit? == true and not $overlay

    let out = [
      (if $timeit { $"hooks time start ($name)" })
      $load_env
      $res.stdout
      $on_load
      (if $timeit { $"hooks time stop ($name)" })
    ] | compact --empty | str join "\n" | default ""

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
  }
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
  if ($depends | is-not-empty) {
    let type = $depends | describe
    if ($type == 'string') {
      return (which $depends | is-not-empty)
    } else if ($type == 'list<string>') {
      return $depends | all { (which $in) | is-not-empty }
    } else if ($type | str starts-with 'closure') {
      return (do $depends)
    } else {
      error make -u {
        msg: $"hooks: ($name): depends must be a string, list of strings, or closure, got: ($type)"
      }
    }
  }

  true
}

def hook-generate [
  --force (-f)  # Force regeneration of the hook
  name: string
  hook: record
  manifest: record
] {
  let fast_hash = hook-hash $hook
  let path = hook-path $name
  let manifest_entry = $manifest | get -o $name | default {}
  let current_hash = $manifest_entry | get -o hash | default ""

  let is_plugin = $hook | get -o plugin | default false
  let hash_files = normalize-hash-files $hook
  mut plugin_updated = false
  mut plugin_info = {hash: null, stat: null}
  mut files_info = {hash: null, stat: null}

  # Handle plugin installation/update (uses stat for fast check, only hashes when needed)
  if $is_plugin {
    let check = plugin-check $name $hook $manifest_entry
    $plugin_updated = (plugin-update $name $hook $check)
    $plugin_info = {hash: $check.hash, stat: $check.stat}
  }

  # Handle hash_files (uses stat for fast check, only hashes when needed)
  if ($hash_files | is-not-empty) {
    let check = files-check $hash_files $manifest_entry
    $files_info = {hash: $check.hash, stat: $check.stat}
  }

  if $force or ($current_hash != $fast_hash) or (not ($path | path exists)) {
    hook-init $name $hook

    let has_module = $hook | get -o module | default false

    {
      manifest: ($manifest | upsert $name {
        hash: $fast_hash
        module: $has_module
        plugin: $is_plugin
        plugin_hash: $plugin_info.hash
        plugin_stat: $plugin_info.stat
        files_hash: $files_info.hash
        files_stat: $files_info.stat
      })
      plugin_updated: $plugin_updated
    }
  } else if $is_plugin or ($hash_files | is-not-empty) {
    # Plugin/files check may have updated stat even if hook didn't regenerate
    {
      manifest: ($manifest | upsert $name ($manifest_entry | merge {
        plugin_hash: $plugin_info.hash
        plugin_stat: $plugin_info.stat
        files_hash: $files_info.hash
        files_stat: $files_info.stat
      }))
      plugin_updated: $plugin_updated
    }
  } else {
    {
      manifest: $manifest
      plugin_updated: $plugin_updated
    }
  }
}

const HOOKS_HELP = r#'HOOKS - Nushell startup hook manager

COMMANDS:
  hooks                  Show status of all hooks and plugins
  hooks use <record>     Initialize hooks from configuration
  hooks status           Show detailed hook status
  hooks plugins          List plugin hooks and their status
  hooks list             List hook names
  hooks clean <name>     Remove a hook's generated files
  hooks clean-all        Remove all generated hook files
  hooks regenerate <n>   Force regenerate a specific hook
  hooks regenerate-all   Force regenerate all hooks
  hooks update-plugin    Force update a plugin (or all plugins)

HOOK OPTIONS:
  enabled       bool                      Enable/disable the hook (default: true)
  cmd           string|list|closure       Command to generate hook code
  depends       string|list|closure       Dependencies that must exist
  env           record                    Environment variables to set
  module        bool                      Save as a module (default: false)
  lazy          bool                      Don't load immediately (default: false)
  overlay       bool                      Load as overlay (default: false)
  on_load       closure                   Code to run after loading
  hash          string                    Static hash for change detection
  hash_fn       closure                   Dynamic hash function (called every startup)
  hash_files    string|list               File(s) to hash (uses stat-first optimization)
  plugin        bool                      Manages a nushell plugin (default: false)
  plugin_cmd    string                    Plugin command name (for `which`)
  plugin_path   string                    Direct path to plugin binary

CHANGE DETECTION:
  Hooks are regenerated when:
  - The hook configuration changes
  - A new day begins (daily refresh)
  - hash/hash_fn/hash_files indicate a change
  - The generated file is missing

  For hash_files and plugins, a fast stat check (inode+size+mtime) is performed
  first; the actual file hash is only computed if the stat changed.

EXAMPLES:
Basic hook with external command:
  hooks use {
    starship: {
      depends: starship
      cmd: [starship init nu]
    }
  }

Hook with file-based change detection:
  hooks use {
    my-hook: {
      hash_files: ~/.config/myapp/config.toml
      cmd: { myapp generate-nu }
    }
  }

Plugin hook:
  hooks use {
    skim: {
      plugin: true
      plugin_cmd: nu_plugin_skim
      depends: nu_plugin_skim
      cmd: { ... }
    }
  }
'#

# Show hooks and plugins status, or extended help with -h
export def --wrapped main [...args] {
  if ($args | any { $in == "-h" or $in == "--help" }) {
    print $HOOKS_HELP
    return
  }

  let manifest = get-manifest
  let installed_plugins = get-installed-plugins
  let hooks_config = $env._nu_hooks? | default {}

  # Build combined status table
  $manifest | columns | each { |name|
    let manifest_entry = $manifest | get $name
    let hook_config = $hooks_config | get -o $name
    let path = hook-path $name
    let is_plugin = $manifest_entry | get -o plugin | default false
    let is_module = $manifest_entry | get -o module | default false

    let plugin_status = if $is_plugin {
      let installed = $installed_plugins | where name == $name | first | default null
      if ($installed | is-not-empty) { "yes" } else { "no" }
    } else {
      ""
    }

    let type = if $is_plugin and $is_module {
      "plugin+module"
    } else if $is_plugin {
      "plugin"
    } else if $is_module {
      "module"
    } else {
      "hook"
    }

    {
      name: $name
      type: $type
      active: ($path | path exists)
      plugin_ok: $plugin_status
    }
  }
}

# Set up hooks
# hooks should be a record of the form:
# {
#   hook_name: {
#     enabled?: bool = true                  # Whether to enable the hook
#     cmd?: string|list<string>|closure      # Command to run to initialize the hook, or a closure that returns a string/list of lines
#     depends?: string|list<string>|closure  # Command that must be installed; if not found, hook is quietly disabled
#     env?: record|closure                   # Environment variables to set before running the command or closure returning a record of env vars
#     module?: bool = false                  # If true, save as a module
#     lazy?: bool = false                    # If true, don't load the module immediately, use `hooks load <name>` to load the module
#                                            # Mutually exclusive with `overlay`
#     overlay?: bool = false                 # If true (requires module), don't load the module immediately,
#                                            # create aliases `hooks load/unload <name>` to load/unload the module as an overlay
#                                            # Mutually exclusive with `lazy`
#     on_load?: closure                      # Closure to run after the hook is loaded (for overlays, runs after `hooks load <name>`)
#                                            # Note: the closure is run in the context of the hook module, variables captured at the
#                                            # lambda definition will not be available, but variables/functions from the generated
#                                            # hook module will be available.
#     hash?: string                          # Static hash string for change detection
#     hash_fn?: closure                      # Closure to generate a hash (called every startup - use sparingly)
#     hash_files?: string|list<string>       # File path(s) to hash for change detection (uses stat-first optimization)
#                                            # Note: hash/hash_fn/hash_files are combined with hook config to determine regeneration
#     plugin?: bool = false                  # If true, this hook manages a nushell plugin
#     plugin_cmd?: string                    # Command name to find plugin binary via `which` (requires plugin=true)
#     plugin_path?: string                   # Direct path to plugin binary (requires plugin=true, alternative to plugin_cmd)
#   }
# }
# All hooks are automatically regenerated daily
# Plugins and hash_files use stat-first optimization (inode+size+mtime check before hashing)
export def --env use [
  hooks: record
  --timeit # Record hooks execution times, can be displayed with `hooks times`
] {
  mkdir $hooks_dir

  # TODO: Allow `use` to be called multiple times
  $env._nu_hooks = $hooks

  mut manifest = get-manifest
  mut hooks = $hooks
  mut plugins_updated: list<string> = []

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
    let hook = if ($timeit) {
      $hook | upsert timeit true
    } else {
      $hook
    }
    if not (hook-enabled $name $hook) {
      continue
    }
    let result = hook-generate $name $hook $manifest
    $manifest = $result.manifest
    if $result.plugin_updated {
      $plugins_updated = ($plugins_updated | append $name)
    }
  }

  $manifest | save-manifest

  # Notify user if any plugins were updated
  if ($plugins_updated | is-not-empty) {
    print -e $"hooks: Reload nushell to load updated plugins: ($plugins_updated | str join ', ')"
  }
}

def complete-hook-names [] {
  $env._nu_hooks? | default (get-manifest) | columns
}

# Clean up a hook by name
export def clean [
  --quiet (-q)  # Don't print a message
  name: string@complete-hook-names
] {
  let manifest = get-manifest
  let manifest_entry = $manifest | get -o $name

  if $manifest_entry == null {
    if not $quiet {
      print -e $"Hook does not exist: ($name)"
    }
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

# List hooks
export def list [] {
  get-manifest | columns
}

# Get hook statuses
export def status [] {
  let manifest = get-manifest
  let installed_plugins = get-installed-plugins

  ($manifest | columns) | each { |name|
    let manifest_entry = $manifest | get $name
    let path = hook-path $name
    let is_plugin = $manifest_entry | get -o plugin | default false

    let plugin_status = if $is_plugin {
      let installed = $installed_plugins | where name == $name | first | default null
      if ($installed | is-not-empty) { "installed" } else { "not installed" }
    } else {
      null
    }

    {
      name: $name
      exists: ($path | path exists)
      module: ($manifest_entry | get -o module | default false)
      plugin: $plugin_status
    }
  }
}

# Regenerate a hook
export def regenerate [name: string@complete-hook-names] {
  let hook = $env._nu_hooks? | get -o $name
  if ($hook | is-empty) {
    error make -u {
      msg: $"hooks: ($name): hook does not exist"
    }
  }
  let manifest = get-manifest
  clean --quiet $name
  let result = hook-generate --force $name $hook $manifest
  $result.manifest | save-manifest
  if $result.plugin_updated {
    print -e $"hooks: Reload nushell to load updated plugin: ($name)"
  }
}

# Regenerate all hooks
export def regenerate-all [] {
  let manifest = get-manifest
  for name in ($env._nu_hooks? | columns) {
    regenerate $name
  }
}

def complete-plugin-names [] {
  $env._nu_hooks? | default {} | transpose name hook | where { $in.hook | get -o plugin | default false } | get name
}

# List plugin hooks and their status
export def plugins [] {
  let manifest = get-manifest
  let installed_plugins = get-installed-plugins

  $env._nu_hooks? | default {} | transpose name hook | where { $in.hook | get -o plugin | default false } | each { |entry|
    let name = $entry.name
    let hook = $entry.hook
    let manifest_entry = $manifest | get -o $name | default {}
    let path = plugin-path $hook
    let installed = $installed_plugins | where name == $name | first | default null

    {
      name: $name
      path: $path
      installed: ($installed | is-not-empty)
      version: ($installed | get -o version)
      manifest_hash: ($manifest_entry | get -o plugin_hash | default "" | str substring 0..8)
    }
  }
}

# Update a plugin (force reinstall)
export def update-plugin [
  name?: string@complete-plugin-names  # Plugin name to update (updates all if not specified)
] {
  let hooks = $env._nu_hooks? | default {}
  let plugin_hooks = $hooks | transpose name hook | where { $in.hook | get -o plugin | default false }

  if ($plugin_hooks | is-empty) {
    print -e "No plugin hooks configured"
    return
  }

  let to_update = if ($name | is-empty) {
    $plugin_hooks
  } else {
    let found = $plugin_hooks | where name == $name
    if ($found | is-empty) {
      error make -u { msg: $"hooks: plugin ($name) not found" }
    }
    $found
  }

  mut updated: list<string> = []

  for entry in $to_update {
    let hook = $entry.hook
    let path = plugin-path $hook
    if ($path | is-empty) or (not ($path | path exists)) {
      print -e $"hooks: ($entry.name): plugin binary not found"
      continue
    }

    # Force update: remove and re-add
    let installed = get-installed-plugins | where name == $entry.name | first | default null
    if ($installed | is-not-empty) {
      plugin rm $entry.name
    }
    plugin add $path
    print -e $"hooks: Updated plugin ($entry.name) from ($path)"
    $updated = ($updated | append $entry.name)

    # Update manifest with new hash and stat
    let manifest = get-manifest
    let hash = file-hash $path
    let stat = file-stat $path
    $manifest | upsert $entry.name (($manifest | get -o $entry.name | default {}) | merge {
      plugin_hash: $hash
      plugin_stat: $stat
    }) | save-manifest
  }

  if ($updated | is-not-empty) {
    print -e $"hooks: Reload nushell to load updated plugins: ($updated | str join ', ')"
  }
}

def --env save-time [marker: string, name: string] {
  let time = date now
  let hook_time = $env._nu_hooks_time? | get -o $name | default {} | upsert $marker $time
  $env._nu_hooks_time = ($env._nu_hooks_time? | default {}) | upsert $name $hook_time
}

# For internal use only
# Register the load start time of a hook
export def --env "time start" [name: string] {
  save-time start $name
}

# For internal use only
# Register the load stop time of a hook
export def --env "time stop" [name: string] {
  save-time stop $name
}

# Show a summary of hook load times
export def "time list" [] {
  if ('_nu_hooks_time' not-in $env) {
    print -e "hooks time tracking is not enabled, pass --timeit to `hooks use` to enable"
    return
  }
  let times = $env._nu_hooks_time
    | default {}
    | items { |name, times|
      let duration = ($times.stop - $times.start)
      {
        name: $name
        start: $times.start
        stop: $times.stop
        duration: $duration
      }
    }
  let total = $times | get duration | math sum
  { hooks: $times, total: $total }
}

export def "serialize block" [block: closure] {
  view source $block | str trim -lc '{' | str trim -rc '}'
}

export def "serialize env-smart" [
  env_record: record
  --default (-d) # Default to loading $env
] {
  if ($env_record | is-empty) {
    return
  }
  [
    "use nushell/env.nu smart-load-env"
    ($"smart-load-env --default=($default) " ++ ($env_record | to nuon))
  ]
}
