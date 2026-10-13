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

    # Declarative disk partitioning, used by nixos-anywhere to install the
    # cloud servers (hosts/jenkosrv-*). Pinned to a release tag; bump deliberately.
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Site repos served by the web server (hosts/jenkosrv-fsn1-3, via
    # modules/web/sites.nix). Each is a flake exporting `caddyConfig`, its own
    # self-contained Caddy config. They're private, so they're fetched over SSH
    # via per-repo host aliases (github-<repo>): one `Host github-*` ssh_config
    # block maps them to github.com. Your own key works with that block (Home
    # Manager adds it on the laptop); the servers use a read-only deploy key
    # per repo (modules/server.nix).
    ieuan-net = {
      url = "git+ssh://git@github-ieuan-net/dijitali/ieuan-net";
      # Its flake also has a dev shell; reuse this flake's nixpkgs for it.
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    ieuan-co-uk.url = "git+ssh://git@github-ieuan-co-uk/dijitali/ieuan-co-uk";
    jensys-uk.url = "git+ssh://git@github-jensys-uk/dijitali/jensys-uk";
    net-diagnostics.url = "git+ssh://git@github-net-diagnostics/dijitali/net-diagnostics";
    jnkns-uk.url = "git+ssh://git@github-jnkns-uk/dijitali/jnkns-uk";

    # Wipe-on-boot root for the cloud servers (modules/impermanence.nix). No
    # release tags upstream; the commit is pinned in flake.lock.
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # UEFI Secure Boot for NixOS (see modules/secure-boot.nix and
    # docs/secure-boot.md). Pinned to a release tag; bump deliberately.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

      # Hetzner Cloud web server, installed by nixos-anywhere from the
      # vps-config repo and updated with `make deploy`.
      nixosConfigurations.jenkosrv-fsn1-3 = mkSystem {
        inherit inputs;
        system = "x86_64-linux";
        hostname = "jenkosrv-fsn1-3";
        user = "ieuan";
        headless = true;
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
