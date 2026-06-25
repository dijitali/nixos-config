{
  description = "Ieuan's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs =
    inputs@{ self, ... }:
    let
      mkSystem = import ./lib/mkSystem.nix;
    in
    {
      nixosConfigurations.jenkonix-2 = mkSystem {
        inherit inputs;
        system = "x86_64-linux";
        hostname = "jenkonix-2";
        user = "ieuan";
      };
    };
}
