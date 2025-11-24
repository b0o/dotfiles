# Awtrix3 CLI Module for Nushell
# Save this as awtrix.nu in your Nushell modules directory

const CONFIG_FILE = "awtrix-config.json"

# Get the config directory path
def get-config-dir [] {
    let xdg = $env.XDG_CONFIG_HOME? | default ($env.HOME | path join ".config")
    $xdg | path join "awtrix"
}

# Get the full config file path
def get-config-path [] {
    get-config-dir | path join $CONFIG_FILE
}

# Load the Awtrix configuration
def load-config [] {
    let config_path = get-config-path

    if not ($config_path | path exists) {
        error make {
            msg: "Awtrix not configured"
            label: {
                text: "Run 'awtrix use <url>' first to configure your device"
                span: (metadata $config_path).span
            }
        }
    }

    open $config_path
}

# Make an HTTP request to the Awtrix device
export def api-request [
    endpoint: string
    --method: string = "GET"
    --body: any = null
] {
    let config = load-config
    let url = [$config.url "api"] | path join ($endpoint | str trim --left --char "/")
    let headers = {
      "Content-Type": "application/json"
      "Accept": "application/json"
      "Authorization": (if ($config.user? | is-not-empty) and ($config.password? | is-not-empty) {
        let auth = [$config.user $config.password] | str join ":" | encode base64
        $"Basic ($auth)"
      })
    }
    let body = $body | default null | to json
    let res = match $method {
        "GET" => { http get $url -H $headers }
        "HEAD" => { http head $url -H $headers }
        "OPTIONS" => { http options $url -H $headers }
        "PATCH" => { http patch $url -H $headers $body }
        "POST" => { http post $url -H $headers $body }
        "PUT" => { http put $url -H $headers $body }
        "DELETE" => { http delete $url -H $headers }
        _ => { error make {msg: $"Unsupported HTTP method: ($method)"} }
    }
    if ($res == "OK") {
      null
    } else {
      $res
    }
}

# Show current configuration
export def config [] {
    let config_path = get-config-path
    if not ($config_path | path exists) {
        print "No configuration found. Use 'awtrix config set --api <url>' to configure."
        return
    }
    open $config_path | if ($in.password? != null) { update password "********" } else $in
}

# Set configuration options
export def "config set" [
    --api: string            # Device URL (e.g., http://192.168.1.100)
    --user: string           # Username for basic auth
    --password: string       # Password for basic auth (use '-' to read from stdin, or "" for interactive prompt)
] {
    let stdin = $in
    let config_dir = get-config-dir
    let config_path = get-config-path

    # Create config directory if it doesn't exist
    if not ($config_dir | path exists) {
        mkdir $config_dir
    }

    # Load existing config or create new one
    mut config = if ($config_path | path exists) {
        open $config_path
    } else {
        {}
    }

    # Update API URL if provided
    if $api != null {
        $config = ($config | upsert url $api)
    }

    # Update user if provided
    if $user != null {
        $config = ($config | upsert user $user)
    }

    # Handle password
    if $password != null {
        if $password == "-" {
            if ($stdin | is-not-empty) {
              $config = ($config | upsert password $stdin)
            } else {
              print -n "Enter password: "
              let interactive_password = input --suppress-output
              print ""
              $config = ($config | upsert password $interactive_password)
            }
        } else {
            # Use provided value
            $config = ($config | upsert password $password)
        }
    }

    # Save config
    $config | to json | save --force $config_path

    print "✓ Configuration updated"
}

# Reset configuration
export def "config reset" [
    --api                    # Reset only the API URL
    --user                   # Reset only the username
    --password               # Reset only the password
] {
    let config_path = get-config-path

    if not ($config_path | path exists) {
        print "No configuration found."
        return
    }

    # If no specific flags, reset everything
    if not ($api or $user or $password) {
        rm $config_path
        print "✓ Configuration reset (all settings cleared)"
        return
    }

    # Reset specific fields
    mut config = open $config_path

    if $api {
        $config = ($config | reject url)
        print "✓ API URL cleared"
    }

    if $user {
        $config = ($config | reject user)
        print "✓ Username cleared"
    }

    if $password {
        $config = ($config | reject password)
        print "✓ Password cleared"
    }

    # Save updated config or remove if empty
    if ($config | is-empty) {
        rm $config_path
        print "  All settings cleared, config file removed"
    } else {
        $config | to json | save --force $config_path
        print $"  Config saved to: ($config_path)"
    }
}

# Get device statistics
export def stats [] {
    api-request "stats" | to json --indent 2
}

# Get list of available effects
export def effects [] {
    api-request "effects"
}

# Get list of available transitions
export def transitions [] {
    api-request "transitions"
}

