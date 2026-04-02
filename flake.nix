{
  description = "NixOS VM and macOS (nix-darwin) configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, nix-darwin, home-manager, ... }:

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

    darwinConfigurations.host = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        home-manager.darwinModules.home-manager
        ./modules/host.nix
      ];
    };

    darwinConfigurations.devbox = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        home-manager.darwinModules.home-manager
        ./modules/devbox.nix
      ];
    };
  };
}
