export alias oc = opencode

export def complete-model [] {
  use std-rfc/kv *
  let table = "user_ai_opencode"
  let key = "models"
  let cached = kv get --universal --table $table $key
  if ($cached | is-not-empty) and ((date now) - $cached.timestamp < 1day) {
    $cached.models
  } else {
    kv set --universal --table=$table --return=value $key {
      timestamp: (date now)
      models: (opencode models | lines)
    } | get models
  }
}

# Ask a question using OpenCode
export def ask [
  --model (-m): string@complete-model="anthropic/claude-sonnet-4-5" # Model to use (default: anthropic/claude-sonnet-4-5)
  --user-config (-c)  # Use standard OpenCode config dir (otherwise uses minimal config without plugins)
  ...args: string
] {
  let flags = [
    ...(if ($model | is-not-empty) { ["--model" $model] } else { [] })
  ]
  if not $user_config {
    let config_file = [$env.XDG_CONFIG_HOME opencode/opencode.jsonc] | path join
    let tmp_config_home = "/tmp/opencode-ask"
    let tmp_opencode_config_dir = [$tmp_config_home opencode] | path join
    let tmp_opencode_config = [$tmp_opencode_config_dir opencode.jsonc] | path join

    mkdir $tmp_opencode_config_dir
    cd $tmp_opencode_config_dir

    open --raw $config_file | from json
    | select keybinds plugin model autoupdate
    | to json | save --force $tmp_opencode_config

    $env.XDG_CONFIG_HOME = $tmp_config_home
  }
  opencode run ...$args
}
