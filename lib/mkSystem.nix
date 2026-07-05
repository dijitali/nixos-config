# Builds a nixosSystem from a host + user. Keeping this here means adding a new
# machine is a single entry in flake.nix rather than a copy-pasted block.
{
  inputs,
  system,
  hostname,
  user,
  # Server hosts get the lean account from users/<user>/server.nix and skip
  # Home Manager entirely; desktops get nixos.nix + home.nix as before.
  server ? false,
}:

inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  # Make the flake inputs (and a couple of identifiers) available to every
  # module via its arguments, e.g. `{ inputs, ... }:`.
  specialArgs = { inherit inputs hostname user; };

  modules =
    [
      ../hosts/${hostname}
      (if server then ../users/${user}/server.nix else ../users/${user}/nixos.nix)
    ]
    ++ inputs.nixpkgs.lib.optionals (!server) [
      inputs.home-manager.nixosModules.home-manager

      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit inputs; };
        home-manager.users.${user} = import ../users/${user}/home.nix;
      }
    ];
}
