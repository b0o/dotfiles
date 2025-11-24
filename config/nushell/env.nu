# like load-env, but only sets the environment variable if
# it's not already set
def --env default-env [defaults: record] {
  let unset = $defaults
    | transpose name value
    | where {|it| $env | get -o $it.name | is-empty }
    | transpose -dr
  if ($unset | is-not-empty) {
    $unset | load-env
  }
}

# Add paths to PATH
def --env add-path [paths: oneof<string, list<string>>] {
  $env.PATH = $env.PATH
  | append (if ($paths | describe) == "string" { [$paths] } else { $paths })
  | uniq
}

default-env ({
  EDITOR: "nvim"
  GIT_PROJECTS_DIR: $"($nu.home-path)/git"
  XDG_CONFIG_HOME: $"($nu.home-path)/.config"
  XDG_DATA_HOME: $"($nu.home-path)/.local/share"
  XDG_CACHE_HOME: $"($nu.home-path)/.cache"
  DOTFILES_HOME: $"($env.XDG_CONFIG_HOME)/dotfiles"
  GPG_TTY: (^tty | str trim)
})

add-path ([
  $"($nu.home-path)/.nix-profile/bin"
  $"($nu.home-path)/.local/bin"
  $"($nu.home-path)/.bun/bin"
  $"($nu.home-path)/bin"
])

# See ./autoload/plugins.nu
$env.NU_PLUGINS = [
  # { name: example, cmd?: nu_plugin_example }
  # { name: example, path?: /path/to/plugin }
  { name: skim, cmd: nu_plugin_skim }
]

$env.NU_LIB_DIRS = [
  $nu.default-config-dir
]

$env.config.show_banner = false

if (($env.SSH_AUTH_SOCK? | is-empty) or (not ($env.SSH_AUTH_SOCK? | path exists))) and (which gpgconf | is-not-empty) {
  try {
    $env.SSH_AUTH_SOCK = (^gpgconf --list-dirs agent-ssh-socket | str trim)
  } catch {
    print -e "Failed getting SSH auth socket path from gpgconf"
  }
}

$env.FZF_DEFAULT_COMMAND = (
  'fd --type f --hidden --exclude .git'
)
$env.FZF_DEFAULT_OPTS = ([
  --layout reverse
  --bind ctrl-p:up
  --bind ctrl-n:down
  --bind alt-p:up
  --bind alt-n:down
  --bind btab:up
  --bind tab:down
  --bind ctrl-j:preview-down
  --bind ctrl-k:preview-up
  --bind alt-j:preview-half-page-down
  --bind alt-k:preview-half-page-up
  --preview-border none
  --separator ─
  --scrollbar ▌
  --preview ([
    '"'
    "bat --decorations=never --color=always {} 2>/dev/null"
    " || "
    "eza -algF --git --group-directories-first -TL1 --color=always {}"
    '"'
  ] | str join '')
  --color ([
    # Lavi colorscheme
    fg:#FFF1E0
    bg:#25213B
    fg+:#FFFFFF
    bg+:#2D2846
    gutter:#25213B
    hl:#E2B2F1
    hl+:#F5D9FD
    query:#FFF1E0
    disabled:#9A9AC0
    info:#848FF1
    prompt:#B29EED
    pointer:#9C73FE
    marker:#7CF89C
    spinner:#3FC4C4
    header:#B29EED
    footer:#B29EED
    border:#8977A8
    scrollbar:#4C435C
    separator:#4C435C
    preview-border:#8977A8
    preview-scrollbar:#4C435C
    label:#EBBBF9
    preview-label:#EBBBF9
    preview-fg:#EEE6FF
    preview-bg:#1D1A2E
  ] | str join ",")
] | str join ' ')

$env.SKIM_DEFAULT_OPTIONS = ([
  --layout reverse
  --color ([
    # Lavi colorscheme
    bg:-1
    bg+:-1
    fg+:12
    current:#FFFFFF
    current_bg:#2D2846
    matched:#E2B2F1
    matched_bg:empty
    current_match:#F5D9FD
    current_match_bg:empty
    info:#848FF1
    prompt:#B29EED
    cursor:#9C73FE
    selected:#7CF89C
    spinner:#3FC4C4
    header:#B29EED
    border:#8977A8
  ] | str join ",")
] | str join ' ')
