# Builds a nixosSystem from a host + user. Keeping this here means adding a new
# machine is a single entry in flake.nix rather than a copy-pasted block.
{
  inputs,
  system,
  hostname,
  user,
}:

inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  # Make the flake inputs (and a couple of identifiers) available to every
  # module via its arguments, e.g. `{ inputs, ... }:`.
  specialArgs = { inherit inputs hostname user; };

  modules = [
    inputs.home-manager.nixosModules.home-manager

    ../hosts/${hostname}
    ../users/${user}/nixos.nix

    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = { inherit inputs; };
      home-manager.users.${user} = import ../users/${user}/home.nix;
    }
  ];
}
