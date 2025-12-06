# Format a duration in human-readable relative time format
#
# Converts a duration into a human-friendly string like "5 minutes ago" or "in 2 hours".
# Positive durations represent the past (uses "ago"), while negative durations represent
# the future (uses "in").
#
# Examples:
#   > 5min | format duration human
#   5 minutes ago
#
#   > -2hr | format duration human
#   in 2 hours
#
#   > (date now) - ('2024-01-01' | into datetime) | format duration human
#   9 months ago
export def "duration human" []: duration -> string {
  let dur = $in
  let abs_dur = ($dur | math abs)

  let seconds = ($abs_dur / 1sec)
  let minutes = ($abs_dur / 1min)
  let hours = ($abs_dur / 1hr)
  let days = ($abs_dur / 1day)
  let weeks = ($abs_dur / 1wk)
  let years = ($abs_dur / 365day)

  let result = if $seconds < 60 {
    if $seconds == 1 { "1 second" } else { $"($seconds | math round) seconds" }
  } else if $minutes < 60 {
    if $minutes == 1 { "1 minute" } else { $"($minutes | math round) minutes" }
  } else if $hours < 24 {
    if $hours == 1 { "1 hour" } else { $"($hours | math round) hours" }
  } else if $days < 7 {
    if $days == 1 { "1 day" } else { $"($days | math round) days" }
  } else if $days < 30 {
    if $weeks == 1 { "1 week" } else { $"($weeks | math round) weeks" }
  } else if $days < 365 {
    let months = ($days / 30 | math round)
    if $months == 1 { "1 month" } else { $"($months) months" }
  } else {
    if $years == 1 { "1 year" } else { $"($years | math round) years" }
  }

  # Positive duration = past, negative = future
  if $dur < 0sec {
    $"in ($result)"
  } else {
    $"($result) ago"
  }
}

