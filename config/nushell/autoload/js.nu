# find the root of the pnpm workspace
def pnpm-workspace-root [] {
  mut current_dir = $env.PWD

  while $current_dir != "/" {
    let workspace_file = ($current_dir | path join "pnpm-workspace.yaml")
    if ($workspace_file | path exists) {
      return $current_dir
    }
    $current_dir = ($current_dir | path dirname)
  }

  error make {msg: "pnpm-workspace.yaml not found."}
}

# usage: pnpm-pick-workspace [-pn] [query]
# pick and print path to pnpm workspace
# -p: print path (default)
# -n: print name
# -R: hide root
def pnpm-pick-workspace [
  --path (-p)        # print path (default)
  --name (-n)        # print name
  --hide-root (-R)   # hide root
  query?: string     # search query
] {
  let mode = if $name { "name" } else { "path" }
  let root = (pnpm-workspace-root)
  let query_str = ($query | default "")

  # Build jq command - using string concatenation to avoid escaping issues
  let jq_cmd = ('jq --arg pwd "$(realpath --relative-to="' + $root + '" "$PWD")" -r "\"\(if \$pwd == \".\" then \"./\" else \"./\" + \$pwd end):\(.name)\"" package.json')

  # Collect workspace info
  let workspace_list = (
    if not $hide_root {
      do --ignore-errors { ^sh -c $"cd ($root) && ($jq_cmd)" }
    } else {
      ""
    } | lines | append (
      ^pnpm -rc --parallel exec $jq_cmd | lines
    ) | where { |line| not ($line | is-empty) }
    | str join "\n"
  )

  # Format with column and select with fzf
  let sel = (
    echo $workspace_list
    | ^column --table --separator=:
    | ^fzf -1 --query $query_str --height 10 --preview $"echo 'path: ' {1} && echo 'pkg:  ' {2} && eza -la --color=always ($root)/{1}"
    | complete
  )

  if $sel.exit_code != 0 or ($sel.stdout | is-empty) {
    return
  }

  let selected = ($sel.stdout | str trim)

  let res = match $mode {
    "path" => {
      let path_part = ($selected | split row " " | first)
      $"($root)/($path_part)" | path expand
    }
    "name" => {
      $selected | split row " " | get 1
    }
    _ => { $selected }
  }

  return $res
}

# pnpm
alias pp = pnpm
alias ppi = pnpm install
alias ppr = pnpm run
alias pprf = pnpm run --filter
alias pprff = pnpm run --filter (pnpm-pick-workspace -n -R)
alias pprw = pnpm -w run
alias ppx = pnpm exec
alias ppxf = pnpm --filter (pnpm-pick-workspace -n -R) exec
alias ppxw = pnpm -w exec
alias ppa = pnpm add
alias ppad = pnpm add -D
alias ppaf = pnpm add --filter
alias ppaff = pnpm add --filter (pnpm-pick-workspace -n -R)
alias ppadf = pnpm add -D --filter
alias ppadff = pnpm add -D --filter (pnpm-pick-workspace -n -R)
alias pprm = pnpm remove
alias pprmf = pnpm remove --filter
alias pprmff = pnpm remove --filter (pnpm-pick-workspace -n -R)
alias pwr = cd (pnpm-workspace-root)
alias ppw = cd (pnpm-pick-workspace)

# bun
alias b = bun
alias br = bun run
alias bi = bun install
alias bb = bun run build
alias brb = bun run build
alias brb = bun run build
alias bu = bun update
alias bx = bun x
alias ba = bun add
alias bad = bun add --dev
alias bt = bun test
alias brt = bun run test
alias brm = bun remove

