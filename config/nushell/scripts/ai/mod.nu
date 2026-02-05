def complete-model [] {
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

const OPENCODE_BASE_THEMES = [
  nord
  monokai
  solarized
  ayu
  aura
  nightowl
  tokyonight
  deltarune
  shadesofpurple
  catppuccin
  "oc-1"
  onedarkpro
  undertale
  vesper
  gruvbox
  dracula
  carbonfox
]

export def opencode-user-themes [] {
  glob ([$env.XDG_CONFIG_HOME opencode/themes/*.json] | path join)
  | reduce --fold {} {|theme acc|
    $acc | upsert ($theme | path basename | path parse | get stem) ($theme | path expand --no-symlink)
  }
}

export def complete-theme [] {
  $OPENCODE_BASE_THEMES ++ (opencode-user-themes | columns)
}

const NOCONTEXT_HOME = "/tmp/oc-nocontext"
const NOCONTEXT_CONFIG_HOME = [$NOCONTEXT_HOME config] | path join

# Ask a question using OpenCode
def --env opencode-nocontext-setup [--theme: string] {
  let config_file = [$env.XDG_CONFIG_HOME opencode/opencode.jsonc] | path join
  let tmp_home = $NOCONTEXT_HOME | path expand
  let tmp_config_home = $NOCONTEXT_CONFIG_HOME | path expand

  let tmp_day_dir = [$tmp_home (date now | format date "%Y-%m-%d")] | path join
  mkdir $tmp_day_dir
  let tmp_dir = mktemp -p $tmp_day_dir --directory
  cd $tmp_dir

  let tmp_opencode_config_dir = [$tmp_config_home opencode] | path join
  let tmp_opencode_config = [$tmp_opencode_config_dir opencode.jsonc] | path join

  mkdir $tmp_opencode_config_dir

  if not ($theme | is-empty) {
    if $theme not-in $OPENCODE_BASE_THEMES {
      let user_themes = opencode-user-themes
      let user_theme = $user_themes | get -o $theme
      if ($user_theme | is-empty) or not ($user_theme | path exists) {
        error make -u {msg: $"theme ($theme) not found"}
      }

      let theme_dir = [$tmp_opencode_config_dir themes] | path join
      let user_theme_file = ($user_theme | path basename)
      mkdir $theme_dir
      ln -s $user_theme ([$theme_dir $user_theme_file] | path join)
    }
  }

  open --raw $config_file | from json
  | select keybinds plugin model autoupdate
  | if ($theme | is-not-empty) { insert theme $theme } else { $in }
  | to json | save --force $tmp_opencode_config

  $env.XDG_CONFIG_HOME = $tmp_config_home
}

# Ask a question using OpenCode
export def opencode-nocontext [
  --model (-m): string@complete-model = "anthropic/claude-sonnet-4-5" # Model to use (default: anthropic/claude-sonnet-4-5)
  --theme (-t): string@complete-theme = "tokyonight" # Theme to use (default: tokyonight)
  ...args: string
] {
  let flags = [
    ...(if ($model | is-not-empty) { ["--model" $model] } else { [] })
  ]
  opencode-nocontext-setup --theme=$theme
  opencode ...$flags ...$args
}

# Ask a question using OpenCode
export def opencode-ask [
  --model (-m): string@complete-model = "anthropic/claude-sonnet-4-5" # Model to use (default: anthropic/claude-sonnet-4-5)
  --user-config (-c) # Use standard OpenCode config dir (otherwise uses minimal config without plugins)
  --hide-thinking (-T) # Hide thinking output
  ...args: string
] {
  let flags = [
    ...(if ($model | is-not-empty) { ["--model" $model] } else { [] })
    ...(if not $hide_thinking { ["--thinking"] } else { [] })
  ]
  if not $user_config {
    opencode-nocontext-setup
  }
  opencode run ...$flags ...$args
}

export def opencode-nocontext-clear [] {
  rm -vrf $NOCONTEXT_HOME
}

export alias oc = opencode
export alias ocn = opencode-nocontext
export alias ocn-clear = opencode-nocontext-clear
export alias ask = opencode-ask
