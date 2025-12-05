use ../../builder.nu [init, draw, duration, submit]
use ./palettes.nu [palettes, temporal-palette]

def get-color [
  kind: string
  --palette: record
]: nothing -> int {
  ($palette | default $palettes.default) | get -o $kind | default ($palette.NONE)
}

# Get the date of the first day of the week for a given date,
# assuming each week starts on Sunday
def week-start [date: datetime]: nothing -> datetime {
  $date - ($date | format date "%w" | into duration -u day)
}

# Fetch GitHub contribution data and process it into pixel array
def contributions-chart [
  --user: string  # GitHub username (defaults to authenticated user)
  --date: datetime  # End date, will fetch 32 weeks ending on this date (defaults to today)
  --palette (-p): oneof<string,record>  # Color palette
  --width (-w): int = 32  # Width of the heatmap
]: nothing -> list<int> {
  let now = date now
  let date = $date | default $now
  let end_week_start = week-start $date
  let first_week_start = $end_week_start - ($width - 1 | into duration -u wk)

  let palette = if ($palette | is-empty) {
    temporal-palette --date=$date
  } else if ($palette | describe) == "record" {
    $palette
  } else if $palette == "random" {
    $palettes | values | get (random int 0..(($palettes | columns | length) - 1))
  } else {
    $palettes | get ($palette | into string)
  }

  let response = (^gh api graphql
    -F $"from=($first_week_start | format date "%FT00:00:00%:z")"
    -F $"to=($end_week_start + 7day | format date "%FT00:00:00%:z")"
    -F $"user=($user)"
    -f query='
      query($user: String!, $from: DateTime!, $to: DateTime!) {
        user(login: $user) {
          contributionsCollection(from: $from, to: $to) {
            contributionCalendar {
              weeks {
                contributionDays {
                  date
                  contributionLevel
                }
              }
            }
          }
        }
      }
    ') | from json

  let gh_data = try {
    $response.data.user.contributionsCollection.contributionCalendar.weeks
  } catch {
    error make -u { msg: "Failed to fetch GitHub contribution data" }
  }

  let dates = ($gh_data.contributionDays
    | flatten
    | reduce -f {} { |day, acc| $acc | insert $day.date $day.contributionLevel })

  (0..(7 * $width - 1)) | each { |i|
    let weeks = $i mod $width | into duration -u wk
    let days = $i / $width | math floor | into duration -u day
    let date = $first_week_start + $weeks + $days
    let date_str = ($date | format date "%Y-%m-%d")
    let kind = ($dates | get -o $date_str | default "NONE")
    let kind = if ($kind == "NONE" and $now < $date) { "FUTURE" } else { $kind }
    get-color --palette=$palette $kind
  }
}

def complete-palette [] {
  $palettes | columns | append "random"
}

# Run the GitHub contribution heatmap app
export def run [
  --user (-u): string  # GitHub username (defaults to authenticated user)
  --date (-d): datetime  # End date, will fetch 32 weeks ending on this date (defaults to today)
  --palette (-p): oneof<string,record>@complete-palette  # Color palette
  --width (-w): int = 32  # Width of the heatmap
  -x: int = 0  # X position of the heatmap
  -y: int = 0  # Y position of the heatmap
] {
  let user = if ($user | is-not-empty) { $user } else {
    try {
      ^git config github.user
    } catch {
      error make -u { msg: "No GitHub user configured. Pass --user <username> or set github.user in git config." }
    }
  }
  let chart = contributions-chart --date=$date --user=$user --width=$width --palette=$palette
  init "gh"
    | draw bitmap $x $y $width 8 $chart
    | duration 20
    | submit
}
