{
  description = "Ieuan's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Nix on Android (Termux). No stable release-25.11 branch exists yet, so
    # track prerelease-25.11 which is built against the 25.11 line; the exact
    # commit is pinned in flake.lock. Swap to release-25.11 once it is cut.
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/prerelease-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
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

      # Android / Termux environment, activated on-device with
      # `nix-on-droid switch --flake .#default`.
      nixOnDroidConfigurations.default = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
        pkgs = import inputs.nixpkgs {
          system = "aarch64-linux";
          config.allowUnfree = true;
        };
        extraSpecialArgs = { inherit inputs; };
        modules = [ ./hosts/droid ];
      };
    };
}
