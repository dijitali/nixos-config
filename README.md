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
├── tests/
│   └── jenkosrv-fsn1-3.nix   # NixOS VM test of the web server (see Testing)
└── Makefile                  # switch / test / boot / deploy / test-server / update / check / fmt
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

`nix flake check` evaluates every configuration and also runs the VM tests
under `checks` (see [Testing](#testing)), so it needs KVM and takes a minute or
two. `make test` above is unrelated: it is `nixos-rebuild test` on this
machine.

## Updating

```sh
make update    # nix flake update  -> bumps flake.lock, commit the result
make update-sites  # bump only the web server's site repos (web.sites)
make switch
```

Auto-upgrade is enabled (`modules/nix.nix`) and rebuilds from the flake on
GitHub. Because inputs are pinned by `flake.lock`, upgrades only move when you
run `make update` and push the new lock file.

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
make test-server   # check the change in VMs first (see Testing)
make deploy    # build here, activate over SSH (nixos-rebuild --target-host)
```

`make deploy` ships this checkout as it is, branch and uncommitted changes
included; the next nightly auto-upgrade returns the server to `main`.

`modules/server.nix` enables passwordless sudo for `wheel` so this, and the
`sudo systemctl reload caddy` in ieuan-net's deploy script, run without a
prompt. The server also auto-upgrades from this flake on GitHub
(`modules/nix.nix`), so pushing a new `flake.lock` updates it too.

## Testing

The server has a NixOS VM test, `tests/jenkosrv-fsn1-3.nix`, exposed as
`checks.x86_64-linux.jenkosrv-fsn1-3`. It boots the real `jenkosrv-fsn1-3`
config in a QEMU VM next to a client VM. The test itself checks only the
server:

- it boots with no failed units, and `/persist` is mounted
- the firewall lets the client reach only SSH, HTTP and HTTPS
- Caddy has a certificate for every site host in its running config, and each
  answers over HTTP
- after a reboot of the tmpfs root, certificates and machine-id survive on
  `/persist`

How each site behaves is tested in that site's own repo (see
[Site tests](#site-tests)).

Run it before deploying a server change:

```sh
make test-server   # nix build .#checks.x86_64-linux.jenkosrv-fsn1-3 -L
```

It takes about a minute once the server's closure is built. On failure the
log ends with the failing subtest and assertion. Nix caches a passing result,
so it only re-runs when the config, a site or the test changes (force it with
`--rebuild`).

**Requirements.** KVM (`/dev/kvm`) on the machine running it, and SSH access
to the private site repos, since the sites are flake inputs fetched over the
`github-*` host aliases that Home Manager adds to `~/.ssh/config`. On a fresh
machine, `make switch` first.

**What differs from production.** The test switches off what only works on
Hetzner or the real internet: the metadata-service IPv6 unit, Tailscale,
auto-upgrade, GRUB and the catch-all DHCP network. Caddy issues certificates
from its internal CA (`web.localCerts`) instead of Let's Encrypt, so requests
in the test don't verify them.

### Site tests

A site flake can export `caddyTest` next to `caddyConfig`: Python that the
server test runs as a subtest named after the site, with these in scope:

| Name | What it is |
| --- | --- |
| `server`, `client` | the two VMs ([test driver machine API](https://nixos.org/manual/nixos/stable/#sec-nixos-tests)) |
| `server_ip`, `client_ip` | their addresses |
| `get(url, *curl_args)` | `(status, redirect, headers)` for a request from the client, by name, to the server; header names are lower-cased |
| `expect(url, status, redirect="")` | asserts a status and redirect target |

For example:

```python
expect("https://example.org/old", 301, "https://example.org/new")
status, _, headers = get("https://example.org/")
assert headers["x-frame-options"] == "DENY", headers
```

To try a site change before it is merged and locked here, point the input at a
local checkout:

```sh
nix build .#checks.x86_64-linux.jenkosrv-fsn1-3 -L \
  --override-input <site> path:/path/to/<site>
```

### Debugging interactively

Build the test driver and drive the VMs from its Python prompt:

```sh
nix build .#checks.x86_64-linux.jenkosrv-fsn1-3.driverInteractive
./result/bin/nixos-test-driver
>>> start_all()
>>> server.succeed("systemctl status caddy")
>>> server.shell_interact()   # root shell on the server VM
>>> test_script()             # run the whole test script
```

If QEMU fails with a glibc version error, unset `LD_LIBRARY_PATH` in that
shell first.

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
