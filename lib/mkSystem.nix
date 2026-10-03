# Builds a nixosSystem from a host + user. Keeping this here means adding a new
# machine is a single entry in flake.nix rather than a copy-pasted block.
#
# `headless = true` is for servers: no Home Manager, and the user comes from
# users/<user>/server.nix (SSH keys, sudo) instead of the desktop nixos.nix.
{
  inputs,
  system,
  hostname,
  user,
  headless ? false,
}:

let
  lib = inputs.nixpkgs.lib;
in
inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  # Make the flake inputs (and a couple of identifiers) available to every
  # module via its arguments, e.g. `{ inputs, ... }:`.
  specialArgs = {
    inherit
      inputs
      hostname
      user
      headless
      ;
  };

  modules = [
    ../hosts/${hostname}
    ../users/${user}/${if headless then "server.nix" else "nixos.nix"}
  ]
  ++ lib.optionals (!headless) [
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = { inherit inputs; };
      home-manager.users.${user} = import ../users/${user}/home.nix;
    }
  ];
}
