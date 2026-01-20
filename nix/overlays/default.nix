{inputs, ...}: let
  additions = final: _prev:
    import ../pkgs {
      inherit inputs;
      pkgs = final;
    };

  modifications = final: prev: let
    inherit (final.stdenv.hostPlatform) system;
  in {
    wlr-which-key-b0o = inputs.wlr-which-key-b0o.packages.${system}.default;
    ghostty = inputs.ghostty.packages.${system}.default;
    opencode = inputs.opencode.packages.${system}.default;

    # TODO: remove once https://github.com/NixOS/nixpkgs/pull/481226 is merged
    nushell = let
      version = "0.110.0";
      src = final.fetchFromGitHub {
        owner = "nushell";
        repo = "nushell";
        tag = version;
        hash = "sha256-iytTJZ70kg2Huwj/BSwDX4h9DVDTlJR2gEHAB2pGn/k=";
      };
      cargoHash = "sha256-a/N0a9ZVqXAjAl5Z7BdEsIp0He3h0S/owS0spEPb3KI=";
    in
      prev.nushell.overrideAttrs (oldAttrs: {
        inherit version src;
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          inherit src;
          name = "nushell-${version}-vendor";
          hash = cargoHash;
        };
      });

    # TODO: remove once https://github.com/NixOS/nixpkgs/pull/466454 is merged
    nushellPlugins =
      prev.nushellPlugins
      // {
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

    charles = prev.charles.overrideAttrs (oldAttrs: {
      postFixup = ''
        ${oldAttrs.postFixup or ""}
        # Wrap with Wayland compatibility and font rendering fixes
        wrapProgram $out/bin/charles \
          --set _JAVA_AWT_WM_NONREPARENTING 1 \
          --set _JAVA_OPTIONS "-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true"
      '';
    });
  };
in
  inputs.nixpkgs.lib.composeManyExtensions [
    additions
    modifications
  ]
