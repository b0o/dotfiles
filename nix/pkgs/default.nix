{
  inputs,
  pkgs,
}:
  (
    if inputs ? opentui-src
    then {
      opentui-b0o = pkgs.callPackage ./opentui.nix {
        src = inputs.opentui-src;
      };
    }
    else {}
  )
  // (
    if inputs ? opentui-spinner-src && inputs ? opentui-src
    then {
      opentui-spinner-b0o = pkgs.callPackage ./opentui-spinner.nix {
        src = inputs.opentui-spinner-src;
        opentui-b0o = pkgs.opentui-b0o;
      };
    }
    else {}
  )
