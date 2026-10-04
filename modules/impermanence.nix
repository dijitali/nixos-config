# Impermanent root for servers: `/` is a tmpfs (declared in the host's disko
# layout), so every boot starts from exactly what this flake declares. Only two
# places survive a reboot:
#
#   /nix/persist  on the system disk: install-time secrets written by
#                 nixos-anywhere from vps-config's OpenTofu (SSH host key,
#                 Tailscale auth key, GitHub deploy key). Read in place; never
#                 bind-mounted. Recreated by every reinstall.
#   /persist      on a separate Hetzner volume: runtime state (logs, certs,
#                 Tailscale identity, site content). Survives a reinstall when
#                 the volume is reattached.
#
# Hosts add their own state under environment.persistence."/persist".
{ inputs, ... }:

{
  imports = [ inputs.impermanence.nixosModules.impermanence ];

  # systemd in stage 1, so the udev rule below runs before /persist is mounted.
  boot.initrd.systemd.enable = true;

  # Hetzner volumes appear as SCSI disks with vendor "HC" and model "Volume"
  # (the by-id name embeds the volume's numeric ID). Give whichever one is
  # attached a fixed name so this config never needs that ID. A server using
  # this module must have exactly one volume attached.
  boot.initrd.services.udev.rules = ''
    SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_VENDOR}=="HC", ENV{ID_MODEL}=="Volume", SYMLINK+="disk/persist"
  '';

  # Formatted ext4 by Hetzner when OpenTofu creates the volume, and outside the
  # disko layout so a reinstall never reformats it.
  fileSystems."/persist" = {
    device = "/dev/disk/persist";
    fsType = "ext4";
    neededForBoot = true;
  };

  environment.persistence."/persist" = {
    # Keep the bind mounts out of `mount`/`df` noise.
    hideMounts = true;
    directories = [
      "/var/log"
      # UID/GID allocations for dynamically created users.
      "/var/lib/nixos"
      # Persistent timers, random seed, coredumps.
      "/var/lib/systemd"
      {
        directory = "/var/lib/tailscale";
        mode = "0700";
      }
    ];
    files = [
      # Stable journal identity across boots.
      "/etc/machine-id"
    ];
  };
}
