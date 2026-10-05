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

  # Read-only GitHub token for the private site repos used as flake inputs
  # (modules/web/sites.nix). The file holds one line,
  # `access-tokens = github.com=<token>`, and lives outside the store:
  #   - laptop: /etc/nix/access-tokens.conf, created by hand (owner ieuan, 0600,
  #     so both your own builds and root's auto-upgrade can read it);
  #   - servers: linked to the copy OpenTofu installs at bootstrap
  #     (modules/server.nix).
  # `!include` ignores a missing file, so evaluation without it just can't
  # fetch those inputs.
  nix.extraOptions = ''
    !include /etc/nix/access-tokens.conf
  '';

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
