# Override opencode to use opentui built from GitHub fork (b0o branch)
#
# Strategy: Copy our full opentui fork, then create symlinks for its
# dependencies (babel, etc.) pointing to the existing .bun cache
{inputs, ...}: final: _prev: let
  bun = final.bun;
  ripgrep = final.ripgrep;
  makeBinaryWrapper = final.makeBinaryWrapper;
in {
  opencode-b0o = inputs.opencode.packages.${final.system}.default.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs or [] ++ [makeBinaryWrapper];
    buildPhase = ''
      runHook preBuild

      cp -r ${old.node_modules}/node_modules .
      cp -r ${old.node_modules}/packages .

      (
        cd packages/opencode

        chmod -R u+w ./node_modules

        # Replace npm @opentui with our fork BEFORE bundling
        rm -rf ./node_modules/@opentui
        mkdir -p ./node_modules/@opentui
        for pkg in ${final.opentui-b0o}/lib/node_modules/@opentui/*; do
          cp -r "$pkg" "./node_modules/@opentui/$(basename "$pkg")"
        done
        chmod -R u+w ./node_modules/@opentui

        # Replace opentui-spinner with our build (against our opentui fork)
        # Need to replace both the direct module and the .bun cache entry
        rm -rf ./node_modules/opentui-spinner
        cp -r ${final.opentui-spinner-b0o}/lib/node_modules/opentui-spinner ./node_modules/opentui-spinner
        chmod -R u+w ./node_modules/opentui-spinner

        # opentui-spinner depends on cli-spinners - copy it from our build
        rm -rf ./node_modules/cli-spinners
        cp -r ${final.opentui-spinner-b0o}/lib/node_modules/cli-spinners ./node_modules/cli-spinners
        chmod -R u+w ./node_modules/cli-spinners

        # Also replace in top-level .bun cache (used by bun's module resolution)
        chmod -R u+w ../../node_modules/.bun
        for spinner_cache in ../../node_modules/.bun/opentui-spinner@*/node_modules/opentui-spinner; do
          if [ -d "$spinner_cache" ]; then
            rm -rf "$spinner_cache"
            cp -r ${final.opentui-spinner-b0o}/lib/node_modules/opentui-spinner "$spinner_cache"
            chmod -R u+w "$spinner_cache"
          fi
        done

        # Create dependency symlinks for @opentui/solid
        # These point to packages in the top-level .bun cache (7 levels up from @babel/core)
        mkdir -p ./node_modules/@opentui/solid/node_modules/@babel
        ln -s ../../../../../../../node_modules/.bun/@babel+core@7.28.0+6c39b2892b0950f6/node_modules/@babel/core \
          ./node_modules/@opentui/solid/node_modules/@babel/core
        ln -s ../../../../../../../node_modules/.bun/@babel+preset-typescript@7.27.1+6c39b2892b0950f6/node_modules/@babel/preset-typescript \
          ./node_modules/@opentui/solid/node_modules/@babel/preset-typescript
        ln -s ../../../../../../node_modules/.bun/babel-preset-solid@1.9.9+8ef28aad7564279e/node_modules/babel-preset-solid \
          ./node_modules/@opentui/solid/node_modules/babel-preset-solid
        ln -s ../../../../../../node_modules/.bun/babel-plugin-module-resolver@5.0.2/node_modules/babel-plugin-module-resolver \
          ./node_modules/@opentui/solid/node_modules/babel-plugin-module-resolver

        mkdir -p ./node_modules/@opencode-ai
        rm -f ./node_modules/@opencode-ai/{script,sdk,plugin}
        ln -s $(pwd)/../../packages/script ./node_modules/@opencode-ai/script
        ln -s $(pwd)/../../packages/sdk/js ./node_modules/@opencode-ai/sdk
        ln -s $(pwd)/../../packages/plugin ./node_modules/@opencode-ai/plugin

        cp ${old.src}/nix/bundle.ts ./bundle.ts
        chmod +x ./bundle.ts
        bun run ./bundle.ts
      )

      runHook postBuild
    '';

    postInstall = ''
      # Recreate wrapper with OTUI_TREE_SITTER_WORKER_PATH env var
      rm $out/bin/opencode
      makeWrapper ${bun}/bin/bun $out/bin/opencode \
        --add-flags "run" \
        --add-flags "$out/lib/opencode/dist/src/index.js" \
        --prefix PATH : ${final.lib.makeBinPath [ripgrep]} \
        --set OTUI_TREE_SITTER_WORKER_PATH "$out/lib/opencode/dist/node_modules/@opentui/core/parser.worker.js" \
        --argv0 opencode

      # Symlink opentui for runtime imports
      rm -rf $out/lib/opencode/node_modules/@opentui
      mkdir -p $out/lib/opencode/node_modules/@opentui
      for pkg in ${final.opentui-b0o}/lib/node_modules/@opentui/*; do
        ln -s "$pkg" "$out/lib/opencode/node_modules/@opentui/$(basename "$pkg")"
      done
    '';
  });
}
