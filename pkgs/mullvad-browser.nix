# Mullvad Browser 16.0a5 (alpha) — pre-built binary for aarch64-linux.
#
# The alpha is based on Firefox Rapid Release (not ESR like stable).
# The nixpkgs mullvad-browser package only supports x86_64-linux.
# Once nixpkgs adds aarch64-linux support, delete this file and the overlay.
#
# Modeled after nixpkgs/pkgs/by-name/mu/mullvad-browser/package.nix
{
  lib,
  stdenv,
  fetchurl,
  makeDesktopItem,
  copyDesktopItems,
  makeWrapper,
  writeText,
  wrapGAppsHook3,
  autoPatchelfHook,
  patchelfUnstable,

  atk,
  cairo,
  dbus,
  dbus-glib,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  libxcb,
  libx11,
  libxext,
  libxrender,
  libxt,
  libxtst,
  libgbm,
  pango,
  pciutils,
  zlib,

  libnotify,

  libxkbcommon,
  libdrm,
  libGL,

  ffmpeg_7,

  pipewire,
  libpulseaudio,
  alsa-lib,

  libva,
}:

let
  libPath = lib.makeLibraryPath [
    alsa-lib
    atk
    cairo
    dbus
    dbus-glib
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libxcb
    libx11
    libxext
    libxrender
    libxt
    libxtst
    libgbm
    pango
    pciutils
    stdenv.cc.cc
    stdenv.cc.libc
    zlib
    libnotify
    libxkbcommon
    libdrm
    libGL
    pipewire
    libpulseaudio
    libva
    ffmpeg_7
  ];

  version = "16.0a5";

  policiesJson = writeText "policies.json" (builtins.toJSON {
    policies.DisableAppUpdate = true;
  });
in
stdenv.mkDerivation {
  pname = "mullvad-browser";
  inherit version;

  src = fetchurl {
    url = "https://cdn.mullvad.net/browser/${version}/mullvad-browser-linux-aarch64-${version}.tar.xz";
    hash = "sha256-BsAc6lN6OA6xPCqAiRNVgDsw497ILakMzLtpmcZJge4=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    patchelfUnstable
    copyDesktopItems
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    gtk3
    alsa-lib
    dbus-glib
    libxtst
  ];

  patchelfFlags = [ "--no-clobber-old-sections" ];

  preferLocalBuild = true;
  allowSubstitutes = false;

  desktopItems = [
    (makeDesktopItem {
      name = "mullvad-browser";
      exec = "mullvad-browser %U";
      icon = "mullvad-browser";
      desktopName = "Mullvad Browser";
      genericName = "Web Browser";
      comment = "Privacy-focused browser";
      categories = [ "Network" "WebBrowser" "Security" ];
      mimeTypes = [
        "text/html"
        "text/xml"
        "application/xhtml+xml"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
    })
  ];

  buildPhase = ''
    runHook preBuild

    MB_IN_STORE=$out/share/mullvad-browser

    mkdir -p "$MB_IN_STORE"
    tar xf "$src" -C "$MB_IN_STORE" --strip-components=2

    pushd "$MB_IN_STORE"

    autoPatchelf mullvadbrowser.real
    mv mullvadbrowser.real mullvadbrowser

    touch "$MB_IN_STORE/system-install"

    libPath=${libPath}:$MB_IN_STORE

    cat >defaults/pref/autoconfig.js <<EOF
    //
    pref("general.config.filename", "mozilla.cfg");
    pref("general.config.obscure_value", 0);
    EOF

    cat >mozilla.cfg <<EOF
    // First line must be a comment
    clearPref("extensions.xpiState");
    lockPref("noscript.firstRunRedirection", false);
    EOF

    FONTCONFIG_FILE=$MB_IN_STORE/fonts/fonts.conf
    substituteInPlace "$FONTCONFIG_FILE" \
      --replace-fail '<dir prefix="cwd">fonts</dir>' "<dir>$MB_IN_STORE/fonts</dir>"

    mkdir -p $out/bin

    makeWrapper "$MB_IN_STORE/mullvadbrowser" "$out/bin/mullvad-browser" \
      --prefix LD_LIBRARY_PATH : "$libPath" \
      --set FONTCONFIG_FILE "$FONTCONFIG_FILE" \
      --set-default MOZ_ENABLE_WAYLAND 1

    mkdir -p $out/share/doc
    ln -s $MB_IN_STORE/MullvadBrowser/Docs $out/share/doc/mullvad-browser

    for i in 16 32 48 64 128; do
      mkdir -p $out/share/icons/hicolor/''${i}x''${i}/apps/
      ln -s $out/share/mullvad-browser/browser/chrome/icons/default/default$i.png \
        $out/share/icons/hicolor/''${i}x''${i}/apps/mullvad-browser.png
    done

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dvm644 ${policiesJson} $out/share/mullvad-browser/distribution/policies.json
    runHook postInstall
  '';

  meta = {
    description = "Privacy-focused browser made by Mullvad and the Tor Project (alpha, aarch64)";
    mainProgram = "mullvad-browser";
    homepage = "https://mullvad.net/en/browser";
    license = with lib.licenses; [ mpl20 lgpl21Plus lgpl3Plus free ];
    platforms = [ "aarch64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
