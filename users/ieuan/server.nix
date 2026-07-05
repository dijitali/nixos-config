# Lean server-side account for the ieuan user: no Home Manager, no desktop
# groups — just wheel, zsh and the SSH keys. Selected by `server = true` in
# lib/mkSystem.nix; the desktop variant lives in ./nixos.nix.
{ pkgs, ... }:

{
  users.users.ieuan = {
    isNormalUser = true;
    description = "Ieuan";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    # sshd only accepts keys (modules/ssh-server.nix). sudo still wants a
    # password (security.sudo.wheelNeedsPassword), so set one with `passwd`
    # on first login — it is stateful and survives rebuilds.
    openssh.authorizedKeys.keys = [
      # YubiKey A
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEo+YmeZF08PM0Ojvt6hIUgkaxzHrdc7GUZS+UpEuoxvAAAABHNzaDo= hi@ieuan.net"
      # YubiKey C
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDlEPzSf59qfPwZRF5r5RzZ33DJR69U9xMyvu3yJrEcFAAAABHNzaDo= hi@ieuan.net"
      # Software key (~/.ssh/id_ed25519)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICd3qvLJCEGwvZLWl5dUXI/WAV9a7DDTYa+NlDA9Yjeo hi@ieuan.net"
    ];
  };

  # zsh is enabled system-side because it is the login shell above.
  programs.zsh.enable = true;
}
