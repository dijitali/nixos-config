# Disk layout for a Hetzner Cloud x86 VM, applied by disko during the
# nixos-anywhere install. GPT with both a BIOS boot partition (EF02) and an ESP
# so the image boots whichever firmware mode Hetzner presents; GRUB is told to
# install for both in default.nix.
#
# `/` is a tmpfs (see modules/impermanence.nix): the system disk only holds
# /boot and /nix (the store plus /nix/persist). Runtime state lives on the
# separate Hetzner volume mounted at /persist, which is deliberately not
# declared here so disko never formats it.
{ lib, ... }:

{
  disko.devices = {
    # The system disk is always SCSI LUN 0; an attached volume is LUN 1+.
    # Addressing it by path rather than /dev/sda means the installer can never
    # pick the volume by mistake.
    disk.main = {
      device = lib.mkDefault "/dev/disk/by-path/pci-0000:06:00.0-scsi-0:0:0:0";
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
          nix = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix";
              mountOptions = [ "noatime" ];
            };
          };
        };
      };
    };

    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=512M"
        "mode=755"
      ];
    };
  };
}
