# Expand batch shorthand (e.g., "F25" -> "Fall 2025")
def expand-batch [code: string] {
    let season_map = {
        F: "Fall"
        S: "Summer"
        W: "Winter"
        X: "Spring"
    }

    let valid_seasons = ["Fall", "Summer", "Winter", "Spring"]

    # Determine the format and extract season and year
    let result = if (($code | str length) <= 3) {
        # Format: S25, F24, etc (shorthand)
        let season_code = ($code | str substring 0..0 | str upcase)
        let year_code = ($code | str substring 1..)
        let season = ($season_map | get -o $season_code)
        # let season = batch-season $season_code

        if ($season == null) {
            error make {msg: $"Invalid batch code: ($code). Use F/S/W/X followed by year like F25 or W24"}
        }

        {season: $season, year: $year_code}
    } else {
        # Check if it starts with a valid season name
        let matching_season = ($valid_seasons | where {|s| ($code | str starts-with $s)} | first)

        if ($matching_season == null) {
            error make {msg: $"Invalid batch format: ($code). Season must be Fall, Summer, Winter, or Spring"}
        }

        # Extract the year part after the season
        let year_part = ($code | str substring ($matching_season | str length)..)

        # Handle different separators (space, no space)
        let year = ($year_part | str trim)

        {season: $matching_season, year: $year}
    }

    # Convert 2-digit year to 4-digit
    let full_year = if (($result.year | str length) == 2) {
        $"20($result.year)"
    } else if (($result.year | str length) == 4) {
        $result.year
    } else {
        error make {msg: $"Invalid year format: ($result.year). Use 2-digit (25) or 4-digit (2025) year"}
    }

    # Build the result
    let batch_name = $"($result.season) ($full_year)"

    # Validate against available batches
    let available = (batches | get batch)

    if ($batch_name not-in $available) {
        print $"Warning: Batch '($batch_name)' not found in YC database"
        print $"Available batches: ($available | str join ', ')"
    }

    $batch_name
}

# Given any batch format, return the short batch name like "F25"
export def batch-short [batch: string] {
    let season_to_code = {
        Fall: "F"
        Summer: "S"
        Winter: "W"
        Spring: "X"
    }

    # Parse the canonical format "Season YYYY"
    let parts = ($batch | split row " ")
    let season = ($parts | first)
    let year = ($parts | last)

    # Get the short code
    let short_code = ($season_to_code | get $season)
    let short_year = ($year | str substring 2..)

    $"($short_code)($short_year)"
}

# List all available batches from Y Combinator
export def batches [] {
  let cache_file = ($nu.cache-dir | path join "xtras_ycombinator_batches.json")
  if ($cache_file | path exists) {
    let cached = open $cache_file
    if ((date now) - ($cached.date | into datetime)) < 1day {
      return $cached.batches
    }
    rm $cache_file
  }
  let request_body = {
    requests: [
      {
        indexName: "YCCompany_production"
        params: "analytics=false&clickAnalytics=false&facets=batch&hitsPerPage=0&maxValuesPerFacet=1000&page=0&query="
      }
    ]
  }

  let response = (
    http post
    --content-type "application/json"
    --headers [
      Accept-Language "en-US,en;q=0.9"
      Origin "https://www.ycombinator.com"
      Referer "https://www.ycombinator.com/"
      accept "application/json"
    ]
    "https://45bwzj1sgc-dsn.algolia.net/1/indexes/*/queries?x-algolia-agent=Algolia%20for%20JavaScript%20(3.35.1)%3B%20Browser%3B%20JS%20Helper%20(3.16.1)&x-algolia-application-id=45BWZJ1SGC&x-algolia-api-key=MjBjYjRiMzY0NzdhZWY0NjExY2NhZjYxMGIxYjc2MTAwNWFkNTkwNTc4NjgxYjU0YzFhYTY2ZGQ5OGY5NDMxZnJlc3RyaWN0SW5kaWNlcz0lNUIlMjJZQ0NvbXBhbnlfcHJvZHVjdGlvbiUyMiUyQyUyMllDQ29tcGFueV9CeV9MYXVuY2hfRGF0ZV9wcm9kdWN0aW9uJTIyJTVEJnRhZ0ZpbHRlcnM9JTVCJTIyeWNkY19wdWJsaWMlMjIlNUQmYW5hbHl0aWNzVGFncz0lNUIlMjJ5Y2RjJTIyJTVE"
    $request_body
  )

  let batches = $response.results.0.facets.batch | transpose batch count | sort-by batch --reverse
  mkdir $nu.cache-dir
  if ($nu.cache-dir | path exists) {
    ({ batches: $batches, date: (date now) } | save $cache_file)
  }
  $batches
}

