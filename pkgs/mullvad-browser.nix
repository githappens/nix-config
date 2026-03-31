# Mullvad Browser 16.0a4 (alpha) — pre-built binary for aarch64-linux.
#
# The alpha is based on Firefox Rapid Release (not ESR like stable).
# This is a standalone package definition because the nixpkgs mullvad-browser
# package only supports x86_64-linux and errors on aarch64 during evaluation.
#
# Once nixpkgs adds aarch64-linux support, delete this file and the overlay.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook,
  makeWrapper,
  alsa-lib,
  dbus-glib,
  gtk3,
  libXtst,
  libva,
  pciutils,
  mesa,
  xorg,
}:

stdenv.mkDerivation rec {
  pname = "mullvad-browser";
  version = "16.0a4";

  src = fetchurl {
    url = "https://github.com/mullvad/mullvad-browser/releases/download/${version}/mullvad-browser-linux-aarch64-${version}.tar.xz";
    sha256 = "c3307acf3ee0d489547ef33d2e55359378ba6dffe189b53107cc4bd5a2dfe956";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    dbus-glib
    gtk3
    libXtst
    libva
    mesa
    pciutils
    stdenv.cc.cc.lib # libstdc++
    xorg.libXdamage
    xorg.libXrandr
    xorg.libxcb
  ];

  # The tarball extracts to a directory like mullvad-browser/
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    # Find the extracted browser directory
    browserDir=$(find . -maxdepth 1 -type d -name '*mullvad*' -o -name '*browser*' | head -1)
    if [ -z "$browserDir" ] || [ "$browserDir" = "." ]; then
      browserDir="."
    fi

    mkdir -p $out/lib/mullvad-browser $out/bin

    cp -r "$browserDir"/* $out/lib/mullvad-browser/ 2>/dev/null || cp -r ./* $out/lib/mullvad-browser/

    # Remove any nested directory if the tarball double-wraps
    if [ -d "$out/lib/mullvad-browser/Browser" ]; then
      mv $out/lib/mullvad-browser/Browser/* $out/lib/mullvad-browser/
      rmdir $out/lib/mullvad-browser/Browser
    fi

    # Main launcher
    makeWrapper $out/lib/mullvad-browser/start-mullvad-browser $out/bin/mullvad-browser \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}"

    # .desktop file
    mkdir -p $out/share/applications
    cat > $out/share/applications/mullvad-browser.desktop <<EOF
    [Desktop Entry]
    Name=Mullvad Browser
    Exec=$out/bin/mullvad-browser %u
    Icon=$out/lib/mullvad-browser/browser/chrome/icons/default/default128.png
    Type=Application
    Categories=Network;WebBrowser;
    MimeType=text/html;text/xml;application/xhtml+xml;
    EOF

    runHook postInstall
  '';

  meta = with lib; {
    description = "Privacy-focused browser made by Mullvad and the Tor Project (alpha, aarch64)";
    homepage = "https://mullvad.net/en/browser";
    license = licenses.mpl20;
    platforms = [ "aarch64-linux" ];
    maintainers = [ ];
  };
}
