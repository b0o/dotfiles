# edits the current commandline to search for the path at the cursor position
# using fd and fzf, replacing it with the selected result
# Falls back to nushell builtins if fd is not available
# Requires fzf to be installed and available in PATH
export def fzf-path-complete [] {
    let line_buffer = (commandline)
    let cursor_pos = (commandline get-cursor)

    # Find word boundaries around cursor position
    let before_cursor = ($line_buffer | str substring 0..<$cursor_pos)
    let after_cursor = ($line_buffer | str substring $cursor_pos..)

    # Find where the current word starts (last space before cursor, or beginning)
    let word_start = if ($before_cursor | str contains ' ') {
        let reversed = ($before_cursor | str reverse)
        let space_pos = ($reversed | str index-of ' ')
        if $space_pos == -1 {
            0
        } else {
            ($before_cursor | str length) - $space_pos
        }
    } else {
        0
    }

    # Find where the current word ends (first space after cursor, or end)
    let word_end = if ($after_cursor | str contains ' ') {
        let first_space = ($after_cursor | str index-of ' ')
        $cursor_pos + $first_space
    } else {
        $line_buffer | str length
    }

    # Extract the current word and the parts before/after it
    let current_word = ($line_buffer | str substring $word_start..<$word_end)
    let prefix = ($line_buffer | str substring 0..<$word_start)
    let suffix = ($line_buffer | str substring $word_end..)

    # Detect the original path style for preservation
    let path_style = if ($current_word | str starts-with '~/') or ($current_word == '~') {
        {type: "tilde", prefix: "~"}
    } else if ($current_word | str starts-with './') or ($current_word == '.') {
        {type: "dot", prefix: "."}
    } else if ($current_word | str starts-with '../') or ($current_word == '..') {
        {type: "dotdot", prefix: ".."}
    } else {
        {type: "other", prefix: ""}
    }

    # Expand tilde for path operations
    let expanded_word = ($current_word | path expand)

    # Determine search directory and initial query
    let search_context = if ($current_word | str trim | is-empty) {
        {dir: ".", query: "", original_dir: "."}
    } else if ($expanded_word | path exists) and ($expanded_word | path type) == "dir" {
        {dir: $expanded_word, query: "", original_dir: $current_word}
    } else if ($expanded_word | path exists) and ($expanded_word | path type) == "file" {
        {dir: ($expanded_word | path dirname), query: ($expanded_word | path basename), original_dir: ($current_word | path dirname)}
    } else {
        let parent_dir = ($expanded_word | path dirname)
        if ($parent_dir | path exists) {
            {dir: $parent_dir, query: ($expanded_word | path basename), original_dir: ($current_word | path dirname)}
        } else {
            {dir: ".", query: $current_word, original_dir: "."}
        }
    }

    # Check if fd is available
    let has_fd = (which fd | is-not-empty)

    # Get file list and run fzf
    let selected = if $has_fd {
        # Use fd (respects .gitignore and other ignore files)
        ^fd . $search_context.dir
        | ^fzf --query $search_context.query
        | complete
    } else {
        # Fall back to nushell builtins
        glob ([$search_context.dir, "**", "*"] | path join)
        | each { |path| $path | path relative-to $search_context.dir }
        | ^fzf --query $search_context.query
        | complete
    }

    # If something was selected, update the commandline
    if ($selected.exit_code == 0) and (not ($selected.stdout | is-empty)) {
        let raw_result = ($selected.stdout | str trim)

        # Convert result back to original path style
        let result = match $path_style.type {
            "tilde" => {
                # Convert to tilde-prefixed path
                let home = ($nu.home-path | path expand)
                let abs_result = ($raw_result | path expand)
                if ($abs_result | str starts-with $home) {
                    $abs_result | str replace $home "~"
                } else {
                    $raw_result
                }
            },
            "dot" => {
                # Keep as relative path from current directory
                if ($raw_result | str starts-with '/') {
                    # Try to make relative, but keep absolute if it fails
                    try {
                        let rel = ($raw_result | path relative-to (pwd))
                        if ($rel | str starts-with './') {
                            $rel
                        } else {
                            $"./($rel)"
                        }
                    } catch {
                        $raw_result
                    }
                } else if ($raw_result | str starts-with './') {
                    $raw_result
                } else {
                    $"./($raw_result)"
                }
            },
            "dotdot" => {
                # Try to maintain parent-relative style if possible
                if ($raw_result | str starts-with '../') or ($raw_result | str starts-with './') {
                    $raw_result
                } else if ($raw_result | str starts-with '/') {
                    # Try to make relative to pwd, but fallback to absolute
                    try {
                        $raw_result | path relative-to (pwd)
                    } catch {
                        # If relative-to fails, try relative to search directory
                        try {
                            let rel_to_search = ($raw_result | path relative-to ($search_context.dir | path expand))
                            ($search_context.original_dir | path join $rel_to_search)
                        } catch {
                            $raw_result
                        }
                    }
                } else {
                    # Prepend the original directory prefix if it's a relative path
                    ($search_context.original_dir | path join $raw_result)
                }
            },
            _ => {
                # Keep result as-is for other cases
                $raw_result
            }
        }

        # Build the new buffer with the selected item replacing the current word
        let new_buffer = $prefix + $result + $suffix

        # Position cursor at the end of the inserted result
        let new_cursor_pos = ($prefix | str length) + ($result | str length)

        commandline edit --replace $new_buffer
        commandline set-cursor $new_cursor_pos
    }
}
