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
