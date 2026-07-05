# NixOS Configuration

Flake-based NixOS + Home Manager configuration.

## Repository Structure

```
.
├── flake.nix                 # Inputs (nixpkgs, home-manager, nixos-hardware) + outputs
├── flake.lock                # Pinned input versions (generated)
├── lib/
│   └── mkSystem.nix          # Helper that builds a host from a name + user
├── hosts/
│   ├── jenkonix-2/
│   │   ├── default.nix       # Host wiring: hostname, LUKS, imports, stateVersion
│   │   └── hardware-configuration.nix  # Machine-generated (see below)
│   └── droid/                # Android/Termux (Nix-on-Droid)
│       ├── default.nix       # environment.packages, shell, flakes
│       └── home.nix          # Lighter Home Manager config for mobile
├── modules/                  # Reusable system modules
│   ├── boot.nix              # Boot loader + kernel hardening
│   ├── networking.nix        # NetworkManager, firewall, Tailscale, Avahi
│   ├── desktop.nix           # Plasma 6, SDDM, PipeWire, printing
│   ├── hardware.nix          # Bluetooth, scanners, firmware (fwupd)
│   ├── security.nix          # sudo, AppArmor, smartcards, SSH/GnuPG agents
│   ├── secure-boot.nix       # UEFI Secure Boot via lanzaboote (docs/secure-boot.md)
│   ├── locale.nix            # Time zone + locale
│   ├── packages.nix          # System programs + environment.systemPackages
│   └── nix.nix               # Nix daemon, GC, flake auto-upgrade
├── users/
│   └── ieuan/
│       ├── nixos.nix         # System account
│       └── home.nix          # Home Manager configuration
└── Makefile                  # switch / test / boot / update / check / fmt
```

Adding a new machine is a single `mkSystem` entry in `flake.nix` plus a
directory under `hosts/`. Home Manager is wired in as a NixOS module by
`lib/mkSystem.nix`, so `home.nix` changes apply during a normal system rebuild.

## First-time setup / `hardware-configuration.nix`

The per-machine hardware scan is **not** committed by default. Flakes only see
files tracked by git, so after cloning on a machine you must generate it and
add it:

```sh
sudo nixos-generate-config --show-hardware-config \
  > hosts/jenkonix-2/hardware-configuration.nix
git add hosts/jenkonix-2/hardware-configuration.nix
```

## Applying Changes

You no longer need to copy files into `/etc/nixos`; build directly from this
checkout with `--flake`.

```sh
make switch    # build + activate + set as default boot entry
make test      # activate without making it default (reverts on reboot)
make boot      # set as default boot entry without activating now
```

These wrap `sudo nixos-rebuild <action> --flake ".#jenkonix-2"`. Target another
host with `make switch NIXNAME=<host>`.

### Validate before applying

```sh
make check     # nix flake check
```

## Updating

```sh
make update    # nix flake update  -> bumps flake.lock, commit the result
make switch
```

Auto-upgrade is enabled (`modules/nix.nix`) and rebuilds from the flake on
GitHub. Because inputs are pinned by `flake.lock`, upgrades only move when you
run `make update` and push the new lock file.

## Android / Termux (Nix-on-Droid)

The flake also exposes `nixOnDroidConfigurations.default` for a phone running
[Nix-on-Droid](https://github.com/nix-community/nix-on-droid). On the device:

1. Install the Nix-on-Droid app (F-Droid) and open it once to bootstrap Nix.
2. From a clone of this repo (or directly from GitHub), activate it:

   ```sh
   nix-on-droid switch --flake .#default
   ```

   If activation fails with store-path errors under proot, retry with
   `--impure`.

The device config lives in `hosts/droid/` and is intentionally lighter than the
laptop: terminal tooling only, no desktop or YubiKey signing. The input tracks
`nix-on-droid`'s `prerelease-25.11` branch (no stable `release-25.11` exists
yet) and follows this flake's `nixpkgs`/`home-manager`.

## Rolling Back

Boot into a previous generation from the systemd-boot menu, or:

```sh
sudo nixos-rebuild switch --rollback           # roll back the running system
home-manager generations                       # list HM generations
```

## Maintenance

```sh
make fmt                                        # format all Nix files (nixfmt)
sudo nix-collect-garbage --delete-older-than 30d
sudo nix-store --optimise
nixos-version
```

> GC and store optimisation also run automatically (configured in
> `modules/nix.nix`).
