# NixOS Configuration

Flake-based NixOS + Home Manager configuration.

## Repository Structure

```
.
├── flake.nix                 # Inputs (nixpkgs, home-manager, nixos-hardware, disko, impermanence) + outputs
├── flake.lock                # Pinned input versions (generated)
├── lib/
│   └── mkSystem.nix          # Helper that builds a host from a name + user (+ headless)
├── hosts/
│   ├── jenkonix-2/
│   │   ├── default.nix       # Host wiring: hostname, LUKS, imports, stateVersion
│   │   └── hardware-configuration.nix  # Machine-generated (see below)
│   ├── jenkosrv-fsn1-3/      # Hetzner Cloud web server (headless)
│   │   ├── default.nix       # Host wiring: GRUB, addresses, Tailscale tags
│   │   └── disk-config.nix   # disko layout: /boot + /nix on disk, tmpfs /
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
│   ├── server.nix            # Headless baseline: SSH, networkd, firewall, Tailscale, sudo
│   ├── impermanence.nix      # Wipe-on-boot root; state on a /persist Hetzner volume
│   ├── web/sites.nix         # Caddy + site configs from the site repos (flake inputs)
│   ├── locale.nix            # Time zone + locale
│   ├── packages.nix          # System programs + environment.systemPackages
│   └── nix.nix               # Nix daemon, GC, flake auto-upgrade
├── users/
│   └── ieuan/
│       ├── nixos.nix         # System account (desktop)
│       ├── server.nix        # System account (headless: SSH keys, wheel)
│       └── home.nix          # Home Manager configuration
└── Makefile                  # switch / test / boot / deploy / update / check / fmt
```

Adding a new machine is a single `mkSystem` entry in `flake.nix` plus a
directory under `hosts/`. Home Manager is wired in as a NixOS module by
`lib/mkSystem.nix`, so `home.nix` changes apply during a normal system rebuild.
Pass `headless = true` for servers: Home Manager is skipped and the user is
defined by `users/<user>/server.nix` instead of `nixos.nix`.

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
make update-sites  # bump only the web server's site repos (web.sites)
make switch
```

Auto-upgrade is enabled (`modules/nix.nix`) and rebuilds from the flake on
GitHub. Because inputs are pinned by `flake.lock`, upgrades only move when you
run `make update` and push the new lock file.

Renovate (`renovate.json`, run from vps-config's workflow) opens those bumps
as PRs: one weekly "flake inputs" PR for the branch-tracking inputs, and one
per release for the tag-pinned ones (disko, lanzaboote). Merging a PR is the
deploy, since the nightly auto-upgrade builds `main`. The private site repos
are left to `make update-sites`: they are fetched over SSH aliases Renovate
doesn't have, which is also why it never does a whole-lock update.

Caddy's plugins (the `withPlugins` list in `hosts/jenkosrv-fsn1-3`) get a
weekly "Caddy plugins" PR too. Both a plugin bump and a nixpkgs bump that
moves Caddy change `withPlugins`' vendor hash, so on those PRs Renovate runs
`scripts/update-caddy-hash.sh`, which builds just the vendored source and
writes in the hash from the mismatch error. After a `make update` by hand,
run it yourself:

```sh
scripts/update-caddy-hash.sh .#nixosConfigurations.jenkosrv-fsn1-3.config.services.caddy.package hosts/jenkosrv-fsn1-3/default.nix
```

If a wrong hash reaches `main` anyway, the server's auto-upgrade fails, the
server stays on its current generation, and the failure is mailed (see
Vulnerability reports).

## Servers

`jenkosrv-fsn1-3` is a Hetzner Cloud VM. Its first install is done by
nixos-anywhere from the OpenTofu in the
[vps-config](https://github.com/dijitali/vps-config) repo (see
`docs/nixos-migration.md` there), which partitions the disk with
`hosts/jenkosrv-fsn1-3/disk-config.nix` and installs this flake. No addresses
are pinned here: IPv4 comes from DHCP and IPv6 from Hetzner's metadata service
at boot (`server.hetznerMetadataIPv6`). Its root
filesystem is a tmpfs, so every boot starts from this flake; only
`/nix/persist` (install-time secrets) and the separate `/persist` volume
(listed in `modules/impermanence.nix` and the host file) survive. After that:

```sh
make deploy    # build here, activate over SSH (nixos-rebuild --target-host)
```

`modules/server.nix` enables passwordless sudo for `wheel` so this, and the
`sudo systemctl reload caddy` in ieuan-net's deploy script, run without a
prompt. The server also auto-upgrades from this flake on GitHub
(`modules/nix.nix`), so pushing a new `flake.lock` updates it too.

### Vulnerability reports

Every Monday the server scans what it is actually running and emails
hi@ieuan.net (`modules/vuln-scan`): vulnix checks the runtime closure against
NVD, and govulncheck checks every Go binary against the Go vulnerability
database (it catches what NVD hasn't categorised yet, and dependency modules
compiled into a binary). Clean weeks send nothing; a failed scan sends its
log. Reports never go into this repo, which is public.

Triage false positives into `modules/vuln-scan/vulnix-whitelist.toml` (per
package and CVE, with the reason) or `security.vulnScan.goIgnore` in the host
file. To run a scan now: `sudo systemctl start vuln-scan` on the server.

The scan mails through Fastmail with an app password in
`/nix/persist/secrets/smtp-password` (root, 0400), written at install time
by vps-config. vulnix needs the system's `.drv` files, which exist once an
auto-upgrade has evaluated the flake on the server; right after a
`make deploy` the report says vulnix couldn't run.

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
