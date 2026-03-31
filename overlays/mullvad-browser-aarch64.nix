# Overlay: Mullvad Browser alpha for aarch64-linux.
#
# The stable channel (15.x) only ships x86_64-linux.
# The alpha channel (16.x) includes aarch64-linux builds.
# Once stable ships aarch64, replace this with the upstream nixpkgs package.
#
# Track releases: https://github.com/mullvad/mullvad-browser/releases
final: prev: {
  mullvad-browser = final.callPackage ../pkgs/mullvad-browser.nix { };
}
