# Helper to install neovim plugins to ~/.nix-profile/share/nvim/lazy/<name>
# This allows lazy.nvim to load plugins from the nix store
{ pkgs }:

{
  # Takes a list of { name, pkg } attrs and creates a derivation
  # that symlinks each plugin to share/nvim/lazy/<name>
  mkLazyPlugins =
    plugins:
    pkgs.symlinkJoin {
      name = "nvim-lazy-plugins";
      paths = map (
        p:
        pkgs.runCommand "nvim-lazy-${p.name}" { } ''
          mkdir -p $out/share/nvim/lazy
          ln -s ${p.pkg} $out/share/nvim/lazy/${p.name}
        ''
      ) plugins;
    };

  # Convenience wrapper for a single plugin
  mkLazyPlugin =
    name: pkg:
    pkgs.runCommand "nvim-lazy-${name}" { } ''
      mkdir -p $out/share/nvim/lazy
      ln -s ${pkg} $out/share/nvim/lazy/${name}
    '';
}
