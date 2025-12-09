# When you add custom packages, list them here
# These are similar to nixpkgs packages
{
  inputs,
  pkgs,
}:
{
  # foo = pkgs.callPackage ./foo.nix {};
}
// (
  if inputs ? opentui-src
  then {
    opentui-b0o = pkgs.callPackage ./opentui.nix {
      src = inputs.opentui-src;
    };
  }
  else {}
)
