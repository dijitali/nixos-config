# Headless counterpart to ./nixos.nix: the same account, but no desktop groups,
# no Home Manager and SSH-key-only access. Used by mkSystem when
# `headless = true`.
{ pkgs, ... }:

{
  users.users.ieuan = {
    isNormalUser = true;
    description = "Ieuan";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICd3qvLJCEGwvZLWl5dUXI/WAV9a7DDTYa+NlDA9Yjeo hi@ieuan.net"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEo+YmeZF08PM0Ojvt6hIUgkaxzHrdc7GUZS+UpEuoxvAAAABHNzaDo= hi@ieuan.net (yka)"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDlEPzSf59qfPwZRF5r5RzZ33DJR69U9xMyvu3yJrEcFAAAABHNzaDo= hi@ieuan.net (ykC)"
    ];
  };

  # zsh is the login shell above; enabling it system-wide installs the shell
  # init so a login over SSH gets a working environment.
  programs.zsh.enable = true;
}
