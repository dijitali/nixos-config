# NixOS Configuration

System-level configuration and user-specific Home Manager configuration for `jenkonix-2`.

## Repository Structure

```
.
├── configuration.nix          # System configuration
├── hardware-configuration.nix # Auto-generated hardware config (do not edit)
└── home-manager/
    └── home.nix               # User environment (ieuan)
```

Home Manager is integrated as a NixOS module, so `home.nix` changes are applied
as part of a normal system rebuild — no separate `home-manager` command needed.

---

## Applying Changes

> Changes must be applied from `/etc/nixos/`. If editing files in this repo,
> ensure they are synced there first (e.g. symlink or copy).

### Rebuild and switch (live system)

```sh
sudo nixos-rebuild switch
```

Applies changes immediately. The new config becomes the default boot entry.

### Test before committing

```sh
sudo nixos-rebuild test
```

Activates the new config without making it the default boot entry. Reverts on
next reboot if you don't follow up with `switch`.

### Build without activating

```sh
sudo nixos-rebuild build
```

Builds the config and creates a `./result` symlink. Useful for checking the
build succeeds before applying.

### Dry run (show what would change)

```sh
sudo nixos-rebuild dry-activate
```

Shows which systemd units would be started/stopped/restarted without actually
doing anything.

---

## Rolling Back

### Boot into a previous generation

At the systemd-boot menu, select an older entry — each generation is listed.

### Roll back the running system

```sh
sudo nixos-rebuild switch --rollback
```

Or activate a specific generation directly:

```sh
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system-<N>-link/bin/switch-to-configuration switch
```

---

## Home Manager

Because Home Manager runs as a NixOS module, `home.nix` is applied automatically
during `nixos-rebuild switch`. No separate activation step is required.

To check the current Home Manager generation:

```sh
home-manager generations
```

To roll back the user environment independently (without a system rebuild):

```sh
home-manager rollback
```

---

## Package Management

### Search for packages

```sh
nix search nixpkgs <package>
```

### Open a temporary shell with a package

```sh
nix shell nixpkgs#<package>
```

### Run a package without installing

```sh
nix run nixpkgs#<package>
```

---

## Maintenance

### Garbage collect old generations

```sh
# Remove generations older than 30 days and collect garbage
sudo nix-collect-garbage --delete-older-than 30d

# Also clean up the boot menu entries
sudo /run/current-system/bin/switch-to-configuration boot
```

> Garbage collection also runs automatically weekly (configured in `configuration.nix`).

### Optimise the Nix store (deduplication)

```sh
sudo nix-store --optimise
```

> Also runs automatically (configured in `configuration.nix`).

### Update the system

```sh
sudo nix-channel --update
sudo nixos-rebuild switch
```

> Auto-upgrades are enabled and run on a schedule. Run manually to upgrade
> immediately.

### Show current NixOS version

```sh
nixos-version
```
