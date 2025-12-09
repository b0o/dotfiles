{
  inputs,
  pkgs,
}:
{
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
// (
  if inputs ? opencode && inputs ? opentui-src
  then {
    opencode-b0o = pkgs.callPackage ./opencode.nix {
      src = inputs.opencode;
      inherit (pkgs) opentui-b0o;
    };
  }
  else {}
)
