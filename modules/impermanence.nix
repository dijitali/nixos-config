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

  # Hetzner volumes appear as SCSI disks whose kernel-reported vendor is "HC"
  # and model "Volume" (space-padded in sysfs; checked on a live Hetzner
  # server). Matching the kernel attributes avoids depending on the scsi_id
  # helper that sets ID_VENDOR/ID_MODEL in a full system. Give whichever volume
  # is attached a fixed name so this config never needs its numeric ID; a
  # server using this module must have exactly one volume attached.
  boot.initrd.services.udev.rules = ''
    SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ATTRS{vendor}=="HC*", ATTRS{model}=="Volume*", SYMLINK+="disk/persist"
  '';

  # Formatted ext4 by Hetzner when OpenTofu creates the volume, and outside the
  # disko layout so a reinstall never reformats it.
  fileSystems."/persist" = {
    device = "/dev/disk/persist";
    fsType = "ext4";
    neededForBoot = true;
    # Fail fast (emergency shell) if the volume is missing, rather than
    # waiting the default 90 s.
    options = [ "x-systemd.device-timeout=20s" ];
  };

  # Nix builds default to /tmp, which is on the small root tmpfs; an
  # auto-upgrade that has to compile something (e.g. plugin-built Caddy, not in
  # the binary cache) would run out of space. Build on the /nix disk instead.
  nix.settings.build-dir = "/nix/var/nix/builds";
  systemd.tmpfiles.rules = [ "d /nix/var/nix/builds 0755 root root -" ];

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
