default:
    @just --list

stow:
    stow --verbose --target="$XDG_CONFIG_HOME" --restow config
