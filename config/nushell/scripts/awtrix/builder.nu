# Awtrix App Builder Pattern
# Provides a fluent API for creating custom Awtrix apps

# Initialize a new app builder
export def init [name: string] {
  { name: $name, payload: {} }
}

# Add text to display
export def text [txt: string] {
  let state = $in
  $state | update payload { |p| $p.payload | insert text $txt }
}

# Add icon
export def icon [ico: string] {
  let state = $in
  $state | update payload { |p| $p.payload | insert icon $ico }
}

# Set text color
export def color [col] {
  let state = $in
  $state | update payload { |p| $p.payload | insert color $col }
}

# Enable rainbow effect
export def rainbow [] {
  let state = $in
  $state | update payload { |p| $p.payload | insert rainbow true }
}

# Set display duration in seconds
export def duration [dur: int] {
  let state = $in
  $state | update payload { |p| $p.payload | insert duration $dur }
}

# Add sound to play
export def sound [snd: string] {
  let state = $in
  $state | update payload { |p| $p.payload | insert sound $snd }
}

# Hold the app (don't auto-advance)
export def hold [] {
  let state = $in
  $state | update payload { |p| $p.payload | insert hold true }
}

# Set repeat count
export def repeat [count: int] {
  let state = $in
  $state | update payload { |p| $p.payload | insert repeat $count }
}

# Submit the app to Awtrix (create/update custom app)
export def submit [] {
  let state = $in
  use core.nu api-request
  api-request $"/custom?name=($state.name)" --method POST --body $state.payload
}

# Draw commands submodule
export module draw {
  # Draw a pixel at position (x, y) with color
  export def pixel [x: int, y: int, color] {
    let state = $in
    let cmd = { dp: [$x, $y, $color] }
    $state | update payload { |p|
      $p.payload | upsert draw ($p.payload.draw? | default [] | append $cmd)
    }
  }

  # Draw a line from (x0, y0) to (x1, y1) with color
  export def line [x0: int, y0: int, x1: int, y1: int, color] {
    let state = $in
    let cmd = { dl: [$x0, $y0, $x1, $y1, $color] }
    $state | update payload { |p|
      $p.payload | upsert draw ($p.payload.draw? | default [] | append $cmd)
    }
  }

  # Draw a rectangle with top-left corner at (x, y), width w, height h, and color
  export def rect [x: int, y: int, w: int, h: int, color] {
    let state = $in
    let cmd = { dr: [$x, $y, $w, $h, $color] }
    $state | update payload { |p|
      $p.payload | upsert draw ($p.payload.draw? | default [] | append $cmd)
    }
  }

  # Draw a filled rectangle with top-left corner at (x, y), width w, height h, and color
  export def filled-rect [x: int, y: int, w: int, h: int, color] {
    let state = $in
    let cmd = { df: [$x, $y, $w, $h, $color] }
    $state | update payload { |p|
      $p.payload | upsert draw ($p.payload.draw? | default [] | append $cmd)
    }
  }

  # Draw a circle with center at (x, y), radius r, and color
  export def circle [x: int, y: int, r: int, color] {
    let state = $in
    let cmd = { dc: [$x, $y, $r, $color] }
    $state | update payload { |p|
      $p.payload | upsert draw ($p.payload.draw? | default [] | append $cmd)
    }
  }

  # Draw a filled circle with center at (x, y), radius r, and color
  export def filled-circle [x: int, y: int, r: int, color] {
    let state = $in
    let cmd = { dfc: [$x, $y, $r, $color] }
    $state | update payload { |p|
      $p.payload | upsert draw ($p.payload.draw? | default [] | append $cmd)
    }
  }

  # Draw text with top-left corner at (x, y) and color
  export def text [x: int, y: int, txt: string, color] {
    let state = $in
    let cmd = { dt: [$x, $y, $txt, $color] }
    $state | update payload { |p|
      $p.payload | upsert draw ($p.payload.draw? | default [] | append $cmd)
    }
  }

  # Draw a RGB888 bitmap array with top-left corner at (x, y) and size (w, h)
  export def bitmap [x: int, y: int, w: int, h: int, data: list] {
    let state = $in
    let cmd = { db: [$x, $y, $w, $h, $data] }
    $state | update payload { |p|
      $p.payload | upsert draw ($p.payload.draw? | default [] | append $cmd)
    }
  }
}