# Get list of apps in the loop
export def loop [] {
    api-request "loop"
}

# Navigate to the next app
export def "next-app" [] {
    api-request "nextapp" --method POST
    print "✓ Switched to next app"
}

# Navigate to the previous app
export def "previous-app" [] {
    api-request "previousapp" --method POST
    print "✓ Switched to previous app"
}

# Switch to a specific app
export def switch [
    app_name: string  # App name (e.g., Time, Date, Temperature)
] {
    let body = { name: $app_name }
    api-request "switch" --method POST --body $body
    print $"✓ Switched to app: ($app_name)"
}

# Control device power
export def power [
    state: string  # Power state: "on" or "off"
] {
    let power_state = if $state == "on" { true } else { false }
    let body = { power: $power_state }
    api-request "power" --method POST --body $body
    print $"✓ Power ($state)"
}

# Put device to sleep
export def sleep [
    seconds: int  # Sleep duration in seconds
] {
    let body = { sleep: $seconds }
    api-request "sleep" --method POST --body $body
    print $"✓ Device sleeping for ($seconds) seconds"
}

# Send a notification
export def notify [
    text: string              # Text to display
    --icon: string            # Icon ID or filename
    --color: string           # Text color (hex or RGB array)
    --duration: int = 5       # Display duration in seconds
    --rainbow                 # Rainbow effect
    --hold                    # Hold notification until dismissed
    --sound: string           # Sound file to play
] {
    mut body = { text: $text, duration: $duration }

    if $icon != null { $body = ($body | insert icon $icon) }
    if $color != null { $body = ($body | insert color $color) }
    if $rainbow { $body = ($body | insert rainbow true) }
    if $hold { $body = ($body | insert hold true) }
    if $sound != null { $body = ($body | insert sound $sound) }

    api-request "notify" --method POST --body $body
    print "✓ Notification sent"
}

# Dismiss a held notification
export def dismiss [] {
    api-request "notify/dismiss" --method POST
    print "✓ Notification dismissed"
}

# Set a colored indicator
export def indicator [
    number: int               # Indicator number (1-3)
    --color: string           # Color (hex or RGB array)
    --blink: int              # Blink interval in ms
    --fade: int               # Fade interval in ms
    --off                     # Turn indicator off
] {
    if $number < 1 or $number > 3 {
        error make { msg: "Indicator number must be 1, 2, or 3" }
    }

    mut body = {}

    if $off {
        $body = { color: "0" }
    } else if $color != null {
        $body = { color: $color }
        if $blink != null { $body = ($body | insert blink $blink) }
        if $fade != null { $body = ($body | insert fade $fade) }
    } else {
        error make { msg: "Must specify --color or --off" }
    }

    api-request $"indicator($number)" --method POST --body $body
    print $"✓ Indicator ($number) updated"
}

# Play a sound
export def sound [
    name: string  # Sound name or 4-digit MP3 number
] {
    let body = { sound: $name }
    api-request "sound" --method POST --body $body
    print $"✓ Playing sound: ($name)"
}

# Set mood lighting
export def mood [
    --brightness: int = 170   # Brightness (0-255)
    --kelvin: int             # Color temperature in Kelvin
    --color: string           # Color (hex or RGB array)
    --off                     # Turn mood lighting off
] {
    if $off {
        api-request "moodlight" --method POST --body {}
        print "✓ Mood lighting off"
        return
    }

    mut body = { brightness: $brightness }

    if $kelvin != null {
        $body = ($body | insert kelvin $kelvin)
    } else if $color != null {
        $body = ($body | insert color $color)
    } else {
        error make { msg: "Must specify --kelvin, --color, or --off" }
    }

    api-request "moodlight" --method POST --body $body
    print "✓ Mood lighting updated"
}

# Reboot the device
export def reboot [] {
    api-request "reboot" --method POST
    print "✓ Device rebooting..."
}

# Update device settings
export def settings [
    --brightness: int         # Matrix brightness (0-255)
    --auto-brightness         # Automatic brightness
    --auto-transition         # Auto switch to next app
    --app-time: int           # App display duration in seconds
    --uppercase               # Display text in uppercase
] {
    mut body = {}

    if $brightness != null { $body = ($body | insert BRI $brightness) }
    if $auto_brightness { $body = ($body | insert ABRI true) }
    if $auto_transition { $body = ($body | insert ATRANS true) }
    if $app_time != null { $body = ($body | insert ATIME $app_time) }
    if $uppercase { $body = ($body | insert UPPERCASE true) }

    if ($body | is-empty) {
        # GET request to retrieve settings
        api-request "settings"
    } else {
        # POST request to update settings
        api-request "settings" --method POST --body $body
        print "✓ Settings updated"
    }
}
