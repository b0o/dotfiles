# Override opencode to use opentui and opentui-spinner built from custom forks
#
# This overlay defines three packages:
# - opentui-b0o: OpenTUI built from b0o/opentui fork
# - opentui-spinner-b0o: opentui-spinner built against opentui-b0o
# - opencode-b0o: OpenCode from b0o/opencode fork using the above custom packages as dependencies
{inputs, ...}: final: _prev: let
  inherit (final) lib stdenv bun nodejs zig_0_14 llvmPackages cacert ripgrep makeBinaryWrapper;
  opentui-b0o = stdenv.mkDerivation {
    pname = "opentui";
    version = "0.1.59-b0o";
    src = inputs.opentui-src;

    nativeBuildInputs = [bun cacert nodejs zig_0_14 llvmPackages.bintools];

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-XzjPjvLnGUDU2Q+eyVYF5vIxBHiXxRDAt6bCRc5w1x0=";

    dontConfigure = true;

    buildPhase = ''
      export HOME=$TMPDIR
      export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache
      export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
      bun install --frozen-lockfile

      patchShebangs node_modules/typescript/bin

      (cd packages/core && bun run build)
      (cd packages/solid && bun run build)
    '';

    installPhase = ''
      mkdir -p $out/lib/node_modules/@opentui

      cp -r packages/core/dist $out/lib/node_modules/@opentui/core
      cp -r packages/solid/dist $out/lib/node_modules/@opentui/solid
      cp -r node_modules/solid-js $out/lib/node_modules/solid-js
      cp -r node_modules/yoga-layout $out/lib/node_modules/yoga-layout

      # The zig build process puts the core-{platform}-{arch} into the node_modules/@opentui/ directory
      # (these are not from NPM). We need to copy them over.
      for pkg in packages/core/node_modules/@opentui/core-*; do
        [ -d "$pkg" ] && cp -r "$pkg" $out/lib/node_modules/@opentui/
      done

      # Strip debug info from native libraries to ensure reproducibility
      # (Zig embeds non-deterministic cache paths in debug sections)
      find $out -type f \( -name "*.so" -o -name "*.dylib" -o -name "*.dll" \) \
        -exec llvm-strip --strip-debug {} \;

      find $out -exec touch -h -d '@0' {} + 2>/dev/null || true
    '';

    meta = {
      description = "OpenTUI - TypeScript library for building terminal user interfaces";
      homepage = "https://github.com/sst/opentui";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  };

  opentui-spinner-b0o = stdenv.mkDerivation {
    pname = "opentui-spinner";
    version = "0.0.6-b0o";
    src = inputs.opentui-spinner-src;

    nativeBuildInputs = [bun cacert];

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-Qbe7dhHSHq7JIlc32ptPlrBprEVq60k08IJ1dV6S9EY=";

    dontConfigure = true;

    buildPhase = ''
      export HOME=$TMPDIR
      bun install --frozen-lockfile

      patchShebangs node_modules/.bin

      # Replace @opentui peer dependencies with our fork
      rm -rf node_modules/@opentui
      mkdir -p node_modules/@opentui
      for pkg in ${opentui-b0o}/lib/node_modules/@opentui/*; do
        cp -r "$pkg" "node_modules/@opentui/$(basename "$pkg")"
      done
      chmod -R u+w node_modules/@opentui

      # Also need solid-js from opentui
      rm -rf node_modules/solid-js
      cp -r ${opentui-b0o}/lib/node_modules/solid-js node_modules/solid-js
      chmod -R u+w node_modules/solid-js

      bun node_modules/tsdown/dist/run.mjs
    '';

    installPhase = ''
      mkdir -p $out/lib/node_modules/opentui-spinner

      cp -r dist $out/lib/node_modules/opentui-spinner/
      cp package.json $out/lib/node_modules/opentui-spinner/

      # Copy cli-spinners dependency
      mkdir -p $out/lib/node_modules
      cp -r node_modules/cli-spinners $out/lib/node_modules/

      find $out -exec touch -h -d '@0' {} + 2>/dev/null || true
    '';

    meta = {
      description = "A small & opinionated spinner library for OpenTUI";
      homepage = "https://github.com/msmps/opentui-spinner";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  };

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
        for pkg in ${opentui-b0o}/lib/node_modules/@opentui/*; do
          cp -r "$pkg" "./node_modules/@opentui/$(basename "$pkg")"
        done
        chmod -R u+w ./node_modules/@opentui

        # Replace opentui-spinner with our build (against our opentui fork)
        rm -rf ./node_modules/opentui-spinner
        cp -r ${opentui-spinner-b0o}/lib/node_modules/opentui-spinner ./node_modules/opentui-spinner
        chmod -R u+w ./node_modules/opentui-spinner

        # opentui-spinner depends on cli-spinners
        rm -rf ./node_modules/cli-spinners
        cp -r ${opentui-spinner-b0o}/lib/node_modules/cli-spinners ./node_modules/cli-spinners
        chmod -R u+w ./node_modules/cli-spinners

        # Also replace in top-level .bun cache (used by bun's module resolution)
        chmod -R u+w ../../node_modules/.bun
        for spinner_cache in ../../node_modules/.bun/opentui-spinner@*/node_modules/opentui-spinner; do
          if [ -d "$spinner_cache" ]; then
            rm -rf "$spinner_cache"
            cp -r ${opentui-spinner-b0o}/lib/node_modules/opentui-spinner "$spinner_cache"
            chmod -R u+w "$spinner_cache"
          fi
        done

        # Create dependency symlinks for @opentui/solid's babel dependencies
        # These point to packages in the top-level .bun cache
        # TODO: Make these dynamic to avoid breaking when opencode updates deps
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
        --prefix PATH : ${lib.makeBinPath [ripgrep]} \
        --set OTUI_TREE_SITTER_WORKER_PATH "$out/lib/opencode/dist/node_modules/@opentui/core/parser.worker.js" \
        --argv0 opencode

      # Symlink opentui for runtime imports
      rm -rf $out/lib/opencode/node_modules/@opentui
      mkdir -p $out/lib/opencode/node_modules/@opentui
      for pkg in ${opentui-b0o}/lib/node_modules/@opentui/*; do
        ln -s "$pkg" "$out/lib/opencode/node_modules/@opentui/$(basename "$pkg")"
      done
    '';
  });
in {
  inherit opentui-b0o opentui-spinner-b0o opencode-b0o;
}
