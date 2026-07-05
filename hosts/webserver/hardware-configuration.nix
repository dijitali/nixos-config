# Hetzner Cloud VM "hardware". Unlike the physical machines this is stable
# virtual hardware (QEMU/KVM with virtio devices), so a hand-written profile
# is committed instead of a per-machine scan. After the first install, verify
# it against `nixos-generate-config --show-hardware-config` on the server and
# fold in any differences (in particular the root filesystem device — newer
# images may use a different partition layout or a by-uuid path).
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  # Hetzner Cloud VMs have no swap partition by default; add a swapfile or
  # zram here if the plan's RAM turns out to be tight.
  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
