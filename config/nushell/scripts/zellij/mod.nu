use types/kdl.nu *

export use ./layout.nu

export def in-zellij [] {
  $env.ZELLIJ? | is-not-empty
}

export def ensure-zellij [
  --invert # Invert the condition
] {
  if not (in-zellij) xor $invert {
    error make -u {
      msg: (if $invert {
        "Already in a Zellij session"
      } else {
        "Must be in a Zellij session"
      })
    }
  }
}

# Execute a closure with a temporary layout file, cleaning up after
export def with-layout [
  layout: any       # Layout structure (pass to `to kdl`)
  action: closure   # Closure receiving the temp file path
] {
  let tmp_layout = mktemp -t "XXXXXX.kdl"
  try {
    $layout | to kdl -v 1 | save -f $tmp_layout
    do $action $tmp_layout
    rm -f $tmp_layout
  } catch { |e|
    rm -f $tmp_layout
    error make -u { msg: $e.msg }
  }
}

