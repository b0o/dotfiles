gh completion -s fish | source
mise completion fish | source
pw completion fish | source

# Add -f to niri completions to avoid file/path suggestions
niri completions fish | string replace -r '^complete -c niri (?!.*-[fF])(.*)' 'complete -c niri -f $1' | source
