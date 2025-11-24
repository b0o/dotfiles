def _plugin_path [plugin: record] {
  if ($plugin | get -o path | is-not-empty) {
    $plugin.path
  } else if ($plugin | get -o cmd | is-not-empty) {
    which $plugin.cmd | first | get path
  } else {
    error make -u {msg: $"Plugin ($plugin.name) has no path or cmd"}
  }
}

def _init_plugins [] {
  if ($env | get -o NU_PLUGINS | is-empty) {
    return
  }
  let installed_plugins = plugin list
  mut reload = false
  for plugin in $env.NU_PLUGINS {
    let p = $installed_plugins | where name == $plugin.name | get -o 0
    if ($p | is-not-empty) {
      continue
    }
    let path = _plugin_path $plugin
    plugin add $path
    print -e $"Installed plugin ($plugin.name) from ($path)"
    $reload = true
  }

  if $reload {
    print -e "Reload nushell to load new plugins"
  }
}

def _complete-plugin-name [spans: list<string>] {
  $env.NU_PLUGINS | get name
}

# Update nushell plugins
@complete _complete-plugin-name
def "plugin update" [...plugins: string] {
  if ($env | get -o NU_PLUGINS | is-empty) {
    print -e "$env.NU_PLUGINS is empty"
  }
  let plugins = if ($plugins | is-empty) {
    $env.NU_PLUGINS
  } else {
    for plugin in $plugins {
      if ($env.NU_PLUGINS | where name == $plugin | is-empty) {
        error make -u {msg: $"Plugin ($plugin) not found"}
      }
    }
    $env.NU_PLUGINS | where name in $plugins
  }
  if ($plugins | is-empty) {
    print -e "No plugins to update"
    return
  }
  for plugin in $plugins {
    let path = _plugin_path $plugin
    plugin rm $plugin.name
    plugin add $path
    print -e $"Updated plugin ($plugin.name) from ($path)"
  }
  print -e "Reload nushell to load new plugins"
}

_init_plugins
