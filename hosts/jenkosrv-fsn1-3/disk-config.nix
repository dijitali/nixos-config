# Disk layout for a Hetzner Cloud x86 VM, applied by disko during the
# nixos-anywhere install. GPT with both a BIOS boot partition (EF02) and an ESP
# so the image boots whichever firmware mode Hetzner presents; GRUB is told to
# install for both in default.nix.
{ lib, ... }:

{
  disko.devices.disk.main = {
    device = lib.mkDefault "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        esp = {
          size = "500M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
