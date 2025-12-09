# Override opencode to use opentui built from GitHub fork (b0o branch)
{inputs, ...}: final: _prev: {
  opencode-b0o = inputs.opencode.packages.${final.system}.default.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        # Make node_modules writable so we can modify it
        chmod -R u+w $out/lib/opencode/node_modules

        # Remove npm-fetched opentui (both the symlinks and the .bun cache entries)
        rm -rf $out/lib/opencode/node_modules/@opentui
        rm -rf $out/lib/opencode/node_modules/.bun/@opentui*

        # Link to opentui built from GitHub fork
        mkdir -p $out/lib/opencode/node_modules/@opentui
        for pkg in ${final.opentui-b0o}/lib/node_modules/@opentui/*; do
          ln -s "$pkg" "$out/lib/opencode/node_modules/@opentui/$(basename "$pkg")"
        done
      '';
  });
}
