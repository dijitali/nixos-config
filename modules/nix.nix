# Nix daemon settings, garbage collection and flake-based auto-upgrade.
{
  nix.settings = {
    # Restrict who may talk to the Nix daemon (build/substitute) to wheel.
    allowed-users = [ "@wheel" ];
    # Flakes + the new CLI are required to build this configuration.
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  nix.optimise.automatic = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Auto-upgrade from the flake on GitHub. Because the flake is pinned by
  # flake.lock, upgrades only move when you run `nix flake update` and push;
  # this rebuilds against whatever is committed there.
  system.autoUpgrade = {
    enable = true;
    flake = "github:dijitali/nixos-config";
    flags = [ "--refresh" ];
  };
}
