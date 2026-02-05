export def nix-profiles [] {
  $env.NIX_PROFILES? | split row ' ' | default []
}

export def is-using-home-manager []: nothing -> bool {
  for profile in (nix-profiles) {
    let profile = $profile | path expand
    let manifest = [$profile manifest.nix] | path join
    if ($manifest | path exists) and (
      nix eval --raw --impure
      --expr $"\(builtins.head \(import ($manifest)\)\).name"
    ) == "home-manager-path" {
      return true
    }
  }
  false
}

export def is-using-flakey-profile []: nothing -> bool {
  # TODO: better detection of flakey-profile
  not (is-using-home-manager)
}