def "complete companies batch" [context: string] {
  let batch_value = ($context | parse --regex '(?:--batch|-b)[\s=]+(.*)' | get -o 0.capture0 | default "")
  let all_valid_shorts = (batches | where batch != "Unspecified" | get batch | each {|b| batch-short $b})

  # Only include valid batch codes in selected list
  let selected = (
    $batch_value
    | split row ","
    | str trim
    | where {|b| not ($b | is-empty) and ($b in $all_valid_shorts)}
  )

  let prefix = if ($selected | is-empty) { "" } else { ($selected | str join ",") + "," }

  {
    options: {
      sort: false
      case_sensitive: false
      completion_algorithm: fuzzy
    },
    completions: (
      batches
      | where batch != "Unspecified"
      | get batch
      | each {|b|
          let short = (batch-short $b)
          if $short not-in $selected {
            {
              value: $"($prefix)($short)"
              description: $b
              style: (match ($b | split row " " | first) {
                "Fall" => "red",
                "Summer" => "green",
                "Winter" => "blue",
                "Spring" => "magenta"
              })
            }
          }
        }
    )
  }
}

# Get company information from Y Combinator's database
export def companies [
    --query (-q): string = ""             # Search query
    --batch (-b): string@"complete companies batch" # Filter by batch(es), comma-separated e.g., "F25,S25,W24"
    --industry (-i): list<string> = []    # Filter by industry
    --subindustry (-s): list<string> = [] # Filter by subindustry
    --region (-r): list<string> = []      # Filter by region
    --hiring                              # Only show companies that are hiring
    --nonprofit                           # Only show nonprofits
    --top-company                         # Only show top companies
    --has-video                           # Only show companies with demo day videos
    --page (-p): int = 0                  # Page number (0-indexed)
    --per-page: int = 1000                # Results per page
] {
    # Build facet filters as nested arrays
    let facet_filters = (
        [
            # Batch filter - handle comma-separated batches
            (if ($batch | is-empty) { null } else {
                $batch
                | split row ","
                | each {|b| $"batch:(expand-batch ($b | str trim))"}
            })
            # Industry filter
            (if ($industry | is-empty) { null } else {
                $industry | each {|ind| $"industries:($ind)"}
            })
            # Subindustry filter
            (if ($subindustry | is-empty) { null } else {
                $subindustry | each {|sub| $"subindustry:($sub)"}
            })
            # Region filter
            (if ($region | is-empty) { null } else {
                $region | each {|reg| $"regions:($reg)"}
            })
            # isHiring filter
            (if $hiring { ["isHiring:true"] } else { null })
            # Nonprofit filter
            (if $nonprofit { ["nonprofit:true"] } else { null })
            # Top company filter
            (if $top_company { ["top_company:true"] } else { null })
            # Demo day video filter
            (if $has_video { ["demo_day_video_public:true"] } else { null })
        ]
        | compact
    )

    let facet_filter_param = if ($facet_filters | is-empty) {
        "[]"
    } else {
        $facet_filters | to json --raw | url encode
    }

    # Build the request body
    let request_body = {
        requests: [
            {
                indexName: "YCCompany_production"
                params: $"facetFilters=($facet_filter_param)&facets=%5B%22app_answers%22%2C%22app_video_public%22%2C%22batch%22%2C%22demo_day_video_public%22%2C%22industries%22%2C%22isHiring%22%2C%22nonprofit%22%2C%22question_answers%22%2C%22regions%22%2C%22subindustry%22%2C%22top_company%22%5D&hitsPerPage=($per_page)&maxValuesPerFacet=1000&page=($page)&query=($query)&tagFilters="
            }
        ]
    }

    # Make the API request
    let response = (
        http post
        --content-type "application/json"
        --headers [
            Accept-Language "en-US,en;q=0.9"
            Origin "https://www.ycombinator.com"
            Referer "https://www.ycombinator.com/"
            accept "application/json"
        ]
        "https://45bwzj1sgc-dsn.algolia.net/1/indexes/*/queries?x-algolia-agent=Algolia%20for%20JavaScript%20(3.35.1)%3B%20Browser%3B%20JS%20Helper%20(3.16.1)&x-algolia-application-id=45BWZJ1SGC&x-algolia-api-key=MjBjYjRiMzY0NzdhZWY0NjExY2NhZjYxMGIxYjc2MTAwNWFkNTkwNTc4NjgxYjU0YzFhYTY2ZGQ5OGY5NDMxZnJlc3RyaWN0SW5kaWNlcz0lNUIlMjJZQ0NvbXBhbnlfcHJvZHVjdGlvbiUyMiUyQyUyMllDQ29tcGFueV9CeV9MYXVuY2hfRGF0ZV9wcm9kdWN0aW9uJTIyJTVEJnRhZ0ZpbHRlcnM9JTVCJTIyeWNkY19wdWJsaWMlMjIlNUQmYW5hbHl0aWNzVGFncz0lNUIlMjJ5Y2RjJTIyJTVE"
        $request_body
    )

    # Return the results
    $response.results.0.hits
}
