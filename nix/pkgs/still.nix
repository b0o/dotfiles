{pkgs, ...}:
pkgs.stdenv.mkDerivation rec {
  pname = "still";
  version = "0.0.8";

  src = pkgs.fetchFromGitHub {
    owner = "faergeek";
    repo = "still";
    rev = "v${version}";
    hash = "sha256-Ld93xCTgxK4NI4aja6VBYdT9YJHDtoHuiy0c18ACv6M=";
  };

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    scdoc
    wayland-scanner
  ];

  buildInputs = with pkgs; [
    pixman
    wayland
    wayland-protocols
  ];

  meta = with pkgs.lib; {
    description = "Freeze the screen of a Wayland compositor until a provided command exits";
    homepage = "https://github.com/faergeek/still";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
