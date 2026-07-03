{
  description = "Ieuan's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # A parallel channel used only for a handful of packages that we want to
    # track more aggressively than the stable channel (see modules/packages.nix).
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Nix on Android (Termux). nix-on-droid has no release-26.05 branch, so
    # track master and have it follow this flake's nixpkgs/home-manager (26.05).
    # The exact commit is pinned in flake.lock; swap to a release-26.05 branch
    # once one is cut.
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid";
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
