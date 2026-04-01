{
  description = "NixOS VM configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }:

  let
    hostPkgs = nixpkgs.legacyPackages.aarch64-darwin;
  in {

    devShells.aarch64-darwin.default = hostPkgs.mkShell {
      packages = with hostPkgs; [ git openssh ];
    };

    nixosConfigurations.mullvad-vm = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        disko.nixosModules.disko
        ./disko/mullvad-vm.nix
        ./modules/hardware-parallels.nix
        ./modules/mullvad-vm.nix
        {
          nixpkgs.overlays = [
            (import ./overlays/mullvad-browser-aarch64.nix)
          ];
        }
      ];
    };
  };
}
