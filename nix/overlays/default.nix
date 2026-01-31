{inputs, ...}: let
  additions = final: _prev:
    import ../pkgs {
      inherit inputs;
      pkgs = final;
    };

  nixgl = import ./nixgl.nix {inherit inputs;};

  modifications = final: prev: let
    inherit (final.stdenv.hostPlatform) system;
    nushellVersion = "0.110.0";
    nushellHash = "sha256-iytTJZ70kg2Huwj/BSwDX4h9DVDTlJR2gEHAB2pGn/k=";
    nushellCargoHash = "sha256-a/N0a9ZVqXAjAl5Z7BdEsIp0He3h0S/owS0spEPb3KI=";
  in {
    opencode = import ./opencode.nix {inherit inputs final;};
    wlr-which-key-b0o = inputs.wlr-which-key-b0o.packages.${system}.default;

    # Give neovim access to a C compiler for tree-sitter grammars
    neovim-nightly = inputs.neovim-nightly-overlay.packages.${system}.neovim.overrideAttrs (old: {
      propagatedBuildInputs = (old.propagatedBuildInputs or []) ++ [final.stdenv.cc.cc];
    });
    # Tree Sitter + Node for installing Treesitter Grammars
    tree-sitter-nightly = inputs.neovim-nightly-overlay.packages.${system}.tree-sitter;

    # TODO: remove once https://github.com/NixOS/nixpkgs/pull/481226 is merged
    nushell = let
      version = nushellVersion;
      src = final.fetchFromGitHub {
        owner = "nushell";
        repo = "nushell";
        tag = version;
        hash = nushellHash;
      };
      cargoHash = nushellCargoHash;
    in
      prev.nushell.overrideAttrs (oldAttrs: {
        inherit version src;
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          inherit src;
          name = "nushell-${version}-vendor";
          hash = cargoHash;
        };
      });
    nushellPlugins =
      prev.nushellPlugins
      // {
        formats = let
          version = nushellVersion;
          src = final.fetchFromGitHub {
            owner = "nushell";
            repo = "nushell";
            tag = version;
            hash = nushellHash;
          };
          cargoHash = nushellCargoHash;
        in
          prev.nushellPlugins.formats.overrideAttrs (oldAttrs: {
            inherit version src;
            cargoDeps = final.rustPlatform.fetchCargoVendor {
              inherit src;
              name = "${oldAttrs.pname}-${version}-vendor";
              hash = cargoHash;
            };
          });
        # TODO: remove once https://github.com/NixOS/nixpkgs/pull/466454 is merged
        skim = let
          version = "0.22.0";
          src = final.fetchFromGitHub {
            owner = "idanarye";
            repo = "nu_plugin_skim";
            rev = "v${version}";
            hash = "sha256-TdsemIPbknJiglxhQwBch8iJ9GVa+Sj3fqSq4xaDqfk=";
          };
          cargoHash = "sha256-vpRL4oiOmhnGO+eWWTA7/RvVrtouVzqJvPGZY/cHeXY=";
        in
          prev.nushellPlugins.skim.overrideAttrs (oldAttrs: {
            inherit version src;
            cargoDeps = final.rustPlatform.fetchCargoVendor {
              inherit src;
              name = "${oldAttrs.pname}-${version}-vendor";
              hash = cargoHash;
            };
          });
      };

    # TODO: remove once nixpkgs.slurp is updated to 1.6.0
    slurp = prev.slurp.overrideAttrs (oldAttrs: {
      src = final.fetchFromGitHub {
        owner = "emersion";
        repo = "slurp";
        rev = "v1.6.0";
        hash = "sha256-kH7K/ttTNYQ5im7YsJ28bLi8yKfWZ3HGEDOfTs22UR0=";
      };
    });

    charles = prev.charles.overrideAttrs (oldAttrs: {
      postFixup = ''
        ${oldAttrs.postFixup or ""}
        # Wrap with Wayland compatibility and font rendering fixes
        wrapProgram $out/bin/charles \
          --set _JAVA_AWT_WM_NONREPARENTING 1 \
          --set _JAVA_OPTIONS "-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true"
      '';
    });

    # TODO: remove once https://github.com/LuaLS/lua-language-server/issues/3322 is fixed
    lua-language-server = prev.lua-language-server.overrideAttrs (oldAttrs: {
      version = "3.15.0";
      src = final.fetchFromGitHub {
        owner = "luals";
        repo = "lua-language-server";
        tag = "3.15.0";
        hash = "sha256-frsq5OA3giLOJ/KPcAqVhme+0CtJuZrS3F4zHN1PnFM=";
        fetchSubmodules = true;
      };
    });
  };
in
  inputs.nixpkgs.lib.composeManyExtensions [additions nixgl modifications]
