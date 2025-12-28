{pkgs}:
pkgs.stdenv.mkDerivation rec {
  pname = "ttf-pragmasevka";
  version = "1.7.0";

  src = pkgs.fetchurl {
    url = "https://github.com/shytikov/pragmasevka/releases/download/v${version}/Pragmasevka_NF.zip";
    hash = "sha256-7qt1jv9WLRyu12EkRIjlZUW+Jegaa0DNhLMbAyo3YVw=";
  };

  unpackPhase = ''
    runHook preUnpack
    ${pkgs.unzip}/bin/unzip $src

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/truetype/
    install -Dm444 *.ttf -t $out/share/fonts/truetype

    runHook postInstall
  '';
}
