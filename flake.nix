{
  description = "NixOS VM configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }: {

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
